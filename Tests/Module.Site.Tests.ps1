#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }
# Read side of the module: the connection check, target resolution and the CIM reads of site scripts and
# their run status. ConfigMgr cmdlets are global stubs (TestHelpers.ps1) that Pester mocks. A mock body
# cannot see test variables, so fixtures pass through $global:Fx and arguments are read from
# $PesterBoundParameters.

BeforeAll {
    . "$PSScriptRoot\TestHelpers.ps1"
    Import-AppModule
    Import-SuiteCommonGlobal
    $script:Stubs = New-CmStub -Name $script:CmStubNames
    $script:Mod = 'PivotsAndScripts'
    # The CIM cmdlets have typed parameters, so a mock needs a real session object. A local DCOM session opens no network connection.
    $script:Session = [Microsoft.Management.Infrastructure.CimSession]::Create('localhost', (New-CimSessionOption -Protocol Dcom))
}

AfterAll {
    if ($script:Session) { $script:Session.Dispose() }
    Remove-CmStub -Name $script:CmStubNames
    Remove-Variable -Name Fx -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Assert-PasConnection' {
    BeforeEach {
        Mock Connect-CMSite { $true } -ModuleName PivotsAndScripts
        Mock Get-CMSite { [pscustomobject]@{ SiteCode = 'MCM' } } -ModuleName PivotsAndScripts
    }
    It 'connects, checks the site and returns nothing' {
        Assert-PasConnection -SiteCode 'MCM' -SMSProvider 'cm01.contoso.com' | Should -BeNullOrEmpty
        Should -Invoke Connect-CMSite -ModuleName PivotsAndScripts -Times 1 -Exactly -ParameterFilter { $SiteCode -eq 'MCM' -and $SMSProvider -eq 'cm01.contoso.com' }
        Should -Invoke Get-CMSite -ModuleName PivotsAndScripts -Times 1 -Exactly -ParameterFilter { $SiteCode -eq 'MCM' }
    }
    It 'refuses the site code <Case> before it connects' -ForEach @(
        @{ Case = 'empty';                Code = '' }
        @{ Case = 'null';                 Code = $null }
        @{ Case = 'two characters';       Code = 'MC' }
        @{ Case = 'four characters';      Code = 'MCM1' }
        @{ Case = 'with a space';         Code = 'M M' }
        @{ Case = 'with a dash';          Code = 'M-M' }
        @{ Case = 'with a wildcard';      Code = 'M*M' }
        @{ Case = 'with a trailing line break'; Code = "MCM`n" }
        @{ Case = 'with an accent';       Code = ('M' + [char]0xC7 + 'M') }
        @{ Case = 'with a quote';         Code = "M'M" }
    ) {
        { Assert-PasConnection -SiteCode $Code -SMSProvider 'cm01' } | Should -Throw '*three-character site code*'
        Should -Invoke Connect-CMSite -ModuleName PivotsAndScripts -Times 0 -Exactly
    }
    It 'refuses the provider <Case> before it connects' -ForEach @(
        @{ Case = 'empty';            Name = '' }
        @{ Case = 'null';             Name = $null }
        @{ Case = 'a URL';            Name = 'https://cm01.contoso.com' }
        @{ Case = 'with a path';      Name = 'cm01/AdminService' }
        @{ Case = 'with a port';      Name = 'cm01:443' }
        @{ Case = 'with a space';     Name = 'cm 01' }
        @{ Case = 'starting with a dot'; Name = '.cm01' }
        @{ Case = 'starting with a dash'; Name = '-cm01' }
        @{ Case = 'with a trailing line break'; Name = "cm01`n" }
        @{ Case = 'with a backslash'; Name = 'cm01\x' }
        @{ Case = 'with a user part'; Name = 'user@cm01' }
    ) {
        { Assert-PasConnection -SiteCode 'MCM' -SMSProvider $Name } | Should -Throw '*SMS Provider hostname*'
        Should -Invoke Connect-CMSite -ModuleName PivotsAndScripts -Times 0 -Exactly
    }
    It 'accepts the provider <Name>' -ForEach @(
        @{ Name = 'cm01' }, @{ Name = 'cm01.contoso.com' }, @{ Name = '10.0.0.5' }, @{ Name = 'CM-01.lab-1.local' }
    ) {
        { Assert-PasConnection -SiteCode 'abc' -SMSProvider $Name } | Should -Not -Throw
    }
    It 'throws when the connection fails and does not look up the site' {
        Mock Connect-CMSite { $false } -ModuleName PivotsAndScripts
        { Assert-PasConnection -SiteCode 'MCM' -SMSProvider 'cm01' } | Should -Throw '*connection failed*'
        Should -Invoke Get-CMSite -ModuleName PivotsAndScripts -Times 0 -Exactly
    }
    It 'throws when the provider does not host the site code: <Count> sites' -ForEach @(
        @{ Count = 0 }, @{ Count = 2 }
    ) {
        $global:Fx = $Count
        Mock Get-CMSite { for ($i = 0; $i -lt $global:Fx; $i++) { [pscustomobject]@{ SiteCode = 'MCM' } } } -ModuleName PivotsAndScripts
        { Assert-PasConnection -SiteCode 'MCM' -SMSProvider 'cm01' } | Should -Throw '*Site MCM was not found on SMS Provider cm01*'
    }
    It 'says the check failed, and writes the reason to the log file, when the site lookup fails' {
        Mock Get-CMSite { Write-Error 'Access is denied to the SMS Provider.' -ErrorAction Continue } -ModuleName PivotsAndScripts
        $message = $null
        $log = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.log')
        Set-PasLogPath $log
        try { Assert-PasConnection -SiteCode 'MCM' -SMSProvider 'cm01' } catch { $message = $_.Exception.Message } finally { Set-PasLogPath '' }
        $message | Should -Be 'Site MCM could not be checked on SMS Provider cm01. The log file has the details.'
        $message | Should -Not -BeLike '*was not found*'
        $message | Should -Not -BeLike '*Access is denied*'
        (Get-Content -LiteralPath $log -Raw) | Should -Match 'Access is denied to the SMS Provider'
    }
    It 'passes a connection error up' {
        Mock Connect-CMSite { throw 'boom from Connect-CMSite' } -ModuleName PivotsAndScripts
        { Assert-PasConnection -SiteCode 'MCM' -SMSProvider 'cm01' } | Should -Throw '*boom from Connect-CMSite*'
    }
}

Describe 'Resolve-PasTargets' {
    BeforeEach {
        $global:Fx = @{ Devices = @{}; Collections = @(); Calls = [System.Collections.Generic.List[object]]::new(); Throw = $null }
        Mock Get-CMDeviceCollection {
            $global:Fx.Calls.Add(@{ Cmd = 'Collection'; Id = $PesterBoundParameters.Id; Name = $PesterBoundParameters.Name })
            if ($global:Fx.Throw) { throw $global:Fx.Throw }
            if ($PesterBoundParameters.ContainsKey('Id')) { $global:Fx.Collections | Where-Object { $_.CollectionID -eq $PesterBoundParameters.Id } }
            else {
                # Like the real cmdlet: -Name is a wildcard pattern.
                $global:Fx.Collections | Where-Object { $_.Name -like $PesterBoundParameters.Name }
            }
        } -ModuleName PivotsAndScripts
        Mock Get-CMDevice {
            $global:Fx.Calls.Add(@{ Cmd = 'Device'; Name = $PesterBoundParameters.Name; CollectionId = $PesterBoundParameters.CollectionId; NoWildcard = [bool]$PesterBoundParameters.DisableWildcardHandling; Fast = [bool]$PesterBoundParameters.Fast })
            if ($global:Fx.Throw) { throw $global:Fx.Throw }
            # Like the real cmdlet, a lookup with no match returns nothing (not a null object).
            if ($PesterBoundParameters.ContainsKey('CollectionId')) { if ($global:Fx.Devices.ContainsKey($PesterBoundParameters.CollectionId)) { $global:Fx.Devices[$PesterBoundParameters.CollectionId] } }
            else {
                $n = $PesterBoundParameters.Name
                if ($PesterBoundParameters.DisableWildcardHandling) { if ($global:Fx.Devices.ContainsKey($n)) { $global:Fx.Devices[$n] } } else { $global:Fx.Devices.Keys | Where-Object { $_ -like $n } | ForEach-Object { $global:Fx.Devices[$_] } }
            }
        } -ModuleName PivotsAndScripts
    }
    It 'deduplicates by ResourceID and tracks unknown names' {
        $global:Fx.Devices['PC-1'] = [pscustomobject]@{ Name = 'PC-1'; ResourceID = 17; IsClient = $true; IsActive = $true }
        $global:Fx.Devices['PC-1b'] = [pscustomobject]@{ Name = 'PC-1'; ResourceID = 17; IsClient = $true; IsActive = $true }
        $snapshot = Resolve-PasTargets -Kind List -InputText "PC-1`nPC-1`nmissing"
        $snapshot.Targets.Count | Should -Be 1
        $snapshot.Unknown.Count | Should -Be 1
        $snapshot = Resolve-PasTargets -Kind Pattern -InputText 'PC-1*'
        $snapshot.Targets.Count | Should -Be 1
    }
    It 'resolves a single collection by ID and by exact name' {
        $global:Fx.Collections = @([pscustomobject]@{ Name = 'All Systems'; CollectionID = 'SMS00001' })
        $global:Fx.Devices['SMS00001'] = [pscustomobject]@{ Name = 'PC-1'; ResourceID = 17; IsClient = $true; IsActive = $true }
        (Resolve-PasTargets -Kind Collection -InputText 'SMS00001').Targets.Count | Should -Be 1
        (Resolve-PasTargets -Kind Collection -InputText 'All Systems').Targets.Count | Should -Be 1
    }
    It 'treats an eight-character collection name as a name' {
        $global:Fx.Collections = @([pscustomobject]@{ Name = 'Desktops'; CollectionID = 'MCM00012' })
        $global:Fx.Devices['MCM00012'] = [pscustomobject]@{ Name = 'PC-2'; ResourceID = 18; IsClient = $true; IsActive = $true }
        (Resolve-PasTargets -Kind Collection -InputText 'Desktops').Targets.Count | Should -Be 1
        $global:Fx.Calls | Where-Object { $_.Cmd -eq 'Collection' -and $_.Id } | Should -BeNullOrEmpty
    }
    It 'looks a trimmed collection ID up by ID only and returns the ID of the collection' {
        $global:Fx.Collections = @([pscustomobject]@{ Name = 'All Systems'; CollectionID = 'SMS00001' })
        $global:Fx.Devices['SMS00001'] = [pscustomobject]@{ Name = 'PC-1'; ResourceID = 17; IsClient = $true; IsActive = $true }
        $r = Resolve-PasTargets -Kind Collection -InputText ' sms00001 '
        $r.CollectionID | Should -Be 'SMS00001'
        @($global:Fx.Calls | Where-Object { $_.Cmd -eq 'Collection' -and $_.Id -eq 'sms00001' }).Count | Should -Be 1
        @($global:Fx.Calls | Where-Object { $_.Cmd -eq 'Collection' -and $_.Name }).Count | Should -Be 0
    }
    It 'falls back to the name when an ID-shaped text matches no collection ID' {
        $global:Fx.Collections = @([pscustomobject]@{ Name = 'DEFACED1'; CollectionID = 'MCM00099' })
        $global:Fx.Devices['MCM00099'] = [pscustomobject]@{ Name = 'PC-9'; ResourceID = 19; IsClient = $true; IsActive = $true }
        $r = Resolve-PasTargets -Kind Collection -InputText 'DEFACED1'
        $r.CollectionID | Should -Be 'MCM00099'
        @($global:Fx.Calls | Where-Object { $_.Cmd -eq 'Collection' -and $_.Id }).Count | Should -Be 1
    }
    It 'keeps wildcard characters of a collection name literal and takes only the exact match' {
        $global:Fx.Collections = @(
            [pscustomobject]@{ Name = 'Servers [Prod]'; CollectionID = 'MCM00001' }
            [pscustomobject]@{ Name = 'Servers P';      CollectionID = 'MCM00002' }
            [pscustomobject]@{ Name = 'Servers [Prod] extra'; CollectionID = 'MCM00003' })
        $global:Fx.Devices['MCM00001'] = [pscustomobject]@{ Name = 'S1'; ResourceID = 5; IsClient = $true; IsActive = $true }
        $r = Resolve-PasTargets -Kind Collection -InputText 'Servers [Prod]'
        $r.CollectionID | Should -Be 'MCM00001'
        $sent = ($global:Fx.Calls | Where-Object { $_.Cmd -eq 'Collection' } | Select-Object -Last 1).Name
        $sent | Should -Be ([Management.Automation.WildcardPattern]::Escape('Servers [Prod]'))
    }
    It 'matches the collection name without regard to case' {
        $global:Fx.Collections = @([pscustomobject]@{ Name = 'All Systems'; CollectionID = 'SMS00001' })
        (Resolve-PasTargets -Kind Collection -InputText 'all systems').CollectionID | Should -Be 'SMS00001'
    }
    It 'refuses a collection name that matches <Count> collections' -ForEach @(@{ Count = 0 }, @{ Count = 2 }) {
        $global:Fx.Collections = @(for ($i = 1; $i -le $Count; $i++) { [pscustomobject]@{ Name = 'Dup'; CollectionID = ('MCM0000' + $i) } })
        { Resolve-PasTargets -Kind Collection -InputText 'Dup' } | Should -Throw "*Collection 'Dup' must resolve to exactly one device collection*"
        @($global:Fx.Calls | Where-Object { $_.Cmd -eq 'Device' }).Count | Should -Be 0
    }
    It 'returns an empty snapshot for a collection without members' {
        $global:Fx.Collections = @([pscustomobject]@{ Name = 'Empty'; CollectionID = 'MCM00005' })
        $r = Resolve-PasTargets -Kind Collection -InputText 'Empty'
        @($r.Targets).Count | Should -Be 0
        $r.CollectionID | Should -Be 'MCM00005'
    }
    It 'refuses a missing target for every kind: <Kind> / <Case>' -ForEach @(
        foreach ($k in 'Collection', 'Device', 'Pattern', 'List') { foreach ($c in @(@{ Case = 'empty'; Text = '' }, @{ Case = 'null'; Text = $null }, @{ Case = 'white space'; Text = "  `r`n " })) { @{ Kind = $k; Case = $c.Case; Text = $c.Text } } }
    ) {
        { Resolve-PasTargets -Kind $Kind -InputText $Text } | Should -Throw '*Enter a target*'
        $global:Fx.Calls.Count | Should -Be 0
    }
    It 'refuses a kind it does not know' {
        { Resolve-PasTargets -Kind 'Everything' -InputText 'x' } | Should -Throw
    }
    It 'resolves one device by exact name with wildcard handling off' {
        $global:Fx.Devices['PC-*'] = [pscustomobject]@{ Name = 'PC-*'; ResourceID = 40; IsClient = $true; IsActive = $true }
        $global:Fx.Devices['PC-1'] = [pscustomobject]@{ Name = 'PC-1'; ResourceID = 41; IsClient = $true; IsActive = $true }
        $r = Resolve-PasTargets -Kind Device -InputText '  PC-*  '
        @($r.Targets).Count | Should -Be 1
        $r.Targets[0].ResourceID | Should -Be 40
        ($global:Fx.Calls | Where-Object { $_.Cmd -eq 'Device' }).NoWildcard | Should -BeTrue
    }
    It 'does not split a device name at a comma' {
        Resolve-PasTargets -Kind Device -InputText 'A,B' | Out-Null
        @($global:Fx.Calls | Where-Object { $_.Cmd -eq 'Device' }).Count | Should -Be 1
        ($global:Fx.Calls | Where-Object { $_.Cmd -eq 'Device' }).Name | Should -Be 'A,B'
    }
    It 'resolves a pattern with wildcard handling on, and trims the text' {
        $global:Fx.Devices['LAB-01'] = [pscustomobject]@{ Name = 'LAB-01'; ResourceID = 50; IsClient = $true; IsActive = $false }
        $global:Fx.Devices['LAB-02'] = [pscustomobject]@{ Name = 'LAB-02'; ResourceID = 51; IsClient = $false; IsActive = $false }
        $r = Resolve-PasTargets -Kind Pattern -InputText ' LAB-* '
        @($r.Targets).Count | Should -Be 2
        ($global:Fx.Calls | Where-Object { $_.Cmd -eq 'Device' }).NoWildcard | Should -BeFalse
        ($global:Fx.Calls | Where-Object { $_.Cmd -eq 'Device' }).Name | Should -Be 'LAB-*'
    }
    It 'splits a list at commas, semicolons and line breaks and drops empty entries' {
        foreach ($n in 'A', 'B', 'C', 'D') { $global:Fx.Devices[$n] = [pscustomobject]@{ Name = $n; ResourceID = [int][char]$n; IsClient = $true; IsActive = $true } }
        $r = Resolve-PasTargets -Kind List -InputText "A, B;C`r`n`r`n;,D ,"
        @($r.Targets | ForEach-Object Device) | Should -Be @('A', 'B', 'C', 'D')
        @($r.Unknown).Count | Should -Be 0
    }
    It 'asks once per distinct name, without regard to case' {
        $global:Fx.Devices['pc-1'] = [pscustomobject]@{ Name = 'pc-1'; ResourceID = 7; IsClient = $true; IsActive = $true }
        Resolve-PasTargets -Kind List -InputText 'PC-1, pc-1, Pc-1' | Out-Null
        @($global:Fx.Calls | Where-Object { $_.Cmd -eq 'Device' }).Count | Should -Be 1
    }
    It 'keeps a wildcard character in a list entry literal' {
        $r = Resolve-PasTargets -Kind List -InputText 'PC-*'
        @($r.Unknown) | Should -Be @('PC-*')
        ($global:Fx.Calls | Where-Object { $_.Cmd -eq 'Device' }).NoWildcard | Should -BeTrue
    }
    It 'passes hostile names through as data: <Name>' -ForEach @(
        @{ Name = "O'Brien" }, @{ Name = 'a%b' }, @{ Name = '& Remove-Item C:\ #' }, @{ Name = ('caf' + [char]0xE9) }, @{ Name = '$(calc)' }
    ) {
        $r = Resolve-PasTargets -Kind List -InputText $Name
        @($r.Unknown) | Should -Be @($Name)
        ($global:Fx.Calls | Where-Object { $_.Cmd -eq 'Device' }).Name | Should -BeExactly $Name
    }
    It 'maps a device to the snapshot fields and sorts by ResourceID' {
        $global:Fx.Devices['B'] = [pscustomobject]@{ Name = 'B'; ResourceID = 2046820353; IsClient = $false; IsActive = $false }
        $global:Fx.Devices['A'] = [pscustomobject]@{ Name = 'A'; ResourceID = 16777221; IsClient = 1; IsActive = 0 }
        $r = Resolve-PasTargets -Kind List -InputText 'B,A'
        @($r.Targets | ForEach-Object ResourceID) | Should -Be @(16777221, 2046820353)
        $r.Targets[0].Device | Should -BeOfType [string]
        $r.Targets[0].ResourceID | Should -BeOfType [int]
        $r.Targets[0].Client | Should -BeOfType [bool]
        $r.Targets[0].Client | Should -BeTrue
        $r.Targets[0].Active | Should -BeFalse
        $r.CollectionID | Should -Be ''
        [DateTime]::Parse($r.ResolvedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).Kind | Should -Be 'Utc'
    }
    It 'drops a device without a usable ResourceID' -ForEach @(@{ Id = 0 }, @{ Id = -4 }) {
        $global:Fx.Devices['Z'] = [pscustomobject]@{ Name = 'Z'; ResourceID = $Id; IsClient = $true; IsActive = $true }
        @((Resolve-PasTargets -Kind List -InputText 'Z').Targets).Count | Should -Be 0
    }
    It 'passes a provider error up and does not call it a missing target' {
        $global:Fx.Throw = 'The SMS Provider is unavailable.'
        { Resolve-PasTargets -Kind List -InputText 'A' } | Should -Throw '*SMS Provider is unavailable*'
        { Resolve-PasTargets -Kind Collection -InputText 'SMS00001' } | Should -Throw '*SMS Provider is unavailable*'
        { Resolve-PasTargets -Kind Pattern -InputText 'A*' } | Should -Throw '*SMS Provider is unavailable*'
    }
    It 'resolves a list of 1500 names with one lookup per distinct name' {
        1..1500 | ForEach-Object { $global:Fx.Devices["PC$_"] = [pscustomobject]@{ Name = "PC$_"; ResourceID = $_; IsClient = $true; IsActive = $true } }
        $r = Resolve-PasTargets -Kind List -InputText ((1..1500 | ForEach-Object { "PC$_" }) -join "`n")
        @($r.Targets).Count | Should -Be 1500
        @($global:Fx.Calls | Where-Object { $_.Cmd -eq 'Device' }).Count | Should -Be 1500
    }
    It 'asks for fast results only' {
        $global:Fx.Devices['A'] = [pscustomobject]@{ Name = 'A'; ResourceID = 1; IsClient = $true; IsActive = $true }
        Resolve-PasTargets -Kind Device -InputText 'A' | Out-Null
        ($global:Fx.Calls | Where-Object { $_.Cmd -eq 'Device' }).Fast | Should -BeTrue
    }
}

Describe 'New-PasCimSession' {
    It 'opens a DCOM session to the provider and stops on error' {
        Mock New-CimSession { [pscustomobject]@{ ComputerName = $PesterBoundParameters.ComputerName; Option = $PesterBoundParameters.SessionOption.GetType().Name; Action = [string]$PesterBoundParameters.ErrorAction } } -ModuleName PivotsAndScripts
        $s = New-PasCimSession 'cm01.contoso.com'
        $s.ComputerName | Should -Be 'cm01.contoso.com'
        $s.Option | Should -Be 'DComSessionOptions'
        $s.Action | Should -Be 'Stop'
    }
    It 'passes a connection error up' {
        Mock New-CimSession { throw 'RPC server unavailable' } -ModuleName PivotsAndScripts
        { New-PasCimSession 'cm01' } | Should -Throw '*RPC server unavailable*'
    }
}

Describe 'Get-PasSiteScript' {
    BeforeEach {
        $global:Fx = @{ Items = @(); Calls = [System.Collections.Generic.List[object]]::new(); Throw = $null; Session = $script:Session }
        Mock New-PasCimSession { $global:Fx.Session } -ModuleName PivotsAndScripts
        Mock Remove-CimSession { $global:Fx.Calls.Add(@{ Cmd = 'Remove' }) } -ModuleName PivotsAndScripts
        Mock Get-CimInstance {
            $global:Fx.Calls.Add(@{ Cmd = 'Get'; Namespace = $PesterBoundParameters.Namespace; Class = $PesterBoundParameters.ClassName; Filter = $PesterBoundParameters.Filter; Piped = $PesterBoundParameters.ContainsKey('InputObject') })
            if ($global:Fx.Throw) { throw $global:Fx.Throw }
            if ($PesterBoundParameters.ContainsKey('InputObject')) { $PesterBoundParameters.InputObject } else { $global:Fx.Items }
        } -ModuleName PivotsAndScripts
    }
    It 'returns the script with its parameters and removes the session' {
        $xml = ConvertTo-PasParamsDefinition @(Get-PasParameters 'param([Parameter(Mandatory)][string]$Name="x",[int]$N=3)')
        $global:Fx.Items = @((New-CimFixture 'SMS_Scripts' @{ ScriptGuid = '685E0A08-8ACE-4948-BE8F-9D0416852976'; ScriptName = 'S1'; ApprovalState = 3; Author = 'CONTOSO\a'; Approver = 'CONTOSO\b'; ParamsDefinition = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($xml)) }))
        $s = Get-PasSiteScript -SMSProvider 'cm01' -SiteCode 'MCM' -ScriptGuid ([guid]'685e0a08-8ace-4948-be8f-9d0416852976')
        $s.ScriptGuid | Should -Be '685E0A08-8ACE-4948-BE8F-9D0416852976'
        $s.ScriptName | Should -Be 'S1'
        $s.ApprovalState | Should -Be 3
        $s.ApprovalState | Should -BeOfType [int]
        $s.Author | Should -Be 'CONTOSO\a'
        $s.Approver | Should -Be 'CONTOSO\b'
        @($s.Parameters).Count | Should -Be 2
        $s.DefinitionError | Should -Be ''
        @($global:Fx.Calls | Where-Object Cmd -eq 'Remove').Count | Should -Be 1
    }
    It 'asks the site namespace for the upper-case GUID' {
        $global:Fx.Items = @((New-CimFixture 'SMS_Scripts' @{ ScriptGuid = 'G'; ScriptName = 'S'; ApprovalState = 3; Author = 'a'; Approver = 'b'; ParamsDefinition = '' }))
        Get-PasSiteScript -SMSProvider 'cm01' -SiteCode 'ZZ1' -ScriptGuid ([guid]'685e0a08-8ace-4948-be8f-9d0416852976') | Out-Null
        $first = $global:Fx.Calls | Where-Object { $_.Cmd -eq 'Get' -and -not $_.Piped } | Select-Object -First 1
        $first.Namespace | Should -Be 'root\SMS\site_ZZ1'
        $first.Class | Should -Be 'SMS_Scripts'
        $first.Filter | Should -Be "ScriptGuid = '685E0A08-8ACE-4948-BE8F-9D0416852976'"
    }
    It 'returns nothing for a script that does not exist, and still removes the session' {
        $global:Fx.Items = @()
        Get-PasSiteScript -SMSProvider 'cm01' -SiteCode 'MCM' -ScriptGuid ([guid]::NewGuid()) | Should -BeNullOrEmpty
        @($global:Fx.Calls | Where-Object Cmd -eq 'Remove').Count | Should -Be 1
    }
    It 'reads a script without a parameter definition as a script with no parameters' {
        $global:Fx.Items = @((New-CimFixture 'SMS_Scripts' @{ ScriptGuid = 'G'; ScriptName = 'S'; ApprovalState = 3; Author = 'a'; Approver = 'b'; ParamsDefinition = '' }))
        $s = Get-PasSiteScript -SMSProvider 'cm01' -SiteCode 'MCM' -ScriptGuid ([guid]::NewGuid())
        @($s.Parameters).Count | Should -Be 0
        $s.DefinitionError | Should -Be ''
    }
    It 'reads a script whose definition lists no parameter as a script with no parameters' {
        $empty = '<?xml version="1.0" encoding="utf-16"?><ScriptParameters SchemaVersion="1"></ScriptParameters>'
        $global:Fx.Items = @((New-CimFixture 'SMS_Scripts' @{ ScriptGuid = 'G'; ScriptName = 'S'; ApprovalState = 3; Author = 'a'; Approver = 'b'; ParamsDefinition = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($empty)) }))
        $s = Get-PasSiteScript -SMSProvider 'cm01' -SiteCode 'MCM' -ScriptGuid ([guid]::NewGuid())
        $s.DefinitionError | Should -Be ''
        @($s.Parameters).Count | Should -Be 0
    }
    It 'returns a fixed sentence instead of throwing when the definition cannot be read, and logs the reason' {
        $global:Fx.Items = @((New-CimFixture 'SMS_Scripts' @{ ScriptGuid = 'G'; ScriptName = 'S'; ApprovalState = 3; Author = 'a'; Approver = 'b'; ParamsDefinition = 'not base64 !!' }))
        $log = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.log')
        Set-PasLogPath $log
        try { $s = Get-PasSiteScript -SMSProvider 'cm01' -SiteCode 'MCM' -ScriptGuid ([guid]::NewGuid()) } finally { Set-PasLogPath '' }
        $s.DefinitionError | Should -Be 'The stored definition is not valid. The log file has the details.'
        @($s.Parameters).Count | Should -Be 0
        (Get-Content -LiteralPath $log -Raw) | Should -Match 'could not be read'
    }
    It 'removes the session when the query fails, and passes the error up' {
        $global:Fx.Throw = 'WMI query failed'
        { Get-PasSiteScript -SMSProvider 'cm01' -SiteCode 'MCM' -ScriptGuid ([guid]::NewGuid()) } | Should -Throw '*WMI query failed*'
        @($global:Fx.Calls | Where-Object Cmd -eq 'Remove').Count | Should -Be 1
    }
    It 'passes a session error up' {
        Mock New-PasCimSession { throw 'no session' } -ModuleName PivotsAndScripts
        { Get-PasSiteScript -SMSProvider 'cm01' -SiteCode 'MCM' -ScriptGuid ([guid]::NewGuid()) } | Should -Throw '*no session*'
        @($global:Fx.Calls | Where-Object Cmd -eq 'Remove').Count | Should -Be 0
    }
    It 'refuses a text that is not a GUID' {
        { Get-PasSiteScript -SMSProvider 'cm01' -SiteCode 'MCM' -ScriptGuid 'x'' OR 1=1' } | Should -Throw
        @($global:Fx.Calls).Count | Should -Be 0
    }
}

Describe 'Get-PasSiteScripts' {
    BeforeEach {
        $global:Fx = @{ Items = @(); Calls = [System.Collections.Generic.List[object]]::new(); Throw = $null; Session = $script:Session }
        Mock New-PasCimSession { $global:Fx.Session } -ModuleName PivotsAndScripts
        Mock Remove-CimSession { $global:Fx.Calls.Add(@{ Cmd = 'Remove' }) } -ModuleName PivotsAndScripts
        Mock Get-CimInstance {
            $global:Fx.Calls.Add(@{ Cmd = 'Get'; Namespace = $PesterBoundParameters.Namespace; Filter = $PesterBoundParameters.Filter })
            if ($global:Fx.Throw) { throw $global:Fx.Throw }
            $global:Fx.Items
        } -ModuleName PivotsAndScripts
    }
    It 'lists only scripts that no site feature owns' {
        Get-PasSiteScripts -SMSProvider 'cm01' -SiteCode 'MCM' | Out-Null
        $call = $global:Fx.Calls | Where-Object Cmd -eq 'Get'
        $call.Filter | Should -Be 'Feature = 0'
        $call.Namespace | Should -Be 'root\SMS\site_MCM'
    }
    It 'maps the fields, names the approval state and sorts by last update, newest first' {
        $global:Fx.Items = @(
            [pscustomobject]@{ ScriptName = 'old'; ApprovalState = 3; Author = 'a'; Approver = 'b'; LastUpdateTime = [datetime]'2026-01-02T03:04:05'; ScriptGuid = 'G1' }
            [pscustomobject]@{ ScriptName = 'new'; ApprovalState = 0; Author = 'a'; Approver = $null; LastUpdateTime = [datetime]'2026-11-06T14:09:59'; ScriptGuid = 'G2' }
            [pscustomobject]@{ ScriptName = 'none'; ApprovalState = 1; Author = $null; Approver = ''; LastUpdateTime = $null; ScriptGuid = 'G3' })
        $r = @(Get-PasSiteScripts -SMSProvider 'cm01' -SiteCode 'MCM')
        @($r | ForEach-Object Name) | Should -Be @('new', 'old', 'none')
        $r[0].LastUpdated | Should -Be '2026-11-06 14:09'
        $r[0].State | Should -Be 'Waiting for approval'
        $r[0].Approver | Should -Be ''
        $r[1].State | Should -Be 'Approved'
        $r[2].State | Should -Be 'Denied'
        $r[2].LastUpdated | Should -Be ''
        $r[2].Author | Should -Be ''
        $r[0].ApprovalState | Should -BeOfType [int]
        $r[0].ScriptGuid | Should -Be 'G2'
    }
    It 'returns an empty array for a site without scripts' {
        $r = Get-PasSiteScripts -SMSProvider 'cm01' -SiteCode 'MCM'
        @($r).Count | Should -Be 0
        @($global:Fx.Calls | Where-Object Cmd -eq 'Remove').Count | Should -Be 1
    }
    It 'returns one script as a list of one' {
        $global:Fx.Items = @([pscustomobject]@{ ScriptName = 'only'; ApprovalState = 3; Author = 'a'; Approver = 'b'; LastUpdateTime = [datetime]'2026-01-02'; ScriptGuid = 'G1' })
        @(Get-PasSiteScripts -SMSProvider 'cm01' -SiteCode 'MCM').Count | Should -Be 1
    }
    It 'removes the session when the query fails, and passes the error up' {
        $global:Fx.Throw = 'access denied'
        { Get-PasSiteScripts -SMSProvider 'cm01' -SiteCode 'MCM' } | Should -Throw '*access denied*'
        @($global:Fx.Calls | Where-Object Cmd -eq 'Remove').Count | Should -Be 1
    }
    It 'shows a script name with markup characters as plain text' {
        $global:Fx.Items = @([pscustomobject]@{ ScriptName = '<b>&"x"'; ApprovalState = 3; Author = 'a'; Approver = 'b'; LastUpdateTime = [datetime]'2026-01-02'; ScriptGuid = 'G1' })
        (Get-PasSiteScripts -SMSProvider 'cm01' -SiteCode 'MCM').Name | Should -Be '<b>&"x"'
    }
}

Describe 'Get-PasScriptRunStatus' {
    BeforeEach {
        $global:Fx = @{ Rows = @(); Call = $null; Throw = $null }
        Mock Get-CimInstance {
            $global:Fx.Call = @{ Namespace = $PesterBoundParameters.Namespace; Class = $PesterBoundParameters.ClassName; Filter = $PesterBoundParameters.Filter; Session = $PesterBoundParameters.CimSession }
            if ($global:Fx.Throw) { throw $global:Fx.Throw }
            $global:Fx.Rows
        } -ModuleName PivotsAndScripts
    }
    It 'queries the status class of the operation and maps every field' {
        $global:Fx.Rows = @([pscustomobject]@{ ClientOperationId = 42; ResourceId = 16777221; DeviceName = 'CLIENT01'; ScriptExecutionState = 4; ScriptExitCode = 0; ScriptOutput = 'out'; ScriptGuid = 'G'; ScriptName = 'S'; LastUpdateTime = [datetime]'2026-11-06'; Extra = 'ignored' })
        $r = @(Get-PasScriptRunStatus -CimSession $script:Session -SiteCode 'MCM' -OperationID 42)
        $r.Count | Should -Be 1
        $r[0].DeviceName | Should -Be 'CLIENT01'
        $r[0].ResourceId | Should -Be 16777221
        $r[0].ScriptOutput | Should -Be 'out'
        $r[0].PSObject.Properties['Extra'] | Should -BeNullOrEmpty
        $global:Fx.Call.Filter | Should -Be 'ClientOperationId = 42'
        $global:Fx.Call.Class | Should -Be 'SMS_ScriptsExecutionStatus'
        $global:Fx.Call.Namespace | Should -Be 'root\SMS\site_MCM'
        [object]::ReferenceEquals(@($global:Fx.Call.Session)[0], $script:Session) | Should -BeTrue
    }
    It 'returns nothing before any device has reported' {
        @(Get-PasScriptRunStatus -CimSession $script:Session -SiteCode 'MCM' -OperationID 1).Count | Should -Be 0
    }
    It 'returns a row for each device' {
        $global:Fx.Rows = 1..3 | ForEach-Object { [pscustomobject]@{ ClientOperationId = 5; ResourceId = $_; DeviceName = "PC$_"; ScriptExecutionState = 1; ScriptExitCode = 0; ScriptOutput = ''; ScriptGuid = 'G'; ScriptName = 'S'; LastUpdateTime = $null } }
        @(Get-PasScriptRunStatus -CimSession $script:Session -SiteCode 'MCM' -OperationID 5).Count | Should -Be 3
    }
    It 'refuses a row without ScriptOutput as an unsupported schema' {
        $global:Fx.Rows = @([pscustomobject]@{ ClientOperationId = 5; ResourceId = 1 })
        { Get-PasScriptRunStatus -CimSession $script:Session -SiteCode 'MCM' -OperationID 5 } | Should -Throw '*unsupported script-result schema*'
    }
    It 'passes a query error up' {
        $global:Fx.Throw = 'Invalid class'
        { Get-PasScriptRunStatus -CimSession $script:Session -SiteCode 'MCM' -OperationID 5 } | Should -Throw '*Invalid class*'
    }
    It 'writes a large operation ID without a thousands separator' {
        Get-PasScriptRunStatus -CimSession $script:Session -SiteCode 'MCM' -OperationID 16777216123 | Out-Null
        $global:Fx.Call.Filter | Should -Be 'ClientOperationId = 16777216123'
    }
}
