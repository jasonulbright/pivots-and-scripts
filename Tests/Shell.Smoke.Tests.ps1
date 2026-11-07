#Requires -Modules Pester
# Starts the real start script in Windows PowerShell with -SmokeTest: the window opens, switches themes
# and modes, shows the three dialogs, closes, and the script checks its own log. This is the test that was
# in Core.Tests.ps1 before the suite was added.

BeforeDiscovery {
    . "$PSScriptRoot\WindowHarness.ps1"
    $script:WindowGuard = Test-WindowTestsAllowed
    if (-not $script:WindowGuard.Allowed) { Write-Host ("Window tests skipped: {0}" -f $script:WindowGuard.Reason) }
}

Describe 'Window smoke test' -Skip:(-not $script:WindowGuard.Allowed) {
    It 'starts the WPF window, switches themes and modes, and closes' {
        $output = & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\start-pivotsandscripts.ps1') -SmokeTest 2>&1
        ($output | Out-String) | Should -Match 'PASS: WPF startup'
    }
}
