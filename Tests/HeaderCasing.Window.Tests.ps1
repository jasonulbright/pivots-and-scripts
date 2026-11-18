#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }
# Title Case of the grid column headers (D-12). The result grids generate their columns from data properties (ResourceID,
# Target_Count). ConvertTo-PasHeaderText of start-pivotsandscripts.ps1 turns each name into Title Case words, and the grid header
# style keeps the case. The window test attaches the real function to the three result grids, fills them, and reads the drawn
# header text in both themes, so that a header in capitals (the MahApps default) fails.

BeforeDiscovery {
    . "$PSScriptRoot\WindowHarness.ps1"
    $script:WindowGuard = Test-WindowTestsAllowed
    if (-not $script:WindowGuard.Allowed -and -not $env:SUITE_WINDOW_GUARD_REPORTED) { Write-Host ('Window tests skipped: {0}.' -f $script:WindowGuard.Reason) }
    $script:ThemeCases = @(@{ Dark = $true; Theme = 'dark' }, @{ Dark = $false; Theme = 'light' })
}

BeforeAll {
    . "$PSScriptRoot\TestHelpers.ps1"
    $script:Root = Split-Path -Parent $PSScriptRoot
    $script:ShellPath = Join-Path $script:Root 'start-pivotsandscripts.ps1'
    $script:FunctionText = Get-ScriptFunctionText -Path $script:ShellPath -Name 'ConvertTo-PasHeaderText'
    . ([scriptblock]::Create($script:FunctionText))
    . "$PSScriptRoot\WindowHarness.ps1"
    $script:WindowGuard = Test-WindowTestsAllowed
    if (-not $script:WindowGuard.Allowed) { return }
    . "$PSScriptRoot\WindowConfig.ps1"
    $script:Design = Get-DesignSize
    Add-Type -AssemblyName PresentationFramework
    $script:Headers = @{}
    foreach ($dark in $true, $false) {
        $case = @{ Dark = $dark; W = $script:Design.W; H = $script:Design.H; Config = $script:AppConfig; FunctionText = $script:FunctionText }
        $script:Headers[$(if ($dark) { 'dark' } else { 'light' })] = Invoke-WpfSta -Arguments $case -Script {
            $hcW = $null
            try {
                $hcW = Open-TestWindow -XamlPath (Join-Path $Root $Arguments.Config.Xaml) -Dark $Arguments.Dark -Width $Arguments.W -Height $Arguments.H
                Initialize-ShellTheme -Window $hcW -Dark $Arguments.Dark -Views $Arguments.Config.Views -OptionsButtonNames $Arguments.Config.OptionsButtons -ActiveView $Arguments.Config.Views[0].Mode
                . ([scriptblock]::Create($Arguments.FunctionText))
                $hcHandler = { param($s, $e) $e.Column.Header = ConvertTo-PasHeaderText ([string]$e.PropertyName) }
                $hcRows = @{
                    results  = @([pscustomobject]@{ Device = 'CLIENT01'; ResourceID = 16777220; Target_Count = 1; OperationID = 7 })
                    devices  = @([pscustomobject]@{ Device = 'CLIENT01'; ResourceID = 16777220; Client = $true; ExitCode = 0 })
                    pipeline = @([pscustomobject]@{ Number = 1; Mode = 'Pivot'; TargetCount = 1; ResultCount = 1 })
                }
                foreach ($hcName in 'results', 'devices', 'pipeline') {
                    $hcGrid = $hcW.FindName($hcName)
                    $hcGrid.Add_AutoGeneratingColumn($hcHandler)
                    $hcGrid.ItemsSource = $hcRows[$hcName]
                }
                $hcFound = @()
                foreach ($hcTab in 0, 1, 3) {
                    $hcW.FindName('resultTabs').SelectedIndex = $hcTab
                    Wait-Layout $hcW
                    foreach ($hcEl in (Get-VisualDescendants $hcW)) {
                        if ($hcEl -isnot [System.Windows.Controls.Primitives.DataGridColumnHeader]) { continue }
                        $hcDrawn = @(Get-VisualDescendants $hcEl | Where-Object { $_ -is [System.Windows.Controls.TextBlock] -and $_.Text } | ForEach-Object { $_.Text })
                        $hcFound += [pscustomobject]@{ Tab = $hcTab; Header = [string]$hcEl.Content; Drawn = ($hcDrawn -join '') }
                    }
                }
                , $hcFound
            }
            finally { if ($hcW) { $hcW.Close() } }
        }
    }
}

AfterAll {
    if ($script:WindowGuard.Allowed) { Close-WpfSession }
}

Describe 'ConvertTo-PasHeaderText' -Skip:(-not $script:WindowGuard.Allowed) {
    It 'turns <Name> into <Expected>' -ForEach @(
        @{ Name = 'ResourceID'; Expected = 'Resource ID' }
        @{ Name = 'Target_Count'; Expected = 'Target Count' }
        @{ Name = 'TargetCount'; Expected = 'Target Count' }
        @{ Name = 'OperationID'; Expected = 'Operation ID' }
        @{ Name = 'Device'; Expected = 'Device' }
        @{ Name = 'device_name'; Expected = 'Device Name' }
        @{ Name = 'ExitCode'; Expected = 'Exit Code' }
        @{ Name = 'SMSID'; Expected = 'SMSID' }
        @{ Name = 'LastBootUpTime'; Expected = 'Last Boot Up Time' }
    ) {
        ConvertTo-PasHeaderText $Name | Should -BeExactly $Expected
    }

    It 'is attached to the three result grids in the start script' {
        $text = Get-Content -LiteralPath $script:ShellPath -Raw
        $text | Should -Match '\$ui\.devices\.Add_AutoGeneratingColumn'
        $text | Should -Match '\$ui\.pipeline\.Add_AutoGeneratingColumn'
        $text | Should -Match 'Column\.Header=ConvertTo-PasHeaderText'
    }
}

Describe 'Column headers in the result grids <Theme>' -ForEach $script:ThemeCases -Skip:(-not $script:WindowGuard.Allowed) {
    It 'draws Title Case text, not capitals' {
        $h = @($script:Headers[$Theme] | Where-Object { $_.Header } | Sort-Object Tab, Header -Unique)
        foreach ($x in $h) { Write-Host ('{0}: header "{1}" draws "{2}"' -f $Theme, $x.Header, $x.Drawn) }
        $h.Count | Should -BeGreaterThan 8
        $bad = @($h | Where-Object { $_.Drawn -cne $_.Header } | ForEach-Object { '"{0}" is drawn as "{1}"' -f $_.Header, $_.Drawn })
        $bad | Should -BeNullOrEmpty -Because ($bad -join '; ')
        @($h | Where-Object { $_.Header -ceq 'Resource ID' }).Count | Should -BeGreaterThan 0
    }
}
