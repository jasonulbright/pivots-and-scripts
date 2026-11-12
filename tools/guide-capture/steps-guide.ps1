# Capture steps for the user guide of Pivots and Scripts. Runs in the interactive session of a lab account.
# Read-only against the site. CMPivot runs on one device. A script is never run, submitted, approved,
# denied or removed: every confirmation of those actions is answered No.
$dataDir = Join-Path $env:LOCALAPPDATA 'SignalRidgeLabs\PivotsAndScripts'
Remove-Item $dataDir -Recurse -Force -ErrorAction SilentlyContinue
$win = Start-App 'start-pivotsandscripts.ps1' 'Pivots and Scripts'
Size-Win $win 1440 900
$win = Find-Top 'Pivots and Scripts' 10
$work = Join-Path $OutDir 'work'; New-Item -ItemType Directory $work -Force | Out-Null
function Idle([int]$sec = 180) {
    Start-Sleep -Seconds 1
    if (-not (Wait-Until { $b = Get-El $win 'btnRun' -Quiet; $b -and $b.Current.IsEnabled -and (Get-El $win 'btnConnect').Current.IsEnabled } $sec)) { throw "Timeout: the app stayed busy for $sec seconds." }
    Start-Sleep -Seconds 1
}
function Status { Get-ElText (Get-El $win 'status') }
function Pick-Kind([string]$kind) { $c = Get-El $win 'targetKind'; Expand-El $c; Start-Sleep -Milliseconds 400; Click-El (Find-Role $win 'ListItem' $kind); Start-Sleep -Milliseconds 500 }
function Tab([string]$name) { Select-El (Find-Role $win 'TabItem' $name); Start-Sleep -Milliseconds 900 }
function Top-Dialog {
    $c = New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)
    @($root.FindAll('Descendants', $c)) | Where-Object { $_.Current.Name -notin 'Pivots and Scripts', 'Program Manager', '' -and $_.Current.Name -notlike 'Administrator*' -and $_.Current.Name -notlike 'GlowWindow*' } | Select-Object -First 1
}
# Wait for a dialog, capture it, and answer with the named button. A missing button fails the capture.
function Answer([string]$shot, [string]$button) {
    if (-not (Wait-Until { $script:d2 = Top-Dialog; [bool]$script:d2 } 20)) { throw "No dialog for $shot" }
    $d = $script:d2
    Start-Sleep -Milliseconds 800; Shot $d $shot; Dump-Tree $d $shot
    $b = Get-El $d $button -Quiet
    if (-not $b) { throw "No $button button in $shot. Nothing was answered." }
    Invoke-El $b; Start-Sleep -Seconds 1
}
function Double-Click-El($El) {
    $r = $El.Current.BoundingRectangle; $x = [int]($r.X + $r.Width / 2); $y = [int]($r.Y + $r.Height / 2)
    [void][NativeUi]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 200
    1..2 | ForEach-Object { [NativeUi]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); [NativeUi]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 90 }
    Start-Sleep -Milliseconds 600
}
function Open-Library([string]$item) {
    $li = Find-Role $win 'ListItem' $item
    if (-not $li) { throw "Library item not found: $item" }
    Double-Click-El $li; Start-Sleep -Seconds 1
}

Section 'first run' {
    Shot $win 'start-first-run'; Dump-Tree $win 'main'
    Invoke-El (Get-El $win 'btnConnect'); Answer 'connect-without-connection' 'btnPrimary'
    Invoke-El (Get-El $win 'btnOptions'); $d = Find-Last 'Options' 10; Shot $d 'options-empty'; Dump-Tree $d 'options'
    Set-Text (Get-El $d 'txtSiteCode') $Capture.SiteCode; Set-Text (Get-El $d 'txtSmsProvider') $Capture.SMSProvider; Shot $d 'options-connection'
    Select-El (Find-Role $d 'ListItem' 'Run Scripts'); Start-Sleep -Milliseconds 600; Shot $d 'options-run-scripts'
    Select-El (Find-Role $d 'ListItem' 'About'); Start-Sleep -Milliseconds 600; Shot $d 'options-about'
    Select-El (Find-Role $d 'ListItem' 'Connection'); Start-Sleep -Milliseconds 400
    Set-Text (Get-El $d 'txtSiteCode') '12'; Invoke-El (Get-El $d 'btnOK'); Answer 'options-site-code-invalid' 'btnPrimary'
    Set-Text (Get-El $d 'txtSiteCode') $Capture.SiteCode; Invoke-El (Get-El $d 'btnOK'); Start-Sleep -Seconds 1
    Shot $win 'connection-set'
}
Section 'bad site code' {
    Invoke-El (Get-El $win 'btnOptions'); $d = Find-Last 'Options' 10; Set-Text (Get-El $d 'txtSiteCode') 'ZZZ'; Invoke-El (Get-El $d 'btnOK'); Start-Sleep -Seconds 1
    Invoke-El (Get-El $win 'btnConnect'); Idle; Start-Sleep -Seconds 1
    if ($null -ne (Top-Dialog)) { Answer 'connect-bad-site-code-message' 'btnPrimary' }
    Log ('status after bad site code: ' + (Status)); Shot $win 'connect-bad-site-code'
    Invoke-El (Get-El $win 'btnOptions'); $d = Find-Last 'Options' 10; Set-Text (Get-El $d 'txtSiteCode') $Capture.SiteCode; Invoke-El (Get-El $d 'btnOK'); Start-Sleep -Seconds 1
}
Section 'connect' {
    Invoke-El (Get-El $win 'btnConnect'); Start-Sleep -Seconds 2; Shot $win 'connect-running'; Idle
    Log ('status after connect: ' + (Status)); Shot $win 'connect-ok'
}
Section 'resolve' {
    Pick-Kind 'Collection'; Set-Text (Get-El $win 'targetInput') 'All Systems'; Invoke-El (Get-El $win 'btnResolve'); Idle
    Log ('resolve collection: ' + (Get-ElText (Get-El $win 'targetSummary'))); Shot $win 'resolve-collection'
    Pick-Kind 'Pattern'; Set-Text (Get-El $win 'targetInput') 'CLIENT*'; Invoke-El (Get-El $win 'btnResolve'); Idle; Shot $win 'resolve-pattern'
    Pick-Kind 'List'; Set-Text (Get-El $win 'targetInput') 'CLIENT01; CM01; NOSUCHPC'; Invoke-El (Get-El $win 'btnResolve'); Idle
    Log ('resolve list: ' + (Get-ElText (Get-El $win 'targetSummary'))); Shot $win 'resolve-list'
    Invoke-El (Get-El $win 'btnTargets'); Start-Sleep -Seconds 1; Shot $win 'targets-snapshot'
    Pick-Kind 'Device'; Set-Text (Get-El $win 'targetInput') 'CLIENT01'; Invoke-El (Get-El $win 'btnResolve'); Idle; Shot $win 'resolve-device'
    Set-Text (Get-El $win 'targetInput') 'CLIENT*'; Start-Sleep -Milliseconds 500; Shot $win 'targets-changed'
    Set-Text (Get-El $win 'targetInput') 'CLIENT01'; Invoke-El (Get-El $win 'btnResolve'); Idle
}
Section 'import list' {
    Set-Content (Join-Path $work 'devices.txt') "CLIENT01`r`nCM01" -Encoding ASCII
    Pick-Kind 'List'; Invoke-El (Get-El $win 'btnImport'); File-Dialog (Join-Path $work 'devices.txt') 'dialog-import-list'; Start-Sleep -Seconds 1; Shot $win 'import-list'
    Pick-Kind 'Device'; Set-Text (Get-El $win 'targetInput') 'CLIENT01'; Invoke-El (Get-El $win 'btnResolve'); Idle
}
Section 'library and editor' {
    Open-Library 'Operating system.cmpivot'; Shot $win 'pivot-library-open'
    Set-Text (Get-El $win 'libraryFilter') 'disk'; Start-Sleep -Seconds 1; Shot $win 'library-filter'; Set-Text (Get-El $win 'libraryFilter') ''
    Invoke-El (Get-El $win 'btnCheck'); Start-Sleep -Seconds 1; Shot $win 'pivot-check-syntax'
    Set-Text (Get-El $win 'findText') 'Caption'; Invoke-El (Get-El $win 'btnFind'); Start-Sleep -Milliseconds 700; Shot $win 'editor-find'
    Set-Text (Get-El $win 'findText') ''
}
Section 'run cmpivot' {
    Open-Library 'Operating system.cmpivot'
    Invoke-El (Get-El $win 'btnRun'); Answer 'confirm-run-cmpivot' 'btnNo'
    Log ('status after No: ' + (Status)); Shot $win 'run-cancelled'
    # Send the query only to the one resolved device. Stop when the snapshot is anything else.
    $summary = Get-ElText (Get-El $win 'targetSummary')
    if ($summary -notmatch '^Matched: 1 \|') { throw ('The target snapshot is not one device: ' + $summary) }
    Invoke-El (Get-El $win 'btnRun'); Answer 'confirm-run-cmpivot-yes' 'btnYes'
    Start-Sleep -Seconds 2; Shot $win 'run-working'
    Idle 240; Log ('status after run: ' + (Status)); Tab 'Results'; Shot $win 'results'
    Tab 'Devices'; Shot $win 'results-devices'; Tab 'Raw'; Shot $win 'results-raw'; Tab 'Pipeline'; Shot $win 'results-pipeline'; Tab 'Results'
    Set-Text (Get-El $win 'resultFilter') 'Windows'; Start-Sleep -Seconds 1; Shot $win 'results-filter'; Set-Text (Get-El $win 'resultFilter') ''
    $rows = @((Get-El $win 'results').FindAll('Descendants', (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::DataItem))))
    Log ('result rows: ' + $rows.Count)
    if ($rows.Count) { Select-El $rows[0]; Start-Sleep -Milliseconds 700; Shot $win 'results-selected' }
    Invoke-El (Get-El $win 'btnCsv'); File-Dialog (Join-Path $work 'results.csv') 'dialog-export-csv'; Start-Sleep -Seconds 1; Shot $win 'results-exported'
    Invoke-El (Get-El $win 'btnJson'); File-Dialog (Join-Path $work 'results.json') $null; Start-Sleep -Seconds 1
    Invoke-El (Get-El $win 'btnCopy'); Start-Sleep -Seconds 1; Shot $win 'results-copied'
    Invoke-El (Get-El $win 'btnGrid'); Start-Sleep -Seconds 5
    # Out-GridView opens its own window, which UI Automation names OutGridViewWindow Object. Find it by that name; fail the capture when it does not show.
    $g = $root.FindFirst('Descendants', (New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, 'OutGridViewWindow Object')))
    if (-not $g) {
        Log ('top windows: ' + ((@($root.FindAll('Children', [System.Windows.Automation.Condition]::TrueCondition)) | ForEach-Object { '{0}|{1}|{2}' -f $_.Current.Name, $_.Current.ClassName, $_.Current.ProcessId }) -join ' ; '))
        throw 'The Out-GridView window did not show.'
    }
    Shot $g 'results-gridview'; $g.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close(); Start-Sleep -Seconds 1
}
Section 'session' {
    Invoke-El (Get-El $win 'btnSaveSession'); File-Dialog (Join-Path $work 'session.json') 'dialog-save-session'; Start-Sleep -Seconds 1; Shot $win 'session-saved'
    Invoke-El (Get-El $win 'btnNewSession'); Start-Sleep -Seconds 1; Shot $win 'session-new'
    Invoke-El (Get-El $win 'btnHistory'); File-Dialog (Join-Path $work 'session.json') 'dialog-open-session'; Start-Sleep -Seconds 2; Shot $win 'session-opened'
}
Section 'selection without rows' {
    Invoke-El (Get-El $win 'btnSelectionScript'); Start-Sleep -Seconds 1
    if ($null -ne (Top-Dialog)) { Answer 'selection-none-message' 'btnPrimary' }
}
Section 'script view' {
    Pick-Kind 'Device'; Set-Text (Get-El $win 'targetInput') 'CLIENT01'; Invoke-El (Get-El $win 'btnResolve'); Idle
    Invoke-El (Get-El $win 'btnScript'); Start-Sleep -Seconds 2; Shot $win 'script-start'
    Open-Library 'Service state.ps1'; Shot $win 'script-library-open'
    Invoke-El (Get-El $win 'btnCheck'); Start-Sleep -Seconds 1; Shot $win 'script-check-syntax'
    Invoke-El (Get-El $win 'btnParameters'); Answer 'dialog-parameters' 'Close'
    Invoke-El (Get-El $win 'btnSubmit'); Answer 'confirm-submit-script' 'btnNo'
    Log ('status after submit No: ' + (Status)); Shot $win 'submit-cancelled'
    Invoke-El (Get-El $win 'btnRun'); Answer 'run-script-no-guid' 'btnPrimary'
    Invoke-El (Get-El $win 'btnSiteScripts'); Start-Sleep -Seconds 3
    $sd = Find-Last 'Site Scripts' 15; Start-Sleep -Seconds 4; Shot $sd 'dialog-site-scripts'; Dump-Tree $sd 'site-scripts'
    Invoke-El (Get-El $sd 'Close'); Start-Sleep -Seconds 1
    Set-Text (Get-El $win 'scriptGuid') '11111111-2222-3333-4444-555555555555'; Start-Sleep -Milliseconds 500
    Invoke-El (Get-El $win 'btnRun'); Answer 'confirm-run-script' 'btnNo'
    Shot $win 'script-guid-entered'
}
Section 'tab order' {
    Focus-Win $win; Click-El (Get-El $win 'btnPivot')
    1..16 | ForEach-Object { Send-Keys '{TAB}'; $f = [System.Windows.Automation.AutomationElement]::FocusedElement; Log ('tab -> ' + $f.Current.AutomationId + ' / ' + $f.Current.Name) }
}
Section 'light' {
    Toggle-El (Get-El $win 'toggleTheme'); Start-Sleep -Seconds 1
    Invoke-El (Get-El $win 'btnPivot'); Start-Sleep -Seconds 1; Shot $win 'light-pivot'
    Invoke-El (Get-El $win 'btnScript'); Start-Sleep -Seconds 1; Shot $win 'light-script'
    Invoke-El (Get-El $win 'btnOptions'); $d = Find-Last 'Options' 10; Shot $d 'light-options'; Invoke-El (Get-El $d 'btnCancel'); Start-Sleep -Seconds 1
    Toggle-El (Get-El $win 'toggleTheme')
}
Section 'persist' {
    Invoke-El (Get-El $win 'btnPivot'); Invoke-El (Get-El $win 'Close'); Start-Sleep -Seconds 8
    $win = Start-App 'start-pivotsandscripts.ps1' 'Pivots and Scripts'; Shot $win 'start-reopen'
}
Stop-App 'start-pivotsandscripts.ps1'
Remove-Item $dataDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
