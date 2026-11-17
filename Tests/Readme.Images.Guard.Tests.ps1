#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }
# Headless guard for the images of README.md. It parses the README and compares file names. It opens no window.
# Every README image is a guide image: it sits in docs\images and the capture tool (tools\guide-capture\steps-*.ps1)
# produces it, so a capture run retakes it and no README image can go stale. A badge from a web address is not a guide image.

BeforeDiscovery {
    $root = Split-Path -Parent $PSScriptRoot
    $script:ImageCases = @([regex]::Matches((Get-Content -LiteralPath (Join-Path $root 'README.md') -Raw), '!\[[^\]]*\]\(([^)\s]+)\)') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notmatch '^https?://' } | Sort-Object -Unique | ForEach-Object { @{ Image = $_ } })
}

BeforeAll {
    $script:Root = Split-Path -Parent $PSScriptRoot
    $script:Steps = (Get-ChildItem -LiteralPath (Join-Path $script:Root 'tools\guide-capture') -Filter 'steps-*.ps1' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join [Environment]::NewLine
}

Describe 'README images' {
    It 'shows at least one guide image' {
        @([regex]::Matches((Get-Content -LiteralPath (Join-Path $script:Root 'README.md') -Raw), '!\[[^\]]*\]\(docs/images/[^)\s]+\)')).Count | Should -BeGreaterThan 0
    }

    It 'takes <Image> from docs/images' -ForEach $script:ImageCases {
        $Image | Should -Match '^docs/images/[A-Za-z0-9._-]+\.png$'
        Test-Path -LiteralPath (Join-Path $script:Root $Image) | Should -BeTrue
    }

    It 'has a capture step for <Image>' -ForEach $script:ImageCases {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($Image)
        $script:Steps | Should -Match ([regex]::Escape("'$name'"))
    }
}
