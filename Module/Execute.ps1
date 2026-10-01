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
    $jobs = [Collections.Generic.List[object]]::new()
    $targets = @($Request.Targets)
    for ($index = 0; $index -lt $targets.Count; $index++) {
        $target = $targets[$index]
        if ($Control.Stop) {
            foreach ($rest in $targets[$index..($targets.Count-1)]) { Send-Device ([pscustomobject]@{Device=$rest.Device;ResourceID=$rest.ResourceID;OperationID=$null;ExitCode=$null}) 'Not submitted' 'Stopped before submission.' }
            break
        }
        $job=[pscustomobject]@{Device=$target.Device;ResourceID=$target.ResourceID;OperationID=$null;ExitCode=$null;State='Waiting';Started=[DateTime]::UtcNow;Finished=$false;LastError='';Polled=$false}
        if ($target.PSObject.Properties['Client'] -and $target.Client -eq $false) { Send-Device $job 'Not a client' 'The device has no Configuration Manager client.'; continue }
        try {
            if ($Request.Mode -eq 'Pivot') {
                $started = Start-PasPivot -SMSProvider $Request.Provider -ResourceID $target.ResourceID -Query $Request.Text
                $job.OperationID = $started.OperationID
                Send-Event 'Raw' ([pscustomobject]@{Device=$target.Device;Phase='Submit';Response=$started.Raw})
            } else {
                $started = Invoke-PasManagedScript -ScriptGuid $Request.ScriptGuid -ResourceID $target.ResourceID -Arguments $arguments
                Send-Event 'Raw' ([pscustomobject]@{Device=$target.Device;Phase='Submit';Response=$started})
                if ($null -eq $started.OperationID) { Send-Device $job 'Submitted, no operation ID' 'The site accepted the run but returned no operation ID. Check Monitoring > Script Status before running again.'; continue }
                $job.OperationID = $started.OperationID
            }
            $jobs.Add($job)
            Send-Device $job 'Waiting'
        } catch { Send-Device $job 'Submission error' $_.Exception.Message }
    }
    while (@($jobs | Where-Object { -not $_.Finished }).Count -gt 0 -and -not $Control.Stop) {
        foreach ($job in @($jobs | Where-Object { -not $_.Finished })) {
            if ($Control.Stop) { break }
            $raw = $null
            try {
                if ($Request.Mode -eq 'Pivot') { $raw = Get-PasPivotResult -SMSProvider $Request.Provider -ResourceID $job.ResourceID -OperationID $job.OperationID }
                else { $raw = Get-PasScriptStatus -CimSession $cim -SiteCode $Request.SiteCode -OperationID $job.OperationID -ResourceID $job.ResourceID }
                $job.LastError = ''
            } catch {
                $code = $_.Exception.Data['StatusCode']
                if (-not ($Request.Mode -eq 'Pivot' -and $code -eq 404)) { $job.LastError = $_.Exception.Message }
            }
            $job.Polled = $true
            if ($null -eq $raw) {
                # A device is timed out only after a poll that found no result.
                if (([DateTime]::UtcNow-$job.Started).TotalSeconds -gt $Request.TimeoutSeconds) {
                    $job.Finished=$true
                    if ($job.LastError) { Send-Device $job 'Result error' $job.LastError } else { Send-Device $job 'No response within timeout' 'No result arrived. The device can still run the operation.' }
                }
                continue
            }
            Send-Event 'Raw' ([pscustomobject]@{Device=$job.Device;Phase='Result';Response=$raw})
            $detail = ''
            if ($Request.Mode -eq 'Script') {
                $job.ExitCode = $raw.ScriptExitCode
                $rows = @(Convert-PasRows -Payload ([string]$raw.ScriptOutput) -Device $job.Device -ResourceID $job.ResourceID)
                $state = if ([int64]$raw.ScriptExitCode -ne 0 -or [int]$raw.ScriptExecutionState -eq 2) { 'Script failed' } else { 'Response received' }
                if ($state -eq 'Script failed') { $detail = "Exit code $($raw.ScriptExitCode), execution state $($raw.ScriptExecutionState)." }
            } else {
                $rows = @(Convert-PasRows -Payload $raw -Device $job.Device -ResourceID $job.ResourceID)
                $state = 'Response received'
                if ($raw.PSObject.Properties['value'] -and $null -ne $raw.value -and $raw.value.PSObject.Properties['MoreResult'] -and $raw.value.MoreResult -eq $true) { $detail = 'The provider reported more results than it returned.' }
            }
            foreach ($row in $rows) { Send-Event 'Row' $row }
            $job.Finished=$true
            Send-Device $job $state $detail
        }
        if (-not $Control.Stop -and @($jobs | Where-Object { -not $_.Finished }).Count) { Start-Sleep -Milliseconds 2000 }
    }
    if ($Control.Stop) { foreach ($job in @($jobs | Where-Object { -not $_.Finished })) { Send-Device $job 'Stopped waiting' 'The operation was sent and can still run on the device.' } }
} catch { Send-Event 'Error' $_.Exception.Message }
finally {
    if ($cim) { Remove-CimSession $cim }
    Send-Event 'Done' $null
}
