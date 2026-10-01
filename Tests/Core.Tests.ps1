BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\Module\PivotsAndScripts.psm1') -Force -DisableNameChecking
}

Describe 'Convert-PasRows' {
    It 'normalizes nested CMPivot JSON and keeps the trusted target identity' {
        $rows = @(Convert-PasRows -Payload ([pscustomobject]@{value=@([pscustomobject]@{Result='[{"FreeSpace":14,"TargetResourceID":999}]'})}) -Device 'PC-1' -ResourceID 17)
        $rows.Count | Should -Be 1
        $rows[0].FreeSpace | Should -Be 14
        $rows[0].TargetResourceID | Should -Be 17
        $rows[0].TargetDevice | Should -Be 'PC-1'
    }
    It 'reads the AdminService CMPivot envelope' {
        $payload = '{"value":{"Status":"1","MoreResult":false,"Result":[{"Caption":"Windows 11","Device":"CLIENT01"},{"Caption":"Windows 11","Device":"CLIENT01"}]}}' | ConvertFrom-Json
        $rows = @(Convert-PasRows -Payload $payload -Device 'CLIENT01' -ResourceID 16777221)
        $rows.Count | Should -Be 2
        $rows[0].Caption | Should -Be 'Windows 11'
    }
    It 'keeps a data column named Result' {
        $rows = @(Convert-PasRows -Payload '{"Device":"PC1","Result":"OK","Code":5}' -Device 'PC1' -ResourceID 1)
        $rows[0].Result | Should -Be 'OK'
        $rows[0].Code | Should -Be 5
    }
    It 'splits Run Scripts output stored with escaped quotes into columns' {
        $stored = '{\"Device\":\"CLIENT01\",\"Name\":\"CcmExec\",\"Status\":4}'
        $rows = @(Convert-PasRows -Payload $stored -Device 'CLIENT01' -ResourceID 16777221)
        $rows[0].Name | Should -Be 'CcmExec'
        $rows[0].Status | Should -Be 4
    }
    It 'keeps plain script output as text' {
        (@(Convert-PasRows -Payload 'plain output' -Device 'PC-2' -ResourceID 18))[0].Output | Should -Be 'plain output'
    }
    It 'creates no row for empty script output from a failed run' {
        @(Convert-PasRows -Payload '' -Device 'PC-1' -ResourceID 17).Count | Should -Be 0
    }
    It 'creates no row for an empty result' {
        @(Convert-PasRows -Payload ([pscustomobject]@{value=@()}) -Device 'PC-1' -ResourceID 17).Count | Should -Be 0
    }
}

Describe 'Script parameters' {
    It 'extracts parameters from the AST' {
        $params = @(Get-PasParameters 'param([string]$Name="CcmExec",[switch]$VerboseOutput) Get-Service $Name')
        $params.Count | Should -Be 2
        $params[0].Name | Should -Be 'Name'
        $params[0].DefaultLiteral | Should -Be 'CcmExec'
    }
    It 'rejects invalid script text' {
        { Get-PasParameters 'param( {' } | Should -Throw
    }
    It 'does not evaluate default expressions' {
        $marker = Join-Path ([IO.Path]::GetTempPath()) ('pas-marker-' + [guid]::NewGuid().ToString('N'))
        $params = @(Get-PasParameters ('param([string]$Path=$(Set-Content -LiteralPath ''{0}'' -Value x))' -f $marker))
        $params[0].DefaultLiteral | Should -Be ''
        Test-Path -LiteralPath $marker | Should -BeFalse
    }
    It 'reads Mandatory and ValidateSet' {
        $params = @(Get-PasParameters 'param([Parameter(Mandatory)][ValidateSet("A","B")][string]$Mode,[Parameter(Mandatory=$false)][int]$Count=2)')
        $params[0].Mandatory | Should -BeTrue
        $params[0].Choices | Should -Be @('A','B')
        $params[1].Mandatory | Should -BeFalse
        $params[1].SiteType | Should -Be 'System.Int32'
    }
    It 'refuses switch and bool parameters, which the site rejects' {
        { Assert-PasScriptParameters @(Get-PasParameters 'param([switch]$Detailed)') } | Should -Throw '*string and integer*'
        { Assert-PasScriptParameters @(Get-PasParameters 'param([bool]$Flag)') } | Should -Throw '*string and integer*'
    }
    It 'refuses a single quote in a default value' {
        { Assert-PasScriptParameters @(Get-PasParameters "param([string]`$Name=""O'Brien"")") } | Should -Throw '*single quote*'
    }
    It 'refuses more than 10 parameters' {
        $text = 'param(' + ((1..11 | ForEach-Object { "[string]`$P$_" }) -join ',') + ')'
        { Assert-PasScriptParameters @(Get-PasParameters $text) } | Should -Throw '*at most 10*'
    }
    It 'writes the site parameter definition and reads it back' {
        $params = @(Get-PasParameters 'param([Parameter(Mandatory)][string]$Name="A&B",[int]$Count=1)')
        $xml = ConvertTo-PasParamsDefinition $params
        $xml | Should -Match '^<\?xml version="1.0" encoding="utf-16"\?><ScriptParameters SchemaVersion="1">'
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($xml))
        $back = @(ConvertFrom-PasParamsDefinition $encoded)
        $back.Count | Should -Be 2
        $back[0].Name | Should -Be 'Name'
        $back[0].Type | Should -Be 'System.String'
        $back[0].Required | Should -BeTrue
        $back[0].Default | Should -Be 'A&B'
        $back[1].Type | Should -Be 'System.Int32'
    }
    It 'reads the definition format of the built-in CMPivot script' {
        $builtin = '<?xml version="1.0" encoding="utf-16"?><ScriptParameters SchemaVersion="1"><ScriptParameter Name="kustoquery" FriendlyName="kustoquery" Type="System.String" Description="" IsRequired="false" IsHidden="false" DefaultValue=""><Validators /></ScriptParameter></ScriptParameters>'
        $back = @(ConvertFrom-PasParamsDefinition ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($builtin))))
        $back[0].Name | Should -Be 'kustoquery'
    }
}

Describe 'Get-PasSubmittedMessage' {
    It 'names the script GUID and the stored parameters' {
        Get-PasSubmittedMessage -Guid 'ACDC21DE-0DF7-41F6-A406-36772AFFD432' -Parameters @('ServiceName') | Should -Be 'Script ACDC21DE-0DF7-41F6-A406-36772AFFD432 created with parameters ServiceName. Obtain approval in Configuration Manager before running.'
        Get-PasSubmittedMessage -Guid 'G' -Parameters @() | Should -Be 'Script G created. Obtain approval in Configuration Manager before running.'
    }
    It 'reports the result of approval at submission' {
        Get-PasSubmittedMessage -Guid 'G' -Parameters @() -Approved $true | Should -Be 'Script G created. Approved.'
        Get-PasSubmittedMessage -Guid 'G' -Parameters @() -ApprovalError 'Refused.' | Should -Be 'Script G created. Not approved: Refused.'
    }
}

Describe 'ConvertTo-PasScriptArguments' {
    BeforeAll {
        $script:site = [pscustomobject]@{ScriptGuid='G';Parameters=@([pscustomobject]@{Name='Name';Type='System.String';Required=$false;Default='CcmExec'},[pscustomobject]@{Name='Count';Type='System.Int32';Required=$false;Default='1'})}
    }
    It 'sends integers as Int32; the site drops integer values sent as text' {
        $arguments = ConvertTo-PasScriptArguments -SiteScript $script:site -Parameters @{Count='7';Name='Spooler'}
        $arguments.Count | Should -BeOfType [int]
        $arguments.Count | Should -Be 7
    }
    It 'refuses a name the site does not define; the site drops it silently' {
        { ConvertTo-PasScriptArguments -SiteScript $script:site -Parameters @{Nope='x'} } | Should -Throw '*not defined*'
    }
    It 'refuses values when the site script has no definitions' {
        $bare = [pscustomobject]@{ScriptGuid='G';Parameters=@()}
        { ConvertTo-PasScriptArguments -SiteScript $bare -Parameters @{Name='x'} } | Should -Throw '*no parameter definitions*'
    }
    It 'refuses a single quote; the client script fails on it' {
        { ConvertTo-PasScriptArguments -SiteScript $script:site -Parameters @{Name="O'Brien"} } | Should -Throw '*single quote*'
    }
    It 'refuses to run when the stored definitions cannot be read' {
        $broken = [pscustomobject]@{ScriptGuid='G';Parameters=@();DefinitionError='The input is not a valid Base-64 string.'}
        { ConvertTo-PasScriptArguments -SiteScript $broken -Parameters @{} } | Should -Throw '*cannot be read*'
    }
    It 'refuses a missing required value without a default' {
        $required = [pscustomobject]@{ScriptGuid='G';Parameters=@([pscustomobject]@{Name='Path';Type='System.String';Required=$true;Default=''})}
        { ConvertTo-PasScriptArguments -SiteScript $required -Parameters @{} } | Should -Throw '*required*'
    }
}

Describe 'Script approval' {
    BeforeAll { $script:module = Get-Module PivotsAndScripts }
    It 'names the approval states seen on the site' {
        Get-PasApprovalStateName 0 | Should -Be 'Waiting for approval'
        Get-PasApprovalStateName 1 | Should -Be 'Denied'
        Get-PasApprovalStateName 3 | Should -Be 'Approved'
    }
    It 'refuses to change a script that belongs to a site feature' {
        & $script:module {
            function Get-CMScript { param($ScriptGuid,[switch]$Fast) [pscustomobject]@{ScriptGuid=$ScriptGuid;Feature=1;Author='CM';ApprovalState=3} }
            $failed = $false
            try { Set-PasScriptApproval -ScriptGuid ([guid]::NewGuid()) -Decision Deny } catch { $failed = $_.Exception.Message -like '*belongs to a Configuration Manager feature*' }
            if (-not $failed) { throw 'A feature script was not protected from Deny.' }
            $failed = $false
            try { Remove-PasManagedScript -ScriptGuid ([guid]::NewGuid()) } catch { $failed = $_.Exception.Message -like '*belongs to a Configuration Manager feature*' }
            if (-not $failed) { throw 'A feature script was not protected from Remove.' }
        }
    }
    It 'reports the GUID in the casing the site stores' {
        & $script:module {
            function Get-CMScript { param($ScriptGuid,[switch]$Fast) [pscustomobject]@{ScriptGuid='685E0A08-8ACE-4948-BE8F-9D0416852976';Feature=0;Author='CONTOSO\other';ApprovalState=3;Approver='CONTOSO\me'} }
            function Approve-CMScript { param($ScriptGuid,$Comment) }
            function Remove-CMScript { param($InputObject,[switch]$Force) }
            $guid = [guid]'685e0a08-8ace-4948-be8f-9d0416852976'
            if ((Set-PasScriptApproval -ScriptGuid $guid -Decision Approve).ScriptGuid -cne '685E0A08-8ACE-4948-BE8F-9D0416852976') { throw 'Approval result GUID is not in site casing.' }
            if ((Remove-PasManagedScript -ScriptGuid $guid).ScriptGuid -cne '685E0A08-8ACE-4948-BE8F-9D0416852976') { throw 'Remove result GUID is not in site casing.' }
        }
    }
    It 'explains a refused self-approval' {
        & $script:module {
            $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
            function Get-CMScript { param($ScriptGuid,[switch]$Fast) [pscustomobject]@{ScriptGuid=$ScriptGuid;Feature=0;Author=$me.ToUpperInvariant();ApprovalState=0} }
            function Approve-CMScript { param($ScriptGuid,$Comment) throw 'The SMS Provider reported an error.' }
            $message = ''
            try { Set-PasScriptApproval -ScriptGuid ([guid]::NewGuid()) -Decision Approve } catch { $message = $_.Exception.Message }
            if ($message -notlike '*second approver*') { throw "Unexpected message: $message" }
        }
    }
}

Describe 'Collection IDs' {
    It 'accepts site IDs and rejects eight-character names' {
        Test-PasCollectionId 'SMS00001' | Should -BeTrue
        Test-PasCollectionId 'MCM0001A' | Should -BeTrue
        Test-PasCollectionId 'Desktops' | Should -BeFalse
        Test-PasCollectionId 'Servers1' | Should -BeFalse
    }
}

Describe 'Write-PasJson' {
    It 'overwrites atomically and keeps an empty array as JSON' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('pas-tests-' + [guid]::NewGuid().ToString('N'))
        $path = Join-Path $root 'session.json'
        try {
            Write-PasJson $path @{Results=@();ID='first'}
            Write-PasJson $path @{Results=@([pscustomobject]@{Device='PC-1'});ID='second'}
            $saved = [IO.File]::ReadAllText($path) | ConvertFrom-Json
            $saved.ID | Should -Be 'second'
            $saved.Results[0].Device | Should -Be 'PC-1'
            Write-PasJson $path @()
            ([IO.File]::ReadAllText($path) -replace '\s','') | Should -Be '[]'
            Write-PasJson $path @([pscustomobject]@{Device='PC-1'})
            ([IO.File]::ReadAllText($path) -replace '\s','') | Should -Be '[{"Device":"PC-1"}]'
        } finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force } }
    }
}

Describe 'Resolve-PasTargets' {
    BeforeAll { $script:module = Get-Module PivotsAndScripts }
    It 'deduplicates by ResourceID and tracks unknown names' {
        & $script:module {
            function Get-CMDevice {
                param($Name,$CollectionId,[switch]$DisableWildcardHandling,[switch]$Fast)
                if ($Name -eq 'missing') { return }
                if ($Name -eq 'PC-*') { return @([pscustomobject]@{Name='PC-1';ResourceID=17;IsClient=$true;IsActive=$true},[pscustomobject]@{Name='PC-1';ResourceID=17;IsClient=$true;IsActive=$true}) }
                [pscustomobject]@{Name=$Name;ResourceID=17;IsClient=$true;IsActive=$true}
            }
            $snapshot = Resolve-PasTargets -Kind List -InputText "PC-1`nPC-1`nmissing"
            if ($snapshot.Targets.Count -ne 1 -or $snapshot.Unknown.Count -ne 1) { throw 'Target deduplication or unknown tracking failed.' }
            $snapshot = Resolve-PasTargets -Kind Pattern -InputText 'PC-*'
            if ($snapshot.Targets.Count -ne 1) { throw 'Wildcard targets were not deduplicated by ResourceID.' }
        }
    }
    It 'resolves a single collection by ID and by exact name' {
        & $script:module {
            function Get-CMDeviceCollection { param($Id,$Name) if ($Id -eq 'SMS00001' -or $Name -eq 'All Systems') { [pscustomobject]@{Name='All Systems';CollectionID='SMS00001'} } }
            function Get-CMDevice { param($Name,$CollectionId,[switch]$DisableWildcardHandling,[switch]$Fast) if ($CollectionId -eq 'SMS00001') { [pscustomobject]@{Name='PC-1';ResourceID=17;IsClient=$true;IsActive=$true} } }
            if ((Resolve-PasTargets -Kind Collection -InputText 'SMS00001').Targets.Count -ne 1) { throw 'Collection ID lookup failed for a single collection.' }
            if ((Resolve-PasTargets -Kind Collection -InputText 'All Systems').Targets.Count -ne 1) { throw 'Collection name lookup failed.' }
        }
    }
    It 'treats an eight-character collection name as a name' {
        & $script:module {
            function Get-CMDeviceCollection { param($Id,$Name) if ($Name -eq 'Desktops') { [pscustomobject]@{Name='Desktops';CollectionID='MCM00012'} } }
            function Get-CMDevice { param($Name,$CollectionId,[switch]$DisableWildcardHandling,[switch]$Fast) if ($CollectionId -eq 'MCM00012') { [pscustomobject]@{Name='PC-2';ResourceID=18;IsClient=$true;IsActive=$true} } }
            if ((Resolve-PasTargets -Kind Collection -InputText 'Desktops').Targets.Count -ne 1) { throw 'Eight-character collection name was treated as an ID.' }
        }
    }
}

Describe 'Get-PasVisibleRows' {
    It 'returns an array with Count 1 for one visible row' {
        $rows = Get-PasVisibleRows @([pscustomobject]@{Device='CLIENT01'})
        $rows.Count | Should -Be 1
        $rows[0].Device | Should -Be 'CLIENT01'
    }
    It 'returns an empty array for no rows or a null source' {
        (Get-PasVisibleRows @()).Count | Should -Be 0
        (Get-PasVisibleRows $null).Count | Should -Be 0
    }
}

Describe 'New-PasDeviceTable' {
    It 'keys every target by ResourceID text so a run keeps Client and Active' {
        $table = New-PasDeviceTable @([pscustomobject]@{Device='CLIENT01';ResourceID=16777221;Client=$true;Active=$true},[pscustomobject]@{Device='x64 Unknown Computer';ResourceID=2046820353;Client=$false;Active=$false})
        $table.Count | Should -Be 2
        $table['16777221'].Client | Should -BeTrue
        $table['2046820353'].Client | Should -BeFalse
        (New-PasDeviceTable @()).Count | Should -Be 0
    }
}

Describe 'Sort-PasRows' {
    It 'sorts Int32 and Int64 values from ConvertFrom-Json as numbers' {
        $rows = ConvertFrom-Json '[{"Device":"A","FreeSpace":5000000000},{"Device":"B","FreeSpace":7},{"Device":"C","FreeSpace":300}]'
        $rows[0].FreeSpace | Should -BeOfType [long]
        $rows[1].FreeSpace | Should -BeOfType [int]
        (@(Sort-PasRows -Rows $rows -Property FreeSpace) | ForEach-Object Device) -join ',' | Should -Be 'B,C,A'
        (@(Sort-PasRows -Rows $rows -Property FreeSpace -Descending) | ForEach-Object Device) -join ',' | Should -Be 'A,C,B'
    }
    It 'sorts numeric strings from AdminService as numbers and other text as text' {
        $rows = @([pscustomobject]@{Name='a';WorkingSetSize='9977856'},[pscustomobject]@{Name='b';WorkingSetSize='90755072'},[pscustomobject]@{Name='c';WorkingSetSize=''},[pscustomobject]@{Name='d';WorkingSetSize='8192'})
        (@(Sort-PasRows -Rows $rows -Property WorkingSetSize -Descending) | ForEach-Object Name) -join ',' | Should -Be 'b,a,d,c'
        $text = @([pscustomobject]@{V='10'},[pscustomobject]@{V='9'},[pscustomobject]@{V='x'})
        (@(Sort-PasRows -Rows $text -Property V) | ForEach-Object V) -join ',' | Should -Be '10,9,x'
    }
    It 'keeps the input order for a column the rows do not have' {
        $rows = @([pscustomobject]@{Device='B'},[pscustomobject]@{Device='A'})
        (@(Sort-PasRows -Rows $rows -Property Missing) | ForEach-Object Device) -join ',' | Should -Be 'B,A'
    }
}

Describe 'Get-PasSettingsToSave' {
    It 'keeps the saved connection when the dialog leaves a command-line override unchanged' {
        $settings = Get-PasSettingsToSave -Entered @{SiteCode='ZZ1';SMSProvider='cm01.contoso.com';ApproveAfterSubmit=$true} -Session @{SiteCode='ZZ1';SMSProvider='cm01.contoso.com'} -Persisted @{SiteCode='MCM';SMSProvider='cm01.contoso.com'}
        $settings.SiteCode | Should -Be 'MCM'
        $settings.SMSProvider | Should -Be 'cm01.contoso.com'
        $settings.ApproveAfterSubmit | Should -BeTrue
    }
    It 'saves a value the dialog changed' {
        $settings = Get-PasSettingsToSave -Entered @{SiteCode='ZZ2';SMSProvider='cm02.contoso.com';ApproveAfterSubmit=$false} -Session @{SiteCode='ZZ1';SMSProvider='cm01.contoso.com'} -Persisted @{SiteCode='MCM';SMSProvider='cm01.contoso.com'}
        $settings.SiteCode | Should -Be 'ZZ2'
        $settings.SMSProvider | Should -Be 'cm02.contoso.com'
    }
}

Describe 'Get-PasWorkerError' {
    It 'returns nothing for a cmdlet error the worker caught; HadErrors is still true' {
        $ps = [PowerShell]::Create()
        try {
            [void]$ps.AddScript('$ErrorActionPreference="Stop"; try { Get-Item -LiteralPath "C:\pas-no-such-path" } catch { }')
            $null = $ps.Invoke()
            $ps.HadErrors | Should -BeTrue
            Get-PasWorkerError $ps | Should -BeNullOrEmpty
        } finally { $ps.Dispose() }
    }
    It 'returns the text of an uncaught non-terminating error' {
        $ps = [PowerShell]::Create()
        try {
            [void]$ps.AddScript('Write-Error "worker failed"')
            $null = $ps.Invoke()
            Get-PasWorkerError $ps | Should -Be 'worker failed'
        } finally { $ps.Dispose() }
    }
}

Describe 'Worker script actions' {
    It 'sends the decision after the refreshed list, so the status line names the decision' {
        $stub = Join-Path $TestDrive 'Stub.psm1'
        Set-Content -LiteralPath $stub -Value @'
function Assert-PasConnection { param($SiteCode,$SMSProvider) }
function Set-PasScriptApproval { param($ScriptGuid,$Decision,$Comment) [pscustomobject]@{ScriptGuid=$ScriptGuid;State='Approved';Approver='CONTOSO\approver'} }
function Remove-PasManagedScript { param($ScriptGuid) [pscustomobject]@{ScriptGuid=$ScriptGuid;State='Removed'} }
function Get-PasSiteScripts { param($SMSProvider,$SiteCode) [pscustomobject]@{Name='S';ScriptGuid='G'} }
'@
        foreach ($action in @('Approve','Deny','Remove')) {
            $queue = [Collections.Concurrent.ConcurrentQueue[object]]::new()
            $ps = [PowerShell]::Create()
            try {
                [void]$ps.AddScript([IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\Module\Execute.ps1'))).AddArgument(@{Module=$stub;SiteCode='MCM';Provider='cm01';Action=$action;ScriptGuid='G';Comment=''}).AddArgument($queue).AddArgument([hashtable]::Synchronized(@{Stop=$false}))
                $null = $ps.Invoke()
            } finally { $ps.Dispose() }
            (@($queue.ToArray() | ForEach-Object Kind) -join ',') | Should -Be 'Scripts,ScriptChanged,Done'
        }
    }
}

Describe 'Window smoke test' {
    It 'starts the WPF window, switches themes and modes, and closes' {
        $output = & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\start-pivotsandscripts.ps1') -SmokeTest 2>&1
        ($output | Out-String) | Should -Match 'PASS: WPF startup'
    }
}
