#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }
# Window test for the chrome and the buttons of the main window and of every dialog, in both themes.
# Every dialog of the app is measured:
#   - the dialogs that Module\*Dialog.ps1 builds from XAML text (here-strings in the functions Show-...Dialog) are loaded,
#     given the theme the way the script gives it (Set-DialogTheme) and shown
#   - the dialogs that the start script and the modules take from SuiteCommon (Show-ThemedMessage, Show-ConfirmDialog) are
#     opened by the real function with the main window as owner, and measured and closed by a timer while they are open
# Rules:
#   - the dialog title bar brush (active and inactive) is the title bar brush of the main window
#   - the title bar text of the dialog is readable (4.5:1) on that brush
#   - every button has bold text (SemiBold or heavier, 600; a normal weight is a defect)
#   - no button has a border thicker than 1 px, and no button border has the text color of the theme

BeforeDiscovery {
    . "$PSScriptRoot\WindowHarness.ps1"
    $script:WindowGuard = Test-WindowTestsAllowed
    if (-not $script:WindowGuard.Allowed -and -not $env:SUITE_WINDOW_GUARD_REPORTED) { Write-Host ('Window tests skipped: {0}.' -f $script:WindowGuard.Reason) }
    $script:ThemeCases = @(@{ Dark = $true; Theme = 'dark' }, @{ Dark = $false; Theme = 'light' })
}

BeforeAll {
    . "$PSScriptRoot\WindowHarness.ps1"
    $script:WindowGuard = Test-WindowTestsAllowed
    if (-not $script:WindowGuard.Allowed) { return }
    . "$PSScriptRoot\WindowConfig.ps1"
    $script:RepoDir = Split-Path -Parent $PSScriptRoot
    $shellPath = Join-Path $script:RepoDir $script:AppConfig.Shell

    # A string that holds the XAML of a dialog.
    $isDialogString = {
        param($n)
        ($n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) -and $n.Value -match '^\s*<Controls:MetroWindow'
    }
    $sources = @($shellPath) + @($script:AppConfig.DialogFiles | ForEach-Object { Join-Path $script:RepoDir $_ })
    $script:OwnDialogFunction = @()
    $script:DialogFunctionCount = 0
    $dialogXaml = @()
    $called = @()
    foreach ($path in $sources) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
        $script:DialogFunctionCount += @([regex]::Matches((Get-Content -LiteralPath $path -Raw), '(?m)^function Show-\w*Dialog\b')).Count
        foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            foreach ($s in @($fn.Body.FindAll($isDialogString, $true))) {
                $script:OwnDialogFunction += $fn.Name
                $dialogXaml += $s.Value
            }
        }
        $called += @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
    }
    $called = @($called | Sort-Object -Unique)

    # The dialogs of SuiteCommon that the script and the modules call.
    $suiteAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:RepoDir 'Lib\SuiteCommon\SuiteCommon.psm1'), [ref]$null, [ref]$null)
    $suiteDialog = @($suiteAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and @($n.Body.FindAll($isDialogString, $true)).Count -gt 0 }, $true) | ForEach-Object { $_.Name })
    $script:SharedDialogFunction = @($suiteDialog | Where-Object { $called -contains $_ } | Sort-Object -Unique)

    $script:Measured = @{}
    foreach ($dark in $true, $false) {
        $key = if ($dark) { 'dark' } else { 'light' }
        $script:Measured[$key] = Invoke-WpfSta -Arguments @{ Dark = $dark; Config = $script:AppConfig; Dialogs = $dialogXaml; Shared = $script:SharedDialogFunction } -Script {
            $cfg = $Arguments.Config
            $main = Open-TestWindow -XamlPath (Join-Path $Root $cfg.Xaml) -Dark $Arguments.Dark
            Initialize-ShellTheme -Window $main -Dark $Arguments.Dark -Views $cfg.Views -OptionsButtonNames $cfg.OptionsButtons -ActiveView $cfg.Views[0].Mode
            $mainChrome = Get-SuiteWindowChrome -Window $main -Label 'main'
            $out = [pscustomobject]@{
                ThemeText = $mainChrome.ThemeText
                MainTitle = $mainChrome.Active; MainTitleInactive = $mainChrome.Inactive
                Main = @($mainChrome.Buttons); Dialogs = @(); Unmeasured = @()
            }
            $left = if ($env:SUITE_VISIBLE_WINDOWS -eq '1') { 120 } else { -32000 }
            $i = 0
            foreach ($xaml in $Arguments.Dialogs) {
                $i++
                [xml]$x = $xaml
                $d = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
                $d.WindowStartupLocation = 'Manual'
                $d.Left = $left; $d.Top = $left
                $d.ShowInTaskbar = $false
                Set-DialogTheme -Dialog $d -IsDark $Arguments.Dark
                $d.Show(); Wait-Layout $d
                $c = Get-SuiteWindowChrome -Window $d -Label ([string]$d.Title)
                $out.Dialogs += [pscustomobject]@{ Title = $c.Title; Index = $i; Source = 'script'; Active = $c.Active; Inactive = $c.Inactive; TitleRatio = $c.TitleRatio; Buttons = @($c.Buttons) }
                $d.Close()
            }

            # SuiteCommon dialogs: the real function opens the dialog modal; a timer measures and closes it.
            # The owned windows of the main window include the glow windows of MahApps, so take only the MetroWindow.
            foreach ($name in $Arguments.Shared) {
                $holder = @{ Chrome = $null; Error = $null }
                $timer = New-Object System.Windows.Threading.DispatcherTimer
                $timer.Interval = [TimeSpan]::FromMilliseconds(700)
                $mainWindow = $main
                $timer.Add_Tick({
                        $timer.Stop()
                        try {
                            $d = @($mainWindow.OwnedWindows) | Where-Object { $_ -is [MahApps.Metro.Controls.MetroWindow] } | Select-Object -First 1
                            Wait-Layout $d
                            $holder.Chrome = Get-SuiteWindowChrome -Window $d -Label ([string]$d.Title)
                            $d.Close()
                        }
                        catch { $holder.Error = $_.ToString(); foreach ($o in @($mainWindow.OwnedWindows)) { $o.Close() } }
                    }.GetNewClosure())
                $watchdog = New-Object System.Windows.Threading.DispatcherTimer
                $watchdog.Interval = [TimeSpan]::FromSeconds(10)
                $watchdog.Add_Tick({ $holder.Error = 'watchdog closed the dialog'; foreach ($o in @($mainWindow.OwnedWindows)) { $o.Close() }
                    }.GetNewClosure())
                $timer.Start(); $watchdog.Start()
                try {
                    switch ($name) {
                        'Show-ThemedMessage' { [void](Show-ThemedMessage -Owner $main -Title 'Error' -Message 'The query could not run.' -Buttons OK) }
                        'Show-ConfirmDialog' { [void](Show-ConfirmDialog -Title 'Remove Script' -Message 'Permanently remove the script?' -Owner $main) }
                        default { $timer.Stop(); $holder.Error = 'no recipe for ' + $name }
                    }
                }
                finally { $timer.Stop(); $watchdog.Stop() }
                if ($holder.Chrome) {
                    $c = $holder.Chrome
                    $out.Dialogs += [pscustomobject]@{ Title = $c.Title; Index = 0; Source = $name; Active = $c.Active; Inactive = $c.Inactive; TitleRatio = $c.TitleRatio; Buttons = @($c.Buttons) }
                }
                else { $out.Unmeasured += ('{0}: {1}' -f $name, $holder.Error) }
            }
            $main.Close()
            $out
        }
    }
}

AfterAll {
    if ($script:WindowGuard.Allowed) { Close-WpfSession }
}

Describe 'Chrome <Theme>' -ForEach $script:ThemeCases -Skip:(-not $script:WindowGuard.Allowed) {
    BeforeAll { $script:M = $script:Measured[$Theme] }

    It 'finds every dialog of the app: the dialogs of the modules and the dialogs of SuiteCommon that they call' {
        # One dialog window per function Show-...Dialog of the script and the modules.
        $script:DialogFunctionCount | Should -BeGreaterOrEqual 3
        @($script:OwnDialogFunction | Sort-Object -Unique).Count | Should -Be $script:DialogFunctionCount
        @($script:M.Dialogs | Where-Object { $_.Source -eq 'script' }).Count | Should -Be $script:DialogFunctionCount
        $script:SharedDialogFunction.Count | Should -BeGreaterThan 0
        @($script:M.Dialogs | Where-Object { $_.Source -ne 'script' }).Count | Should -Be $script:SharedDialogFunction.Count
        @($script:M.Unmeasured) | Should -BeNullOrEmpty
    }

    It 'gives every dialog the title bar brush of the main window' {
        $bad = @($script:M.Dialogs | Where-Object { $_.Active -ne $script:M.MainTitle -or $_.Inactive -ne $script:M.MainTitleInactive } |
                ForEach-Object { '{0}: active {1} inactive {2}, main {3} {4}' -f $_.Title, $_.Active, $_.Inactive, $script:M.MainTitle, $script:M.MainTitleInactive })
        $bad | Should -BeNullOrEmpty
    }

    It 'keeps the title text of every dialog readable at 4.5:1' {
        $bad = @($script:M.Dialogs | Where-Object { $_.TitleRatio -lt 4.5 } | ForEach-Object { '{0}: {1}' -f $_.Title, $_.TitleRatio })
        $bad | Should -BeNullOrEmpty
    }

    It 'shows bold text on every button of the main window and of every dialog' {
        $all = @($script:M.Main) + @($script:M.Dialogs | ForEach-Object { $_.Buttons })
        $all.Count | Should -BeGreaterThan 5
        $bad = @($all | Where-Object { $_.Weight -lt 600 } | ForEach-Object { '{0} "{1}" weight {2}' -f $_.Window, $_.Text, $_.Weight })
        $bad | Should -BeNullOrEmpty
    }

    It 'gives no button a border thicker than 1 px or in the text color of the theme' {
        $all = @($script:M.Main) + @($script:M.Dialogs | ForEach-Object { $_.Buttons })
        $bad = @($all | Where-Object { $_.BorderThickness -gt 1 -or ($_.BorderThickness -gt 0 -and $_.BorderColor -eq $script:M.ThemeText) } |
                ForEach-Object { '{0} "{1}" border {2}px {3}' -f $_.Window, $_.Text, $_.BorderThickness, $_.BorderColor })
        $bad | Should -BeNullOrEmpty
    }
}
