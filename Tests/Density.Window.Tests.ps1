#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }

<#
.SYNOPSIS
    Pester 5.x window test for the compact 1080p density and for vacant space. The main window is opened off screen, in
    both themes and in both views, at the work area of the session (1920x1032 on a 1080p screen at 100 percent) and at
    1024x720 (the minimum-size case: it proves that nothing clips). It measures the sidebar buttons, the buttons, the
    single-line boxes, the grid rows and headers, and the vacant area below and right of the content.
    The window test prints the work area of the session (SystemParameters.WorkArea).
#>

BeforeDiscovery {
    . "$PSScriptRoot\WindowHarness.ps1"
    $script:WindowGuard = Test-WindowTestsAllowed
    if (-not $script:WindowGuard.Allowed -and -not $env:SUITE_WINDOW_GUARD_REPORTED) { Write-Host ('Window tests skipped: {0}.' -f $script:WindowGuard.Reason) }
    $design = Get-DesignSize
    $script:Cases = @(foreach ($dark in $true, $false) {
            foreach ($size in @(@(1024, 720), @($design.W, $design.H))) {
                @{ Dark = $dark; Theme = $(if ($dark) { 'dark' } else { 'light' }); W = $size[0]; H = $size[1]; Size = ('{0}x{1}' -f $size[0], $size[1]) }
            }
        })
    $script:ViewCases = @(@{ View = 'Pivot' }, @{ View = 'Script' })
}

BeforeAll {
    . "$PSScriptRoot\WindowHarness.ps1"
    $script:WindowGuard = Test-WindowTestsAllowed
    if (-not $script:WindowGuard.Allowed) { return }
    . "$PSScriptRoot\WindowConfig.ps1"
    . "$PSScriptRoot\TestHelpers.ps1"
    $script:Root = Split-Path -Parent $PSScriptRoot
    $script:Design = Get-DesignSize
    Add-Type -AssemblyName PresentationFramework
    $wa = [System.Windows.SystemParameters]::WorkArea
    Write-Host ('Work area of this session: {0}x{1}' -f $wa.Width, $wa.Height)
    $modeFunctions = @(Get-ScriptFunctionText -Path (Join-Path $script:Root $script:AppConfig.Shell) -Name $script:AppConfig.ModeFunctions)
    $script:Measured = @{}
    foreach ($case in @(
            @{ Dark = $true; W = 1024; H = 720 }, @{ Dark = $true; W = $script:Design.W; H = $script:Design.H },
            @{ Dark = $false; W = 1024; H = 720 }, @{ Dark = $false; W = $script:Design.W; H = $script:Design.H })) {
        $key = '{0}|{1}x{2}' -f $(if ($case.Dark) { 'dark' } else { 'light' }), $case.W, $case.H
        $case.Config = $script:AppConfig
        $case.ModeFunctions = $modeFunctions
        $script:Measured[$key] = Invoke-WpfSta -Arguments $case -Script {
            $cfg = $Arguments.Config
            $w = $null
            try {
                $w = Open-TestWindow -XamlPath (Join-Path $Root $cfg.Xaml) -Dark $Arguments.Dark -Width $Arguments.W -Height $Arguments.H
                foreach ($text in $Arguments.ModeFunctions) { . ([scriptblock]::Create($text)) }
                $global:ui = @{}
                foreach ($n in 'heading', 'editorLabel', 'btnRun', 'btnSubmit', 'guidLabel', 'scriptGuid', 'btnParameters', 'btnSiteScripts', 'editor', 'library', 'libraryFilter', 'toggleTheme') { $global:ui[$n] = $w.FindName($n) }
                $global:ui.toggleTheme.IsOn = [bool]$Arguments.Dark
                Set-TestFixtureText $w
                $script:mode = 'Pivot'
                $script:drafts = @{ Pivot = 'Disk | project Device, Name, FreeSpace'; Script = '' }
                $sidebar = @(foreach ($v in $cfg.Views) { $b = $w.FindName($v.Button); $p = $b.TransformToAncestor($w).Transform([System.Windows.Point]::new(0, 0)); [pscustomobject]@{ Name = $v.Button; Bottom = $p.Y + $b.ActualHeight; Height = $b.ActualHeight } })
                $views = @(foreach ($view in $cfg.Views) {
                        $global:HarnessActiveView = $view.Mode
                        Initialize-ShellTheme -Window $w -Dark $Arguments.Dark -Views $cfg.Views -OptionsButtonNames $cfg.OptionsButtons -ActiveView $view.Mode
                        Set-PasMode $view.Mode
                        if ($view.Mode -eq 'Pivot') { $global:ui.editor.Text = 'Disk | project Device, Name, FreeSpace' }
                        Wait-Layout $w
                        $tabs = $w.FindName('resultTabs')
                        # The content area is the grid that holds the result tabs; its margin is the padding of the view.
                        $area = [System.Windows.Media.VisualTreeHelper]::GetParent($tabs)
                        $areaTop = $area.TransformToAncestor($w).Transform([System.Windows.Point]::new(0, 0))
                        $margin = $area.Margin
                        $left = $areaTop.X + $margin.Left; $right = $areaTop.X + $area.ActualWidth - $margin.Right
                        $top = $areaTop.Y + $margin.Top; $bottom = $areaTop.Y + $area.ActualHeight - $margin.Bottom
                        $maxRight = $left; $maxBottom = $top
                        $buttons = @(); $boxes = @(); $grids = @()
                        foreach ($e in (Get-VisualDescendants $area)) {
                            if ($e -isnot [System.Windows.FrameworkElement] -or -not (Test-VisibleInTree $e) -or $e.ActualWidth -le 0 -or $e.ActualHeight -le 0) { continue }
                            $p = $e.TransformToAncestor($w).Transform([System.Windows.Point]::new(0, 0))
                            if ($p.X + $e.ActualWidth -gt $maxRight) { $maxRight = $p.X + $e.ActualWidth }
                            if ($p.Y + $e.ActualHeight -gt $maxBottom) { $maxBottom = $p.Y + $e.ActualHeight }
                            if ($e -is [System.Windows.Controls.Button] -and $e.Name) { $buttons += [pscustomobject]@{ Name = $e.Name; Height = $e.ActualHeight } }
                            if ($e -is [System.Windows.Controls.TextBox] -and $e.Name -in 'findText', 'replaceText', 'scriptGuid', 'resultFilter') { $boxes += [pscustomobject]@{ Name = $e.Name; Height = $e.ActualHeight } }
                            if ($e -is [System.Windows.Controls.DataGrid]) {
                                $hdr = Get-VisualDescendants $e | Where-Object { $_ -is [System.Windows.Controls.Primitives.DataGridColumnHeadersPresenter] } | Select-Object -First 1
                                $row = Get-VisualDescendants $e | Where-Object { $_ -is [System.Windows.Controls.DataGridRow] } | Select-Object -First 1
                                $grids += [pscustomobject]@{ Name = $e.Name; Width = $e.ActualWidth; HeaderHeight = $(if ($hdr) { $hdr.ActualHeight } else { $null }); RowHeight = $(if ($row) { $row.ActualHeight } else { $null }) }
                            }
                        }
                        [pscustomobject]@{
                            View = $view.Name; AreaWidth = ($right - $left); AreaHeight = ($bottom - $top)
                            VacantHeight = [math]::Max(0, $bottom - $maxBottom); VacantWidth = [math]::Max(0, $right - $maxRight)
                            EditorHeight = $global:ui.editor.ActualHeight; TabsHeight = $tabs.ActualHeight
                            Buttons = $buttons; Boxes = $boxes; Grids = $grids
                        }
                    })
                [pscustomobject]@{ Width = $w.ActualWidth; Height = $w.ActualHeight; Sidebar = $sidebar; Views = $views }
            }
            finally { if ($w) { $w.Close() } }
        }
    }
}

AfterAll {
    if ($script:WindowGuard.Allowed) { Close-WpfSession }
}

Describe 'Density <Theme> <Size>' -ForEach $script:Cases -Skip:(-not $script:WindowGuard.Allowed) {
    It 'sizes every sidebar button between 34 and 36 px and fits all of them without scrolling' {
        $m = $script:Measured['{0}|{1}' -f $Theme, $Size]
        foreach ($b in $m.Sidebar) { $b.Height | Should -BeIn 34, 35, 36 -Because $b.Name }
        ($m.Sidebar | Select-Object -Last 1).Bottom | Should -BeLessThan $m.Height
    }

    It 'sizes the buttons at 26 to 28 px and the single-line boxes at 26 to 28 px in the <View> view' -ForEach $script:ViewCases {
        $m = $script:Measured['{0}|{1}' -f $Theme, $Size].Views | Where-Object View -eq $View
        foreach ($b in $m.Buttons) { $b.Height | Should -BeIn 26, 27, 28 -Because $b.Name }
        foreach ($b in $m.Boxes) { $b.Height | Should -BeIn 26, 27, 28 -Because $b.Name }
    }

    It 'gives grid rows 24 to 26 px and headers 26 px in the <View> view' -ForEach $script:ViewCases {
        $m = $script:Measured['{0}|{1}' -f $Theme, $Size].Views | Where-Object View -eq $View
        foreach ($g in $m.Grids) {
            if ($null -ne $g.HeaderHeight) { $g.HeaderHeight | Should -BeLessOrEqual 26.5 -Because $g.Name }
            if ($null -ne $g.RowHeight) { [math]::Round($g.RowHeight) | Should -BeIn 24, 25, 26 -Because $g.Name }
        }
    }

    It 'lets the content fill the width in the <View> view' -ForEach $script:ViewCases {
        $mm = $script:Measured['{0}|{1}' -f $Theme, $Size]
        $m = $mm.Views | Where-Object View -eq $View
        $m.AreaWidth | Should -BeGreaterOrEqual ($mm.Width - 300)
        foreach ($g in $m.Grids) { $g.Width | Should -BeGreaterOrEqual ($m.AreaWidth * 0.3) -Because $g.Name }
    }
}

Describe 'Vacant space <Theme> at the design size' -ForEach @(@{ Theme = 'dark' }, @{ Theme = 'light' }) -Skip:(-not $script:WindowGuard.Allowed) {
    It 'leaves no vacant area larger than 120 px high or 160 px wide in the <View> view, and gives the editor and the results a real share' -ForEach $script:ViewCases {
        $m = ($script:Measured['{0}|{1}x{2}' -f $Theme, $script:Design.W, $script:Design.H].Views | Where-Object View -eq $View)
        $bad = @()
        if ($m.VacantHeight -gt 120) { $bad += ('{0}: {1} px vacant below the content' -f $View, [math]::Round($m.VacantHeight)) }
        if ($m.VacantWidth -gt 160) { $bad += ('{0}: {1} px vacant right of the content' -f $View, [math]::Round($m.VacantWidth)) }
        if ($m.EditorHeight -lt 150) { $bad += ('{0}: the editor is only {1} px high' -f $View, [math]::Round($m.EditorHeight)) }
        if ($m.TabsHeight -lt 200) { $bad += ('{0}: the result tabs are only {1} px high' -f $View, [math]::Round($m.TabsHeight)) }
        $bad | Should -BeNullOrEmpty -Because ($bad -join '; ')
    }
}
