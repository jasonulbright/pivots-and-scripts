#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }
# Guard tests for the theme rules. They parse the files (XAML, XAML here-strings and PowerShell syntax trees). The one
# behavior test builds a Button without a window in an STA runspace. They run on Windows PowerShell 5.1 and PowerShell 7
# and open no window.
#   (a) Every blue background in XAML and PowerShell has a white foreground, also in hover, pressed and selected states.
#   (b) No font size, weight, style or text decoration depends on the theme. Every title is bold. A title of a site code
#       or SMS Provider box is bold and 14 pt or larger, and its value is not (the main window and the Options dialog).
#   (c) No banned word is in a tooltip, a UI string, the README or the user guide. A tooltip is one short sentence.
#   (d) Every button takes the shared themed style. The dialog has one secondary style. Titles are in Title Case.
#   (e) No window text shows the text of an exception.
#   (f) No path filter of a repository script depends on where the repository folder is.

BeforeDiscovery {
    . "$PSScriptRoot\ThemeGuardHelpers.ps1"
    $script:arrPsFileD = @(
        'start-pivotsandscripts.ps1', 'Module\PivotsAndScripts.psm1', 'Module\Execute.ps1', 'Module\OptionsDialog.ps1',
        'Module\ParameterDialog.ps1', 'Module\ScriptsDialog.ps1', 'Lib\SuiteCommon\SuiteCommon.psm1'
    ) | ForEach-Object { @{ Name = $_; Path = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath $_) } }
    $script:arrAppPsFileD = @($script:arrPsFileD | Where-Object { $_.Name -notmatch 'SuiteCommon' })
    $script:arrXamlDocD = @(Get-XamlDocument)
    $script:arrOwnXamlDocD = @($script:arrXamlDocD | Where-Object { $_.Source -notmatch 'SuiteCommon' })
}

BeforeAll {
    . "$PSScriptRoot\ThemeGuardHelpers.ps1"
    $script:arrXamlDoc = @(Get-XamlDocument)
    $script:arrOwnXamlDoc = @($script:arrXamlDoc | Where-Object { $_.Source -notmatch 'SuiteCommon' })
    $script:strShellPath = Join-Path -Path $script:strRepoRoot -ChildPath 'start-pivotsandscripts.ps1'
    $script:strModulePath = Join-Path -Path $script:strRepoRoot -ChildPath 'Module\PivotsAndScripts.psm1'
    $script:strOptionsPath = Join-Path -Path $script:strRepoRoot -ChildPath 'Module\OptionsDialog.ps1'
    $script:arrDialogPath = @('Module\OptionsDialog.ps1', 'Module\ParameterDialog.ps1', 'Module\ScriptsDialog.ps1') | ForEach-Object { Join-Path -Path $script:strRepoRoot -ChildPath $_ }
    $script:strNamespace = 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro"'
    $script:strThemedStyle = '<Style x:Key="ThemedButtonStyle" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square}"/>'
    function Write-TempScript {
        param([string]$Text)
        $strTemp = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('themeguard-' + [guid]::NewGuid().ToString('N') + '.ps1')
        [System.IO.File]::WriteAllText($strTemp, $Text)
        return $strTemp
    }
}

Describe 'Blue backgrounds have white text (a)' {
    It 'finds XAML to check' {
        $script:arrXamlDoc.Count | Should -BeGreaterThan 2
        @($script:arrXamlDoc | Where-Object { $_.Source -eq 'MainWindow.xaml' }).Count | Should -Be 1
        @($script:arrOwnXamlDoc | Where-Object { $_.Source -like '*Dialog.ps1 here-string*' }).Count | Should -Be 3
    }

    It 'recognizes blue and white brushes' {
        Test-BlueBrush '{DynamicResource MahApps.Brushes.Accent}' | Should -BeTrue
        Test-BlueBrush '{DynamicResource MahApps.Colors.Accent}' | Should -BeTrue
        Test-BlueBrush '{DynamicResource MahApps.Colors.AccentBase}' | Should -BeTrue
        Test-BlueBrush '{DynamicResource MahApps.Brushes.Accent3}' | Should -BeTrue
        Test-BlueBrush '{DynamicResource MahApps.Brushes.Highlight}' | Should -BeTrue
        Test-BlueBrush '{DynamicResource {x:Static SystemColors.HighlightBrushKey}}' | Should -BeTrue
        Test-BlueBrush '#0078D4' | Should -BeTrue
        Test-BlueBrush '#FF0078D4' | Should -BeTrue
        Test-BlueBrush '#07D' | Should -BeTrue
        Test-BlueBrush '#1E1E1E' | Should -BeFalse
        Test-BlueBrush '#3A3A3A' | Should -BeFalse
        Test-BlueBrush '{DynamicResource MahApps.Brushes.ThemeBackground}' | Should -BeFalse
        Test-WhiteBrush '{DynamicResource MahApps.Brushes.IdealForeground}' | Should -BeTrue
        Test-WhiteBrush 'White' | Should -BeTrue
        Test-WhiteBrush 'Black' | Should -BeFalse
    }

    It 'flags a blue background that has no white foreground, with every property form' {
        $strOpen = '<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro" TargetType="Button">'
        @(Get-BlueWithoutWhite -Text ($strOpen + '<Setter Property="Background" Value="#0078D4"/></Style>') -Source 's').Count | Should -Be 1
        @(Get-BlueWithoutWhite -Text ($strOpen + '<Setter Property="Background" Value="#0078D4"/><Setter Property="Foreground" Value="White"/></Style>') -Source 's').Count | Should -Be 0
        @(Get-BlueWithoutWhite -Text ($strOpen + '<Setter Property="Border.Background" Value="{DynamicResource MahApps.Brushes.Accent}"/></Style>') -Source 's').Count | Should -Be 1
        @(Get-BlueWithoutWhite -Text ($strOpen + '<Setter Property="Controls:ControlsHelper.MouseOverBackground" Value="{DynamicResource MahApps.Brushes.Accent}"/></Style>') -Source 's').Count | Should -Be 1
        @(Get-BlueWithoutWhite -Text ($strOpen + '<Setter Property="Background"><Setter.Value><SolidColorBrush Color="{DynamicResource MahApps.Colors.Accent}"/></Setter.Value></Setter></Style>') -Source 's').Count | Should -Be 1
        @(Get-BlueWithoutWhite -Text ($strOpen + '<Setter Property="Background"><Setter.Value><LinearGradientBrush><GradientStop Color="#0078D4"/></LinearGradientBrush></Setter.Value></Setter></Style>') -Source 's').Count | Should -Be 1
        @(Get-BlueWithoutWhite -Text ($strOpen + '<Style.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Accent}"/></Trigger></Style.Triggers></Style>') -Source 's').Count | Should -Be 1
        @(Get-BlueWithoutWhite -Text ($strOpen + '<Style.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Accent}"/><Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.IdealForeground}"/></Trigger></Style.Triggers></Style>') -Source 's').Count | Should -Be 0
        $strGrid = '<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">'
        @(Get-BlueWithoutWhite -Text ($strGrid + '<Border Background="#0078D4"><TextBlock Text="x"/></Border></Grid>') -Source 's').Count | Should -Be 1
        @(Get-BlueWithoutWhite -Text ($strGrid + '<Border Background="#0078D4"><TextBlock Text="x" Foreground="White"/></Border></Grid>') -Source 's').Count | Should -Be 0
        @(Get-BlueWithoutWhite -Text ($strGrid + '<Button Background="{DynamicResource MahApps.Brushes.Accent}" Content="x"/></Grid>') -Source 's').Count | Should -Be 1
        @(Get-BlueWithoutWhite -Text ($strGrid + '<Border><Border.Background><SolidColorBrush Color="#0078D4"/></Border.Background></Border></Grid>') -Source 's').Count | Should -Be 1
    }

    It 'has a white foreground on every blue background of <_.Source>' -ForEach $script:arrOwnXamlDocD {
        $arrBad = @(Get-BlueWithoutWhite -Text $_.Text -Source $_.Source)
        $arrBad | Should -BeNullOrEmpty
    }

    It 'sets no blue color as a Background in <Name>' -ForEach $script:arrAppPsFileD {
        $arrBad = @(foreach ($strHit in @(Get-ScriptBlueBackground -Path $Path)) { 'background ' + $strHit })
        $arrBad | Should -BeNullOrEmpty
    }

    It 'finds a blue Background assignment in a script' {
        $strTemp = Write-TempScript "`$b.Background = '#0078D4'`n`$c.Foreground = '#0078D4'`n`$d.Background = '#1E1E1E'`n"
        try {
            @(Get-ScriptBlueBackground -Path $strTemp).Count | Should -Be 1
            [System.IO.File]::WriteAllText($strTemp, "`$b.Background = '#0078D4'`n`$b.Foreground = 'White'`n")
            @(Get-ScriptBlueBackground -Path $strTemp).Count | Should -Be 0
        }
        finally { Remove-Item -LiteralPath $strTemp -Force -ErrorAction SilentlyContinue }
    }

    It 'sets a white foreground on every accent button style outside SuiteCommon in <_.Source>' -ForEach $script:arrOwnXamlDocD {
        $arrBad = @(Get-AccentButtonWithoutWhite -Text $_.Text -Source $_.Source)
        $arrBad | Should -BeNullOrEmpty
    }

    It 'flags an accent button style that has no white foreground' {
        $strXaml = '<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"><Style x:Key="A" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square.Accent}"><Setter Property="Height" Value="32"/></Style></ResourceDictionary>'
        @(Get-AccentButtonWithoutWhite -Text $strXaml -Source 'sample').Count | Should -Be 1
        $strOk = $strXaml.Replace('<Setter Property="Height" Value="32"/>', '<Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.IdealForeground}"/>')
        @(Get-AccentButtonWithoutWhite -Text $strOk -Source 'sample').Count | Should -Be 0
    }

    It 'sets no literal color and no Opacity on a blue element outside the styles of <_.Source>' -ForEach $script:arrOwnXamlDocD {
        @(Get-ElementColorViolation -Text $_.Text -Source $_.Source) | Should -BeNullOrEmpty
    }

    It 'flags a literal color on an element and an Opacity on a blue element' {
        $strGrid = '<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">'
        @(Get-ElementColorViolation -Text ($strGrid + '<TextBlock Foreground="White"/></Grid>') -Source 's').Count | Should -Be 1
        @(Get-ElementColorViolation -Text ($strGrid + '<Border Background="#0078D4"/></Grid>') -Source 's').Count | Should -Be 1
        @(Get-ElementColorViolation -Text ($strGrid + '<Border Background="{DynamicResource MahApps.Brushes.Accent}" Opacity="0.85"/></Grid>') -Source 's').Count | Should -Be 1
        @(Get-ElementColorViolation -Text ($strGrid + '<Border Background="{DynamicResource MahApps.Brushes.ThemeBackground}" Opacity="0.9"><TextBlock Foreground="{DynamicResource MahApps.Brushes.IdealForeground}"/></Border></Grid>') -Source 's').Count | Should -Be 0
        @(Get-ElementColorViolation -Text ($strGrid + '<Grid.Resources><Style TargetType="TextBlock"><Setter Property="Foreground" Value="White"/></Style></Grid.Resources></Grid>') -Source 's').Count | Should -Be 0
    }

    It 'sets the foreground of every selected-state trigger that sets a Background in <_.Source>' -ForEach $script:arrXamlDocD {
        [xml]$xml = $_.Text
        $arrBad = foreach ($objTrigger in @($xml.SelectNodes("//*[local-name()='Trigger'][@Property='IsSelected' or @Property='IsHighlighted' or @Property='IsMouseOver' or @Property='IsPressed']"))) {
            $objBackground = Get-SetterChild -Node $objTrigger -LeafPattern 'Background$' | Select-Object -First 1
            $objForeground = Get-SetterChild -Node $objTrigger -LeafPattern 'Foreground$' | Select-Object -First 1
            if ($objBackground -and -not $objForeground -and -not (Test-WhiteForegroundInScope $objBackground)) { '{0} trigger sets a Background and no Foreground' -f $objTrigger.GetAttribute('Property') }
        }
        @($arrBad) | Should -BeNullOrEmpty
    }

    It 'gives every list, combo box, tree and grid a selected state with white text on blue in <_.Source>' -ForEach $script:arrOwnXamlDocD {
        $arrBad = @(Get-SelectedStateViolation -Text $_.Text -Source $_.Source)
        $arrBad | Should -BeNullOrEmpty
    }

    It 'finds the item controls of the main window and of the dialogs' {
        $objMain = @($script:arrXamlDoc | Where-Object { $_.Source -eq 'MainWindow.xaml' })[0]
        [xml]$xml = $objMain.Text
        foreach ($strControl in 'DataGrid', 'ListBox', 'ComboBox') {
            @($xml.SelectNodes(("//*[local-name()='{0}']" -f $strControl))).Count | Should -BeGreaterThan 0 -Because $strControl
        }
        $objOptions = @($script:arrOwnXamlDoc | Where-Object { $_.Source -like 'OptionsDialog.ps1 here-string*' })[0]
        [xml]$xmlOptions = $objOptions.Text
        @($xmlOptions.SelectNodes("//*[local-name()='ListBox']")).Count | Should -BeGreaterThan 0
        $objScripts = @($script:arrOwnXamlDoc | Where-Object { $_.Source -like 'ScriptsDialog.ps1 here-string*' })[0]
        [xml]$xmlScripts = $objScripts.Text
        @($xmlScripts.SelectNodes("//*[local-name()='DataGrid']")).Count | Should -BeGreaterThan 0
    }

    It 'gives every combo box that a dialog builds in code the themed item container style' {
        foreach ($strPath in $script:arrDialogPath) { @(Get-CodeComboViolation -Path $strPath) | Should -BeNullOrEmpty }
        (Get-Content -LiteralPath (Join-Path -Path $script:strRepoRoot -ChildPath 'Module\ParameterDialog.ps1') -Raw) | Should -Match "ItemContainerStyleProperty,\s*'ThemedComboBoxItemStyle'"
    }

    It 'flags a combo box that a script builds in code without the themed item container style' {
        $strTemp = Write-TempScript "function A {`n  `$c = [Windows.Controls.ComboBox]::new()`n  `$c.ItemsSource = @(1)`n}`nfunction B {`n  `$c = [Windows.Controls.ComboBox]::new()`n  `$c.SetResourceReference([Windows.Controls.ItemsControl]::ItemContainerStyleProperty, 'ThemedComboBoxItemStyle')`n}`n"
        try { @(Get-CodeComboViolation -Path $strTemp).Count | Should -Be 1 }
        finally { Remove-Item -LiteralPath $strTemp -Force -ErrorAction SilentlyContinue }
    }

    It 'selects the editor text with white text on the highlight blue' {
        $strShell = Get-Content -LiteralPath $script:strShellPath -Raw
        $strShell | Should -Match "SelectionBrushProperty,'MahApps\.Brushes\.Highlight'"
        $strShell | Should -Match "SelectionForegroundProperty,'MahApps\.Brushes\.IdealForeground'"
    }

    It 'flags a combo box without the IsHighlighted state and a list without an item container style' {
        $strOpen = '<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">'
        $strSelected = '<Trigger Property="IsSelected" Value="True"><Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Accent}"/><Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.IdealForeground}"/></Trigger>'
        $strHighlighted = '<Trigger Property="IsHighlighted" Value="True"><Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Accent}"/><Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.IdealForeground}"/></Trigger>'
        $strRow = '<Style x:Key="R" TargetType="DataGridRow"><Style.Triggers>' + $strSelected + '</Style.Triggers></Style><Style x:Key="G" TargetType="DataGrid"><Setter Property="RowStyle" Value="{StaticResource R}"/></Style>'
        $strCell = '<Style x:Key="C" TargetType="DataGridCell"><Style.Triggers>' + $strSelected + '</Style.Triggers></Style>'
        $strComboBad = '<Style x:Key="I" TargetType="ComboBoxItem"><Style.Triggers>' + $strSelected + '</Style.Triggers></Style>'
        $strComboGood = '<Style x:Key="I" TargetType="ComboBoxItem"><Style.Triggers>' + $strSelected + $strHighlighted + '</Style.Triggers></Style>'
        $strBox = '<ComboBox ItemContainerStyle="{StaticResource I}"/>'
        @(Get-SelectedStateViolation -Text ($strOpen + '<Grid.Resources>' + $strComboBad + '</Grid.Resources>' + $strBox + '</Grid>') -Source 's').Count | Should -Be 1
        @(Get-SelectedStateViolation -Text ($strOpen + '<Grid.Resources>' + $strComboGood + '</Grid.Resources>' + $strBox + '</Grid>') -Source 's').Count | Should -Be 0
        @(Get-SelectedStateViolation -Text ($strOpen + '<ListBox/></Grid>') -Source 's').Count | Should -Be 1
        @(Get-SelectedStateViolation -Text ($strOpen + '<Grid.Resources>' + $strRow + $strCell + '</Grid.Resources><DataGrid Style="{StaticResource G}" CellStyle="{StaticResource C}"/></Grid>') -Source 's').Count | Should -Be 0
        @(Get-SelectedStateViolation -Text ($strOpen + '<Grid.Resources>' + $strRow + '</Grid.Resources><DataGrid Style="{StaticResource G}"/></Grid>') -Source 's').Count | Should -Be 1
        @(Get-SelectedStateViolation -Text ($strOpen + '<TreeView/></Grid>') -Source 's').Count | Should -Be 1
    }

    It 'finds the sidebar buttons of the shell and lists each in the Initialize-SuiteTheme call' {
        $objAst = [System.Management.Automation.Language.Parser]::ParseFile($script:strShellPath, [ref]$null, [ref]$null)
        $arrInit = @($objAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Initialize-SuiteTheme' }, $true))
        $arrInit.Count | Should -Be 1
        $strInit = $arrInit[0].Extent.Text
        $objMain = @($script:arrXamlDoc | Where-Object { $_.Source -eq 'MainWindow.xaml' })[0]
        [xml]$xml = $objMain.Text
        $arrSidebar = @($xml.SelectNodes("//*[local-name()='Button'][contains(@Style,'ViewButtonStyle') or contains(@Style,'OptionsButtonStyle')]"))
        $arrSidebar.Count | Should -Be 4
        $arrMissing = foreach ($objButton in $arrSidebar) {
            $strName = $objButton.GetAttribute('Name', $script:strXamlNamespace)
            if (-not $strName) { 'a sidebar button has no x:Name' } elseif ($strInit -notmatch ('\$ui\.' + $strName + '\b')) { $strName }
        }
        @($arrMissing) | Should -BeNullOrEmpty
        $strInit | Should -Match '-ViewButtons'
        $strInit | Should -Match '-WorkflowButtons'
        $strInit | Should -Match '-OptionsButtons'
        $strShell = Get-Content -LiteralPath $script:strShellPath -Raw
        ([regex]::Matches($strShell, 'Update-SidebarButtonTheme')).Count | Should -BeGreaterOrEqual 3
        ([regex]::Matches($strShell, 'Set-ButtonTheme')).Count | Should -BeGreaterOrEqual 2
    }
}

Describe 'Theme helpers of SuiteCommon behave and are used (a, b)' {
    BeforeAll {
        # Set-ThemeForeground tests a type of WindowsBase. The test loads the assemblies itself, so it runs alone.
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
        $script:strSuitePath = Join-Path -Path $script:strRepoRoot -ChildPath 'Lib\SuiteCommon\SuiteCommon.psm1'
        $script:objSuiteAst = [System.Management.Automation.Language.Parser]::ParseFile($script:strSuitePath, [ref]$null, [ref]$null)
        function Get-SuiteFunction {
            param([string]$Name)
            $script:objSuiteAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name }, $true)
        }
        function Get-CommandCount {
            param($Ast, [string]$Name)
            @($Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq $Name }, $true)).Count
        }
        . ([scriptblock]::Create((Get-SuiteFunction 'Set-ThemeForeground').Extent.Text))
    }

    It 'paints the light theme buttons of SuiteCommon with white text' {
        $strText = Remove-ScriptComment -Text (Get-Content -LiteralPath $script:strSuitePath -Raw)
        $strText | Should -Match "OnBlue\s*=\s*\`$bc\.ConvertFrom\('#FFFFFF'\)"
        foreach ($strName in 'Update-SidebarButtonTheme', 'Set-ButtonTheme') {
            $objFunction = Get-SuiteFunction $strName
            $objFunction | Should -Not -BeNullOrEmpty -Because $strName
            (Get-CommandCount $objFunction 'Set-ThemeForeground') | Should -BeGreaterThan 0 -Because ('{0} sets the foreground with each background' -f $strName)
            (Get-CommandCount $objFunction 'Set-ConnectionTextTheme') | Should -BeGreaterThan 0 -Because $strName
        }
    }

    It 'Set-ThemeForeground sets the on-blue brush in light mode and clears it in dark mode on a plain object' {
        $objControl = [pscustomobject]@{ Foreground = $null }
        Set-ThemeForeground -Control $objControl -IsDark $false -OnBlue 'White'
        $objControl.Foreground | Should -Be 'White'
        Set-ThemeForeground -Control $objControl -IsDark $true -OnBlue 'White'
        $objControl.Foreground | Should -BeNullOrEmpty
    }

    It 'Set-ThemeForeground clears a dependency object through ClearValue and takes a null control' {
        $objAst = Get-SuiteFunction 'Set-ThemeForeground'
        $objAst.Extent.Text | Should -Match 'ClearValue\(\[System\.Windows\.Controls\.Control\]::ForegroundProperty\)'
        { Set-ThemeForeground -Control $null -IsDark $false -OnBlue 'White' } | Should -Not -Throw
    }

    It 'Set-ThemeForeground paints a real Button white in light mode and gives the foreground back in dark mode' {
        $strFunction = (Get-SuiteFunction 'Set-ThemeForeground').Extent.Text
        $arrResult = Invoke-StaBlock -Argument @($strFunction) -Script {
            param($Function)
            Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
            . ([scriptblock]::Create($Function))
            $objButton = New-Object System.Windows.Controls.Button
            $objWhite = [System.Windows.Media.Brushes]::White
            $strUnset = [System.Windows.DependencyProperty]::UnsetValue
            Set-ThemeForeground -Control $objButton -IsDark $false -OnBlue $objWhite
            $boolLightWhite = [object]::ReferenceEquals($objButton.ReadLocalValue([System.Windows.Controls.Control]::ForegroundProperty), $objWhite)
            Set-ThemeForeground -Control $objButton -IsDark $true -OnBlue $objWhite
            $boolDarkCleared = [object]::ReferenceEquals($objButton.ReadLocalValue([System.Windows.Controls.Control]::ForegroundProperty), $strUnset)
            $boolLightWhite
            $boolDarkCleared
        }
        $arrResult.Count | Should -Be 2
        $arrResult[0] | Should -BeTrue -Because 'light mode sets the on-blue brush on the button'
        $arrResult[1] | Should -BeTrue -Because 'dark mode clears the local value, so the theme brush shows again'
    }

    It 'the script starts the theme and every dialog calls Set-DialogTheme' {
        $objShell = [System.Management.Automation.Language.Parser]::ParseFile($script:strShellPath, [ref]$null, [ref]$null)
        (Get-CommandCount $objShell 'Initialize-SuiteTheme') | Should -BeGreaterThan 0
        (Get-CommandCount $objShell 'Update-SidebarButtonTheme') | Should -BeGreaterThan 0
        $intDialog = @($script:arrOwnXamlDoc | Where-Object { $_.Source -like '*Dialog.ps1 here-string*' }).Count
        $intDialog | Should -Be 3
        $intCall = 0
        foreach ($strPath in $script:arrDialogPath) {
            $objDialogAst = [System.Management.Automation.Language.Parser]::ParseFile($strPath, [ref]$null, [ref]$null)
            (Get-CommandCount $objDialogAst 'Set-DialogTheme') | Should -BeGreaterThan 0 -Because $strPath
            $intCall++
        }
        $intCall | Should -Be $intDialog
        (Get-SuiteFunction 'Set-DialogTheme') | Should -Not -BeNullOrEmpty
    }
}

Describe 'Fonts do not depend on the theme (b)' {
    It 'has no font property in a theme branch of <Name>' -ForEach $script:arrPsFileD {
        $objAst = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $arrAssign = $objAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left -is [System.Management.Automation.Language.MemberExpressionAst] }, $true)
        $arrBad = foreach ($objAssign in $arrAssign) {
            $strMember = [string]$objAssign.Left.Member.Value
            if ($script:arrThemeProperty -notcontains $strMember) { continue }
            $objParent = $objAssign.Parent
            while ($objParent) {
                $strCondition = ''
                if ($objParent -is [System.Management.Automation.Language.IfStatementAst]) { $strCondition = (@($objParent.Clauses | ForEach-Object { $_.Item1.Extent.Text }) -join ' ') }
                elseif ($objParent -is [System.Management.Automation.Language.SwitchStatementAst]) { $strCondition = $objParent.Condition.Extent.Text }
                if ($strCondition -match '(?i)IsDark|DarkMode|Light|Theme|IsOn') { '{0}:{1} sets {2} in a theme branch' -f $Name, $objAssign.Extent.StartLineNumber, $strMember; break }
                $objParent = $objParent.Parent
            }
        }
        @($arrBad) | Should -BeNullOrEmpty
    }

    It 'sets no font property in the theme functions of SuiteCommon except the connection boxes' {
        $strPath = Join-Path -Path $script:strRepoRoot -ChildPath 'Lib\SuiteCommon\SuiteCommon.psm1'
        $objAst = [System.Management.Automation.Language.Parser]::ParseFile($strPath, [ref]$null, [ref]$null)
        foreach ($strName in 'Set-ThemeForeground', 'Update-SidebarButtonTheme', 'Set-ButtonTheme', 'Set-DialogTheme', 'Update-TitleBarBrushes', 'Initialize-SuiteTheme') {
            $objFunction = $objAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $strName }, $true)
            $objFunction | Should -Not -BeNullOrEmpty -Because $strName
            $objFunction.Extent.Text | Should -Not -Match '\.(FontSize|FontWeight|FontStyle|TextDecorations)\s*=' -Because $strName
        }
    }

    It 'makes the title of each connection box bold and 14 pt or larger, and leaves the value alone, the same way in both themes' {
        $strPath = Join-Path -Path $script:strRepoRoot -ChildPath 'Lib\SuiteCommon\SuiteCommon.psm1'
        $strText = Remove-ScriptComment -Text (Get-Content -LiteralPath $strPath -Raw)
        $strText | Should -Match 'FieldTitleFontSize\s*=\s*14'
        $objAst = [System.Management.Automation.Language.Parser]::ParseFile($strPath, [ref]$null, [ref]$null)
        $objFunction = $objAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Set-ConnectionTextTheme' }, $true)
        $objFunction | Should -Not -BeNullOrEmpty
        $strCode = Remove-ScriptComment -Text $objFunction.Extent.Text
        $strCode | Should -Match '\$title\.FontWeight\s*=\s*\[System\.Windows\.FontWeights\]::Bold'
        $strCode | Should -Not -Match '\$box\.(FontSize|FontWeight)\s*='
    }

    It 'uses no SemiBold or other weight than Bold for a title or label in the XAML of <_.Source>' -ForEach $script:arrOwnXamlDocD {
        $_.Text | Should -Not -Match 'FontWeight(=|" Value=)"(SemiBold|Light|Medium|Normal|Regular)"'
    }

    It 'sets every font weight in the script and in the module to Bold' -ForEach $script:arrAppPsFileD {
        @(Get-NonBoldWeight -Path $Path) | Should -BeNullOrEmpty
    }

    It 'flags a font weight that is not Bold' {
        $strTemp = Write-TempScript "`$a.FontWeight = [System.Windows.FontWeights]::SemiBold`n`$b.FontWeight = [System.Windows.FontWeights]::Bold`n"
        try { @(Get-NonBoldWeight -Path $strTemp).Count | Should -Be 1 }
        finally { Remove-Item -LiteralPath $strTemp -Force -ErrorAction SilentlyContinue }
    }

    It 'sets Bold on every heading of 14 pt or more in <_.Source>' -ForEach $script:arrOwnXamlDocD {
        [xml]$xml = $_.Text
        $arrBad = foreach ($objText in @($xml.SelectNodes("//*[local-name()='TextBlock'][@FontSize]"))) {
            if ([double]$objText.GetAttribute('FontSize') -ge 14 -and $objText.GetAttribute('FontWeight') -ne 'Bold') { '{0} {1}' -f $objText.GetAttribute('Name', $script:strXamlNamespace), $objText.GetAttribute('Text') }
        }
        @($arrBad) | Should -BeNullOrEmpty
    }

    It 'uses no theme trigger on a font property in <_.Source>' -ForEach $script:arrXamlDocD {
        # A trigger on the selected tab or on the mouse is not a theme trigger. A trigger is a theme trigger when its own condition names the theme.
        [xml]$xml = $_.Text
        $arrBad = foreach ($objSetter in @($xml.SelectNodes("//*[local-name()='Setter']"))) {
            if ($script:arrThemeProperty -contains (Get-PropertyLeaf $objSetter.GetAttribute('Property'))) {
                $objParent = $objSetter.ParentNode
                if ($objParent.LocalName -match 'Trigger') {
                    $strCondition = '{0} {1} {2}' -f $objParent.GetAttribute('Property'), $objParent.GetAttribute('Binding'), $objParent.GetAttribute('Value')
                    if ($strCondition -match '(?i)theme|dark|light|IsDark') { $objParent.OuterXml.Substring(0, [Math]::Min(80, $objParent.OuterXml.Length)) }
                }
            }
        }
        @($arrBad) | Should -BeNullOrEmpty
    }

    It 'sets the title of a site code or SMS Provider box to bold 14 pt or more, and the value to normal weight and a size below 14 pt, in <_.Source>' -ForEach $script:arrOwnXamlDocD {
        # The main window shows the site code and the SMS Provider as a title and a value TextBlock (the status pair).
        [xml]$xml = $_.Text
        foreach ($strName in 'txtSiteCode', 'txtSmsProvider', 'txtProvider', 'txtSiteServer') {
            $objElement = $xml.SelectSingleNode(("//*[@*[local-name()='Name']='{0}']" -f $strName))
            if (-not $objElement) { continue }
            $objTitle = $objElement.PreviousSibling
            while ($objTitle -and $objTitle.NodeType -ne 'Element') { $objTitle = $objTitle.PreviousSibling }
            $objTitle | Should -Not -BeNullOrEmpty -Because ('{0} has a title element before it' -f $strName)
            $objTitle.LocalName | Should -BeIn @('TextBlock', 'Label') -Because $strName
            [double]$objTitle.GetAttribute('FontSize') | Should -BeGreaterOrEqual 14 -Because ('the title of {0}' -f $strName)
            $objTitle.GetAttribute('FontWeight') | Should -Be 'Bold' -Because ('the title of {0}' -f $strName)
            $objElement.GetAttribute('FontWeight') | Should -Not -Be 'Bold' -Because ('the value of {0}' -f $strName)
            if ($objElement.GetAttribute('FontSize')) { [double]$objElement.GetAttribute('FontSize') | Should -BeLessThan 14 -Because ('the value of {0}' -f $strName) }
        }
    }

    It 'finds both connection value boxes in the main window, each with a title before it' {
        $objMain = @($script:arrXamlDoc | Where-Object { $_.Source -eq 'MainWindow.xaml' })[0]
        [xml]$xml = $objMain.Text
        foreach ($strName in 'txtSiteCode', 'txtSmsProvider') {
            $objElement = $xml.SelectSingleNode(("//*[@*[local-name()='Name']='{0}']" -f $strName))
            $objElement | Should -Not -BeNullOrEmpty -Because $strName
            $objElement.PreviousSibling | Should -Not -BeNullOrEmpty -Because $strName
        }
    }

    It 'builds the Site Code and SMS Provider titles of the Options dialog bold at 14 pt, and sets no font on their boxes' {
        @(Get-FieldTitleViolation -Path $script:strOptionsPath) | Should -BeNullOrEmpty
        $strText = Get-Content -LiteralPath $script:strOptionsPath -Raw
        foreach ($strTitle in 'Site Code', 'SMS Provider') { $strText | Should -Match ("New-PasOptionsText '{0}' 14 -Bold" -f $strTitle) }
        $strText | Should -Not -Match '\$txt(Site|Provider)\.(FontSize|FontWeight)\s*='
    }

    It 'flags a connection title that is not bold 14 pt' {
        $strTemp = Write-TempScript "[void]`$p.Children.Add((New-PasOptionsText 'Site Code' 12 -Bold))`n[void]`$p.Children.Add((New-PasOptionsText 'SMS Provider' 14))`n[void]`$p.Children.Add((New-PasOptionsText 'Site Code' 14 -Bold))`n[void]`$p.Children.Add((New-PasOptionsText 'Other' 11))`n"
        try { @(Get-FieldTitleViolation -Path $strTemp).Count | Should -Be 2 }
        finally { Remove-Item -LiteralPath $strTemp -Force -ErrorAction SilentlyContinue }
    }

    It 'knows every connection box name of SuiteCommon' {
        $strText = Get-Content -LiteralPath (Join-Path -Path $script:strRepoRoot -ChildPath 'Lib\SuiteCommon\SuiteCommon.psm1') -Raw
        foreach ($strName in 'txtSiteCode', 'txtSmsProvider', 'txtProvider', 'txtSiteServer') { $strText | Should -Match $strName }
    }
}

Describe 'No banned word in the UI text and the documents (c)' {
    It 'finds the banned word <Word>' -ForEach @(@{ Word = 'simply' }, @{ Word = 'Helps you' }, @{ Word = 'streamlines' }, @{ Word = 'just' }, @{ Word = 'quickly' }) {
        $Word | Should -Match $script:strBannedPattern
    }

    It 'has no banned word in the XAML text of <_.Source>' -ForEach $script:arrXamlDocD {
        $arrBad = @(Get-XamlUiText -Text $_.Text | Where-Object { $_ -match $script:strBannedPattern })
        $arrBad | Should -BeNullOrEmpty
    }

    It 'has no banned word in the strings of <Name>' -ForEach $script:arrPsFileD {
        $arrBad = @(Get-ScriptString -Path $Path | Where-Object { $_ -match $script:strBannedPattern })
        $arrBad | Should -BeNullOrEmpty
    }

    It 'has no banned word in the README or the user guide' {
        $arrFile = @(Get-Item -LiteralPath (Join-Path -Path $script:strRepoRoot -ChildPath 'README.md')) + @(Get-ChildItem -LiteralPath (Join-Path -Path $script:strRepoRoot -ChildPath 'docs') -Filter '*.md' -File -Recurse)
        $arrFile.Count | Should -BeGreaterThan 10
        $arrBad = foreach ($objFile in $arrFile) {
            $intLine = 0
            foreach ($strLine in (Get-Content -LiteralPath $objFile.FullName)) {
                $intLine++
                if ($strLine -match $script:strBannedPattern) { '{0}:{1}: {2}' -f $objFile.Name, $intLine, $Matches[0] }
            }
        }
        @($arrBad) | Should -BeNullOrEmpty
    }

    It 'writes each tooltip as one short sentence in <_.Source>' -ForEach $script:arrOwnXamlDocD {
        [xml]$xml = $_.Text
        $arrBad = foreach ($objElement in @($xml.SelectNodes('//*[@ToolTip]'))) {
            $strTip = $objElement.GetAttribute('ToolTip')
            if ($strTip -match '^\{') { continue }
            if ($strTip -cnotmatch '^[A-Z0-9].*\.$' -or $strTip -match '[.!?]\s+\S' -or $strTip.Length -gt 110) { $strTip }
        }
        @($arrBad) | Should -BeNullOrEmpty
    }

    It 'finds the tooltips of the main window' {
        $objMain = @($script:arrXamlDoc | Where-Object { $_.Source -eq 'MainWindow.xaml' })[0]
        [xml]$xml = $objMain.Text
        @($xml.SelectNodes('//*[@ToolTip]')).Count | Should -BeGreaterThan 6
    }

    It 'writes ConfigMgr and never MECM in the UI text and the documents' {
        $arrFile = @(Get-Item -LiteralPath (Join-Path -Path $script:strRepoRoot -ChildPath 'README.md')) + @(Get-ChildItem -LiteralPath (Join-Path -Path $script:strRepoRoot -ChildPath 'docs') -Filter '*.md' -File -Recurse)
        $arrBad = foreach ($objFile in $arrFile) { if ((Get-Content -LiteralPath $objFile.FullName -Raw) -cmatch '\bMECM\b') { $objFile.Name } }
        @($arrBad) | Should -BeNullOrEmpty
        $arrText = foreach ($objDoc in $script:arrOwnXamlDoc) { Get-XamlUiText -Text $objDoc.Text }
        @($arrText | Where-Object { $_ -cmatch '\bMECM\b' }) | Should -BeNullOrEmpty
    }
}

Describe 'Every button takes the shared themed style (d)' {
    It 'has no unthemed button and no literal button color in <_.Source>' -ForEach $script:arrOwnXamlDocD {
        $arrBad = @(Get-ButtonThemeViolation -Text $_.Text -Source $_.Source)
        $arrBad | Should -BeNullOrEmpty
    }

    # The dialogs of SuiteCommon are vendored code. They are fixed in the suite repository (app-packager-suite), not here.
    # The test is skipped on purpose and shows in the result as Skipped with this reason.
    It 'SKIPPED until the suite repository fixes its dialogs: has no unthemed button in <_.Source>' -Skip -ForEach @($script:arrXamlDocD | Where-Object { $_.Source -match 'SuiteCommon' }) {
        $arrBad = @(Get-ButtonThemeViolation -Text $_.Text -Source $_.Source)
        $arrBad | Should -BeNullOrEmpty
    }

    It 'finds the buttons of the documents' {
        $intCount = 0
        foreach ($objDoc in $script:arrOwnXamlDoc) {
            [xml]$xml = $objDoc.Text
            $intCount += @($xml.SelectNodes("//*[local-name()='Button']")).Count
        }
        $intCount | Should -BeGreaterThan 15
    }

    It 'flags a button that has no style, a literal color and a style that is not shared' {
        @(Get-ButtonThemeViolation -Text "<Grid $script:strNamespace><Button x:Name=`"a`"/></Grid>" -Source 's').Count | Should -Be 1
        @(Get-ButtonThemeViolation -Text "<Grid $script:strNamespace><Grid.Resources>$script:strThemedStyle<Style x:Key=`"S`" TargetType=`"Button`" BasedOn=`"{StaticResource ThemedButtonStyle}`"/></Grid.Resources><Button Style=`"{StaticResource S}`" Background=`"#1E1E1E`"/></Grid>" -Source 's').Count | Should -Be 1
        @(Get-ButtonThemeViolation -Text "<Grid $script:strNamespace><Grid.Resources>$script:strThemedStyle<Style x:Key=`"S`" TargetType=`"Button`" BasedOn=`"{StaticResource MahApps.Styles.Button.Square.Accent}`"/></Grid.Resources><Button Style=`"{StaticResource S}`"/></Grid>" -Source 's').Count | Should -Be 2
        @(Get-ButtonThemeViolation -Text "<Grid $script:strNamespace><Grid.Resources>$script:strThemedStyle<Style x:Key=`"S`" TargetType=`"Button`" BasedOn=`"{StaticResource ThemedButtonStyle}`"><Setter Property=`"Foreground`" Value=`"White`"/></Style></Grid.Resources><Button Style=`"{StaticResource S}`"/></Grid>" -Source 's').Count | Should -Be 1
        @(Get-ButtonThemeViolation -Text "<Grid $script:strNamespace><Grid.Resources>$script:strThemedStyle<Style x:Key=`"S`" TargetType=`"Button`" BasedOn=`"{StaticResource ThemedButtonStyle}`"><Setter Property=`"Foreground`" Value=`"{DynamicResource MahApps.Brushes.ThemeForeground}`"/></Style></Grid.Resources><Button Style=`"{StaticResource S}`"/></Grid>" -Source 's').Count | Should -Be 0
    }

    It 'flags a named color and a color in a style or template of another control' {
        foreach ($strName in 'Orange', 'Silver', 'WhiteSmoke') {
            $strStyle = '<Style x:Key="T" TargetType="TextBlock"><Setter Property="Foreground" Value="' + $strName + '"/></Style>'
            @(Get-ButtonThemeViolation -Text "<Grid $script:strNamespace><Grid.Resources>$script:strThemedStyle$strStyle</Grid.Resources></Grid>" -Source 's').Count | Should -Be 1 -Because $strName
        }
        $strTemplate = '<ControlTemplate TargetType="ListBoxItem"><Border Background="Silver"/></ControlTemplate>'
        @(Get-ButtonThemeViolation -Text "<Grid $script:strNamespace><Grid.Resources>$script:strThemedStyle$strTemplate</Grid.Resources></Grid>" -Source 's').Count | Should -Be 1
        $strOk = '<Style x:Key="T" TargetType="TextBlock"><Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.Gray1}"/></Style>'
        @(Get-ButtonThemeViolation -Text "<Grid $script:strNamespace><Grid.Resources>$script:strThemedStyle$strOk</Grid.Resources></Grid>" -Source 's').Count | Should -Be 0
    }

    It 'flags a literal color in a qualified brush property and in a nested brush of a button template' {
        $strStyle = '<Style x:Key="S" TargetType="Button" BasedOn="{StaticResource ThemedButtonStyle}"><Setter Property="Controls:ControlsHelper.MouseOverBorderBrush" Value="#3A3A3A"/></Style>'
        @(Get-ButtonThemeViolation -Text "<Grid $script:strNamespace><Grid.Resources>$script:strThemedStyle$strStyle</Grid.Resources><Button Style=`"{StaticResource S}`"/></Grid>" -Source 's').Count | Should -Be 1
        $strNested = '<ControlTemplate TargetType="Button"><Border><Border.Background><SolidColorBrush Color="#3A3A3A"/></Border.Background></Border></ControlTemplate>'
        @(Get-ButtonThemeViolation -Text "<Grid $script:strNamespace><Grid.Resources>$script:strThemedStyle$strNested</Grid.Resources></Grid>" -Source 's').Count | Should -Be 1
        $strSetter = '<Style x:Key="S" TargetType="Button" BasedOn="{StaticResource ThemedButtonStyle}"><Setter Property="Background"><Setter.Value><SolidColorBrush Color="#3A3A3A"/></Setter.Value></Setter></Style>'
        @(Get-ButtonThemeViolation -Text "<Grid $script:strNamespace><Grid.Resources>$script:strThemedStyle$strSetter</Grid.Resources><Button Style=`"{StaticResource S}`"/></Grid>" -Source 's').Count | Should -Be 1
    }

    It 'uses no Opacity in a button style or a button template of <_.Source>' -ForEach $script:arrOwnXamlDocD {
        @(Get-ButtonOpacityViolation -Text $_.Text -Source $_.Source) | Should -BeNullOrEmpty
    }

    It 'flags an Opacity setter in a button trigger and an Opacity attribute in a button template' {
        $strTrigger = '<ControlTemplate TargetType="Button"><Border Name="Bd"/><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.8"/></Trigger></ControlTemplate.Triggers></ControlTemplate>'
        @(Get-ButtonOpacityViolation -Text "<Grid $script:strNamespace><Grid.Resources>$strTrigger</Grid.Resources></Grid>" -Source 's').Count | Should -Be 1
        $strAttribute = '<ControlTemplate TargetType="Button"><Border Name="Bd" Opacity="0.5"/></ControlTemplate>'
        @(Get-ButtonOpacityViolation -Text "<Grid $script:strNamespace><Grid.Resources>$strAttribute</Grid.Resources></Grid>" -Source 's').Count | Should -Be 1
        $strStyle = '<Style x:Key="S" TargetType="Button"><Style.Triggers><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger></Style.Triggers></Style>'
        @(Get-ButtonOpacityViolation -Text "<Grid $script:strNamespace><Grid.Resources>$strStyle</Grid.Resources></Grid>" -Source 's').Count | Should -Be 1
        $strOk = '<Style x:Key="S" TargetType="Button"><Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.ThemeForeground}"/></Style><Style TargetType="Border"><Setter Property="Opacity" Value="0.5"/></Style>'
        @(Get-ButtonOpacityViolation -Text "<Grid $script:strNamespace><Grid.Resources>$strOk</Grid.Resources></Grid>" -Source 's').Count | Should -Be 0
    }

    It 'shows hover and focus as the theme foreground border and pressed as swapped theme colors in <_.Source>' -ForEach $script:arrOwnXamlDocD {
        @(Get-ButtonStateViolation -Text $_.Text -Source $_.Source) | Should -BeNullOrEmpty
    }

    It 'flags a button template without the hover, focus or pressed rule' {
        $strHover = '<Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource MahApps.Brushes.ThemeForeground}"/></Trigger>'
        $strFocus = '<Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource MahApps.Brushes.ThemeForeground}"/></Trigger>'
        $strPressed = '<Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Background" Value="{DynamicResource MahApps.Brushes.ThemeForeground}"/><Setter TargetName="Cp" Property="TextElement.Foreground" Value="{DynamicResource MahApps.Brushes.ThemeBackground}"/></Trigger>'
        $strOpen = "<Grid $script:strNamespace><Grid.Resources><ControlTemplate x:Key=`"ThemedButtonTemplate`" TargetType=`"Button`"><Border Name=`"Bd`"/><ControlTemplate.Triggers>"
        $strClose = '</ControlTemplate.Triggers></ControlTemplate></Grid.Resources></Grid>'
        @(Get-ButtonStateViolation -Text ($strOpen + $strHover + $strFocus + $strPressed + $strClose) -Source 's').Count | Should -Be 0
        @(Get-ButtonStateViolation -Text ($strOpen + $strFocus + $strPressed + $strClose) -Source 's').Count | Should -Be 1
        @(Get-ButtonStateViolation -Text ($strOpen + $strHover + $strPressed + $strClose) -Source 's').Count | Should -Be 1
        @(Get-ButtonStateViolation -Text ($strOpen + $strHover + $strFocus + $strClose) -Source 's').Count | Should -Be 2
        @(Get-ButtonStateViolation -Text "<Grid $script:strNamespace/>" -Source 's').Count | Should -Be 1
    }

    It 'has one gray secondary style and one primary style in the dialog, documented, of one size, and no other button style that sets a Background in <_.Source>' -ForEach $script:arrOwnXamlDocD {
        @(Get-DialogButtonViolation -Text $_.Text -Source $_.Source) | Should -BeNullOrEmpty
    }

    It 'defines the two dialog button styles once in each of the three dialog documents, with the same text, and in no other document' {
        $arrDoc = @($script:arrOwnXamlDoc | Where-Object { $_.Text -match 'x:Key="DialogButton"' })
        $arrDoc.Count | Should -Be 3
        @($arrDoc | Where-Object { $_.Source -notlike '*Dialog.ps1 here-string*' }) | Should -BeNullOrEmpty
        foreach ($strKey in 'DialogButton', 'DialogAccentButton') {
            $arrText = foreach ($objDoc in $arrDoc) {
                [xml]$xml = $objDoc.Text
                $arrNode = @($xml.SelectNodes("//*[local-name()='Style'][@*[local-name()='Key']='$strKey']"))
                $arrNode.Count | Should -Be 1 -Because ('{0} in {1}' -f $strKey, $objDoc.Source)
                ($arrNode[0].OuterXml -replace '\s+', ' ')
            }
            @($arrText | Sort-Object -Unique).Count | Should -Be 1 -Because ('{0} has one text in every dialog' -f $strKey)
        }
        foreach ($objDoc in $arrDoc | Where-Object { $_.Text -match 'IsCancel="True"' }) {
            [xml]$xml = $objDoc.Text
            $objCancel = $xml.SelectSingleNode("//*[local-name()='Button'][@IsCancel='True']")
            $objCancel.GetAttribute('Style') | Should -Be '{StaticResource DialogButton}' -Because $objDoc.Source
        }
        @($arrDoc | Where-Object { $_.Text -match 'IsCancel="True"' }).Count | Should -Be 2
    }

    It 'flags a dialog button that sets its own size and a dialog button that the script sizes in code' {
        $strBase = '<Style x:Key="ThemedButtonStyle" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square}"/>'
        $strSecondary = '<Style x:Key="DialogButton" TargetType="Button" BasedOn="{StaticResource ThemedButtonStyle}"><Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Gray10}"/><Setter Property="MinWidth" Value="140"/><Setter Property="Height" Value="32"/></Style>'
        $strPrimary = '<Style x:Key="DialogAccentButton" TargetType="Button" BasedOn="{StaticResource ThemedButtonStyle}"><Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Highlight}"/><Setter Property="MinWidth" Value="140"/><Setter Property="Height" Value="32"/></Style>'
        $strOpen = "<Grid $script:strNamespace><Grid.Resources>" + $strBase + '<!-- The one secondary dialog style. -->' + $strSecondary + $strPrimary + '</Grid.Resources>'
        @(Get-DialogButtonViolation -Text ($strOpen + '<Button Style="{StaticResource DialogButton}"/></Grid>') -Source 's').Count | Should -Be 0
        foreach ($strAttribute in 'Width="200"', 'MinWidth="90"', 'Height="28"', 'Padding="12,0"') {
            @(Get-DialogButtonViolation -Text ($strOpen + '<Button Style="{StaticResource DialogButton}" ' + $strAttribute + '/></Grid>') -Source 's').Count | Should -Be 1 -Because $strAttribute
        }
        $strTemp = Write-TempScript "function A {`n  `$b = New-Object System.Windows.Controls.Button`n  `$b.SetResourceReference([System.Windows.Controls.Button]::StyleProperty, 'DialogButton')`n  `$b.Padding = [System.Windows.Thickness]::new(12,0,12,0)`n  `$b.MinWidth = 140`n}`n"
        try { @(Get-CodeButtonViolation -Path $strTemp -AllowedKey @('DialogButton')).Count | Should -Be 2 }
        finally { Remove-Item -LiteralPath $strTemp -Force -ErrorAction SilentlyContinue }
    }

    It 'flags a second secondary style, a size that differs, a missing comment and a literal color in the dialog styles' {
        $strBase = '<Style x:Key="ThemedButtonStyle" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square}"/>'
        $strSecondary = '<Style x:Key="DialogButton" TargetType="Button" BasedOn="{StaticResource ThemedButtonStyle}"><Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Gray10}"/><Setter Property="MinWidth" Value="90"/><Setter Property="Height" Value="32"/></Style>'
        $strPrimary = '<Style x:Key="DialogAccentButton" TargetType="Button" BasedOn="{StaticResource ThemedButtonStyle}"><Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Highlight}"/><Setter Property="MinWidth" Value="90"/><Setter Property="Height" Value="32"/></Style>'
        $strComment = '<!-- The one secondary dialog style. -->'
        $strOpen = "<Grid $script:strNamespace><Grid.Resources>"
        $strClose = '</Grid.Resources><Button x:Name="btnCancel" IsCancel="True" Style="{StaticResource DialogButton}"/></Grid>'
        @(Get-DialogButtonViolation -Text ($strOpen + $strBase + $strComment + $strSecondary + $strPrimary + $strClose) -Source 's').Count | Should -Be 0
        $strCopy = '<Style x:Key="BrowseButton" TargetType="Button" BasedOn="{StaticResource ThemedButtonStyle}"><Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Gray10}"/></Style>'
        @(Get-DialogButtonViolation -Text ($strOpen + $strBase + $strComment + $strSecondary + $strPrimary + $strCopy + $strClose) -Source 's').Count | Should -Be 1
        @(Get-DialogButtonViolation -Text ($strOpen + $strBase + $strComment + $strSecondary.Replace('Value="32"', 'Value="28"') + $strPrimary + $strClose) -Source 's').Count | Should -Be 1
        @(Get-DialogButtonViolation -Text ($strOpen + $strBase + $strComment + $strSecondary.Replace('Value="90"', 'Value="80"') + $strPrimary + $strClose) -Source 's').Count | Should -Be 1
        @(Get-DialogButtonViolation -Text ($strOpen + $strBase + $strSecondary + $strPrimary + $strClose) -Source 's').Count | Should -Be 1
        @(Get-DialogButtonViolation -Text ($strOpen + $strBase + $strComment + $strSecondary.Replace('{DynamicResource MahApps.Brushes.Gray10}', '#EEEEEE') + $strPrimary + $strClose) -Source 's').Count | Should -Be 1
        @(Get-DialogButtonViolation -Text ($strOpen + $strBase + $strComment + $strSecondary + $strPrimary + $strClose.Replace('DialogButton', 'ThemedButtonStyle')) -Source 's').Count | Should -Be 1
    }

    It 'gives every button that the script builds in code one of the themed styles, and no literal color' -ForEach $script:arrAppPsFileD {
        @(Get-CodeButtonViolation -Path $Path -AllowedKey @('DialogButton', 'DialogAccentButton', 'ThemedButtonStyle')) | Should -BeNullOrEmpty
    }

    It 'defines the sidebar button styles in the main window and gives every button of the main window a style' {
        $objMain = @($script:arrOwnXamlDoc | Where-Object { $_.Source -eq 'MainWindow.xaml' })[0]
        [xml]$xml = $objMain.Text
        $arrKey = @($xml.SelectNodes("//*[local-name()='Style'][@TargetType='Button']") | ForEach-Object { $_.GetAttribute('Key', $script:strXamlNamespace) })
        $arrKey | Should -Contain 'ThemedButtonStyle'
        $arrKey | Should -Contain 'ViewButtonStyle'
        $arrKey | Should -Contain 'OptionsButtonStyle'
        @($xml.SelectNodes("//*[local-name()='Button'][not(@Style)]")).Count | Should -Be 0
    }

    It 'flags a button that the script builds without a themed style and a button with a literal color' {
        $strTemp = Write-TempScript ("function A {`n  `$b = New-Object System.Windows.Controls.Button`n  `$b.Content = 'x'`n}`nfunction B {`n  `$b = New-Object System.Windows.Controls.Button`n  `$b.SetResourceReference([System.Windows.Controls.Button]::StyleProperty, 'MahApps.Styles.Button.Square')`n}`n" +
            "function C {`n  `$b = New-Object System.Windows.Controls.Button`n  `$b.SetResourceReference([System.Windows.Controls.Button]::StyleProperty, 'DialogButton')`n  `$b.Foreground = 'White'`n  `$b.FontWeight = [System.Windows.FontWeights]::SemiBold`n}`n" +
            "function D {`n  `$b = New-Object System.Windows.Controls.Button`n  `$b.SetResourceReference([System.Windows.Controls.Button]::StyleProperty, 'DialogButton')`n  `$b.FontWeight = [System.Windows.FontWeights]::Bold`n}`n")
        try { @(Get-CodeButtonViolation -Path $strTemp -AllowedKey @('DialogButton')).Count | Should -Be 4 }
        finally { Remove-Item -LiteralPath $strTemp -Force -ErrorAction SilentlyContinue }
    }

    It 'defines the button template and the button style once in each document and no per-dialog button style besides them' {
        foreach ($objDoc in $script:arrOwnXamlDoc) {
            [xml]$xml = $objDoc.Text
            @($xml.SelectNodes("//*[local-name()='Style'][@*[local-name()='Key']='ThemedButtonStyle']")).Count | Should -Be 1 -Because $objDoc.Source
            @($xml.SelectNodes("//*[local-name()='ControlTemplate'][@*[local-name()='Key']='ThemedButtonTemplate']")).Count | Should -Be 1 -Because $objDoc.Source
            @($xml.SelectNodes("//*[local-name()='ControlTemplate'][@TargetType='Button' or @TargetType='ButtonBase']")).Count | Should -Be 1 -Because $objDoc.Source
        }
    }

    It 'uses the same button template and the same button style in every document' {
        $arrTemplate = foreach ($objDoc in $script:arrOwnXamlDoc) {
            [xml]$xml = $objDoc.Text
            $objNode = $xml.SelectSingleNode("//*[local-name()='ControlTemplate'][@*[local-name()='Key']='ThemedButtonTemplate']")
            ($objNode.InnerXml -replace '\s+', ' ')
        }
        @($arrTemplate | Sort-Object -Unique).Count | Should -Be 1
        $arrStyle = foreach ($objDoc in $script:arrOwnXamlDoc) {
            [xml]$xml = $objDoc.Text
            $objNode = $xml.SelectSingleNode("//*[local-name()='Style'][@*[local-name()='Key']='ThemedButtonStyle']")
            ($objNode.InnerXml -replace '\s+', ' ')
        }
        @($arrStyle | Sort-Object -Unique).Count | Should -Be 1
    }
}

Describe 'Titles are in Title Case (d)' {
    It 'recognizes Title Case' {
        Test-TitleCase 'Copy Summary' | Should -BeTrue
        Test-TitleCase 'Open in New Window' | Should -BeTrue
        Test-TitleCase 'Extract to Temp Folder' | Should -BeTrue
        Test-TitleCase 'Browse...' | Should -BeTrue
        Test-TitleCase 'Export JSON' | Should -BeTrue
        Test-TitleCase 'Hash This Entry (SHA-256)' | Should -BeTrue
        Test-TitleCase ([string][char]0x2190 + ' Back') | Should -BeTrue
        Test-TitleCase ([string][char]0x2190 + ' back') | Should -BeFalse
        Test-TitleCase 'Copy summary' | Should -BeFalse
        Test-TitleCase 'Open in new window' | Should -BeFalse
        Test-TitleCase 'LOG output' | Should -BeFalse
        Test-TitleCase 'enable Actions' | Should -BeFalse
    }

    It 'has Title Case for every button, header, tab, menu item, field label and window title in <_.Source>' -ForEach $script:arrOwnXamlDocD {
        $arrBad = @(Get-XamlTitle -Text $_.Text | Where-Object { -not (Test-TitleCase $_) })
        $arrBad | Should -BeNullOrEmpty
    }

    It 'finds titles to check in the main window' {
        $objMain = @($script:arrXamlDoc | Where-Object { $_.Source -eq 'MainWindow.xaml' })[0]
        @(Get-XamlTitle -Text $objMain.Text).Count | Should -BeGreaterThan 30
    }

    It 'has Title Case in the title of every message box and confirmation of the script and the dialogs' {
        $intCall = 0
        $arrBad = foreach ($strPath in (@($script:strShellPath) + @($script:arrDialogPath))) {
            $objAst = [System.Management.Automation.Language.Parser]::ParseFile($strPath, [ref]$null, [ref]$null)
            $arrCall = @($objAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in 'Show-ThemedMessage', 'Show-ConfirmDialog' }, $true))
            $intCall += $arrCall.Count
            foreach ($objCall in $arrCall) {
                $arrElement = @($objCall.CommandElements)
                for ($intIndex = 0; $intIndex -lt $arrElement.Count - 1; $intIndex++) {
                    if ($arrElement[$intIndex] -is [System.Management.Automation.Language.CommandParameterAst] -and $arrElement[$intIndex].ParameterName -eq 'Title' -and $arrElement[$intIndex + 1] -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                        $strTitle = [string]$arrElement[$intIndex + 1].Value
                        if (-not (Test-TitleCase $strTitle)) { $strTitle }
                    }
                }
            }
        }
        $intCall | Should -BeGreaterThan 6
        @($arrBad) | Should -BeNullOrEmpty
    }

    It 'has Title Case in the labels that the script sets in code' {
        $arrTarget = '$ui.heading.Text', '$ui.editorLabel.Text', '$ui.btnRun.Content', '$ui.txtThemeLabel.Text'
        $objAst = [System.Management.Automation.Language.Parser]::ParseFile($script:strShellPath, [ref]$null, [ref]$null)
        $arrAssign = @($objAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $arrTarget -contains $n.Left.Extent.Text }, $true))
        $arrAssign.Count | Should -BeGreaterOrEqual 4
        $arrBad = foreach ($objAssign in $arrAssign) {
            foreach ($objString in @($objAssign.Right.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true))) {
                if (-not (Test-TitleCase ([string]$objString.Value))) { [string]$objString.Value }
            }
        }
        @($arrBad) | Should -BeNullOrEmpty
    }

    It 'has Title Case in the headings and page names of the Options dialog' {
        $objAst = [System.Management.Automation.Language.Parser]::ParseFile($script:strOptionsPath, [ref]$null, [ref]$null)
        $arrHeading = @($objAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'New-PasOptionsText' -and @($n.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'Bold' }).Count -gt 0 }, $true))
        $arrHeading.Count | Should -BeGreaterOrEqual 5
        $arrPage = @($objAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true) | ForEach-Object { foreach ($objPair in $_.KeyValuePairs) { if ([string]$objPair.Item1.Extent.Text -eq 'Name') { $objPair.Item2.Extent.Text.Trim("'") } } })
        $arrPage.Count | Should -Be 3
        $arrBad = @($arrPage | Where-Object { -not (Test-TitleCase $_) })
        foreach ($objCall in $arrHeading) { $strTitle = ([string]@($objCall.CommandElements)[1].Extent.Text).Trim("'"); if (-not (Test-TitleCase $strTitle)) { $arrBad += $strTitle } }
        @($arrBad) | Should -BeNullOrEmpty
    }
}

Describe 'No raw exception text in the window (e)' {
    It 'flags raw exception text that leaves the catch block (the check itself)' {
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { $ui.status.Text = $_.Exception.Message }').Count | Should -Be 1
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { $row.Detail = $_.Exception.Message }').Count | Should -Be 1
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { $State.ErrorMsg = $_.Exception.Message }').Count | Should -Be 1
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { return @{ Success = $false; Error = $_.ToString() } }').Count | Should -Be 1
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { Send-Device $job "Error" $_.Exception.Message }').Count | Should -Be 1
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { $msg = $_.Exception.Message; Show-ThemedMessage -Message $msg }').Count | Should -Be 1
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { throw $_ }').Count | Should -Be 1
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { $notice.Text = "x: $_" }').Count | Should -Be 1
    }

    It 'allows the log file, the helpers, a condition and a deliberate swallow (the check itself)' {
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { Write-PasLog ("x {0}" -f $_.Exception.Message); $ui.status.Text = "Failed." }').Count | Should -Be 0
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { $ui.status.Text = Get-PasUserErrorText -ErrorRecord $_ -Fallback "Failed." -LogDetail }').Count | Should -Be 0
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { Show-PasError $_ }').Count | Should -Be 0
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { if ($_.Exception.Data["StatusCode"] -ne 404) { 1 } }').Count | Should -Be 0
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { $r = $_.Exception.Response }').Count | Should -Be 0
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { $f = [InvalidOperationException]::new("x", $_.Exception) }').Count | Should -Be 0
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { [IO.File]::AppendAllText($log, $_.Exception.ToString()) }').Count | Should -Be 0
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { $null = $_ }').Count | Should -Be 0
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { $x = @(1, 2) | ForEach-Object { $_ + 1 } }').Count | Should -Be 0
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { throw }').Count | Should -Be 0
    }

    It 'scans a nested catch block on its own (the check itself)' {
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { try { 2 } catch { $ui.status.Text = $_.Exception.Message } }').Count | Should -Be 1
        @(Get-RawExceptionToUi -ScriptText 'try { 1 } catch { try { 2 } catch { $null = $_ }; Write-PasLog $_ }').Count | Should -Be 0
    }

    It 'finds the catch blocks of <Name> (the scan is not empty)' -ForEach @(@{ Name = 'start-pivotsandscripts.ps1'; Min = 25 }, @{ Name = 'Module\PivotsAndScripts.psm1'; Min = 8 }, @{ Name = 'Module\Execute.ps1'; Min = 4 }, @{ Name = 'Module\ScriptsDialog.ps1'; Min = 5 }) {
        (Get-CatchCount -Path (Join-Path -Path $script:strRepoRoot -ChildPath $Name)) | Should -BeGreaterOrEqual $Min
    }

    It 'sends no raw exception text out of a catch block of <Name>' -ForEach $script:arrAppPsFileD {
        @(Get-RawExceptionToUi -Path $Path) | Should -BeNullOrEmpty
    }

    It 'puts no exception text in a property that the window or the grid shows, in <Name>' -ForEach $script:arrAppPsFileD {
        @(Get-ExceptionPropertyAssignment -Path $Path) | Should -BeNullOrEmpty
    }

    It 'flags exception text in a Note, a Detail, an Error or a Text property and in a hashtable entry' {
        $strTemp = Write-TempScript "`$r.Note = 'Could not read: ' + `$_.Exception.Message`n`$r.Detail = `$_`n`$r.ErrorMessage = `$err`n`$x = @{ Error = 'x ' + `$_.Exception.Message }`n`$r.Note = 'The log file has the details.'`n`$State.ErrorMsg = `$_.Exception.Message`n`$ui.status.Text = Get-PasUserErrorText -ErrorRecord `$_ -Fallback 'x'`n`$ui.n.Text = @(`$a | Where-Object { `$_.Active }).Count`n"
        try { @(Get-ExceptionPropertyAssignment -Path $strTemp).Count | Should -Be 4 }
        finally { Remove-Item -LiteralPath $strTemp -Force -ErrorAction SilentlyContinue }
    }

    It 'defines the log and the error helpers in the module and uses them in the shell and the worker' {
        $strModule = Get-Content -LiteralPath $script:strModulePath -Raw
        foreach ($strName in 'Write-PasLog', 'Set-PasLogPath', 'Get-PasUserErrorText') { $strModule | Should -Match ('function ' + $strName) }
        (Get-Content -LiteralPath $script:strShellPath -Raw) | Should -Match 'Get-PasUserErrorText'
        $strWorker = Get-Content -LiteralPath (Join-Path -Path $script:strRepoRoot -ChildPath 'Module\Execute.ps1') -Raw
        $strWorker | Should -Match 'Get-PasUserErrorText'
        $strWorker | Should -Match 'Set-PasLogPath'
    }
}

Describe 'Every test file requires Pester 5.1.0 (g)' {
    It 'finds the test files' {
        @(Get-RepoFile -Filter '*.Tests.ps1').Count | Should -BeGreaterThan 14
        @(Get-RepoFile -Filter '*.Tests.ps1' | Where-Object { $_.Relative -like 'Tests\*' }).Count | Should -BeGreaterThan 14
    }

    It 'has #Requires for Pester ModuleVersion 5.1.0 in every test file' {
        $arrBad = foreach ($objItem in @(Get-RepoFile -Filter '*.Tests.ps1')) { Get-PesterRequiresViolation -Path $objItem.File.FullName }
        @($arrBad) | Should -BeNullOrEmpty
    }

    It 'flags a test file without the requirement, with an old version or with the module name only' {
        foreach ($hashCase in @(@{ Text = "Describe 'x' {}"; Count = 1 }, @{ Text = "#Requires -Modules Pester`nDescribe 'x' {}"; Count = 1 }, @{ Text = "#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }`nDescribe 'x' {}"; Count = 1 }, @{ Text = "#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }`nDescribe 'x' {}"; Count = 0 })) {
            $strTemp = Write-TempScript $hashCase.Text
            try { @(Get-PesterRequiresViolation -Path $strTemp).Count | Should -Be $hashCase.Count -Because $hashCase.Text }
            finally { Remove-Item -LiteralPath $strTemp -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Path filters of the repository scripts work on the repository root (f)' {
    It 'has no FullName comparison with a path pattern in <_>' -ForEach @(
        'Invoke-Checks.ps1', 'Tests\WindowGuard.Tests.ps1', 'Tests\Theme.Guard.Tests.ps1', 'Tests\ThemeGuardHelpers.ps1', 'Tests\GuideCapture.Tests.ps1',
        'Tests\Documentation.Tests.ps1', 'Tests\TestHelpers.ps1', 'Tests\WindowConfig.ps1', 'tools\guide-capture\Invoke-GuideCapture.ps1', 'tools\guide-capture\steps-guide.ps1'
    ) {
        $strPath = Join-Path -Path $script:strRepoRoot -ChildPath $_
        Test-Path -LiteralPath $strPath | Should -BeTrue -Because $_
        @(Get-AbsolutePathFilter -Path $strPath) | Should -BeNullOrEmpty
    }

    It 'flags a FullName comparison with a path pattern' {
        $strTemp = Write-TempScript "Get-ChildItem | Where-Object { `$_.FullName -notlike '*\.git\*' }`nGet-ChildItem | Where-Object { `$_.FullName -match '\\Tests\\' }`nGet-ChildItem | Where-Object { `$_.FullName -ne `$x -and `$_.Name -like '*.ps1' }`n"
        try { @(Get-AbsolutePathFilter -Path $strTemp).Count | Should -Be 2 }
        finally { Remove-Item -LiteralPath $strTemp -Force -ErrorAction SilentlyContinue }
    }

    It 'walks no .claude folder in Invoke-Checks.ps1 and in the window guard test' {
        foreach ($strName in 'Invoke-Checks.ps1', 'Tests\WindowGuard.Tests.ps1') {
            $strPath = Join-Path -Path $script:strRepoRoot -ChildPath $strName
            $objAst = [System.Management.Automation.Language.Parser]::ParseFile($strPath, [ref]$null, [ref]$null)
            $arrString = @($objAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -eq '.claude' }, $true))
            $arrString.Count | Should -BeGreaterThan 0 -Because $strName
        }
    }

    It 'skips the .claude folder in the repository file walk of the guard helpers' {
        $arrRoot = @(Get-RepoFile -Filter '*.ps1' | ForEach-Object { $_.Top } | Sort-Object -Unique)
        $arrRoot | Should -Not -Contain '.claude'
        $arrRoot | Should -Not -Contain '.git'
        @(Get-RepoFile -Filter '*.xaml').Count | Should -BeGreaterThan 0
    }
}
