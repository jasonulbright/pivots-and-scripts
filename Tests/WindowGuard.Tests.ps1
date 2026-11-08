#Requires -Modules Pester
# Tests of the window-test guard (Test-WindowTestsAllowed in WindowHarness.ps1).
# The guard runs window tests only when SUITE_ALLOW_WINDOW_TESTS is 1. This file injects
# the opt-in value, so it never reads the real environment and never opens a window.

BeforeDiscovery {
    # Every other test file that can open a window must carry the guard.
    # The scan covers the whole repository, nested folders and lab folders included.
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:GuardFile = Join-Path $PSScriptRoot 'WindowGuard.Tests.ps1'
    $script:WindowTestFiles = @(Get-ChildItem -LiteralPath $script:RepoRoot -Filter '*.Tests.ps1' -File -Recurse |
            Where-Object { $_.FullName -ne $script:GuardFile -and $_.FullName -notlike '*\.git\*' -and $_.FullName -notlike '*\TestOutput\*' -and (Get-Content -LiteralPath $_.FullName -Raw) -match 'Invoke-WpfSta|New-WpfWindow|ShowDialog|\.Show\(\)|-SmokeTest|WindowHarness' } |
            ForEach-Object { @{ Name = $_.FullName.Substring($script:RepoRoot.Length + 1); Path = $_.FullName } })
}

BeforeAll {
    . "$PSScriptRoot\WindowHarness.ps1"
}

Describe 'Test-WindowTestsAllowed' {
    It 'allows the opt-in 1' {
        $r = Test-WindowTestsAllowed -OptIn '1'
        $r.Allowed | Should -BeTrue
        $r.Reason | Should -BeNullOrEmpty
    }

    It 'refuses when the opt-in is <Label>, and names the opt-in' -ForEach @(
        @{ Label = 'empty'; Value = '' }
        @{ Label = 'null'; Value = $null }
        @{ Label = '0'; Value = '0' }
        @{ Label = 'true'; Value = 'true' }
        @{ Label = '11'; Value = '11' }
    ) {
        $r = Test-WindowTestsAllowed -OptIn $Value
        $r.Allowed | Should -BeFalse
        $r.Reason | Should -Be 'SUITE_ALLOW_WINDOW_TESTS is not 1'
    }
}

Describe 'Test-WindowTestsAllowed decides on the opt-in only' {
    It 'has no ComputerName parameter' {
        (Get-Command Test-WindowTestsAllowed).Parameters.Keys | Should -Not -Contain 'ComputerName'
    }

    It 'has an OptIn parameter' {
        (Get-Command Test-WindowTestsAllowed).Parameters.Keys | Should -Contain 'OptIn'
    }

    It 'does not read the machine name' {
        $text = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'WindowHarness.ps1') -Raw
        $text | Should -Not -Match 'MachineName|COMPUTERNAME|ComputerName'
    }
}

Describe 'Window test files carry the guard' {
    It 'finds at least one test file that can open a window' -ForEach @(@{ Found = @($script:WindowTestFiles).Count }) {
        $Found | Should -BeGreaterThan 0
    }

    It 'prints the skip reason once: Invoke-Checks sets the marker and Window.Tests reads it' {
        (Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-Checks.ps1') -Raw) | Should -Match '\$env:SUITE_WINDOW_GUARD_REPORTED\s*=\s*''1'''
        (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Window.Tests.ps1') -Raw) | Should -Match '-not \$env:SUITE_WINDOW_GUARD_REPORTED'
    }

    It 'Window.Tests.ps1 sets placeholder AppConfig data (Views, DialogFiles) in the denied branch, before it returns' {
        $text = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Window.Tests.ps1') -Raw
        $text -match '(?s)if \(-not \$script:WindowGuard\.Allowed\) \{(?<denied>.*?)\r?\n\s*return\b' | Should -BeTrue
        $denied = $Matches['denied']
        $denied | Should -Match '\$script:AppConfig\s*='
        # Evaluate the literal lists: each placeholder list must hold at least one case.
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($denied, [ref]$null, [ref]$null)
        # Tie the check to the assignment: take the hashtable on the right side of $script:AppConfig, not any table.
        $assign = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$script:AppConfig' }, $true)
        $assign | Should -Not -BeNullOrEmpty
        # The right side must itself be a literal hashtable (one expression), not a conditional that holds one.
        $right = $assign.Right
        $right | Should -BeOfType ([System.Management.Automation.Language.CommandExpressionAst])
        $table = $right.Expression
        $table | Should -BeOfType ([System.Management.Automation.Language.HashtableAst])
        foreach ($key in 'Views', 'DialogFiles') {
            $pair = @($table.KeyValuePairs | Where-Object { $_.Item1.Value -eq $key })
            $pair.Count | Should -Be 1
            $value = $pair[0].Item2.SafeGetValue()
            $value | Should -Not -BeNullOrEmpty
            @($value).Count | Should -BeGreaterThan 0
        }
        $denied | Should -Not -Match 'WindowConfig'
    }

    It '<Name> calls Test-WindowTestsAllowed and applies -Skip' -ForEach $script:WindowTestFiles {
        $text = Get-Content -LiteralPath $Path -Raw
        $text | Should -Match 'Test-WindowTestsAllowed'
        $text | Should -Match '-Skip:'
    }

    It '<Name> applies the guard to every top-level Describe' -ForEach $script:WindowTestFiles {
        $describes = @(Get-Content -LiteralPath $Path | Where-Object { $_ -match '^\s*Describe\b' })
        $describes.Count | Should -BeGreaterThan 0
        @($describes | Where-Object { $_ -notmatch '-Skip:\(-not \$script:WindowGuard\.Allowed\)' }) | Should -BeNullOrEmpty
    }
}

Describe 'Get-WpfSession refuses where the guard says no' {
    BeforeAll {
        Mock Test-WindowTestsAllowed { [pscustomobject]@{ Allowed = $false; Reason = 'test' } }
    }
    AfterEach { $script:HarnessSession = $null }

    It 'throws and creates no session' {
        $script:HarnessSession = $null
        { Get-WpfSession } | Should -Throw '*not allowed*'
        $script:HarnessSession | Should -BeNullOrEmpty
    }

    It 'does not hand out a cached session' {
        $script:HarnessSession = [pscustomobject]@{ RunspaceStateInfo = [pscustomobject]@{ State = 'Opened' } }
        { Get-WpfSession } | Should -Throw '*not allowed*'
    }
}
