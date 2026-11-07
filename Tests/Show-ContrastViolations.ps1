<#
.SYNOPSIS
    Prints the contrast violations of the main window in both themes, in the
    format of KnownContrastDefects.ps1.

.DESCRIPTION
    Run it when the window test reports a new or a fixed violation, to see the
    current list. Opens the window off screen at 1440x900, as Window.Tests.ps1 does.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification='Console tool.')]
param()
. "$PSScriptRoot\TestHelpers.ps1"
. "$PSScriptRoot\WindowHarness.ps1"
$guard = Test-WindowTestsAllowed
if (-not $guard.Allowed) { Write-Host ("Window tools skipped: {0}" -f $guard.Reason); return }
. "$PSScriptRoot\WindowConfig.ps1"
. "$PSScriptRoot\KnownContrastDefects.ps1"
$modeFunctions = @(Get-ScriptFunctionText -Path (Join-Path $script:AppRoot $script:AppConfig.Shell) -Name $script:AppConfig.ModeFunctions)
try {
    foreach ($dark in $true, $false) {
        $r = Invoke-WpfSta -Arguments @{ Dark = $dark; Config = $script:AppConfig; ModeFunctions = $modeFunctions } -Script {
            $cfg = $Arguments.Config
            $w = Open-TestWindow -XamlPath (Join-Path $Root $cfg.Xaml) -Dark $Arguments.Dark
            foreach ($text in $Arguments.ModeFunctions) { . ([scriptblock]::Create($text)) }
            $global:ui = @{}
            foreach ($n in 'heading', 'editorLabel', 'btnRun', 'btnSubmit', 'guidLabel', 'scriptGuid', 'btnParameters', 'btnSiteScripts', 'editor', 'library', 'libraryFilter', 'toggleTheme') { $global:ui[$n] = $w.FindName($n) }
            $global:ui.toggleTheme.IsOn = [bool]$Arguments.Dark
            Set-TestFixtureText $w
            $script:mode = 'Pivot'
            $script:drafts = @{ Pivot = 'Disk | project Device, Name, FreeSpace'; Script = '' }
            $out = @()
            foreach ($view in $cfg.Views) {
                $global:HarnessActiveView = $view.Mode
                Initialize-ShellTheme -Window $w -Dark $Arguments.Dark -Views $cfg.Views -OptionsButtonNames $cfg.OptionsButtons -ActiveView $view.Mode
                Set-PasMode $view.Mode
                if ($view.Mode -eq 'Pivot') { $global:ui.editor.Text = 'Disk | project Device, Name, FreeSpace' }
                Wait-Layout $w
                $out += [PSCustomObject]@{ Text = @(Get-TextContrast $w); Interactive = @(Get-InteractiveContrast $w); TitleBar = Get-TitleBarContrast $w }
            }
            $w.Close(); , $out
        }
        $keys = Get-ContrastViolationKey -Views @($r)
        Write-Host ("== {0}" -f $(if ($dark) { 'dark' } else { 'light' }))
        Write-Host (($keys | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ', ')
    }
}
finally { Close-WpfSession }
