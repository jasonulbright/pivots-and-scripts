#Requires -Modules Pester
# Write actions of the module, with every ConfigMgr call mocked: create a script with its parameters,
# approve, deny and remove a script, start a Run Scripts operation, save a JSON file. Each action has a
# success case, a failure case, a partial-failure case (a step after the first one fails), a -WhatIf
# case, and hostile input. A mock body cannot see test variables, so fixtures pass through $global:Fx.

BeforeAll {
    . "$PSScriptRoot\TestHelpers.ps1"
    Import-AppModule
    Import-SuiteCommonGlobal
    $script:Stubs = New-CmStub -Name $script:CmStubNames
    # The CIM cmdlets have typed parameters, so a mock needs a real session object. A local DCOM session opens no network connection.
    $script:Session = [Microsoft.Management.Infrastructure.CimSession]::Create('localhost', (New-CimSessionOption -Protocol Dcom))
    $script:Guid = '685E0A08-8ACE-4948-BE8F-9D0416852976'
}

AfterAll {
    if ($script:Session) { $script:Session.Dispose() }
    Remove-CmStub -Name $script:CmStubNames
    Remove-Variable -Name Fx -Scope Global -ErrorAction SilentlyContinue
}

Describe 'New-PasManagedScript' {
    BeforeEach {
        $global:Fx = @{
            Calls = [System.Collections.Generic.List[object]]::new(); Session = $script:Session
            Created = [pscustomobject]@{ ScriptGuid = '11111111-2222-3333-4444-555555555555' }
            CreateThrows = $null; UpdateReturn = 0; UpdateThrows = $null; RemoveThrows = $null; Mismatch = $false; NonPiped = 0; Sent = $null; After = $null
        }
        $global:Fx.Instance = New-CimFixture 'SMS_Scripts' @{ ScriptGuid = '11111111-2222-3333-4444-555555555555'; Script = 'stored script text'; ScriptDescription = 'desc'; ScriptName = 'stored name'; ScriptVersion = '1'; Timeout = [uint32]60; ParamsDefinition = '' }
        Mock New-CMScript {
            $global:Fx.Calls.Add(@{ Cmd = 'New'; Name = $PesterBoundParameters.ScriptName; Text = $PesterBoundParameters.ScriptText; Fast = [bool]$PesterBoundParameters.Fast })
            if ($global:Fx.CreateThrows) { throw $global:Fx.CreateThrows }
            $global:Fx.Created
        } -ModuleName PivotsAndScripts
        Mock Remove-CMScript {
            $global:Fx.Calls.Add(@{ Cmd = 'Remove'; Item = $PesterBoundParameters.InputObject; Force = [bool]$PesterBoundParameters.Force })
            if ($global:Fx.RemoveThrows) { throw $global:Fx.RemoveThrows }
        } -ModuleName PivotsAndScripts
        Mock New-PasCimSession { $global:Fx.Session } -ModuleName PivotsAndScripts
        Mock Remove-CimSession { $global:Fx.Calls.Add(@{ Cmd = 'RemoveSession' }) } -ModuleName PivotsAndScripts
        Mock Get-CimInstance {
            if ($PesterBoundParameters.ContainsKey('InputObject')) { return $PesterBoundParameters.InputObject }
            $global:Fx.NonPiped++
            $global:Fx.Calls.Add(@{ Cmd = 'Get'; Filter = $PesterBoundParameters.Filter; Namespace = $PesterBoundParameters.Namespace })
            if ($global:Fx.NonPiped -eq 1) { $global:Fx.Instance } else { $global:Fx.After }
        } -ModuleName PivotsAndScripts
        Mock Invoke-CimMethod {
            $global:Fx.Calls.Add(@{ Cmd = 'Update'; Method = $PesterBoundParameters.MethodName; Arguments = $PesterBoundParameters.Arguments })
            if ($global:Fx.UpdateThrows) { throw $global:Fx.UpdateThrows }
            $global:Fx.Sent = $PesterBoundParameters.Arguments
            $def = if ($global:Fx.Mismatch) { 'different' } else { $PesterBoundParameters.Arguments.ParamsDefinition }
            $global:Fx.After = New-CimFixture 'SMS_Scripts' @{ ScriptGuid = '11111111-2222-3333-4444-555555555555'; Script = 'stored script text'; ScriptDescription = 'desc'; ScriptName = 'stored name'; ScriptVersion = '1'; Timeout = [uint32]60; ParamsDefinition = $def }
            [pscustomobject]@{ ReturnValue = $global:Fx.UpdateReturn }
        } -ModuleName PivotsAndScripts
    }

    It 'creates a script without parameters and stores no definition' {
        $r = New-PasManagedScript -Text 'Get-Service' -SMSProvider 'cm01' -SiteCode 'MCM'
        $r.ScriptGuid | Should -Be '11111111-2222-3333-4444-555555555555'
        @($r.Parameters).Count | Should -Be 0
        $new = $global:Fx.Calls | Where-Object Cmd -eq 'New'
        @($new).Count | Should -Be 1
        $new.Text | Should -Be 'Get-Service'
        $new.Fast | Should -BeTrue
        @($global:Fx.Calls | Where-Object Cmd -in 'Update', 'Get').Count | Should -Be 0
    }
    It 'names the script after the time and the first 8 characters of the text hash' {
        New-PasManagedScript -Text 'Get-Service' -SMSProvider 'cm01' -SiteCode 'MCM' | Out-Null
        $name = ($global:Fx.Calls | Where-Object Cmd -eq 'New').Name
        $name | Should -Match '^PivotsAndScripts-\d{8}-\d{6}-[0-9a-f]{8}$'
        $name | Should -BeLike ('*-' + (Get-PasHash 'Get-Service').Substring(0, 8))
    }
    It 'uses the name it is given' {
        New-PasManagedScript -Text 'Get-Service' -SMSProvider 'cm01' -SiteCode 'MCM' -ScriptName 'ZZTEST-PAS-x-script' | Out-Null
        ($global:Fx.Calls | Where-Object Cmd -eq 'New').Name | Should -Be 'ZZTEST-PAS-x-script'
    }
    It 'stores the parameter definition with named arguments that keep the stored script' {
        $r = New-PasManagedScript -Text 'param([Parameter(Mandatory)][string]$Name = "x", [int]$Count = 2) Get-Service $Name' -SMSProvider 'cm01' -SiteCode 'MCM'
        @($r.Parameters) | Should -Be @('Name', 'Count')
        $update = $global:Fx.Calls | Where-Object Cmd -eq 'Update'
        @($update).Count | Should -Be 1
        $update.Method | Should -Be 'UpdateScript'
        $a = $update.Arguments
        $a.Script | Should -Be 'stored script text'
        $a.ScriptName | Should -Be 'stored name'
        $a.ScriptDescription | Should -Be 'desc'
        $a.ScriptVersion | Should -Be '1'
        $a.Timeout | Should -BeOfType [uint32]
        $a.Timeout | Should -Be 60
        $def = @(ConvertFrom-PasParamsDefinition $a.ParamsDefinition)
        @($def | ForEach-Object Name) | Should -Be @('Name', 'Count')
        $def[0].Required | Should -BeTrue
        $def[1].Type | Should -Be 'System.Int32'
        @($global:Fx.Calls | Where-Object Cmd -eq 'RemoveSession').Count | Should -Be 1
        @($global:Fx.Calls | Where-Object Cmd -eq 'Remove').Count | Should -Be 0
    }
    It 'reads the new script from the site namespace by its GUID' {
        New-PasManagedScript -Text 'param($A)' -SMSProvider 'cm01' -SiteCode 'ZZ1' | Out-Null
        $get = @($global:Fx.Calls | Where-Object Cmd -eq 'Get')
        $get.Count | Should -Be 2
        $get[0].Namespace | Should -Be 'root\SMS\site_ZZ1'
        $get[0].Filter | Should -Be "ScriptGuid = '11111111-2222-3333-4444-555555555555'"
    }
    It 'removes the script and says so when the site refuses the definition (return value <Code>)' -ForEach @(@{ Code = 1 }, @{ Code = 5 }, @{ Code = -1 }) {
        $global:Fx.UpdateReturn = $Code
        $message = $null
        try { New-PasManagedScript -Text 'param($A)' -SMSProvider 'cm01' -SiteCode 'MCM' } catch { $message = $_.Exception.Message }
        $message | Should -BeLike "Script parameters could not be stored: SMS_Scripts.UpdateScript returned $Code. The incomplete script was removed."
        $rm = @($global:Fx.Calls | Where-Object Cmd -eq 'Remove')
        $rm.Count | Should -Be 1
        $rm[0].Item.ScriptGuid | Should -Be '11111111-2222-3333-4444-555555555555'
        $rm[0].Force | Should -BeTrue
        @($global:Fx.Calls | Where-Object Cmd -eq 'RemoveSession').Count | Should -Be 1
    }
    It 'removes the script when the definition read back does not match' {
        $global:Fx.Mismatch = $true
        { New-PasManagedScript -Text 'param($A)' -SMSProvider 'cm01' -SiteCode 'MCM' } | Should -Throw '*do not match*'
        @($global:Fx.Calls | Where-Object Cmd -eq 'Remove').Count | Should -Be 1
    }
    It 'removes the script when the update call throws' {
        $global:Fx.UpdateThrows = 'RPC failed'
        { New-PasManagedScript -Text 'param($A)' -SMSProvider 'cm01' -SiteCode 'MCM' } | Should -Throw '*RPC failed*'
        @($global:Fx.Calls | Where-Object Cmd -eq 'Remove').Count | Should -Be 1
        @($global:Fx.Calls | Where-Object Cmd -eq 'RemoveSession').Count | Should -Be 1
    }
    It 'names the script GUID for removal by hand when the cleanup fails too' {
        $global:Fx.UpdateReturn = 9
        $global:Fx.RemoveThrows = 'access denied'
        $message = $null
        try { New-PasManagedScript -Text 'param($A)' -SMSProvider 'cm01' -SiteCode 'MCM' } catch { $message = $_.Exception.Message }
        $message | Should -BeLike '*returned 9. Remove script 11111111-2222-3333-4444-555555555555 in the console.'
    }
    It 'refuses script text that cannot be stored before it creates anything: <Case>' -ForEach @(
        @{ Case = 'a switch parameter';  Text = 'param([switch]$A)';          Pattern = '*string and integer*' }
        @{ Case = 'a quote in a default'; Text = "param([string]`$A = ""it's"")"; Pattern = '*single quote*' }
        @{ Case = 'a syntax error';       Text = 'param([string]$A';            Pattern = '*' }
        @{ Case = 'eleven parameters';    Text = 'param(' + ((1..11 | ForEach-Object { "`$P$_" }) -join ',') + ')'; Pattern = '*at most 10*' }
    ) {
        { New-PasManagedScript -Text $Text -SMSProvider 'cm01' -SiteCode 'MCM' } | Should -Throw $Pattern
        Should -Invoke New-CMScript -ModuleName PivotsAndScripts -Times 0 -Exactly
    }
    It 'refuses an empty script before it creates anything: <Case>' -ForEach @(
        @{ Case = 'empty';      Text = '' }
        @{ Case = 'null';       Text = $null }
        @{ Case = 'white space'; Text = "  `r`n`t" }
    ) {
        { New-PasManagedScript -Text $Text -SMSProvider 'cm01' -SiteCode 'MCM' } | Should -Throw '*script is empty*'
        Should -Invoke New-CMScript -ModuleName PivotsAndScripts -Times 0 -Exactly
    }
    It 'passes a creation error up and stores nothing' {
        $global:Fx.CreateThrows = 'The script name exists.'
        { New-PasManagedScript -Text 'param($A)' -SMSProvider 'cm01' -SiteCode 'MCM' } | Should -Throw '*script name exists*'
        @($global:Fx.Calls | Where-Object Cmd -in 'Update', 'Get', 'Remove').Count | Should -Be 0
    }
    It 'creates nothing under -WhatIf' {
        $r = New-PasManagedScript -Text 'param($A)' -SMSProvider 'cm01' -SiteCode 'MCM' -WhatIf
        $r | Should -BeNullOrEmpty
        Should -Invoke New-CMScript -ModuleName PivotsAndScripts -Times 0 -Exactly
        Should -Invoke Invoke-CimMethod -ModuleName PivotsAndScripts -Times 0 -Exactly
    }
    It 'sends hostile script text to the site as it is: <Case>' -ForEach @(
        @{ Case = 'quotes';      Text = "Write-Output 'it''s' `"x`"" }
        @{ Case = 'unicode';     Text = ('Write-Output ''caf' + [char]0xE9 + ' ' + [char]0x2018 + 'x' + [char]0x2019 + '''') }
        @{ Case = 'markup';      Text = '<# </ScriptParameters> #> Get-Date' }
    ) {
        New-PasManagedScript -Text $Text -SMSProvider 'cm01' -SiteCode 'MCM' | Out-Null
        ($global:Fx.Calls | Where-Object Cmd -eq 'New').Text | Should -BeExactly $Text
    }
    It 'stores a definition for a default value with markup characters' {
        New-PasManagedScript -Text 'param([string]$A = "<x>&""q""")' -SMSProvider 'cm01' -SiteCode 'MCM' | Out-Null
        $a = ($global:Fx.Calls | Where-Object Cmd -eq 'Update').Arguments
        @(ConvertFrom-PasParamsDefinition $a.ParamsDefinition)[0].Default | Should -Be '<x>&"q"'
    }
}

Describe 'Set-PasScriptApproval' {
    BeforeEach {
        $global:Fx = @{
            Calls = [System.Collections.Generic.List[object]]::new(); Item = $null; After = $null; ActionThrows = $null; GetThrows = $null
            Me = [Security.Principal.WindowsIdentity]::GetCurrent().Name; GetCount = 0
        }
        $global:Fx.Item = [pscustomobject]@{ ScriptGuid = $script:Guid; Feature = 0; Author = 'CONTOSO\other'; ApprovalState = 0; Approver = '' }
        $global:Fx.After = [pscustomobject]@{ ScriptGuid = $script:Guid; Feature = 0; Author = 'CONTOSO\other'; ApprovalState = 3; Approver = 'CONTOSO\me' }
        Mock Get-CMScript {
            $global:Fx.GetCount++
            $global:Fx.Calls.Add(@{ Cmd = 'Get'; ScriptGuid = $PesterBoundParameters.ScriptGuid; Fast = [bool]$PesterBoundParameters.Fast })
            if ($global:Fx.GetThrows) { throw $global:Fx.GetThrows }
            if ($global:Fx.GetCount -eq 1) { $global:Fx.Item } else { $global:Fx.After }
        } -ModuleName PivotsAndScripts
        Mock Approve-CMScript {
            $global:Fx.Calls.Add(@{ Cmd = 'Approve'; ScriptGuid = $PesterBoundParameters.ScriptGuid; Comment = $PesterBoundParameters.Comment })
            if ($global:Fx.ActionThrows) { throw $global:Fx.ActionThrows }
        } -ModuleName PivotsAndScripts
        Mock Deny-CMScript {
            $global:Fx.Calls.Add(@{ Cmd = 'Deny'; ScriptGuid = $PesterBoundParameters.ScriptGuid; Comment = $PesterBoundParameters.Comment })
            if ($global:Fx.ActionThrows) { throw $global:Fx.ActionThrows }
        } -ModuleName PivotsAndScripts
    }

    It 'approves, reads the result back and reports the state the site holds' {
        $r = Set-PasScriptApproval -ScriptGuid ([guid]$script:Guid) -Decision Approve -Comment 'ok'
        $r.ScriptGuid | Should -BeExactly $script:Guid
        $r.State | Should -Be 'Approved'
        $r.Approver | Should -Be 'CONTOSO\me'
        $c = @($global:Fx.Calls | Where-Object Cmd -eq 'Approve')
        $c.Count | Should -Be 1
        $c[0].ScriptGuid | Should -Be $script:Guid.ToLowerInvariant()
        $c[0].Comment | Should -Be 'ok'
        @($global:Fx.Calls | Where-Object Cmd -eq 'Deny').Count | Should -Be 0
    }
    It 'denies with the comment' {
        $global:Fx.After = [pscustomobject]@{ ScriptGuid = $script:Guid; Feature = 0; Author = 'x'; ApprovalState = 1; Approver = 'CONTOSO\me' }
        $r = Set-PasScriptApproval -ScriptGuid ([guid]$script:Guid) -Decision Deny -Comment 'not needed'
        $r.State | Should -Be 'Denied'
        $c = @($global:Fx.Calls | Where-Object Cmd -eq 'Deny')
        $c.Count | Should -Be 1
        $c[0].Comment | Should -Be 'not needed'
        @($global:Fx.Calls | Where-Object Cmd -eq 'Approve').Count | Should -Be 0
    }
    It 'reports the state the site holds, not the state the caller asked for' {
        $global:Fx.After = [pscustomobject]@{ ScriptGuid = $script:Guid; Feature = 0; Author = 'x'; ApprovalState = 0; Approver = '' }
        (Set-PasScriptApproval -ScriptGuid ([guid]$script:Guid) -Decision Approve).State | Should -Be 'Waiting for approval'
    }
    It 'passes an empty comment and a hostile comment through unchanged: <Case>' -ForEach @(
        @{ Case = 'empty';   Comment = '' }
        @{ Case = 'quotes';  Comment = "it's ""fine""" }
        @{ Case = 'unicode'; Comment = ('caf' + [char]0xE9 + ' ' + [char]0x2019) }
        @{ Case = 'script';  Comment = '$(calc); `n' }
    ) {
        Set-PasScriptApproval -ScriptGuid ([guid]$script:Guid) -Decision Approve -Comment $Comment | Out-Null
        ($global:Fx.Calls | Where-Object Cmd -eq 'Approve').Comment | Should -BeExactly $Comment
    }
    It 'refuses a script that belongs to a site feature, for both decisions' -ForEach @(@{ D = 'Approve' }, @{ D = 'Deny' }) {
        $global:Fx.Item = [pscustomobject]@{ ScriptGuid = $script:Guid; Feature = 1; Author = 'CM'; ApprovalState = 3 }
        { Set-PasScriptApproval -ScriptGuid ([guid]$script:Guid) -Decision $D } | Should -Throw '*belongs to a Configuration Manager feature*'
        Should -Invoke Approve-CMScript -ModuleName PivotsAndScripts -Times 0 -Exactly
        Should -Invoke Deny-CMScript -ModuleName PivotsAndScripts -Times 0 -Exactly
    }
    It 'refuses a script that does not exist' {
        $global:Fx.Item = $null
        { Set-PasScriptApproval -ScriptGuid ([guid]$script:Guid) -Decision Approve } | Should -Throw '*does not exist in Configuration Manager*'
        Should -Invoke Approve-CMScript -ModuleName PivotsAndScripts -Times 0 -Exactly
    }
    It 'refuses a decision other than Approve and Deny' {
        { Set-PasScriptApproval -ScriptGuid ([guid]$script:Guid) -Decision Delete } | Should -Throw
        Should -Invoke Get-CMScript -ModuleName PivotsAndScripts -Times 0 -Exactly
    }
    It 'passes a lookup error up instead of calling the script missing' {
        $global:Fx.GetThrows = 'The SMS Provider is unavailable.'
        { Set-PasScriptApproval -ScriptGuid ([guid]$script:Guid) -Decision Approve } | Should -Throw '*SMS Provider is unavailable*'
    }
    It 'explains a refused self-approval and keeps the provider message' {
        $global:Fx.Item = [pscustomobject]@{ ScriptGuid = $script:Guid; Feature = 0; Author = $global:Fx.Me.ToUpperInvariant(); ApprovalState = 0 }
        $global:Fx.ActionThrows = 'The SMS Provider reported an error.'
        $message = ''
        try { Set-PasScriptApproval -ScriptGuid ([guid]$script:Guid) -Decision Approve } catch { $message = $_.Exception.Message }
        $message | Should -BeLike '*second approver*'
        $message | Should -BeLike '*The SMS Provider reported an error*'
    }
    It 'rethrows the provider error when somebody else wrote the script' {
        $global:Fx.ActionThrows = 'The SMS Provider reported an error.'
        { Set-PasScriptApproval -ScriptGuid ([guid]$script:Guid) -Decision Approve } | Should -Throw 'The SMS Provider reported an error.'
    }
    It 'throws when the state cannot be read back after the decision' {
        $script:n = 0
        Mock Get-CMScript { $global:Fx.GetCount++; if ($global:Fx.GetCount -eq 1) { $global:Fx.Item } else { throw 'readback failed' } } -ModuleName PivotsAndScripts
        { Set-PasScriptApproval -ScriptGuid ([guid]$script:Guid) -Decision Approve } | Should -Throw '*readback failed*'
    }
    It 'changes nothing under -WhatIf' {
        $r = Set-PasScriptApproval -ScriptGuid ([guid]$script:Guid) -Decision Approve -WhatIf
        $r | Should -BeNullOrEmpty
        Should -Invoke Approve-CMScript -ModuleName PivotsAndScripts -Times 0 -Exactly
        Should -Invoke Deny-CMScript -ModuleName PivotsAndScripts -Times 0 -Exactly
    }
    It 'reads the script with the fast switch' {
        Set-PasScriptApproval -ScriptGuid ([guid]$script:Guid) -Decision Approve | Out-Null
        @($global:Fx.Calls | Where-Object { $_.Cmd -eq 'Get' -and $_.Fast }).Count | Should -Be 2
    }
}

Describe 'Remove-PasManagedScript' {
    BeforeEach {
        $global:Fx = @{ Calls = [System.Collections.Generic.List[object]]::new(); Item = $null; RemoveThrows = $null; GetThrows = $null }
        $global:Fx.Item = [pscustomobject]@{ ScriptGuid = $script:Guid; Feature = 0; Author = 'x'; ApprovalState = 3 }
        Mock Get-CMScript { if ($global:Fx.GetThrows) { throw $global:Fx.GetThrows }; $global:Fx.Item } -ModuleName PivotsAndScripts
        Mock Remove-CMScript {
            $global:Fx.Calls.Add(@{ Cmd = 'Remove'; Item = $PesterBoundParameters.InputObject; Force = [bool]$PesterBoundParameters.Force })
            if ($global:Fx.RemoveThrows) { throw $global:Fx.RemoveThrows }
        } -ModuleName PivotsAndScripts
    }
    It 'removes the script and reports it in the casing the site stores' {
        $r = Remove-PasManagedScript -ScriptGuid ([guid]$script:Guid.ToLowerInvariant()) -Confirm:$false
        $r.ScriptGuid | Should -BeExactly $script:Guid
        $r.State | Should -Be 'Removed'
        $c = @($global:Fx.Calls)
        $c.Count | Should -Be 1
        $c[0].Item.ScriptGuid | Should -Be $script:Guid
        $c[0].Force | Should -BeTrue
    }
    It 'refuses a script that belongs to a site feature' {
        $global:Fx.Item = [pscustomobject]@{ ScriptGuid = $script:Guid; Feature = 1 }
        { Remove-PasManagedScript -ScriptGuid ([guid]$script:Guid) -Confirm:$false } | Should -Throw '*belongs to a Configuration Manager feature*'
        Should -Invoke Remove-CMScript -ModuleName PivotsAndScripts -Times 0 -Exactly
    }
    It 'refuses a script that does not exist' {
        $global:Fx.Item = $null
        { Remove-PasManagedScript -ScriptGuid ([guid]$script:Guid) -Confirm:$false } | Should -Throw '*does not exist*'
        Should -Invoke Remove-CMScript -ModuleName PivotsAndScripts -Times 0 -Exactly
    }
    It 'reports no success when the removal fails' {
        $global:Fx.RemoveThrows = 'The script is in use.'
        $r = $null
        { $r = Remove-PasManagedScript -ScriptGuid ([guid]$script:Guid) -Confirm:$false } | Should -Throw '*script is in use*'
        $r | Should -BeNullOrEmpty
    }
    It 'passes a lookup error up' {
        $global:Fx.GetThrows = 'provider down'
        { Remove-PasManagedScript -ScriptGuid ([guid]$script:Guid) -Confirm:$false } | Should -Throw '*provider down*'
        Should -Invoke Remove-CMScript -ModuleName PivotsAndScripts -Times 0 -Exactly
    }
    It 'removes nothing under -WhatIf' {
        Remove-PasManagedScript -ScriptGuid ([guid]$script:Guid) -WhatIf | Should -BeNullOrEmpty
        Should -Invoke Remove-CMScript -ModuleName PivotsAndScripts -Times 0 -Exactly
    }
}

Describe 'Start-PasScriptRun' {
    BeforeEach {
        $global:Fx = @{ Calls = [System.Collections.Generic.List[object]]::new(); Devices = $null; Started = @(); InvokeThrows = $null; QueryThrows = $null }
        Mock Invoke-CMWmiQuery {
            $global:Fx.Calls.Add(@{ Cmd = 'Query'; Query = $PesterBoundParameters.Query; Option = [string]$PesterBoundParameters.Option })
            if ($global:Fx.QueryThrows) { throw $global:Fx.QueryThrows }
            if ($null -ne $global:Fx.Devices) { $global:Fx.Devices }
            else { foreach ($id in ([regex]::Match($PesterBoundParameters.Query, 'IN \((.*)\)').Groups[1].Value -split ',')) { [pscustomobject]@{ ResourceID = [int]$id } } }
        } -ModuleName PivotsAndScripts
        Mock Invoke-CMScript {
            $global:Fx.Calls.Add(@{ Cmd = 'Invoke'; ScriptGuid = $PesterBoundParameters.ScriptGuid; CollectionId = $PesterBoundParameters.CollectionId; Devices = @($PesterBoundParameters.Device).Count; Params = $PesterBoundParameters.ScriptParameter; PassThru = [bool]$PesterBoundParameters.PassThru })
            if ($global:Fx.InvokeThrows) { throw $global:Fx.InvokeThrows }
            $global:Fx.Started
        } -ModuleName PivotsAndScripts
        $global:Fx.Started = @([pscustomobject]@{ OperationID = 555; ReturnValue = 0 })
    }
    It 'sends one Run Scripts request for a collection and one for a device list' {
        $ops = @(Start-PasScriptRun -ScriptGuid ([guid]::NewGuid()) -CollectionId 'SMS00001')
        $ops.Count | Should -Be 1
        $calls = $global:Fx.Calls
        @($calls | Where-Object Cmd -eq 'Invoke')[0].CollectionId | Should -Be 'SMS00001'
        @($calls | Where-Object Cmd -eq 'Query').Count | Should -Be 0
        $global:Fx.Calls.Clear()
        $ops = @(Start-PasScriptRun -ScriptGuid ([guid]::NewGuid()) -ResourceIds (1..1201))
        @($global:Fx.Calls | Where-Object Cmd -eq 'Invoke').Count | Should -Be 1
        @($global:Fx.Calls | Where-Object Cmd -eq 'Invoke')[0].Devices | Should -Be 1201
        @($global:Fx.Calls | Where-Object Cmd -eq 'Query').Count | Should -Be 1
    }
    It 'sends the GUID text, the arguments and the pass-through switch' {
        Start-PasScriptRun -ScriptGuid ([guid]$script:Guid) -Arguments @{ Name = 'x'; Count = 3 } -CollectionId 'SMS00001' | Out-Null
        $i = $global:Fx.Calls | Where-Object Cmd -eq 'Invoke'
        $i.ScriptGuid | Should -Be $script:Guid.ToLowerInvariant()
        $i.Params.Name | Should -Be 'x'
        $i.Params.Count | Should -Be 3
        $i.PassThru | Should -BeTrue
    }
    It 'looks the devices up fast, by ResourceID, in one query' {
        Start-PasScriptRun -ScriptGuid ([guid]::NewGuid()) -ResourceIds @(16777221, 16777222) | Out-Null
        $q = $global:Fx.Calls | Where-Object Cmd -eq 'Query'
        $q.Query | Should -Be 'SELECT * FROM SMS_CombinedDeviceResources WHERE ResourceID IN (16777221,16777222)'
        $q.Option | Should -Be 'Fast'
    }
    It 'refuses a run when none of the devices exists any more' {
        $global:Fx.Devices = @()
        { Start-PasScriptRun -ScriptGuid ([guid]::NewGuid()) -ResourceIds @(1) } | Should -Throw '*None of the targets exists*'
        Should -Invoke Invoke-CMScript -ModuleName PivotsAndScripts -Times 0 -Exactly
    }
    It 'refuses a run without a collection and without devices' {
        { Start-PasScriptRun -ScriptGuid ([guid]::NewGuid()) } | Should -Throw '*at least one device*'
        Should -Invoke Invoke-CMScript -ModuleName PivotsAndScripts -Times 0 -Exactly
        Should -Invoke Invoke-CMWmiQuery -ModuleName PivotsAndScripts -Times 0 -Exactly
    }
    It 'refuses a collection ID that is not an ID' {
        { Start-PasScriptRun -ScriptGuid ([guid]::NewGuid()) -CollectionId "SMS00001' OR 1=1" } | Should -Throw "*is not a collection ID*"
        Should -Invoke Invoke-CMScript -ModuleName PivotsAndScripts -Times 0 -Exactly
    }
    It 'refuses a device ID that is not a number' {
        { Start-PasScriptRun -ScriptGuid ([guid]::NewGuid()) -ResourceIds @('1) OR (1=1') } | Should -Throw
        Should -Invoke Invoke-CMWmiQuery -ModuleName PivotsAndScripts -Times 0 -Exactly
    }
    It 'reads the operation ID from <Case>' -ForEach @(
        @{ Case = 'OperationID';       Item = [pscustomobject]@{ OperationID = 7 };         Expected = 7 }
        @{ Case = 'ClientOperationID'; Item = [pscustomobject]@{ ClientOperationID = '8' }; Expected = 8 }
        @{ Case = 'ID';                Item = [pscustomobject]@{ ID = 9 };                  Expected = 9 }
        @{ Case = 'the first usable name'; Item = [pscustomobject]@{ OperationID = 'abc'; ClientOperationID = 11 }; Expected = 11 }
        @{ Case = 'a large ID';        Item = [pscustomobject]@{ OperationID = 16777216123 }; Expected = 16777216123 }
    ) {
        $global:Fx.Started = @($Item)
        $r = @(Start-PasScriptRun -ScriptGuid ([guid]::NewGuid()) -CollectionId 'SMS00001')
        $r[0].OperationID | Should -Be $Expected
        $r[0].OperationID | Should -BeOfType [long]
    }
    It 'returns an operation ID of null when the answer holds none: <Case>' -ForEach @(
        @{ Case = 'no ID property';   Item = [pscustomobject]@{ Other = 1 } }
        @{ Case = 'a text ID';        Item = [pscustomobject]@{ OperationID = 'x1' } }
        @{ Case = 'a negative ID';    Item = [pscustomobject]@{ OperationID = -5 } }
        @{ Case = 'an empty ID';      Item = [pscustomobject]@{ OperationID = '' } }
    ) {
        $global:Fx.Started = @($Item)
        $r = @(Start-PasScriptRun -ScriptGuid ([guid]::NewGuid()) -CollectionId 'SMS00001')
        $r.Count | Should -Be 1
        $r[0].OperationID | Should -BeNullOrEmpty
    }
    It 'keeps the return value, or null when there is none' {
        $global:Fx.Started = @([pscustomobject]@{ OperationID = 1; ReturnValue = 5 }, [pscustomobject]@{ OperationID = 2 })
        $r = @(Start-PasScriptRun -ScriptGuid ([guid]::NewGuid()) -CollectionId 'SMS00001')
        $r.Count | Should -Be 2
        $r[0].ReturnValue | Should -Be 5
        $r[1].ReturnValue | Should -BeNullOrEmpty
    }
    It 'returns nothing when the site answers with nothing' {
        $global:Fx.Started = @()
        @(Start-PasScriptRun -ScriptGuid ([guid]::NewGuid()) -CollectionId 'SMS00001').Count | Should -Be 0
    }
    It 'returns a plain object that ConvertTo-Json can serialize' {
        $r = Start-PasScriptRun -ScriptGuid ([guid]::NewGuid()) -CollectionId 'SMS00001'
        { ConvertTo-Json -InputObject $r -Depth 5 } | Should -Not -Throw
    }
    It 'passes a start error up' {
        $global:Fx.InvokeThrows = 'Access is denied.'
        { Start-PasScriptRun -ScriptGuid ([guid]::NewGuid()) -CollectionId 'SMS00001' } | Should -Throw '*Access is denied*'
    }
    It 'passes a device query error up and starts nothing' {
        $global:Fx.QueryThrows = 'WMI error'
        { Start-PasScriptRun -ScriptGuid ([guid]::NewGuid()) -ResourceIds @(1) } | Should -Throw '*WMI error*'
        Should -Invoke Invoke-CMScript -ModuleName PivotsAndScripts -Times 0 -Exactly
    }
    It 'starts nothing under -WhatIf' {
        Start-PasScriptRun -ScriptGuid ([guid]::NewGuid()) -CollectionId 'SMS00001' -WhatIf | Should -BeNullOrEmpty
        Start-PasScriptRun -ScriptGuid ([guid]::NewGuid()) -ResourceIds @(1) -WhatIf | Should -BeNullOrEmpty
        Should -Invoke Invoke-CMScript -ModuleName PivotsAndScripts -Times 0 -Exactly
    }
}

Describe 'Write-PasJson' {
    BeforeEach { $script:dir = Join-Path $TestDrive ('json-' + [guid]::NewGuid().ToString('N')) }

    It 'overwrites atomically and keeps an empty array as JSON' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('pas-tests-' + [guid]::NewGuid().ToString('N'))
        $path = Join-Path $root 'session.json'
        try {
            Write-PasJson $path @{Results = @(); ID = 'first' }
            Write-PasJson $path @{Results = @([pscustomobject]@{Device = 'PC-1' }); ID = 'second' }
            $saved = [IO.File]::ReadAllText($path) | ConvertFrom-Json
            $saved.ID | Should -Be 'second'
            $saved.Results[0].Device | Should -Be 'PC-1'
            Write-PasJson $path @()
            ([IO.File]::ReadAllText($path) -replace '\s', '') | Should -Be '[]'
            Write-PasJson $path @([pscustomobject]@{Device = 'PC-1' })
            ([IO.File]::ReadAllText($path) -replace '\s', '') | Should -Be '[{"Device":"PC-1"}]'
        } finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force } }
    }
    It 'creates every missing folder of the path' {
        $path = Join-Path $script:dir 'a\b\c\file.json'
        Write-PasJson $path @{ A = 1 }
        Test-Path -LiteralPath $path | Should -BeTrue
    }
    It 'leaves only the target file behind, for a new file and for an overwrite' {
        $path = Join-Path $script:dir 'only.json'
        Write-PasJson $path @{ A = 1 }
        Write-PasJson $path @{ A = 2 }
        @(Get-ChildItem -LiteralPath $script:dir -Force | ForEach-Object Name) | Should -Be @('only.json')
    }
    It 'writes UTF-8 without a byte order mark and keeps non-ASCII text' {
        $path = Join-Path $script:dir 'u.json'
        $text = 'caf' + [char]0xE9 + ' ' + [char]0x20AC + ' ' + [char]0x2018
        Write-PasJson $path @{ T = $text }
        $bytes = [IO.File]::ReadAllBytes($path)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) | Should -BeFalse
        ([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json).T | Should -Be $text
    }
    It 'keeps nested values to 40 levels' {
        $path = Join-Path $script:dir 'deep.json'
        $v = @{ Leaf = 'end' }
        1..30 | ForEach-Object { $v = @{ Child = $v } }
        Write-PasJson $path $v
        [IO.File]::ReadAllText($path) | Should -Match '"Leaf":\s*"end"'
    }
    It 'writes null as JSON null' {
        $path = Join-Path $script:dir 'null.json'
        Write-PasJson $path $null
        ([IO.File]::ReadAllText($path)).Trim() | Should -Be 'null'
    }
    It 'refuses a path that is <Case> and writes nothing' -ForEach @(
        @{ Case = 'empty'; Path = '' }
        @{ Case = 'null';  Path = $null }
    ) {
        { Write-PasJson $Path @{ A = 1 } } | Should -Throw
    }
    It 'leaves the old file and no temporary file when the folder cannot take the new one: <Case>' -ForEach @(
        @{ Case = 'the target is a folder' }
    ) {
        $path = Join-Path $script:dir 'folder.json'
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        { Write-PasJson $path @{ A = 1 } } | Should -Throw
        @(Get-ChildItem -LiteralPath $script:dir -Force | ForEach-Object Name) | Should -Be @('folder.json')
    }
    It 'keeps the old content and removes the temporary file when the old file is read-only' {
        $path = Join-Path $script:dir 'ro.json'
        Write-PasJson $path @{ A = 'old' }
        Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $true
        try {
            { Write-PasJson $path @{ A = 'new' } } | Should -Throw
            ([IO.File]::ReadAllText($path) | ConvertFrom-Json).A | Should -Be 'old'
            @(Get-ChildItem -LiteralPath $script:dir -Force | ForEach-Object Name) | Should -Be @('ro.json')
        }
        finally { Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $false }
    }
    It 'writes nothing under -WhatIf' {
        $path = Join-Path $script:dir 'whatif.json'
        Write-PasJson $path @{ A = 1 } -WhatIf
        Test-Path -LiteralPath $path | Should -BeFalse
        Test-Path -LiteralPath $script:dir | Should -BeFalse
    }
}
