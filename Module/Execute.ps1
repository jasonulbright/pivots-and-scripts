param($Request,$Queue,$Control)
$ErrorActionPreference='Stop'
function Send-Event { param([string]$Kind,$Value) $Queue.Enqueue([pscustomobject]@{Kind=$Kind;Value=$Value}) }
function Send-Device { param($Job,[string]$State,[string]$Detail='') Send-Event 'Device' ([pscustomobject]@{Device=$Job.Device;ResourceID=$Job.ResourceID;OperationID=$Job.OperationID;State=$State;ExitCode=$Job.ExitCode;Detail=$Detail}) }
$cim=$null
try {
    Import-Module $Request.Module -Force -DisableNameChecking
    Assert-PasConnection -SiteCode $Request.SiteCode -SMSProvider $Request.Provider
    if ($Request.Action -eq 'Connect') { Send-Event 'Notice' "Connected to site $($Request.SiteCode)."; return }
    if ($Request.Action -eq 'Resolve') { Send-Event 'Targets' (Resolve-PasTargets -Kind $Request.Kind -InputText $Request.InputText); return }
    if ($Request.Action -eq 'Submit') {
        $script = New-PasManagedScript -Text $Request.Text -SMSProvider $Request.Provider -SiteCode $Request.SiteCode
        $approval = ''; $approved = $false
        if ($Request.AutoApprove) {
            try { $null = Set-PasScriptApproval -ScriptGuid $script.ScriptGuid -Decision Approve -Comment 'Approved at submission by Pivots and Scripts.'; $approved = $true }
            catch { $approval = $_.Exception.Message }
        }
        Send-Event 'Submitted' ([pscustomobject]@{Guid=[string]$script.ScriptGuid;Hash=(Get-PasHash $Request.Text);Parameters=@($script.Parameters);Approved=$approved;ApprovalError=$approval})
        return
    }
    if ($Request.Action -eq 'Scripts') { Send-Event 'Scripts' @(Get-PasSiteScripts -SMSProvider $Request.Provider -SiteCode $Request.SiteCode); return }
    # The list event sets the status line too; the decision is sent last so the status names it.
    if ($Request.Action -in @('Approve','Deny')) { $result = Set-PasScriptApproval -ScriptGuid $Request.ScriptGuid -Decision $Request.Action -Comment $Request.Comment; Send-Event 'Scripts' @(Get-PasSiteScripts -SMSProvider $Request.Provider -SiteCode $Request.SiteCode); Send-Event 'ScriptChanged' $result; return }
    if ($Request.Action -eq 'Remove') { $result = Remove-PasManagedScript -ScriptGuid $Request.ScriptGuid; Send-Event 'Scripts' @(Get-PasSiteScripts -SMSProvider $Request.Provider -SiteCode $Request.SiteCode); Send-Event 'ScriptChanged' $result; return }
    $arguments=@{}
    if ($Request.Mode -eq 'Script') {
        $site = Get-PasSiteScript -SMSProvider $Request.Provider -SiteCode $Request.SiteCode -ScriptGuid $Request.ScriptGuid
        if (-not $site) { throw "Script $($Request.ScriptGuid) does not exist in Configuration Manager." }
        if ($site.ApprovalState -ne 3) { throw "Script $($site.ScriptGuid) $(if($site.ScriptName){'('+$site.ScriptName+') '})is not approved (approval state $($site.ApprovalState)). Obtain approval in Configuration Manager." }
        $arguments = ConvertTo-PasScriptArguments -SiteScript $site -Parameters $Request.Parameters
        Send-Event 'Raw' ([pscustomobject]@{Device='';Phase='Script';Response=$site})
        $cim = New-PasCimSession $Request.Provider
    }
    # One operation per run; the site fans it out to the clients, as the console does.
    $jobs = @{}
    foreach ($target in @($Request.Targets)) {
        $job=[pscustomobject]@{Device=$target.Device;ResourceID=[int]$target.ResourceID;OperationID=$null;ExitCode=$null;Finished=$false}
        if ($target.PSObject.Properties['Client'] -and $target.Client -eq $false) { Send-Device $job 'Not a client' 'The device has no Configuration Manager client.'; continue }
        $jobs[[string]$job.ResourceID] = $job
    }
    if (-not $jobs.Count) { return }
    if ($Control.Stop) { foreach ($job in $jobs.Values) { Send-Device $job 'Not submitted' 'Stopped before submission.' }; return }
    $ids = @($jobs.Values | ForEach-Object { $_.ResourceID } | Sort-Object)
    $collectionId = [string]$Request.CollectionId
    try {
        if ($Request.Mode -eq 'Pivot') { $operations = @(Start-PasPivotRun -SMSProvider $Request.Provider -Query $Request.Text -CollectionId $collectionId -ResourceIds $ids) }
        else { $operations = @(Start-PasScriptRun -ScriptGuid $Request.ScriptGuid -Arguments $arguments -CollectionId $collectionId -ResourceIds $ids) }
    } catch { foreach ($job in $jobs.Values) { Send-Device $job 'Submission error' $_.Exception.Message }; return }
    foreach ($operation in $operations) { Send-Event 'Raw' ([pscustomobject]@{Device='';Phase='Submit';Response=$(if ($operation.PSObject.Properties['Raw']) { $operation.Raw } else { $operation })}) }
    if (@($operations | Where-Object { $null -eq $_.OperationID }).Count) {
        foreach ($job in $jobs.Values) { Send-Device $job 'Submitted, no operation ID' 'The site accepted the run but returned no operation ID. Check Monitoring > Script Status before running again.' }
        return
    }
    foreach ($job in $jobs.Values) { $job.OperationID = $operations[0].OperationID }

    foreach ($job in $jobs.Values) { Send-Device $job 'Waiting' }
    $started = [DateTime]::UtcNow; $lastError = ''
    while (-not $Control.Stop) {
        foreach ($operation in $operations) {
            if ($Control.Stop) { break }
            try {
                if ($Request.Mode -eq 'Pivot') { $statusRows = @(Get-PasPivotStatus -SMSProvider $Request.Provider -OperationID $operation.OperationID) }
                else { $statusRows = @(Get-PasScriptRunStatus -CimSession $cim -SiteCode $Request.SiteCode -OperationID $operation.OperationID) }
                $lastError = ''
            } catch { if ($_.Exception.Data['StatusCode'] -ne 404) { $lastError = $_.Exception.Message }; continue }
            foreach ($status in $statusRows) {
                # State 0 is a row that exists before the client reports.
                if ([int]$status.ScriptExecutionState -eq 0) { continue }
                $key = [string]$status.ResourceId
                $job = $jobs[$key]
                if (-not $job) { $job = [pscustomobject]@{Device=[string]$status.DeviceName;ResourceID=[int]$status.ResourceId;OperationID=$operation.OperationID;ExitCode=$null;Finished=$false}; $jobs[$key] = $job }
                if ($job.Finished) { continue }
                Send-Event 'Raw' ([pscustomobject]@{Device=$job.Device;Phase='Result';Response=$status})
                $job.ExitCode = $status.ScriptExitCode
                $errorText = if ($status.PSObject.Properties['ErrorMessage']) { [string]$status.ErrorMessage } else { '' }
                $failed = [int64]$status.ScriptExitCode -ne 0 -or [int]$status.ScriptExecutionState -eq 2 -or -not [string]::IsNullOrWhiteSpace($errorText)
                $detail = ''
                if ($Request.Mode -eq 'Pivot') {
                    $parsed = ConvertFrom-PasPivotOutput -Output ([string]$status.ScriptOutput) -Device $job.Device -ResourceID $job.ResourceID
                    $rows = @($parsed.Rows)
                    if ($parsed.MoreResults) { $detail = 'The site returned part of the results for this device.' }
                    $state = if ($failed) { 'Query failed' } else { 'Response received' }
                } else {
                    $rows = @(Convert-PasRows -Payload ([string]$status.ScriptOutput) -Device $job.Device -ResourceID $job.ResourceID)
                    $state = if ($failed) { 'Script failed' } else { 'Response received' }
                }
                if ($failed) { $detail = (@("Exit code $($status.ScriptExitCode), execution state $($status.ScriptExecutionState).", $errorText) | Where-Object { $_ }) -join ' ' }
                foreach ($row in $rows) { Send-Event 'Row' $row }
                $job.Finished = $true
                Send-Device $job $state $detail
            }
        }
        $pending = @($jobs.Values | Where-Object { -not $_.Finished })
        if (-not $pending.Count -or $Control.Stop) { break }
        # A device is timed out only after a poll that found no result for it.
        if (([DateTime]::UtcNow - $started).TotalSeconds -gt $Request.TimeoutSeconds) {
            foreach ($job in $pending) { $job.Finished = $true; if ($lastError) { Send-Device $job 'Result error' $lastError } else { Send-Device $job 'No response within timeout' 'No result arrived. The device can still run the operation.' } }
            break
        }
        Start-Sleep -Milliseconds 3000
    }
    if ($Control.Stop) { foreach ($job in @($jobs.Values | Where-Object { -not $_.Finished })) { Send-Device $job 'Stopped waiting' 'The operation was sent and can still run on the device.' } }
} catch { Send-Event 'Error' $_.Exception.Message }
finally {
    if ($cim) { Remove-CimSession $cim }
    Send-Event 'Done' $null
}
