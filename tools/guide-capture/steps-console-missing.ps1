# Test copy only: make the module path lookup return nothing, as on a computer without the console.
$dataDir = Join-Path $env:LOCALAPPDATA 'SignalRidgeLabs\PivotsAndScripts'
Remove-Item $dataDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $dataDir -Force | Out-Null
(@{ SiteCode = $Capture.SiteCode; SMSProvider = $Capture.SMSProvider; ApproveAfterSubmit = $false } | ConvertTo-Json) | Set-Content (Join-Path $dataDir 'preferences.json') -Encoding UTF8
$f = Join-Path $appDir 'Lib\SuiteCommon\SuiteCommon.psm1'
$t = Get-Content -LiteralPath $f -Raw
$patched = [regex]::Replace($t, '(function Resolve-ConfigurationManagerModulePath \{)', '${1} return $null;')
if ($patched -eq $t) { throw 'The module lookup function was not found. The missing-console test cannot run.' }
Set-Content -LiteralPath $f -Value $patched -Encoding UTF8
Remove-Item Env:SMS_ADMIN_UI_PATH -ErrorAction SilentlyContinue
$win = Start-App 'start-pivotsandscripts.ps1' 'Pivots and Scripts'
Size-Win $win 1440 900
$win = Find-Top 'Pivots and Scripts' 10
$before = Get-ElText (Get-El $win 'status')
Invoke-El (Get-El $win 'btnConnect')
# The failure shows in the status line. Wait for it to change; a fixed sleep is not evidence.
if (-not (Wait-Until { (Get-ElText (Get-El $win 'status')) -ne $before -and (Get-El $win 'btnConnect').Current.IsEnabled } 60)) { throw 'The status line did not change after Test Connection.' }
Start-Sleep -Seconds 1
Log ('status: ' + (Get-ElText (Get-El $win 'status')))
Shot $win 'console-missing-connect'
Stop-App 'start-pivotsandscripts.ps1'
Remove-Item $dataDir -Recurse -Force -ErrorAction SilentlyContinue