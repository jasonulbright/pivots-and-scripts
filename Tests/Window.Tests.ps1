#Requires -Modules Pester
# Window tests. The main window is opened off screen on an STA thread in both views (CMPivot and
# PowerShell), in both themes and at 1024x720 and 1440x900, and measured. The three dialogs are built
# from XAML text in Module\*Dialog.ps1; their XAML is opened and measured too. The app-specific names
# live in WindowConfig.ps1. The views are modes of one layout: the tests run the real Set-PasMode of the
# start script to switch them.

BeforeDiscovery {
    . "$PSScriptRoot\WindowHarness.ps1"
    $script:WindowGuard = Test-WindowTestsAllowed
    if (-not $script:WindowGuard.Allowed) { Write-Host ("Window tests skipped: {0}" -f $script:WindowGuard.Reason) }
    . "$PSScriptRoot\WindowConfig.ps1"
    $script:Matrix = foreach ($dark in $true, $false) {
        foreach ($size in @(@(1024, 720), @(1440, 900))) {
            @{ Dark = $dark; Theme = $(if ($dark) { 'dark' } else { 'light' }); W = $size[0]; H = $size[1]; Size = ('{0}x{1}' -f $size[0], $size[1]) }
        }
    }
    $script:ViewCases = @($script:AppConfig.Views | ForEach-Object { @{ View = $_.Name } })
    $root = Split-Path -Parent $PSScriptRoot
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $script:AppConfig.Shell), [ref]$null, [ref]$null)
    # The shell looks the controls up in a loop: foreach($name in @('btnPivot',...)) { $ui[$name]=$window.FindName($name) }.
    $loop = $ast.Find({
            param($n)
            $n -is [System.Management.Automation.Language.ForEachStatementAst] -and $n.Body.Extent.Text -match '\$window\.FindName\(\$name\)'
        }, $true)
    $script:NameCases = @($loop.Condition.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) |
            ForEach-Object { $_.Value } | Sort-Object -Unique | ForEach-Object { @{ Name = $_ } })
    $script:DialogCases = @(foreach ($f in $script:AppConfig.DialogFiles) {
            $a = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $f), [ref]$null, [ref]$null)
            $n = @($a.FindAll({ param($x) $x -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $x.Value -match '^\s*<Controls:MetroWindow' }, $true)).Count
            for ($i = 0; $i -lt $n; $i++) { @{ File = $f; Index = $i; Key = ('{0}#{1}' -f $f, $i) } }
        })
}

BeforeAll {
    . "$PSScriptRoot\WindowHarness.ps1"
    # No runspace and no window unless the guard allows it. AfterAll tolerates "no session".
    if (-not (Test-WindowTestsAllowed).Allowed) { return }
    . "$PSScriptRoot\TestHelpers.ps1"
    . "$PSScriptRoot\KnownContrastDefects.ps1"
    . "$PSScriptRoot\WindowConfig.ps1"
    $script:Root = Split-Path -Parent $PSScriptRoot
    $script:ShellPath = Join-Path $script:Root $script:AppConfig.Shell
    $script:XamlPath = Join-Path $script:Root $script:AppConfig.Xaml

    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ShellPath, [ref]$null, [ref]$null)
    $loop = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] -and $n.Body.Extent.Text -match '\$window\.FindName\(\$name\)' }, $true)
    $script:WindowNames = @($loop.Condition.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { $_.Value } | Sort-Object -Unique)

    # XAML text of every dialog, and the shell and dialog files that name a message title.
    $script:DialogXaml = @{}
    $script:DialogLookups = @{}
    $script:TitleSources = @(Get-Content -LiteralPath $script:ShellPath -Raw -Encoding UTF8)
    foreach ($f in $script:AppConfig.DialogFiles) {
        $a = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root $f), [ref]$null, [ref]$null)
        $found = @($a.FindAll({ param($x) $x -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $x.Value -match '^\s*<Controls:MetroWindow' }, $true))
        for ($i = 0; $i -lt $found.Count; $i++) { $script:DialogXaml['{0}#{1}' -f $f, $i] = $found[$i].Value }
        $script:DialogLookups[$f] = @($a.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'FindName' -and
                    $n.Expression.Extent.Text -eq '$dialog' -and $n.Arguments.Count -eq 1 -and $n.Arguments[0] -is [System.Management.Automation.Language.StringConstantExpressionAst]
                }, $true) | ForEach-Object { $_.Arguments[0].Value } | Sort-Object -Unique)
        $script:TitleSources += Get-Content -LiteralPath (Join-Path $script:Root $f) -Raw -Encoding UTF8
    }

    $modeFunctions = @(Get-ScriptFunctionText -Path $script:ShellPath -Name $script:AppConfig.ModeFunctions)

    $script:Measured = @{}
    foreach ($case in @(
            @{ Dark = $true; W = 1024; H = 720 }, @{ Dark = $true; W = 1440; H = 900 },
            @{ Dark = $false; W = 1024; H = 720 }, @{ Dark = $false; W = 1440; H = 900 })) {
        $key = '{0}|{1}x{2}' -f $(if ($case.Dark) { 'dark' } else { 'light' }), $case.W, $case.H
        $case.Config = $script:AppConfig
        $case.ModeFunctions = $modeFunctions
        $script:Measured[$key] = Invoke-WpfSta -Arguments $case -Script {
            $cfg = $Arguments.Config
            $w = Open-TestWindow -XamlPath (Join-Path $Root $cfg.Xaml) -Dark $Arguments.Dark -Width $Arguments.W -Height $Arguments.H
            # The real functions of the start script switch the view; they read these variables.
            foreach ($text in $Arguments.ModeFunctions) { . ([scriptblock]::Create($text)) }
            $global:ui = @{}
            foreach ($n in 'heading', 'editorLabel', 'btnRun', 'btnSubmit', 'guidLabel', 'scriptGuid', 'btnParameters', 'btnSiteScripts', 'editor', 'library', 'libraryFilter', 'toggleTheme') { $global:ui[$n] = $w.FindName($n) }
            $global:ui.toggleTheme.IsOn = [bool]$Arguments.Dark
            Set-TestFixtureText $w
            $script:mode = 'Pivot'
            $script:drafts = @{ Pivot = 'Disk | project Device, Name, FreeSpace'; Script = '' }
            # Contrast is read only at 1440x900. Clipped text and off-screen controls are read at both sizes.
            $full = $Arguments.W -ge 1440
            $out = @()
            foreach ($view in $cfg.Views) {
                $global:HarnessActiveView = $view.Mode
                Initialize-ShellTheme -Window $w -Dark $Arguments.Dark -Views $cfg.Views -OptionsButtonNames $cfg.OptionsButtons -ActiveView $view.Mode
                Set-PasMode $view.Mode
                if ($view.Mode -eq 'Pivot') { $global:ui.editor.Text = 'Disk | project Device, Name, FreeSpace' }
                Wait-Layout $w
                $out += [PSCustomObject]@{
                    View        = $view.Name
                    Heading     = [string]$global:ui.heading.Text
                    GuidVisible = [string]$global:ui.scriptGuid.Visibility
                    RunText     = [string]$global:ui.btnRun.Content
                    MinWidth    = $w.MinWidth
                    MinHeight   = $w.MinHeight
                    Text        = if ($full) { @(Get-TextContrast $w) } else { @() }
                    Clipped     = @(Get-ClippedText $w)
                    Offscreen   = @(Get-OffscreenControls $w)
                    Interactive = if ($full) { @(Get-InteractiveContrast $w) } else { @() }
                    TitleBar    = if ($full) { Get-TitleBarContrast $w } else { $null }
                }
            }
            $w.Close()
            , $out
        }
    }
}

AfterAll { if (Get-Command Close-WpfSession -ErrorAction SilentlyContinue) { Close-WpfSession } }

Describe 'Main window XAML' -Skip:(-not $script:WindowGuard.Allowed) {
    It 'loads as a MetroWindow with the app title and a minimum size that fits 1024x720' {
        $r = Invoke-WpfSta -Arguments @{ Xaml = $script:AppConfig.Xaml } -Script {
            $w = Open-TestWindow -XamlPath (Join-Path $Root $Arguments.Xaml)
            $o = [PSCustomObject]@{ Type = $w.GetType().FullName; Title = $w.Title; MinW = $w.MinWidth; MinH = $w.MinHeight }
            $w.Close(); $o
        }
        $r.Type | Should -Be 'MahApps.Metro.Controls.MetroWindow'
        $r.Title | Should -Be $script:AppConfig.Title
        $r.MinW | Should -BeLessOrEqual 1024
        $r.MinH | Should -BeLessOrEqual 720
    }

    It 'declares each x:Name once' {
        $names = [regex]::Matches((Get-Content -LiteralPath $script:XamlPath -Raw -Encoding UTF8), 'x:Name="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
        ($names | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name) | Should -BeNullOrEmpty
    }

    It 'finds the script look-ups of the window' {
        $script:WindowNames.Count | Should -BeGreaterThan 40
    }

    It 'has the control <Name> that the script looks up' -ForEach $script:NameCases {
        (Get-Content -LiteralPath $script:XamlPath -Raw -Encoding UTF8) | Should -Match ('x:Name="{0}"' -f [regex]::Escape($Name))
    }

    It 'has the sidebar button of view <Name>' -ForEach $script:AppConfig.Views {
        (Get-Content -LiteralPath $script:XamlPath -Raw -Encoding UTF8) | Should -Match ('x:Name="{0}"' -f $Button)
    }

    It 'starts in the first view' {
        $first = $script:AppConfig.Views[0]
        $m = $script:Measured['dark|1440x900'] | Where-Object View -eq $first.Name
        $m.Heading | Should -Be $first.Heading
        $m.GuidVisible | Should -Be 'Collapsed'
    }

    It 'shows the script controls only in the script view' {
        ($script:Measured['dark|1440x900'] | Where-Object View -eq 'Script').GuidVisible | Should -Be 'Visible'
        ($script:Measured['dark|1440x900'] | Where-Object View -eq 'Pivot').GuidVisible | Should -Be 'Collapsed'
    }

    It 'names the run button after the view' {
        ($script:Measured['dark|1440x900'] | Where-Object View -eq 'Pivot').RunText | Should -Be 'Run CMPivot'
        ($script:Measured['dark|1440x900'] | Where-Object View -eq 'Script').RunText | Should -Be 'Run approved script'
    }

    It 'shows the heading of view <View>' -ForEach $script:ViewCases {
        $expected = ($script:AppConfig.Views | Where-Object Name -eq $View).Heading
        ($script:Measured['dark|1440x900'] | Where-Object View -eq $View).Heading | Should -Be $expected
    }

    It 'has a minimum size that fits the size <Size>, so the window can open at it' -ForEach $script:Matrix {
        # The window is clamped to the work area of the screen, so the test compares the declared minimum and not the size it got.
        $m = $script:Measured['{0}|{1}' -f $Theme, $Size] | Select-Object -First 1
        $m.MinWidth | Should -BeLessOrEqual $W
        $m.MinHeight | Should -BeLessOrEqual $H
    }
}

Describe 'Dialog windows' -Skip:(-not $script:WindowGuard.Allowed) {
    It 'finds the dialog XAML in the dialog files' {
        $script:DialogXaml.Count | Should -Be 3
    }

    It 'parses dialog <Key> as a MetroWindow with named controls' -ForEach $script:DialogCases {
        $r = Invoke-WpfSta -Arguments @{ Xaml = $script:DialogXaml[$Key] } -Script {
            [xml]$x = $Arguments.Xaml
            $w = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
            $names = [regex]::Matches($Arguments.Xaml, 'x:Name="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
            [PSCustomObject]@{ Type = $w.GetType().Name; Missing = @($names | Where-Object { -not $w.FindName($_) }); Count = @($names).Count }
        }
        $r.Type | Should -Be 'MetroWindow'
        $r.Missing | Should -BeNullOrEmpty
        $r.Count | Should -BeGreaterThan 0
    }

    It 'has every control that <File> looks up in its dialog XAML' -ForEach @($script:AppConfig.DialogFiles | ForEach-Object { @{ File = $_ } }) {
        $xaml = ($script:DialogXaml.Keys | Where-Object { $_ -like "$File#*" } | ForEach-Object { $script:DialogXaml[$_] }) -join "`n"
        $script:DialogLookups[$File].Count | Should -BeGreaterThan 0
        foreach ($n in $script:DialogLookups[$File]) { $xaml | Should -Match ('x:Name="{0}"' -f [regex]::Escape($n)) }
    }

    It 'gives every dialog and message a title that differs from the main window title' {
        $titles = @()
        foreach ($text in $script:TitleSources) {
            $titles += @([regex]::Matches($text, "-Title\s+'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        }
        $titles += @($script:DialogXaml.Values | ForEach-Object { if ($_ -match '\sTitle="([^"]*)"') { $Matches[1] } } | Where-Object { $_ })
        $titles.Count | Should -BeGreaterThan 5
        $titles | Should -Not -Contain $script:AppConfig.Title
        foreach ($t in $titles) { $t.Trim() | Should -Not -BeNullOrEmpty }
    }

    It 'gives the dialogs in XAML different titles' {
        $titles = @($script:DialogXaml.Values | ForEach-Object { if ($_ -match '\sTitle="([^"]*)"') { $Matches[1] } } | Where-Object { $_ })
        ($titles | Select-Object -Unique).Count | Should -Be $titles.Count
    }

    It 'shows dialog <Key> inside its window at its declared size and, if it sets one, its minimum size in the <Theme> theme' -ForEach @(
        foreach ($c in $script:DialogCases) { foreach ($t in 'dark', 'light') { @{ Key = $c.Key; Theme = $t } } }
    ) {
        $r = Invoke-WpfSta -Arguments @{ Xaml = $script:DialogXaml[$Key]; Dark = ($Theme -eq 'dark') } -Script {
            [xml]$x = $Arguments.Xaml
            $probe = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
            # The declared size, and the minimum size when the dialog sets one.
            $sizes = @(,@($probe.Width, $probe.Height))
            if ($probe.MinWidth -gt 0 -and $probe.MinHeight -gt 0) { $sizes += ,@($probe.MinWidth, $probe.MinHeight) }
            $probe = $null
            $rows = foreach ($s in $sizes) {
                $w = Open-TestWindow -XamlText $Arguments.Xaml -Dark $Arguments.Dark -Width $s[0] -Height $s[1]
                Set-DialogTheme -Dialog $w -IsDark $Arguments.Dark
                Wait-Layout $w
                $o = [PSCustomObject]@{ Size = ('{0}x{1}' -f $s[0], $s[1]); Clipped = @(Get-ClippedText $w); Offscreen = @(Get-OffscreenControls $w) }
                $w.Close()
                $o
            }
            , @($rows)
        }
        foreach ($m in $r) {
            $m.Clipped | ForEach-Object { '{0}: {1}: needs {2}px, has {3}px' -f $m.Size, $_.Text, $_.Needed, $_.Actual } | Should -BeNullOrEmpty
            $m.Offscreen | ForEach-Object { '{0}: {1} at {2},{3} size {4}x{5}' -f $m.Size, $_.Name, $_.X, $_.Y, $_.W, $_.H } | Should -BeNullOrEmpty
        }
    }
}

Describe 'Layout <Theme> <Size>' -ForEach $script:Matrix -Skip:(-not $script:WindowGuard.Allowed) {
    It 'has no clipped text in the <View> view' -ForEach $script:ViewCases {
        $m = ($script:Measured['{0}|{1}' -f $Theme, $Size] | Where-Object View -eq $View)
        $m.Clipped | ForEach-Object { '{0}: needs {1}px, has {2}px' -f $_.Text, $_.Needed, $_.Actual } | Should -BeNullOrEmpty
    }

    It 'keeps every button, box and list inside the window in the <View> view' -ForEach $script:ViewCases {
        $m = ($script:Measured['{0}|{1}' -f $Theme, $Size] | Where-Object View -eq $View)
        $m.Offscreen | ForEach-Object { '{0} at {1},{2} size {3}x{4}' -f $_.Name, $_.X, $_.Y, $_.W, $_.H } | Should -BeNullOrEmpty
    }
}

Describe 'Contrast measurement' -Skip:(-not $script:WindowGuard.Allowed) {
    It 'measures a text block on its own solid background, not on the parent' {
        $xaml = '<Controls:MetroWindow xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro" Title="Probe" Width="300" Height="200"><StackPanel Background="#101010"><TextBlock x:Name="same" Text="White on white" Foreground="#FFFFFF" Background="#FFFFFF"/><TextBlock x:Name="plain" Text="White on dark" Foreground="#FFFFFF"/></StackPanel></Controls:MetroWindow>'
        $r = Invoke-WpfSta -Arguments @{ Xaml = $xaml } -Script {
            $w = Open-TestWindow -XamlText $Arguments.Xaml
            $rows = @(Get-TextContrast $w)
            $o = [PSCustomObject]@{ Same = ($rows | Where-Object Name -eq 'same').Ratio; Plain = ($rows | Where-Object Name -eq 'plain').Ratio }
            $w.Close(); $o
        }
        $r.Same | Should -BeLessThan 1.5
        $r.Plain | Should -BeGreaterThan 10
    }
    It 'keeps the contrast ratio unrounded' {
        $xaml = '<Controls:MetroWindow xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro" Title="Probe" Width="300" Height="200"><StackPanel Background="#101010"><TextBlock x:Name="grey" Text="Grey" Foreground="#7A7A7A"/></StackPanel></Controls:MetroWindow>'
        $r = Invoke-WpfSta -Arguments @{ Xaml = $xaml } -Script {
            $w = Open-TestWindow -XamlText $Arguments.Xaml
            $v = (@(Get-TextContrast $w) | Where-Object Name -eq 'grey').Ratio
            $w.Close(); $v
        }
        [math]::Round($r, 2) | Should -Not -Be $r
    }
}

Describe 'Contrast <Theme>' -ForEach @(@{ Theme = 'dark' }, @{ Theme = 'light' }) -Skip:(-not $script:WindowGuard.Allowed) {
    It 'shows every text at 4.5:1 (3:1 for large text) in the <View> view, except the listed known defects' -ForEach $script:ViewCases {
        $m = ($script:Measured['{0}|1440x900' -f $Theme] | Where-Object View -eq $View)
        $m.Text.Count | Should -BeGreaterThan 3
        $known = @(Get-KnownContrastDefect -Theme $Theme)
        $bad = $m.Text | Where-Object { $min = if (Test-LargeText $_) { 3.0 } else { 4.5 }; $_.Ratio -lt $min -and ($known -notcontains ('text:{0}' -f $_.Text)) }
        $bad | ForEach-Object { '{0} "{1}" {2} on {3} = {4:N2}' -f $_.Name, $_.Text, $_.Foreground, $_.Backdrop, $_.Ratio } | Should -BeNullOrEmpty
    }
    It 'keeps the title text readable on the active title bar' {
        $tb = ($script:Measured['{0}|1440x900' -f $Theme] | Select-Object -First 1).TitleBar
        $tb.Active | Should -BeGreaterOrEqual 4.5
    }

    It 'meets the standard on every control, except the listed known defects' {
        $known = Get-KnownContrastDefect -Theme $Theme
        $found = @(Get-ContrastViolationKey -Views @($script:Measured['{0}|1440x900' -f $Theme]))
        $new = @($found | Where-Object { $known -notcontains $_ })
        $fixed = @($known | Where-Object { $found -notcontains $_ })
        $new | Should -BeNullOrEmpty -Because 'a new contrast violation appeared'
        $fixed | Should -BeNullOrEmpty -Because 'a known defect is fixed: remove it from Get-KnownContrastDefect'
    }
}
