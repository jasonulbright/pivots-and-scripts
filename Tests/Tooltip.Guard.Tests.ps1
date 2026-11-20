#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }
# Tooltip guard. It parses MainWindow.xaml and the XAML here-string of the Site Scripts dialog.
# It creates no WPF control, opens no window and needs no ConfigMgr site.
#
# Rules: every audited control has a ToolTip that is not empty, is ASCII, ends in a period and is at most 110 characters.
# Controls that are skipped on purpose: OK, Cancel and Use Parameters buttons (the label says it all), read-only
# output boxes, DataGrid columns, the Options dialog page list, and controls that the code builds at run time.

BeforeDiscovery {
    $script:TtAudited = @(
        @{ File = 'MainWindow.xaml'; Name = 'btnPivot' }
        @{ File = 'MainWindow.xaml'; Name = 'btnScript' }
        @{ File = 'MainWindow.xaml'; Name = 'btnHistory' }
        @{ File = 'MainWindow.xaml'; Name = 'btnOptions' }
        @{ File = 'MainWindow.xaml'; Name = 'libraryFilter' }
        @{ File = 'MainWindow.xaml'; Name = 'library' }
        @{ File = 'MainWindow.xaml'; Name = 'btnOpen' }
        @{ File = 'MainWindow.xaml'; Name = 'btnSave' }
        @{ File = 'MainWindow.xaml'; Name = 'btnSaveSession' }
        @{ File = 'MainWindow.xaml'; Name = 'btnNewSession' }
        @{ File = 'MainWindow.xaml'; Name = 'toggleTheme' }
        @{ File = 'MainWindow.xaml'; Name = 'btnConnect' }
        @{ File = 'MainWindow.xaml'; Name = 'targetKind' }
        @{ File = 'MainWindow.xaml'; Name = 'targetInput' }
        @{ File = 'MainWindow.xaml'; Name = 'btnImport' }
        @{ File = 'MainWindow.xaml'; Name = 'btnResolve' }
        @{ File = 'MainWindow.xaml'; Name = 'btnTargets' }
        @{ File = 'MainWindow.xaml'; Name = 'btnFind' }
        @{ File = 'MainWindow.xaml'; Name = 'findText' }
        @{ File = 'MainWindow.xaml'; Name = 'replaceText' }
        @{ File = 'MainWindow.xaml'; Name = 'btnReplace' }
        @{ File = 'MainWindow.xaml'; Name = 'btnCheck' }
        @{ File = 'MainWindow.xaml'; Name = 'btnRun' }
        @{ File = 'MainWindow.xaml'; Name = 'btnStop' }
        @{ File = 'MainWindow.xaml'; Name = 'btnSubmit' }
        @{ File = 'MainWindow.xaml'; Name = 'scriptGuid' }
        @{ File = 'MainWindow.xaml'; Name = 'btnParameters' }
        @{ File = 'MainWindow.xaml'; Name = 'btnSiteScripts' }
        @{ File = 'MainWindow.xaml'; Name = 'resultFilter' }
        @{ File = 'MainWindow.xaml'; Name = 'btnCsv' }
        @{ File = 'MainWindow.xaml'; Name = 'btnJson' }
        @{ File = 'MainWindow.xaml'; Name = 'btnCopy' }
        @{ File = 'MainWindow.xaml'; Name = 'btnGrid' }
        @{ File = 'MainWindow.xaml'; Name = 'btnSelectionScript' }
        @{ File = 'MainWindow.xaml'; Name = 'btnSelectionPivot' }
        @{ File = 'MainWindow.xaml'; Name = 'tab:Devices' }
        @{ File = 'MainWindow.xaml'; Name = 'tab:Raw' }
        @{ File = 'MainWindow.xaml'; Name = 'tab:Pipeline' }
        @{ File = 'Module/ScriptsDialog.ps1'; Name = 'btnRefresh' }
        @{ File = 'Module/ScriptsDialog.ps1'; Name = 'btnUse' }
        @{ File = 'Module/ScriptsDialog.ps1'; Name = 'btnApprove' }
        @{ File = 'Module/ScriptsDialog.ps1'; Name = 'btnDeny' }
        @{ File = 'Module/ScriptsDialog.ps1'; Name = 'btnRemove' }
        @{ File = 'Module/ScriptsDialog.ps1'; Name = 'comment' }
    )
}

BeforeAll {
    $script:TtRepoRoot = Split-Path -Parent $PSScriptRoot
    $script:TtKeyNamespace = 'http://schemas.microsoft.com/winfx/2006/xaml'

    # Returns the XAML document of a file: the file itself for .xaml, the first XAML here-string for .ps1.
    function Get-TtDocument {
        param([string]$File)
        $text = Get-Content -LiteralPath (Join-Path $script:TtRepoRoot $File) -Raw
        if ($File -like '*.ps1') {
            $match = [regex]::Match($text, "(?s)\`$xaml\s*=\s*@'\r?\n(.*?)\r?\n'@")
            if (-not $match.Success) { throw "No XAML here-string in $File" }
            $text = $match.Groups[1].Value
        }
        return [xml]$text
    }

    # Returns the ToolTip text of an audited control, or $null when the control is missing.
    function Get-TtToolTip {
        param([string]$File, [string]$Name)
        $doc = Get-TtDocument -File $File
        if ($Name -like 'tab:*') {
            $header = $Name.Substring(4)
            $node = $doc.SelectSingleNode('//*[local-name()="TabItem"]//*[local-name()="TextBlock"][@Text="' + $header + '"]')
        } else {
            $node = @($doc.SelectNodes('//*[@*[local-name()="Name" and namespace-uri()="' + $script:TtKeyNamespace + '"]]') | Where-Object {
                    $_.GetAttribute('Name', $script:TtKeyNamespace) -eq $Name
                }) | Select-Object -First 1
        }
        if (-not $node) { return $null }
        return $node.GetAttribute('ToolTip')
    }
}

Describe 'Tooltip guard' {
    It 'audits <File> <Name>: the control exists and has a ToolTip' -ForEach $script:TtAudited {
        $tip = Get-TtToolTip -File $File -Name $Name
        $tip | Should -Not -BeNullOrEmpty -Because "$Name in $File needs a ToolTip"
    }

    It 'audits <File> <Name>: the ToolTip is ASCII, ends in a period and is at most 110 characters' -ForEach $script:TtAudited {
        $tip = Get-TtToolTip -File $File -Name $Name
        $tip | Should -Not -BeNullOrEmpty
        $tip | Should -Match '^[\x20-\x7E]+$' -Because 'a ToolTip is ASCII text'
        $tip | Should -Match '\.$' -Because 'a ToolTip is a sentence that ends in a period'
        $tip.Length | Should -BeLessOrEqual 110
        $tip.Trim() | Should -BeExactly $tip
    }
}
