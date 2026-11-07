# Headless window harness for the Pivots and Scripts tests.
#
# A WPF window needs an STA thread. Invoke-WpfSta runs a script block on one,
# and the script block returns plain data (never a WPF object), because a WPF
# object cannot cross to the Pester thread. The windows are shown off screen at
# -32000 so layout, templates and triggers run for real.
#
# One STA runspace serves a whole test file. A runspace per call hangs: the
# theme manager keeps handlers of closed windows from earlier threads, and the
# next theme change waits on their dead dispatchers. Call Close-WpfSession in
# AfterAll.

$script:HarnessRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\WindowMeasure.ps1"

$script:HarnessSession = $null

# Script text that every STA runspace starts with: assemblies, SuiteCommon, and
# helper functions to open a themed window and measure it.
$script:HarnessBootstrap = {
    $ErrorActionPreference = 'Stop'
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
    foreach ($dll in 'Microsoft.Xaml.Behaviors.dll', 'ControlzEx.dll', 'MahApps.Metro.dll', 'ICSharpCode.AvalonEdit.dll') {
        [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Root "Lib\$dll"))
    }
    Import-Module (Join-Path $Root 'Lib\SuiteCommon\SuiteCommon.psd1') -Global -DisableNameChecking

    function Open-TestWindow {
        param([string]$XamlPath, [bool]$Dark = $true, [double]$Width = 1440, [double]$Height = 900, [string]$XamlText)
        [xml]$xaml = if ($XamlText) { $XamlText } else { [System.IO.File]::ReadAllText($XamlPath) }
        $reader = New-Object System.Xml.XmlNodeReader $xaml
        $w = [System.Windows.Markup.XamlReader]::Load($reader)
        $w.WindowStartupLocation = 'Manual'
        $w.Left = -32000; $w.Top = -32000
        $w.ShowInTaskbar = $false
        $w.Width = $Width; $w.Height = $Height
        [void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($w, $(if ($Dark) { 'Dark.Steel' } else { 'Light.Blue' }))
        $w.Show()
        Sync-Layout $w
        # MetroWindow fades its root grid in; measure after the fade ends.
        $root = Get-VisualDescendants $w | Where-Object { $_ -is [System.Windows.FrameworkElement] -and $_.Name -eq 'RootGrid' } | Select-Object -First 1
        for ($i = 0; $root -and $i -lt 100 -and $root.Opacity -lt 0.999; $i++) { Start-Sleep -Milliseconds 50; Sync-Layout $w }
        return $w
    }

    # Applies the theme the way the shell does at start-up and on a toggle:
    # SuiteCommon palette, workflow and options buttons, sidebar buttons, title bar.
    # Each view definition has a Name (the active view name) and a Button (the x:Name of its sidebar button).
    # OptionsButtonNames lists the x:Name of the buttons that the shell passes as OptionsButtons.
    function Initialize-ShellTheme {
        param($Window, [bool]$Dark, [object[]]$Views, [string[]]$OptionsButtonNames, [string]$LogLabelName, [string]$ActiveView)
        $global:HarnessDark = $Dark
        $global:HarnessActiveView = $ActiveView
        $viewButtons = @(foreach ($v in $Views) { @{ Name = $v.Name; Button = $Window.FindName($v.Button) } })
        $theme = @{
            Window = $Window; IsDarkGetter = { [bool]$global:HarnessDark }; ActiveViewGetter = { $global:HarnessActiveView }
            ViewButtons = $viewButtons; WorkflowButtons = @($viewButtons | ForEach-Object { $_.Button })
            OptionsButtons = @($OptionsButtonNames | ForEach-Object { $Window.FindName($_) })
        }
        if ($LogLabelName) { $theme.LogLabel = $Window.FindName($LogLabelName) }
        Initialize-SuiteTheme @theme
        Set-ButtonTheme -IsDark $Dark
        Update-SidebarButtonTheme
        Update-TitleBarBrushes
        Wait-Layout $Window
    }

    # Several layout passes with short pauses, so templates and animations of a newly shown
    # or newly enabled control have run before it is measured.
    function Wait-Layout {
        param($Window, [int]$Passes = 4)
        for ($i = 0; $i -lt $Passes; $i++) { Sync-Layout $Window; Start-Sleep -Milliseconds 40 }
        Sync-Layout $Window
    }

    # Representative text in the boxes that are empty at start-up, so the contrast of entered text is measured too.
    function Set-TestFixtureText {
        param($Window)
        $values = @{ targetInput = 'CLIENT01, CLIENT02'; scriptGuid = '685E0A08-8ACE-4948-BE8F-9D0416852976'; resultFilter = 'disk'; findText = 'Disk'; replaceText = 'OS' }
        foreach ($name in $values.Keys) { $box = $Window.FindName($name); if ($box) { $box.Text = $values[$name] } }
    }

    function Sync-Layout {
        param($Window)
        $Window.UpdateLayout()
        $Window.Dispatcher.Invoke([action] {}, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
    }

    function Get-VisualDescendants {
        param([System.Windows.DependencyObject]$Root)
        $stack = New-Object System.Collections.Generic.Stack[System.Windows.DependencyObject]
        $stack.Push($Root)
        while ($stack.Count -gt 0) {
            $n = $stack.Pop()
            $n
            $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($n)
            for ($i = $count - 1; $i -ge 0; $i--) { $stack.Push([System.Windows.Media.VisualTreeHelper]::GetChild($n, $i)) }
        }
    }

    function Test-VisibleInTree {
        param([System.Windows.UIElement]$Element)
        $d = $Element -as [System.Windows.DependencyObject]
        while ($d) {
            if ($d -is [System.Windows.UIElement] -and $d.Visibility -ne 'Visible') { return $false }
            $d = [System.Windows.Media.VisualTreeHelper]::GetParent($d)
        }
        return $true
    }
}

function Get-WpfSession {
    if ($script:HarnessSession -and $script:HarnessSession.RunspaceStateInfo.State -eq 'Opened') { return $script:HarnessSession }
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('Root', $script:HarnessRoot)
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($script:HarnessBootstrap.ToString(), $false)
    [void]$ps.AddScript($script:MeasureFunctions.ToString(), $false)
    try {
        [void]$ps.Invoke()
        if ($ps.HadErrors) { throw (($ps.Streams.Error | ForEach-Object { $_.ToString() }) -join "`n") }
    }
    catch {
        $ps.Dispose()
        $rs.Dispose()
        throw
    }
    $ps.Dispose()
    $script:HarnessSession = $rs
    return $rs
}

function Close-WpfSession {
    if ($script:HarnessSession) { $script:HarnessSession.Dispose(); $script:HarnessSession = $null }
}

function Invoke-WpfSta {
    param(
        [Parameter(Mandatory)][scriptblock]$Script,
        [hashtable]$Arguments = @{}
    )
    $rs = Get-WpfSession
    $rs.SessionStateProxy.SetVariable('Arguments', $Arguments)
    $ps = [powershell]::Create()
    try {
        $ps.Runspace = $rs
        [void]$ps.AddScript($Script.ToString(), $false)
        $out = @($ps.Invoke())
        if ($ps.HadErrors -and $ps.Streams.Error.Count -gt 0) {
            throw (($ps.Streams.Error | ForEach-Object { $_.ToString() }) -join "`n")
        }
        return $out
    }
    finally {
        $ps.Dispose()
    }
}
