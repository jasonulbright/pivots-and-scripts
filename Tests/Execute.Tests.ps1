#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }
# The background worker (Module\Execute.ps1). The window starts it in its own runspace and reads its events
# from a queue; these tests start it the same way. The module the worker imports is a copy of the real
# module with the site calls replaced by a stub that follows a scenario (the PAS_SCN environment
# variable, as JSON). Every other function is the real one. The stub logs its calls to a file.

BeforeAll {
    . "$PSScriptRoot\TestHelpers.ps1"
    $script:Worker = Join-Path $script:AppRoot 'Module\Execute.ps1'
    $script:Log = Join-Path $TestDrive 'calls.log'
    $overrides = @'
function Get-PasScn { $h = @{}; if ($env:PAS_SCN) { ($env:PAS_SCN | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value } }; $h }
function Get-PasProp { param($Object,[string]$Name) $p = $Object.PSObject.Properties[$Name]; if ($p) { $p.Value } }
function Write-PasCall { param([string]$Text) Add-Content -LiteralPath 'LOG' -Value $Text }
function global:Remove-CimSession { param($CimSession) Add-Content -LiteralPath 'LOG' -Value 'cim-close' }
function Assert-PasConnection { param($SiteCode,$SMSProvider) Write-PasCall 'connect'; if ((Get-PasScn)['ConnectFail']) { throw 'Configuration Manager connection failed. Check console installation, site and permissions.' } }
function New-PasCimSession { param($SMSProvider) Write-PasCall 'cim-open'; [pscustomobject]@{ Name = 'cim' } }
function Resolve-PasTargets { param($Kind,$InputText) Write-PasCall "resolve|$Kind|$InputText"; [pscustomobject]@{Targets=@([pscustomobject]@{Device='PC-1';ResourceID=1;Client=$true;Active=$true});Unknown=@();CollectionID='';ResolvedAt='t'} }
function New-PasManagedScript { [CmdletBinding(SupportsShouldProcess)] param($Text,$SMSProvider,$SiteCode) Write-PasCall "submit|$Text"; if ((Get-PasScn)['SubmitFail']) { throw (Get-PasScn)['SubmitFail'] }; if ((Get-PasScn)['SubmitFailTyped']) { throw [IO.IOException]::new([string](Get-PasScn)['SubmitFailTyped']) }; [pscustomobject]@{ScriptGuid='GUID-1';Parameters=@('A','B')} }
function Set-PasScriptApproval { [CmdletBinding(SupportsShouldProcess)] param($ScriptGuid,$Decision,$Comment) Write-PasCall "approval|$ScriptGuid|$Decision|$Comment"; Write-PasCall ('approval-confirm|' + $PSBoundParameters.ContainsKey('Confirm') + '|' + $PSBoundParameters['Confirm']); if ((Get-PasScn)['ApproveFail']) { throw (Get-PasScn)['ApproveFail'] }; if ((Get-PasScn)['ApproveFailTyped']) { throw [IO.IOException]::new([string](Get-PasScn)['ApproveFailTyped']) }; [pscustomobject]@{ScriptGuid=$ScriptGuid;State=$(if ((Get-PasScn)['ApproveState']) { (Get-PasScn)['ApproveState'] } else { 'Approved' });Approver='CONTOSO\approver'} }
function Remove-PasManagedScript { [CmdletBinding(SupportsShouldProcess)] param($ScriptGuid) Write-PasCall "remove|$ScriptGuid"; Write-PasCall ('remove-confirm|' + $PSBoundParameters.ContainsKey('Confirm') + '|' + $PSBoundParameters['Confirm']); if ((Get-PasScn)['RemoveFail']) { throw (Get-PasScn)['RemoveFail'] }; [pscustomobject]@{ScriptGuid=$ScriptGuid;State='Removed'} }
function Get-PasSiteScripts { param($SMSProvider,$SiteCode) Write-PasCall 'list'; [pscustomobject]@{Name='S';ScriptGuid='G'} }
function Get-PasSiteScript { param($SMSProvider,$SiteCode,$ScriptGuid)
    $s = Get-PasScn
    if ($s['NoScript']) { return }
    $defs = if ($s['Definitions']) { @($s['Definitions'] | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Type = $_.Type; Required = [bool](Get-PasProp $_ 'Required'); Default = [string](Get-PasProp $_ 'Default') } }) } else { @() }
    [pscustomobject]@{ScriptGuid=[string]$ScriptGuid;ScriptName=$(if ($null -ne $s['ScriptName']) { $s['ScriptName'] } else { 'S' });ApprovalState=$(if ($null -ne $s['ApprovalState']) { [int]$s['ApprovalState'] } else { 3 });Parameters=$defs;DefinitionError=[string]$s['DefinitionError']}
}
function Start-PasPivotRun { [CmdletBinding(SupportsShouldProcess)] param($SMSProvider,$Query,$CollectionId,$ResourceIds)
    Write-PasCall ("pivot|$CollectionId|" + (@($ResourceIds) -join ','))
    $s = Get-PasScn
    if ($s['StartThrow']) { throw $s['StartThrow'] }; if ($s['StartThrowTyped']) { throw [IO.IOException]::new([string]$s['StartThrowTyped']) }
    if ($s['StartNone']) { return }
    [pscustomobject]@{OperationID=$(if ($s['StartNullId']) { $null } else { 900 });Raw=[pscustomobject]@{OperationId=900}}
}
function Start-PasScriptRun { [CmdletBinding(SupportsShouldProcess)] param($ScriptGuid,$Arguments,$CollectionId,$ResourceIds)
    Write-PasCall ("script|$CollectionId|" + (@($ResourceIds) -join ',') + '|' + ((@($Arguments.Keys | Sort-Object) | ForEach-Object { "$_=$($Arguments[$_]):$($Arguments[$_].GetType().Name)" }) -join ';'))
    $s = Get-PasScn
    if ($s['StartThrow']) { throw $s['StartThrow'] }; if ($s['StartThrowTyped']) { throw [IO.IOException]::new([string]$s['StartThrowTyped']) }
    if ($s['StartNone']) { return }
    [pscustomobject]@{OperationID=$(if ($s['StartNullId']) { $null } else { 901 });ReturnValue=0}
}
function Invoke-PasPoll { param($OperationID)
    Write-PasCall 'poll'
    $s = Get-PasScn
    $n = @((Get-Content -LiteralPath 'LOG') | Where-Object { $_ -eq 'poll' }).Count
    if ($s['StopOnPoll'] -and $global:PasControl) { $global:PasControl.Stop = $true }
    if ($s['PollThrow'] -and $n -le [int]$(if ($null -ne $s['PollThrowCount']) { $s['PollThrowCount'] } else { 1000 })) {
        $e = [InvalidOperationException]::new([string]$s['PollThrow'])
        if ($s['PollStatus']) { $e.Data['StatusCode'] = [int]$s['PollStatus'] }
        throw $e
    }
    $rows = if ($s['RowsLater'] -and $n -ge 2) { $s['RowsLater'] } else { $s['Rows'] }
    foreach ($r in @($rows)) { $r }
}
function Get-PasPivotStatus { param($SMSProvider,$OperationID) Invoke-PasPoll $OperationID }
function Get-PasScriptRunStatus { param($CimSession,$SiteCode,$OperationID) Invoke-PasPoll $OperationID }
'@.Replace('LOG', $script:Log)
    $script:Stub = New-StubModule -Path (Join-Path $TestDrive 'Stub.psm1') -Overrides $overrides

    # Runs the worker once in its own runspace, as the window does, and returns the events in order.
    function script:Invoke-Worker {
        param([hashtable]$Request, $Scenario = $null, [switch]$Stopped)
        $env:PAS_SCN = if ($Scenario) { $Scenario | ConvertTo-Json -Depth 8 -Compress } else { '' }
        $queue = [Collections.Concurrent.ConcurrentQueue[object]]::new()
        $control = [hashtable]::Synchronized(@{ Stop = [bool]$Stopped })
        $rs = [RunspaceFactory]::CreateRunspace(); $rs.Open()
        $rs.SessionStateProxy.SetVariable('PasControl', $control)
        $ps = [PowerShell]::Create(); $ps.Runspace = $rs
        try {
            [void]$ps.AddScript([IO.File]::ReadAllText($script:Worker)).AddArgument($Request).AddArgument($queue).AddArgument($control)
            $null = $ps.Invoke()
            $script:WorkerStreamErrors = @($ps.Streams.Error | ForEach-Object { $_.ToString() })
        }
        finally { $ps.Dispose(); $rs.Dispose(); $env:PAS_SCN = '' }
        @($queue.ToArray())
    }
    function script:Get-FinalHash { param([string]$Text) $sha = [Security.Cryptography.SHA256]::Create(); try { ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() } }
    function script:Reset-Worker { if (Test-Path -LiteralPath $script:Log) { Remove-Item -LiteralPath $script:Log }; $env:PAS_SCN = '' }
    function script:Get-Calls { if (Test-Path -LiteralPath $script:Log) { @(Get-Content -LiteralPath $script:Log) } else { @() } }
    function script:Get-FinalState {
        param($Events)
        $final = @{}
        foreach ($e in @($Events | Where-Object Kind -eq 'Device')) { $final[[string]$e.Value.ResourceID] = $e.Value }
        $final
    }
    $script:Targets = @(
        [pscustomobject]@{ Device = 'PC-11'; ResourceID = 11; Client = $true; Active = $true }
        [pscustomobject]@{ Device = 'PC-12'; ResourceID = 12; Client = $true; Active = $true }
        [pscustomobject]@{ Device = 'NC'; ResourceID = 13; Client = $false; Active = $false })
    $script:PivotOk = '<result ResultCode="0" moreResults="False"><e _i="0" Caption="A" /></result>'
    function script:New-Request {
        param([string]$Action = 'Run', [string]$Mode = 'Pivot', [hashtable]$Extra = @{})
        $r = @{ Module = $script:Stub; SiteCode = 'MCM'; Provider = 'p'; Action = $Action; Mode = $Mode; Text = 'OS'; Targets = $script:Targets; CollectionId = ''; TimeoutSeconds = 0; Parameters = @{}; ScriptGuid = [guid]::NewGuid().ToString(); Kind = 'List'; InputText = 'PC-1'; AutoApprove = $false; Comment = '' }
        foreach ($k in $Extra.Keys) { $r[$k] = $Extra[$k] }
        $r
    }
}


AfterAll { $env:PAS_SCN = '' }

Describe 'Worker script actions' {
    BeforeEach { Reset-Worker }
    It 'sends the decision after the refreshed list, so the status line names the decision' {
        foreach ($action in @('Approve', 'Deny', 'Remove')) {
            $events = Invoke-Worker (New-Request -Action $action -Extra @{ ScriptGuid = 'G' })
            (@($events | ForEach-Object Kind) -join ',') | Should -Be 'Scripts,ScriptChanged,Done'
        }
    }
    It 'passes the decision and the comment to the approval and reports the new state' {
        $events = Invoke-Worker (New-Request -Action 'Deny' -Extra @{ ScriptGuid = 'G'; Comment = 'too broad' })
        Get-Calls | Should -Contain 'approval|G|Deny|too broad'
        ($events | Where-Object Kind -eq 'ScriptChanged').Value.State | Should -Be 'Approved'
    }
    It 'removes the script and reports it as removed' {
        $events = Invoke-Worker (New-Request -Action 'Remove' -Extra @{ ScriptGuid = 'G' })
        Get-Calls | Should -Contain 'remove|G'
        ($events | Where-Object Kind -eq 'ScriptChanged').Value.State | Should -Be 'Removed'
    }
    It 'reports a failed <Action> as one error, with no list and no change event' -ForEach @(
        @{ Action = 'Approve'; Scenario = @{ ApproveFail = 'The site refused.' } }
        @{ Action = 'Deny';    Scenario = @{ ApproveFail = 'The site refused.' } }
        @{ Action = 'Remove';  Scenario = @{ RemoveFail = 'The site refused.' } }
    ) {
        $events = Invoke-Worker (New-Request -Action $Action -Extra @{ ScriptGuid = 'G' }) -Scenario $Scenario
        (@($events | ForEach-Object Kind) -join ',') | Should -Be 'Error,Done'
        ($events | Where-Object Kind -eq 'Error').Value | Should -Be 'The site refused.'
        Get-Calls | Should -Not -Contain 'list'
    }
    It 'passes -Confirm:$false to the removal, because the window already asked' {
        Invoke-Worker (New-Request -Action 'Remove' -Extra @{ ScriptGuid = 'G' }) | Out-Null
        Get-Calls | Should -Contain 'remove-confirm|True|False'
    }
    It 'passes -Confirm:$false to the approval, also at submission' {
        Invoke-Worker (New-Request -Action 'Approve' -Extra @{ ScriptGuid = 'G' }) | Out-Null
        Invoke-Worker (New-Request -Action 'Submit' -Extra @{ AutoApprove = $true }) | Out-Null
        @(Get-Calls | Where-Object { $_ -eq 'approval-confirm|True|False' }).Count | Should -Be 2
    }
    It 'lists the scripts of the site' {
        $events = Invoke-Worker (New-Request -Action 'Scripts')
        (@($events | ForEach-Object Kind) -join ',') | Should -Be 'Scripts,Done'
        @(($events | Where-Object Kind -eq 'Scripts').Value).Count | Should -Be 1
    }
}

Describe 'Worker connection and target actions' {
    BeforeEach { Reset-Worker }
    It 'connects, tells the site code and stops' {
        $events = Invoke-Worker (New-Request -Action 'Connect')
        (@($events | ForEach-Object Kind) -join ',') | Should -Be 'Notice,Done'
        ($events | Where-Object Kind -eq 'Notice').Value | Should -Be 'Connected to site MCM.'
    }
    It 'reports a failed connection as an error and stops, for every action: <Action>' -ForEach @(
        @{ Action = 'Connect' }, @{ Action = 'Resolve' }, @{ Action = 'Submit' }, @{ Action = 'Scripts' }, @{ Action = 'Approve' }, @{ Action = 'Remove' }, @{ Action = 'Run' }
    ) {
        $events = Invoke-Worker (New-Request -Action $Action) -Scenario @{ ConnectFail = $true }
        (@($events | ForEach-Object Kind) -join ',') | Should -Be 'Error,Done'
        ($events | Where-Object Kind -eq 'Error').Value | Should -BeLike '*connection failed*'
        @(Get-Calls | Where-Object { $_ -ne 'connect' }).Count | Should -Be 0
    }
    It 'resolves the targets of the request' {
        $events = Invoke-Worker (New-Request -Action 'Resolve' -Extra @{ Kind = 'Pattern'; InputText = 'PC-*' })
        (@($events | ForEach-Object Kind) -join ',') | Should -Be 'Targets,Done'
        Get-Calls | Should -Contain 'resolve|Pattern|PC-*'
        @(($events | Where-Object Kind -eq 'Targets').Value.Targets).Count | Should -Be 1
    }
}

Describe 'Worker script submission' {
    BeforeEach { Reset-Worker }
    It 'creates the script and reports its GUID, hash and parameters' {
        $events = Invoke-Worker (New-Request -Action 'Submit' -Extra @{ Text = 'param($A,$B)' })
        (@($events | ForEach-Object Kind) -join ',') | Should -Be 'Submitted,Done'
        $v = ($events | Where-Object Kind -eq 'Submitted').Value
        $v.Guid | Should -Be 'GUID-1'
        $v.Hash | Should -Be (Get-FinalHash 'param($A,$B)')
        @($v.Parameters) | Should -Be @('A', 'B')
        $v.Approved | Should -BeFalse
        $v.ApprovalError | Should -Be ''
        Get-Calls | Should -Not -Contain 'approval|GUID-1|Approve|Approved at submission by Pivots and Scripts.'
    }
    It 'approves at submission when the request says so' {
        $events = Invoke-Worker (New-Request -Action 'Submit' -Extra @{ AutoApprove = $true })
        $v = ($events | Where-Object Kind -eq 'Submitted').Value
        $v.Approved | Should -BeTrue
        Get-Calls | Should -Contain 'approval|GUID-1|Approve|Approved at submission by Pivots and Scripts.'
    }
    It 'reports the script as not approved when the site holds another state after the approval: <State>' -ForEach @(@{ State = 'Waiting for approval' }, @{ State = 'Denied' }) {
        $events = Invoke-Worker (New-Request -Action 'Submit' -Extra @{ AutoApprove = $true }) -Scenario @{ ApproveState = $State }
        (@($events | ForEach-Object Kind) -join ',') | Should -Be 'Submitted,Done'
        $v = ($events | Where-Object Kind -eq 'Submitted').Value
        $v.Approved | Should -BeFalse
        $v.ApprovalError | Should -Be "The site reports the state: $State."
    }
    It 'keeps the new script and reports why the approval failed' {
        $events = Invoke-Worker (New-Request -Action 'Submit' -Extra @{ AutoApprove = $true }) -Scenario @{ ApproveFail = 'The site requires a second approver.' }
        (@($events | ForEach-Object Kind) -join ',') | Should -Be 'Submitted,Done'
        $v = ($events | Where-Object Kind -eq 'Submitted').Value
        $v.Approved | Should -BeFalse
        $v.ApprovalError | Should -Be 'The site requires a second approver.'
        $v.Guid | Should -Be 'GUID-1'
    }
    It 'keeps the raw text of an approval error out of the event and writes it to the log file' {
        $log = Join-Path $TestDrive 'approval.log'
        $events = Invoke-Worker (New-Request -Action 'Submit' -Extra @{ AutoApprove = $true; LogPath = $log }) -Scenario @{ ApproveFailTyped = 'raw approval detail' }
        $v = ($events | Where-Object Kind -eq 'Submitted').Value
        $v.ApprovalError | Should -Be 'The approval failed. The log file has the details.'
        (Get-Content -LiteralPath $log -Raw) | Should -Match 'raw approval detail'
    }
    It 'reports a failed creation as one error and does not try to approve' {
        $events = Invoke-Worker (New-Request -Action 'Submit' -Extra @{ AutoApprove = $true }) -Scenario @{ SubmitFail = 'Script parameters could not be stored: x' }
        (@($events | ForEach-Object Kind) -join ',') | Should -Be 'Error,Done'
        Get-Calls | Should -Not -Contain 'approval|GUID-1|Approve|Approved at submission by Pivots and Scripts.'
    }
    It 'sends a fixed sentence for an error of another kind and writes the raw text to the log file' {
        $log = Join-Path $TestDrive 'submit.log'
        $events = Invoke-Worker (New-Request -Action 'Submit' -Extra @{ LogPath = $log }) -Scenario @{ SubmitFailTyped = 'raw submit detail' }
        (@($events | ForEach-Object Kind) -join ',') | Should -Be 'Error,Done'
        ($events | Where-Object Kind -eq 'Error').Value | Should -Be 'The operation failed. The log file has the details.'
        (Get-Content -LiteralPath $log -Raw) | Should -Match 'raw submit detail'
    }
    It 'does not write a log file when the request has no log path' {
        $events = Invoke-Worker (New-Request -Action 'Submit') -Scenario @{ SubmitFailTyped = 'raw submit detail' }
        ($events | Where-Object Kind -eq 'Error').Value | Should -Be 'The operation failed. The log file has the details.'
    }
}

Describe 'Worker run' {
    BeforeEach { Reset-Worker }
    It 'submits one CMPivot operation for the device list and reads all devices in each poll' {
        $events = Invoke-Worker (New-Request) -Scenario @{ Rows = @(
                @{ ResourceId = 11; DeviceName = 'PC-11'; ScriptExecutionState = 1; ScriptExitCode = 0; ErrorMessage = ''; ScriptOutput = $script:PivotOk }
                @{ ResourceId = 12; DeviceName = 'PC-12'; ScriptExecutionState = 0; ScriptExitCode = 0; ErrorMessage = ''; ScriptOutput = '' }) }
        $calls = Get-Calls
        @($calls | Where-Object { $_ -like 'pivot|*' }) | Should -Be @('pivot||11,12')
        @($calls | Where-Object { $_ -eq 'poll' }).Count | Should -Be 1
        $final = Get-FinalState $events
        $final['11'].State | Should -Be 'Response received'
        $final['12'].State | Should -Be 'No response within timeout'
        $final['13'].State | Should -Be 'Not a client'
        @($events | Where-Object Kind -eq 'Row').Count | Should -Be 1
        @($events | Where-Object { $_.Kind -eq 'Raw' -and $_.Value.Phase -eq 'Submit' }).Count | Should -Be 1
    }
    It 'sends the collection ID and adds a member that was not in the snapshot' {
        $events = Invoke-Worker (New-Request -Extra @{ CollectionId = 'SMS00001' }) -Scenario @{ Rows = @(
                @{ ResourceId = 11; DeviceName = 'PC-11'; ScriptExecutionState = 1; ScriptExitCode = 0; ErrorMessage = ''; ScriptOutput = $script:PivotOk }
                @{ ResourceId = 99; DeviceName = 'PC-99'; ScriptExecutionState = 1; ScriptExitCode = 0; ErrorMessage = ''; ScriptOutput = '<result ResultCode="0" moreResults="True"><e _i="0" Caption="Z" /></result>' }) }
        @(Get-Calls | Where-Object { $_ -like 'pivot|*' }) | Should -Be @('pivot|SMS00001|11,12')
        $extra = @($events | Where-Object { $_.Kind -eq 'Device' -and $_.Value.ResourceID -eq 99 })
        $extra[-1].Value.State | Should -Be 'Response received'
        $extra[-1].Value.Detail | Should -BeLike '*part of the results*'
    }
    It 'submits one script operation and reports a failed device' {
        $events = Invoke-Worker (New-Request -Mode 'Script' -Extra @{ Text = 'x' }) -Scenario @{ Rows = @(
                @{ ResourceId = 11; DeviceName = 'PC-11'; ScriptExecutionState = 2; ScriptExitCode = 1; ScriptOutput = '' }
                @{ ResourceId = 12; DeviceName = 'PC-12'; ScriptExecutionState = 1; ScriptExitCode = 0; ScriptOutput = '{\"Name\":\"Spooler\"}' }) }
        @(Get-Calls | Where-Object { $_ -like 'script|*' } | ForEach-Object { ($_ -split '\|')[0..2] -join '|' }) | Should -Be @('script||11,12')
        $final = Get-FinalState $events
        $final['11'].State | Should -Be 'Script failed'
        $final['11'].ExitCode | Should -Be 1
        $final['12'].State | Should -Be 'Response received'
        (@($events | Where-Object Kind -eq 'Row'))[0].Value.Name | Should -Be 'Spooler'
    }
    It 'opens one CIM session for a script run and closes it' {
        Invoke-Worker (New-Request -Mode 'Script') -Scenario @{ Rows = @() } | Out-Null
        @(Get-Calls | Where-Object { $_ -eq 'cim-open' }).Count | Should -Be 1
        @(Get-Calls | Where-Object { $_ -eq 'cim-close' }).Count | Should -Be 1
    }
    It 'opens no CIM session for a CMPivot run' {
        Invoke-Worker (New-Request) -Scenario @{ Rows = @() } | Out-Null
        @(Get-Calls | Where-Object { $_ -like 'cim-*' }).Count | Should -Be 0
    }
    It 'closes the CIM session also when the run fails' {
        Invoke-Worker (New-Request -Mode 'Script') -Scenario @{ NoScript = $true } | Out-Null
        @(Get-Calls | Where-Object { $_ -eq 'cim-close' }).Count | Should -Be 0
        Invoke-Worker (New-Request -Mode 'Script') -Scenario @{ PollThrow = 'broken'; PollStatus = 500 } | Out-Null
        @(Get-Calls | Where-Object { $_ -eq 'cim-close' }).Count | Should -Be 1
    }
    It 'ends with a Done event after <Case>' -ForEach @(
        @{ Case = 'a normal run';  Scenario = @{ Rows = @() } }
        @{ Case = 'a submission error'; Scenario = @{ StartThrow = 'no' } }
        @{ Case = 'a missing script';   Scenario = @{ NoScript = $true } }
    ) {
        $events = Invoke-Worker (New-Request -Mode 'Script') -Scenario $Scenario
        $events[-1].Kind | Should -Be 'Done'
        @($events | Where-Object Kind -eq 'Done').Count | Should -Be 1
    }
    It 'marks every device not a client and submits nothing when no target is a client' {
        $targets = @([pscustomobject]@{ Device = 'NC1'; ResourceID = 21; Client = $false; Active = $false }, [pscustomobject]@{ Device = 'NC2'; ResourceID = 22; Client = $false; Active = $false })
        $events = Invoke-Worker (New-Request -Extra @{ Targets = $targets })
        @($events | Where-Object { $_.Kind -eq 'Device' -and $_.Value.State -eq 'Not a client' }).Count | Should -Be 2
        @(Get-Calls | Where-Object { $_ -like 'pivot|*' }).Count | Should -Be 0
        $events[-1].Kind | Should -Be 'Done'
    }
    It 'does nothing for an empty target list' {
        $events = Invoke-Worker (New-Request -Extra @{ Targets = @() })
        (@($events | ForEach-Object Kind) -join ',') | Should -Be 'Done'
        @(Get-Calls | Where-Object { $_ -like 'pivot|*' }).Count | Should -Be 0
    }
    It 'submits nothing and marks the devices when the user stopped before submission' {
        $events = Invoke-Worker (New-Request) -Stopped
        @(Get-Calls | Where-Object { $_ -like 'pivot|*' }).Count | Should -Be 0
        $final = Get-FinalState $events
        $final['11'].State | Should -Be 'Not submitted'
        $final['12'].State | Should -Be 'Not submitted'
        $final['13'].State | Should -Be 'Not a client'
    }
    It 'reports a submission error on every device and polls nothing' {
        $events = Invoke-Worker (New-Request) -Scenario @{ StartThrow = 'AdminService returned HTTP 403 (Forbidden).' }
        $final = Get-FinalState $events
        $final['11'].State | Should -Be 'Submission error'
        $final['11'].Detail | Should -BeLike '*HTTP 403*'
        $final['12'].State | Should -Be 'Submission error'
        @(Get-Calls | Where-Object { $_ -eq 'poll' }).Count | Should -Be 0
    }
    It 'gives a fixed sentence for a submission error of another kind and logs the raw text' {
        $log = Join-Path $TestDrive 'start.log'
        $events = Invoke-Worker (New-Request -Extra @{ LogPath = $log }) -Scenario @{ StartThrowTyped = 'raw start detail' }
        $final = Get-FinalState $events
        $final['11'].Detail | Should -Be 'The run could not be submitted. The log file has the details.'
        $final['12'].Detail | Should -Be 'The run could not be submitted. The log file has the details.'
        (Get-Content -LiteralPath $log -Raw) | Should -Match 'raw start detail'
    }
    It 'reports a run that returns nothing as submitted without an operation ID, and polls nothing: <Mode>' -ForEach @(@{ Mode = 'Pivot' }, @{ Mode = 'Script' }) {
        $events = Invoke-Worker (New-Request -Mode $Mode) -Scenario @{ StartNone = $true }
        $final = Get-FinalState $events
        $final['11'].State | Should -Be 'Submitted, no operation ID'
        $final['12'].State | Should -Be 'Submitted, no operation ID'
        @(Get-Calls | Where-Object { $_ -eq 'poll' }).Count | Should -Be 0
    }
    It 'reports an answer without an operation ID as submitted without an operation ID: <Mode>' -ForEach @(@{ Mode = 'Pivot' }, @{ Mode = 'Script' }) {
        $events = Invoke-Worker (New-Request -Mode $Mode) -Scenario @{ StartNullId = $true }
        (Get-FinalState $events)['11'].State | Should -Be 'Submitted, no operation ID'
        (Get-FinalState $events)['11'].Detail | Should -BeLike '*Monitoring > Script Status*'
        @(Get-Calls | Where-Object { $_ -eq 'poll' }).Count | Should -Be 0
    }
    It 'gives each device the operation ID and a Waiting state before it polls' {
        $events = Invoke-Worker (New-Request) -Scenario @{ Rows = @() }
        $waiting = @($events | Where-Object { $_.Kind -eq 'Device' -and $_.Value.State -eq 'Waiting' })
        $waiting.Count | Should -Be 2
        $waiting[0].Value.OperationID | Should -Be 900
    }
    It 'reports a failed device as <State>: <Case>' -ForEach @(
        @{ Case = 'exit code 1';       Mode = 'Pivot';  State = 'Query failed';  Row = @{ ScriptExecutionState = 1; ScriptExitCode = 1; ErrorMessage = '' };  Detail = 'Exit code 1, execution state 1.' }
        @{ Case = 'execution state 2'; Mode = 'Pivot';  State = 'Query failed';  Row = @{ ScriptExecutionState = 2; ScriptExitCode = 0; ErrorMessage = '' };  Detail = 'Exit code 0, execution state 2.' }
        @{ Case = 'an error message';  Mode = 'Pivot';  State = 'Query failed';  Row = @{ ScriptExecutionState = 1; ScriptExitCode = 0; ErrorMessage = 'Boom' }; Detail = 'Exit code 0, execution state 1. Boom' }
        @{ Case = 'exit code 5';       Mode = 'Script'; State = 'Script failed'; Row = @{ ScriptExecutionState = 1; ScriptExitCode = 5; ErrorMessage = '' };  Detail = 'Exit code 5, execution state 1.' }
        @{ Case = 'a large exit code'; Mode = 'Script'; State = 'Script failed'; Row = @{ ScriptExecutionState = 1; ScriptExitCode = 4294967295; ErrorMessage = '' }; Detail = 'Exit code 4294967295, execution state 1.' }
    ) {
        $row = @{ ResourceId = 11; DeviceName = 'PC-11'; ScriptOutput = '' } + $Row
        $events = Invoke-Worker (New-Request -Mode $Mode) -Scenario @{ Rows = @($row) }
        $d = (Get-FinalState $events)['11']
        $d.State | Should -Be $State
        $d.Detail | Should -Be $Detail
    }
    It 'reports a device that returned a result only once, and skips a repeated row' {
        $row = @{ ResourceId = 11; DeviceName = 'PC-11'; ScriptExecutionState = 1; ScriptExitCode = 0; ErrorMessage = ''; ScriptOutput = $script:PivotOk }
        $events = Invoke-Worker (New-Request) -Scenario @{ Rows = @($row, $row) }
        @($events | Where-Object Kind -eq 'Row').Count | Should -Be 1
        @($events | Where-Object { $_.Kind -eq 'Device' -and $_.Value.ResourceID -eq 11 -and $_.Value.State -eq 'Response received' }).Count | Should -Be 1
    }
    It 'keeps the other devices when one device returns output that is not XML' {
        $events = Invoke-Worker (New-Request) -Scenario @{ Rows = @(
                @{ ResourceId = 11; DeviceName = 'PC-11'; ScriptExecutionState = 1; ScriptExitCode = 0; ErrorMessage = ''; ScriptOutput = 'this is not xml' }
                @{ ResourceId = 12; DeviceName = 'PC-12'; ScriptExecutionState = 1; ScriptExitCode = 0; ErrorMessage = ''; ScriptOutput = $script:PivotOk }) }
        @($events | Where-Object Kind -eq 'Error').Count | Should -Be 0
        $final = Get-FinalState $events
        $final['12'].State | Should -Be 'Response received'
        $final['11'].State | Should -Be 'Query failed'
        $final['11'].Detail | Should -Be 'The result could not be read. The log file has the details.'
        @($events | Where-Object Kind -eq 'Row').Count | Should -Be 1
    }
    It 'finds a result that arrives on a later poll' {
        $row = @{ ResourceId = 11; DeviceName = 'PC-11'; ScriptExecutionState = 1; ScriptExitCode = 0; ErrorMessage = ''; ScriptOutput = $script:PivotOk }
        $targets = @([pscustomobject]@{ Device = 'PC-11'; ResourceID = 11; Client = $true; Active = $true })
        $events = Invoke-Worker (New-Request -Extra @{ Targets = $targets; TimeoutSeconds = 30 }) -Scenario @{ Rows = @(); RowsLater = @($row) }
        @(Get-Calls | Where-Object { $_ -eq 'poll' }).Count | Should -Be 2
        (Get-FinalState $events)['11'].State | Should -Be 'Response received'
    }
    It 'treats a 404 from the status page as no result yet' {
        $events = Invoke-Worker (New-Request) -Scenario @{ PollThrow = 'AdminService returned HTTP 404 (Not Found).'; PollStatus = 404 }
        (Get-FinalState $events)['11'].State | Should -Be 'No response within timeout'
    }
    It 'reports the last polling error on the devices that got no result' {
        $log = Join-Path $TestDrive 'poll.log'
        $events = Invoke-Worker (New-Request -Extra @{ LogPath = $log }) -Scenario @{ PollThrow = 'AdminService returned HTTP 500 (Server Error).'; PollStatus = 500 }
        $d = (Get-FinalState $events)['11']
        $d.State | Should -Be 'Result error'
        $d.Detail | Should -Be 'The result could not be requested from the site. The log file has the details.'
        (Get-Content -LiteralPath $log -Raw) | Should -Match 'HTTP 500'
    }
    It 'forgets a polling error after a poll that works' {
        $row = @{ ResourceId = 11; DeviceName = 'PC-11'; ScriptExecutionState = 1; ScriptExitCode = 0; ErrorMessage = ''; ScriptOutput = $script:PivotOk }
        # The first poll fails, the second works and finds device 11, a third finds nothing more and the timeout ends the wait.
        $events = Invoke-Worker (New-Request -Extra @{ TimeoutSeconds = 4 }) -Scenario @{ PollThrow = 'AdminService returned HTTP 500 (Server Error).'; PollStatus = 500; PollThrowCount = 1; Rows = @($row) }
        @(Get-Calls | Where-Object { $_ -eq 'poll' }).Count | Should -BeGreaterThan 2
        $final = Get-FinalState $events
        $final['11'].State | Should -Be 'Response received'
        $final['12'].State | Should -Be 'No response within timeout'
    }
    It 'stops waiting on request and marks the devices that have not answered' {
        $row = @{ ResourceId = 11; DeviceName = 'PC-11'; ScriptExecutionState = 1; ScriptExitCode = 0; ErrorMessage = ''; ScriptOutput = $script:PivotOk }
        $events = Invoke-Worker (New-Request -Extra @{ TimeoutSeconds = 600 }) -Scenario @{ Rows = @($row); StopOnPoll = $true }
        $final = Get-FinalState $events
        $final['11'].State | Should -Be 'Response received'
        $final['12'].State | Should -Be 'Stopped waiting'
        $final['12'].Detail | Should -BeLike '*can still run*'
    }
}

Describe 'Worker script runs' {
    BeforeEach { Reset-Worker }
    It 'refuses a script that is not approved (state <State>), and sends nothing' -ForEach @(@{ State = 0 }, @{ State = 1 }, @{ State = 2 }) {
        $events = Invoke-Worker (New-Request -Mode 'Script') -Scenario @{ ApprovalState = $State; ScriptName = 'Uptime' }
        (@($events | ForEach-Object Kind) -join ',') | Should -Be 'Error,Done'
        ($events | Where-Object Kind -eq 'Error').Value | Should -BeLike "*(Uptime) is not approved (approval state $State)*"
        @(Get-Calls | Where-Object { $_ -like 'script|*' }).Count | Should -Be 0
    }
    It 'names no script in the refusal when the script has no name' {
        $events = Invoke-Worker (New-Request -Mode 'Script') -Scenario @{ ApprovalState = 0; ScriptName = '' }
        ($events | Where-Object Kind -eq 'Error').Value | Should -Not -BeLike '*()*'
    }
    It 'refuses a script that does not exist' {
        $events = Invoke-Worker (New-Request -Mode 'Script') -Scenario @{ NoScript = $true }
        ($events | Where-Object Kind -eq 'Error').Value | Should -BeLike '*does not exist in Configuration Manager*'
    }
    It 'refuses to run when the stored definitions cannot be read' {
        $events = Invoke-Worker (New-Request -Mode 'Script' -Extra @{ Parameters = @{ A = '1' } }) -Scenario @{ DefinitionError = 'The input is not a valid Base-64 string.' }
        ($events | Where-Object Kind -eq 'Error').Value | Should -BeLike '*cannot be read*'
        @(Get-Calls | Where-Object { $_ -like 'script|*' }).Count | Should -Be 0
    }
    It 'refuses a parameter that the site script does not define' {
        $events = Invoke-Worker (New-Request -Mode 'Script' -Extra @{ Parameters = @{ Nope = '1' } }) -Scenario @{ Definitions = @(@{ Name = 'Count'; Type = 'System.Int32' }) }
        ($events | Where-Object Kind -eq 'Error').Value | Should -BeLike "*Parameter 'Nope' is not defined*"
        @(Get-Calls | Where-Object { $_ -like 'script|*' }).Count | Should -Be 0
    }
    It 'sends typed arguments to the run: integers as numbers, text as text' {
        Invoke-Worker (New-Request -Mode 'Script' -Extra @{ Parameters = @{ Count = '7'; Name = 'Spooler' } }) -Scenario @{ Definitions = @(@{ Name = 'Count'; Type = 'System.Int32' }, @{ Name = 'Name'; Type = 'System.String' }); Rows = @() } | Out-Null
        $line = Get-Calls | Where-Object { $_ -like 'script|*' }
        $line | Should -BeLike '*|Count=7:Int32;Name=Spooler:String'
    }
    It 'shows the site script in the raw log before the run' {
        $events = Invoke-Worker (New-Request -Mode 'Script') -Scenario @{ Rows = @() }
        $raw = @($events | Where-Object { $_.Kind -eq 'Raw' -and $_.Value.Phase -eq 'Script' })
        $raw.Count | Should -Be 1
        $raw[0].Value.Response.ApprovalState | Should -Be 3
    }
    It 'turns Run Scripts output into rows with the trusted device identity' {
        $events = Invoke-Worker (New-Request -Mode 'Script') -Scenario @{ Rows = @(@{ ResourceId = 11; DeviceName = 'PC-11'; ScriptExecutionState = 1; ScriptExitCode = 0; ScriptOutput = '[{"A":1,"TargetDevice":"spoof"},{"A":2}]' }) }
        $rows = @($events | Where-Object Kind -eq 'Row' | ForEach-Object Value)
        $rows.Count | Should -Be 2
        $rows[0].TargetDevice | Should -Be 'PC-11'
        $rows[0].TargetResourceID | Should -Be 11
        @($rows | ForEach-Object A) | Should -Be @(1, 2)
    }
}
