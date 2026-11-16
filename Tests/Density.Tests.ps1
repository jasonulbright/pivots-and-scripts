#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }

<#
.SYNOPSIS
    Pester 5.x test for the compact 1080p density of the main window (XAML text only, no window is opened).
    The shared style values are asserted in one place. Density.Window.Tests.ps1 measures them on screen.
#>

BeforeAll {
    $script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:Xaml = [xml](Get-Content -LiteralPath (Join-Path $script:RepoRoot 'MainWindow.xaml') -Raw)
    $script:Ns = New-Object System.Xml.XmlNamespaceManager($script:Xaml.NameTable)
    $script:Ns.AddNamespace('w', 'http://schemas.microsoft.com/winfx/2006/xaml/presentation')
    $script:Ns.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
    function Get-StyleValue {
        param([string]$Key, [string]$Property)
        $style = $script:Xaml.SelectSingleNode("//w:Style[@x:Key='$Key']", $script:Ns)
        $style | Should -Not -BeNullOrEmpty -Because $Key
        $setter = $style.SelectSingleNode("w:Setter[@Property='$Property']", $script:Ns)
        if ($setter) { $setter.GetAttribute('Value') } else { $null }
    }
}

Describe 'Compact density at 1080p' {
    It 'opens at the design size of a maximized 1080p work area and keeps a minimum size that fits 1024x720' {
        $w = $script:Xaml.DocumentElement
        [int]$w.GetAttribute('Width') | Should -Be 1920
        [int]$w.GetAttribute('Height') | Should -Be 1032
        [int]$w.GetAttribute('MinWidth') | Should -BeLessOrEqual 1024
        [int]$w.GetAttribute('MinHeight') | Should -BeLessOrEqual 720
    }

    It 'opens maximized on the first start, when no window state is saved' {
        $text = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'start-pivotsandscripts.ps1') -Raw
        $text | Should -Match "(?s)Test-Path -LiteralPath \(Join-Path \`$dataRoot 'windowstate\.json'\)\)\) \{ \`$window\.WindowState = \[System\.Windows\.WindowState\]::Maximized \}\s*\r?\nRestore-WindowState"
    }

    It 'sizes the sidebar view buttons between 34 and 36 px' {
        [double](Get-StyleValue 'ViewButtonStyle' 'Height') | Should -BeIn 34, 35, 36
    }

    It 'sizes the one button style at 26 to 28 px' {
        [double](Get-StyleValue 'ThemedButtonStyle' 'Height') | Should -BeGreaterOrEqual 26
        [double](Get-StyleValue 'ThemedButtonStyle' 'Height') | Should -BeLessOrEqual 28
    }

    It 'sizes every single-line box between 26 and 28 px' {
        $named = @($script:Xaml.SelectNodes('//w:TextBox[@Height]', $script:Ns))
        $named.Count | Should -BeGreaterThan 4
        foreach ($tb in $named) {
            $name = $tb.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
            # The device list box is a multi-line box and keeps its own height.
            if ($name -eq 'targetInput') { continue }
            [double]$tb.GetAttribute('Height') | Should -BeIn 26, 27, 28 -Because $name
        }
    }

    It 'gives every grid rows of 24 to 26 px and a 26 px column header from the one shared style' {
        [double](Get-StyleValue 'ThemedDataGridStyle' 'RowHeight') | Should -BeGreaterOrEqual 24
        [double](Get-StyleValue 'ThemedDataGridStyle' 'RowHeight') | Should -BeLessOrEqual 26
        [double](Get-StyleValue 'ThemedDataGridStyle' 'ColumnHeaderHeight') | Should -Be 26
        foreach ($g in @($script:Xaml.SelectNodes('//w:DataGrid', $script:Ns))) {
            $g.GetAttribute('RowHeight') | Should -BeNullOrEmpty -Because 'the row height has one place: ThemedDataGridStyle'
            $g.GetAttribute('Style') | Should -Match 'ThemedDataGridStyle' -Because $g.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
        }
    }
}

Describe 'No vacant space at the maximized work area' {
    It 'gives no pane that holds an editor, a list or a grid a fixed height of 100 px or more' {
        $fixed = @($script:Xaml.SelectNodes('//w:RowDefinition[@Height]', $script:Ns) | Where-Object { $_.GetAttribute('Height') -match '^\d+(\.\d+)?$' -and [double]$_.GetAttribute('Height') -ge 100 })
        $fixed | Should -BeNullOrEmpty -Because ('a fixed row leaves dead space at 1080p, use a star row: ' + (($fixed | ForEach-Object { $_.OuterXml }) -join '; '))
    }

    It 'lets the editor row and the results row share the free height with star rows and a splitter between them' {
        $rows = @($script:Xaml.SelectNodes("//w:Grid.RowDefinitions[w:RowDefinition[@Height='5']]/w:RowDefinition", $script:Ns))
        $rows.Count | Should -BeGreaterThan 3
        @($rows | Where-Object { $_.GetAttribute('Height') -match '\*$' }).Count | Should -BeGreaterOrEqual 2
        $script:Xaml.SelectSingleNode('//w:GridSplitter', $script:Ns) | Should -Not -BeNullOrEmpty
    }

    It 'sizes the Script Parameters dialog to its content, with a minimum and a maximum height' {
        $text = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'Module\ParameterDialog.ps1') -Raw
        $text | Should -Match 'Title="Script Parameters"[^>]*SizeToContent="Height"[^>]*MinHeight="\d+"[^>]*MaxHeight="\d+"'
    }

    It 'gives the content column a star width, not a fixed width' {
        $cols = @($script:Xaml.SelectNodes("//w:Grid.ColumnDefinitions[w:ColumnDefinition[@Width='230']]/w:ColumnDefinition", $script:Ns))
        $cols.Count | Should -Be 3
        $cols[2].GetAttribute('Width') | Should -Be '*'
    }
}
