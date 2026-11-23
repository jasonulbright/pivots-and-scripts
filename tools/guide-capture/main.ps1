# Runs on the lab computer in the interactive session (scheduled task). Loads the UI
# Automation helpers, runs the steps file and writes the finished flag. The flag holds
# "finished" or "failed: <reason>", so Invoke-GuideCapture.ps1 can stop before it replaces an image.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'The dot-sourced steps file reads $appDir and $Capture.')]
param([string]$GuideRoot)
$ErrorActionPreference = 'Stop'
$OutDir = Join-Path $GuideRoot 'ui\out'; New-Item -ItemType Directory $OutDir -Force | Out-Null
$appDir = $GuideRoot
# The capture never touches the site data of a real profile: the site data of the app goes to a folder below the guide root,
# and no site is chosen by the environment. The steps set APP_PACKAGER_SITE themselves where a section needs a chosen site.
$env:APP_PACKAGER_DATA_ROOT = Join-Path $GuideRoot 'data'
foreach ($__n in 'APP_PACKAGER_SITE', 'SUITE_CM_SITECODE', 'SUITE_CM_PROVIDER') { Remove-Item -LiteralPath ('Env:' + $__n) -ErrorAction SilentlyContinue }
# Record this runner in the ledger, so that the capture tool stops it by process id and never by a command-line pattern.
$me = Get-Process -Id $PID
('{0}|{1}' -f $me.Id, $me.StartTime.Ticks) | Add-Content -LiteralPath (Join-Path $PSScriptRoot 'run.pids')
$status = 'finished'
try {
    . (Join-Path $GuideRoot 'ui\guilib.ps1')
    # Settings that the caller passes in (site code, SMS provider).
    $Capture = Get-Content -LiteralPath (Join-Path $GuideRoot 'ui\capture.json') -Raw | ConvertFrom-Json
    . (Join-Path $GuideRoot 'ui\steps.ps1')
}
catch {
    # The log may not exist when guilib.ps1 failed, so write the line directly.
    $status = 'failed: ' + $_.Exception.Message
    try { ('{0}  ERROR: {1} @ {2}' -f (Get-Date -Format 'HH:mm:ss'), $_.Exception.Message, $_.ScriptStackTrace) | Add-Content -LiteralPath (Join-Path $OutDir 'run.log') } catch { $null = $_ }
}
finally { $status | Set-Content (Join-Path $OutDir 'finished.flag') }
