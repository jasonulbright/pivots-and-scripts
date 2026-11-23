#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }
# Per-site data (Q-112f). An old-layout data folder is seeded in a temp folder. The path and prefs logic of the tool
# runs for site AB1, then site CD2, then AB1 again, and with no site. The tests check that the old files stay as they
# are, that AB1 data is copied once, that CD2 shows nothing of AB1 and writes only below sites\CD2.
# The site codes are fictional (AB1, CD2). The hosts use example.com. No window opens and no ConfigMgr site is used.

BeforeAll {
    . "$PSScriptRoot\TestHelpers.ps1"
    Import-AppModule

    $script:envNames = 'APP_PACKAGER_DATA_ROOT', 'APP_PACKAGER_SITE', 'SUITE_CM_SITECODE', 'SUITE_CM_PROVIDER'
    $script:envSaved = @{}
    foreach ($n in $script:envNames) { $script:envSaved[$n] = [Environment]::GetEnvironmentVariable($n) }

    function Set-TestEnv {
        param([string]$Site, [string]$DataRoot)
        foreach ($n in $script:envNames) { [Environment]::SetEnvironmentVariable($n, $null) }
        [Environment]::SetEnvironmentVariable('APP_PACKAGER_DATA_ROOT', $DataRoot)
        if ($Site) { [Environment]::SetEnvironmentVariable('APP_PACKAGER_SITE', $Site) }
    }

    # The old single-site layout: preferences and sessions in the data folder of the tool, site AB1.
    # The tool folder is named after the tool. $Local stands for %LOCALAPPDATA%.
    function New-OldLayout {
        param([Parameter(Mandatory)][string]$Base)
        $tool = Join-Path $Base 'suite\pivots-and-scripts'
        $local = Join-Path $Base 'local'
        $old = Join-Path $local 'SignalRidgeLabs\PivotsAndScripts'
        New-Item -ItemType Directory -Path $tool, (Join-Path $old 'Sessions'), (Join-Path $old 'Logs') -Force | Out-Null
        $prefs = [ordered]@{ SiteCode = 'AB1'; SMSProvider = 'ab1-sms.example.com'; ApproveAfterSubmit = $true }
        $prefs | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $old 'preferences.json') -Encoding UTF8
        '{"SchemaVersion":1,"ID":"11111111-1111-1111-1111-111111111111","SiteCode":"AB1","Provider":"ab1-sms.example.com","User":"EXAMPLE\\user","Steps":[]}' |
            Set-Content -LiteralPath (Join-Path $old 'Sessions\11111111-1111-1111-1111-111111111111.json') -Encoding UTF8
        '{"x":1}' | Set-Content -LiteralPath (Join-Path $old 'windowstate.json') -Encoding UTF8
        '[2026-01-01 00:00:00] [INFO] old log' | Set-Content -LiteralPath (Join-Path $old 'Logs\pivotsandscripts-20260101.log') -Encoding UTF8
        return [pscustomobject]@{ Tool = $tool; Local = $local; Old = $old; Prefs = (Join-Path $old 'preferences.json') }
    }

    function Get-FolderHash {
        param([Parameter(Mandatory)][string]$Path)
        $h = @{}
        foreach ($f in Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue) { $h[$f.FullName] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash }
        return $h
    }

    # What the start script does before the window opens: resolve the site, then the session folder and the prefs.
    function Start-ToolForSite {
        param([Parameter(Mandatory)]$Layout, [string]$Site, [Parameter(Mandatory)][string]$DataRoot)
        Set-TestEnv -Site $Site -DataRoot $DataRoot
        $siteInfo = Resolve-SuiteToolSite -Tool 'pivots-and-scripts' -ToolRoot $Layout.Tool -LegacyPrefsPath $Layout.Prefs -LocalRoot $Layout.Local
        $sessionDir = Get-PasSessionDirectory -Site $siteInfo -DataRoot $Layout.Old -Create
        $prefs = Read-PasPreference -Path $Layout.Prefs -Site $siteInfo
        return [pscustomobject]@{ Site = $siteInfo; SessionDir = $sessionDir; Prefs = $prefs }
    }
}

AfterAll {
    foreach ($n in $script:envNames) { [Environment]::SetEnvironmentVariable($n, $script:envSaved[$n]) }
}

Describe 'Pivots and Scripts keeps its data per site' {
    BeforeAll {
        $script:base = Join-Path $TestDrive 'iso'
        $script:layout = New-OldLayout -Base $script:base
        $script:data = Join-Path $script:base 'data'
        $script:before = Get-FolderHash -Path $script:layout.Old
        $script:ab1 = Start-ToolForSite -Layout $script:layout -Site 'AB1' -DataRoot $script:data
        $script:afterAb1 = Get-FolderHash -Path $script:layout.Old
    }

    It 'uses the site AB1 and a site folder below the data root' {
        $script:ab1.Site.Active | Should -BeTrue
        $script:ab1.Site.SiteFolder | Should -Be 'AB1'
        $script:ab1.Site.ToolFolder | Should -BeLike (Join-Path $script:data '*\sites\AB1\tools\pivots-and-scripts')
    }

    It 'leaves every old file as it was after the copy (SHA-256)' {
        $script:afterAb1.Count | Should -Be $script:before.Count
        foreach ($k in $script:before.Keys) { $script:afterAb1[$k] | Should -Be $script:before[$k] -Because $k }
    }

    It 'copies the AB1 session and the site settings into the site folder once' {
        $tf = $script:ab1.Site.ToolFolder
        $name = 'sessions\11111111-1111-1111-1111-111111111111.json'
        Test-Path -LiteralPath (Join-Path $tf $name) | Should -BeTrue
        (Get-FileHash -LiteralPath (Join-Path $tf $name)).Hash | Should -Be (Get-FileHash -LiteralPath (Join-Path $script:layout.Old 'Sessions\11111111-1111-1111-1111-111111111111.json')).Hash
        Test-Path -LiteralPath (Join-Path $tf 'prefs.json') | Should -BeTrue
        $marker = Join-Path $tf 'migrated.json'
        $stamp = (Get-Item -LiteralPath $marker).LastWriteTimeUtc
        $again = Start-ToolForSite -Layout $script:layout -Site 'AB1' -DataRoot $script:data
        $again.Site.Migration | Should -Be 'done earlier'
        (Get-Item -LiteralPath $marker).LastWriteTimeUtc | Should -Be $stamp
    }

    It 'copies only the site keys and no global key into the site prefs' {
        $sitePrefs = Get-Content -LiteralPath (Join-Path $script:ab1.Site.ToolFolder 'prefs.json') -Raw | ConvertFrom-Json
        $sitePrefs.SiteCode | Should -Be 'AB1'
        $sitePrefs.SMSProvider | Should -Be 'ab1-sms.example.com'
        $sitePrefs.PSObject.Properties['ApproveAfterSubmit'] | Should -BeNullOrEmpty
    }

    It 'points the session folder at the site store and leaves the logs and window state global' {
        $script:ab1.SessionDir | Should -Be (Join-Path $script:ab1.Site.ToolFolder 'sessions')
        Test-Path -LiteralPath (Join-Path $script:ab1.Site.ToolFolder 'Logs') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:ab1.Site.ToolFolder 'windowstate.json') | Should -BeFalse
    }

    It 'reads the AB1 site values and the global key from the old prefs file' {
        $script:ab1.Prefs.SiteCode | Should -Be 'AB1'
        $script:ab1.Prefs.SMSProvider | Should -Be 'ab1-sms.example.com'
        $script:ab1.Prefs.ApproveAfterSubmit | Should -BeTrue
    }

    It 'does not read the launcher variables when a site is active' {
        [Environment]::SetEnvironmentVariable('SUITE_CM_PROVIDER', 'launcher-sms.example.com')
        [Environment]::SetEnvironmentVariable('SUITE_CM_SITECODE', 'EF3')
        $p = Read-PasPreference -Path $script:layout.Prefs -Site $script:ab1.Site
        $p.SMSProvider | Should -Be 'ab1-sms.example.com'
        $p.SiteCode | Should -Be 'AB1'
        [Environment]::SetEnvironmentVariable('SUITE_CM_PROVIDER', $null)
        [Environment]::SetEnvironmentVariable('SUITE_CM_SITECODE', $null)
    }

    Context 'site CD2' {
        BeforeAll {
            $script:cd2 = Start-ToolForSite -Layout $script:layout -Site 'CD2' -DataRoot $script:data
        }

        It 'shows none of the AB1 values' {
            $script:cd2.Site.Active | Should -BeTrue
            $script:cd2.Site.SiteFolder | Should -Be 'CD2'
            $script:cd2.Prefs.SiteCode | Should -Be 'CD2'
            $script:cd2.Prefs.SMSProvider | Should -Not -Match 'ab1'
        }

        It 'gets no copy of the AB1 session' {
            Test-Path -LiteralPath (Join-Path $script:cd2.SessionDir '11111111-1111-1111-1111-111111111111.json') | Should -BeFalse
            @(Get-ChildItem -LiteralPath $script:cd2.SessionDir -File -ErrorAction SilentlyContinue).Count | Should -Be 0
            $text = (Get-ChildItem -LiteralPath $script:cd2.Site.ToolFolder -Recurse -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
            $text | Should -Not -Match 'ab1-sms\.example\.com'
        }

        It 'writes only below sites\CD2' {
            $ab1Files = Get-FolderHash -Path $script:ab1.Site.ToolFolder
            $oldBefore = Get-FolderHash -Path $script:layout.Old
            $cd2Prefs = @{} + $script:cd2.Prefs
            $cd2Prefs.SMSProvider = 'cd2-sms.example.com'
            $cd2Prefs.ApproveAfterSubmit = $false
            Save-PasPreference -Path $script:layout.Prefs -Preference $cd2Prefs -Site $script:cd2.Site | Should -BeTrue
            $session = [pscustomobject]@{ SchemaVersion = 1; ID = '22222222-2222-2222-2222-222222222222'; SiteCode = 'CD2'; Steps = @() }
            Write-PasJson -Path (Join-Path $script:cd2.SessionDir ($session.ID + '.json')) -Value $session -Confirm:$false
            $cd2Folder = $script:cd2.Site.ToolFolder
            foreach ($p in (Join-Path $script:cd2.SessionDir '22222222-2222-2222-2222-222222222222.json'), (Join-Path $cd2Folder 'prefs.json')) {
                $p | Should -BeLike (Join-Path $script:data '*\sites\CD2\tools\pivots-and-scripts\*')
                Test-Path -LiteralPath $p | Should -BeTrue -Because $p
            }
            # The AB1 site folder is unchanged.
            $now = Get-FolderHash -Path $script:ab1.Site.ToolFolder
            $now.Count | Should -Be $ab1Files.Count
            foreach ($k in $ab1Files.Keys) { $now[$k] | Should -Be $ab1Files[$k] -Because $k }
            # The old sessions folder is unchanged and gets no new file. Only the old prefs file may change (its global key).
            $oldAfter = Get-FolderHash -Path $script:layout.Old
            @($oldAfter.Keys | Where-Object { -not $oldBefore.ContainsKey($_) }) | Should -BeNullOrEmpty
            foreach ($k in $oldBefore.Keys | Where-Object { $_ -notlike '*preferences.json' }) { $oldAfter[$k] | Should -Be $oldBefore[$k] -Because $k }
            $oldPrefs = Get-Content -LiteralPath $script:layout.Prefs -Raw | ConvertFrom-Json
            $oldPrefs.SiteCode | Should -Be 'AB1'
            $oldPrefs.SMSProvider | Should -Be 'ab1-sms.example.com'
            $oldPrefs.ApproveAfterSubmit | Should -BeFalse
        }
    }

    Context 'back to site AB1' {
        It 'shows the AB1 values and sessions again' {
            $back = Start-ToolForSite -Layout $script:layout -Site 'AB1' -DataRoot $script:data
            $back.Prefs.SiteCode | Should -Be 'AB1'
            $back.Prefs.SMSProvider | Should -Be 'ab1-sms.example.com'
            Test-Path -LiteralPath (Join-Path $back.SessionDir '11111111-1111-1111-1111-111111111111.json') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $back.SessionDir '22222222-2222-2222-2222-222222222222.json') | Should -BeFalse
        }
    }
}

Describe 'Pivots and Scripts with no site chosen' {
    BeforeAll {
        $script:base2 = Join-Path $TestDrive 'nosite'
        $script:layout2 = New-OldLayout -Base $script:base2
        # An old prefs file with no site code names no site.
        @{ SiteCode = ''; SMSProvider = 'old-sms.example.com'; ApproveAfterSubmit = $true } | ConvertTo-Json | Set-Content -LiteralPath $script:layout2.Prefs -Encoding UTF8
        $script:none = Start-ToolForSite -Layout $script:layout2 -Site '' -DataRoot (Join-Path $script:base2 'data')
    }

    It 'is not active and keeps the old session folder' {
        $script:none.Site.Active | Should -BeFalse
        $script:none.SessionDir | Should -Be (Join-Path $script:layout2.Old 'Sessions')
    }

    It 'creates no site folder' {
        Test-Path -LiteralPath (Join-Path $script:base2 'data') | Should -BeFalse
    }

    It 'reads the old prefs file' {
        $script:none.Prefs.SMSProvider | Should -Be 'old-sms.example.com'
        $script:none.Prefs.SiteCode | Should -BeNullOrEmpty
        $script:none.Prefs.ApproveAfterSubmit | Should -BeTrue
    }

    It 'fills an empty site code and provider from the launcher variables only when no site is active' {
        @{ ApproveAfterSubmit = $true } | ConvertTo-Json | Set-Content -LiteralPath $script:layout2.Prefs -Encoding UTF8
        [Environment]::SetEnvironmentVariable('SUITE_CM_PROVIDER', 'launcher-sms.example.com')
        [Environment]::SetEnvironmentVariable('SUITE_CM_SITECODE', 'EF3')
        $noSite = [pscustomobject]@{ Active = $false }
        $p = Read-PasPreference -Path $script:layout2.Prefs -Site $noSite
        $p.SMSProvider | Should -Be 'launcher-sms.example.com'
        $p.SiteCode | Should -Be 'EF3'
        [Environment]::SetEnvironmentVariable('SUITE_CM_PROVIDER', $null)
        [Environment]::SetEnvironmentVariable('SUITE_CM_SITECODE', $null)
    }

    It 'saves to the old prefs file, the site keys included' {
        $noSite = [pscustomobject]@{ Active = $false }
        $p = @{ SiteCode = 'EF3'; SMSProvider = 'ef3-sms.example.com'; ApproveAfterSubmit = $false }
        Save-PasPreference -Path $script:layout2.Prefs -Preference $p -Site $noSite | Should -BeTrue
        $saved = Get-Content -LiteralPath $script:layout2.Prefs -Raw | ConvertFrom-Json
        $saved.SiteCode | Should -Be 'EF3'
        $saved.SMSProvider | Should -Be 'ef3-sms.example.com'
    }

    It 'works with a null site like no site' {
        Get-PasSessionDirectory -Site $null -DataRoot $script:layout2.Old | Should -Be (Join-Path $script:layout2.Old 'Sessions')
        (Read-PasPreference -Path $script:layout2.Prefs -Site $null).SMSProvider | Should -Be 'ef3-sms.example.com'
    }

    It 'throws when the site session folder cannot be created, so that the start script falls back to the old folder' {
        $broken = [pscustomobject]@{ Active = $true; ToolFolder = (Join-Path $TestDrive 'bad|name') }
        { Get-PasSessionDirectory -Site $broken -DataRoot $script:layout2.Old -Create } | Should -Throw
    }
}

Describe 'Pivots and Scripts source builds no site store from the data root' {
    BeforeAll {
        $script:scriptText = Get-Content -LiteralPath (Join-Path $script:AppRoot 'start-pivotsandscripts.ps1') -Raw
        $script:optionsText = Get-Content -LiteralPath (Join-Path $script:AppRoot 'Module\OptionsDialog.ps1') -Raw
    }

    It 'writes the session file through the session folder and builds no Sessions path in the window script' {
        $script:scriptText.Contains("'Sessions\'") | Should -BeFalse
        $script:scriptText.Contains('Get-PasSessionDirectory -Site $script:Site -DataRoot $dataRoot -Create') | Should -BeTrue
        $script:scriptText.Contains('Join-Path $script:sessionDir ($script:session.ID+''.json'')') | Should -BeTrue
    }

    It 'reads the prefs through the site-aware function and keeps no launcher-variable fallback in the window script' {
        $script:scriptText.Contains('Read-PasPreference -Path $prefsPath -Site $script:Site') | Should -BeTrue
        $script:scriptText.Contains('Read-SuiteSettings') | Should -BeFalse
        $script:scriptText.Contains('SUITE_CM_SITECODE') | Should -BeFalse
        $script:optionsText.Contains('Save-SuiteSettings') | Should -BeFalse
        $script:optionsText.Contains('Save-PasPreference -Path $prefsPath') | Should -BeTrue
    }

    It 'keeps the smoke test away from the real data root and the real sites folder' {
        $line = @($script:scriptText -split "`r?`n" | Where-Object { $_ -like '$script:Site=if($SmokeTest)*' })
        $line.Count | Should -Be 1
        $smokeBranch = $line[0].Substring(0, $line[0].IndexOf('}else{'))
        $smokeBranch.Contains('-NoMigration') | Should -BeTrue
        $smokeBranch.Contains('-IgnoreEnvironment') | Should -BeTrue
        $smokeBranch.Contains('-DataRoot (Join-Path $dataRoot ''AppPackagerData'')') | Should -BeTrue
        $smokeBranch.Contains('-LocalRoot $dataRoot') | Should -BeTrue
    }

    It 'makes the Site Code field read-only with the launcher tooltip when a site is active' {
        $script:optionsText.Contains('$txtSite.IsReadOnly = $true') | Should -BeTrue
        $script:optionsText.Contains('The site is chosen in the AppPackager Suite launcher. Restart this tool after you change it.') | Should -BeTrue
    }

    It 'starts the site watch for the footer' {
        $script:scriptText.Contains('Start-SuiteSiteWatch -Window $window -Site $script:Site') | Should -BeTrue
    }
}
