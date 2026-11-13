$script:appVersion = ''
$versionLine = Select-String -LiteralPath (Join-Path (Split-Path $PSScriptRoot) 'start-pivotsandscripts.ps1') -Pattern '^\s*Version\s*:\s*(\S+)' | Select-Object -First 1
if ($versionLine) { $script:appVersion = $versionLine.Matches[0].Groups[1].Value }

function New-PasOptionsText {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification='Builds a TextBlock in memory only.')]
    param([string]$Text,[double]$Size=12,[switch]$Bold,[string]$Margin='0,0,0,8',[switch]$Muted,[string]$Weight='Normal')
    $block = [Windows.Controls.TextBlock]::new()
    $block.Text = $Text; $block.FontSize = $Size; $block.Margin = $Margin; $block.TextWrapping = 'Wrap'
    if ($Bold) { $block.FontWeight = [Windows.FontWeights]::Bold } else { $block.FontWeight = $Weight }
    if ($Muted) { $block.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'MahApps.Brushes.Gray1') }
    $block
}
function Show-PasOptionsDialog {
    $xaml = @'
<Controls:MetroWindow xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro" Title="Options" Width="760" Height="500" MinWidth="640" MinHeight="420" WindowStartupLocation="CenterOwner" TitleCharacterCasing="Normal" ShowIconOnTitleBar="False" GlowBrush="{DynamicResource MahApps.Brushes.Accent}" BorderThickness="1">
 <Window.Resources><ResourceDictionary>
  <ResourceDictionary.MergedDictionaries>
   <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml"/>
   <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml"/>
   <ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Themes/Dark.Steel.xaml"/>
  </ResourceDictionary.MergedDictionaries>
  <!-- Contrast overrides, the same as in MainWindow.xaml. -->
  <SolidColorBrush x:Key="MahApps.Brushes.TextBox.Border" Color="#7F7F7F"/>
  <SolidColorBrush x:Key="MahApps.Brushes.WindowTitle.NonActive" Color="#595959"/>
  <!-- The one button template and the one button style, the same as in MainWindow.xaml. No color literal: the colors come from the MahApps theme resources. -->
  <ControlTemplate x:Key="ThemedButtonTemplate" TargetType="Button">
   <Border Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" SnapsToDevicePixels="True">
    <ContentPresenter Name="Cp" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}" Margin="{TemplateBinding Padding}" RecognizesAccessKey="True" SnapsToDevicePixels="True"/>
   </Border>
   <ControlTemplate.Triggers>
    <Trigger Property="IsMouseOver" Value="True">
     <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource MahApps.Brushes.ThemeForeground}"/>
    </Trigger>
    <Trigger Property="IsKeyboardFocused" Value="True">
     <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource MahApps.Brushes.ThemeForeground}"/>
    </Trigger>
    <Trigger Property="IsPressed" Value="True">
     <Setter TargetName="Bd" Property="Background" Value="{DynamicResource MahApps.Brushes.ThemeForeground}"/>
     <Setter TargetName="Cp" Property="TextElement.Foreground" Value="{DynamicResource MahApps.Brushes.ThemeBackground}"/>
    </Trigger>
   </ControlTemplate.Triggers>
  </ControlTemplate>
  <Style x:Key="ThemedButtonStyle" TargetType="Button" BasedOn="{StaticResource MahApps.Styles.Button.Square}">
   <Setter Property="Template" Value="{StaticResource ThemedButtonTemplate}"/>
   <Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.ThemeForeground}"/>
   <Setter Property="BorderThickness" Value="1"/>
   <Setter Property="Margin" Value="3"/>
   <Setter Property="Padding" Value="10,5"/>
   <Setter Property="HorizontalContentAlignment" Value="Center"/>
   <Setter Property="VerticalContentAlignment" Value="Center"/>
   <Setter Property="Controls:ControlsHelper.ContentCharacterCasing" Value="Normal"/>
   <Style.Triggers>
    <Trigger Property="IsEnabled" Value="False">
     <Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.Gray.MouseOver}"/>
     <Setter Property="BorderBrush" Value="{DynamicResource MahApps.Brushes.Gray2}"/>
    </Trigger>
   </Style.Triggers>
  </Style>
  <!-- The one secondary dialog style: a gray fill, the theme text color and a visible border. Cancel and every other dialog action that is not the
       primary one use it, at one size (MinWidth fits the longest label). The primary dialog style is DialogAccentButton. No other dialog button style sets a Background.
       Every dialog of the app has the same two styles. -->
  <Style x:Key="DialogButton" TargetType="Button" BasedOn="{StaticResource ThemedButtonStyle}">
   <Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Gray10}"/>
   <Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.ThemeForeground}"/>
   <Setter Property="BorderBrush" Value="{DynamicResource MahApps.Brushes.ThemeForeground}"/>
   <Setter Property="MinWidth" Value="120"/>
   <Setter Property="Height" Value="32"/>
   <Setter Property="Margin" Value="0,0,8,0"/>
  </Style>
  <!-- The accent fill is the theme highlight: white text is 7:1 on both themes. The border is the theme foreground. The plain accent fill of the light theme is 4.49:1. -->
  <Style x:Key="DialogAccentButton" TargetType="Button" BasedOn="{StaticResource ThemedButtonStyle}">
   <Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Highlight}"/>
   <Setter Property="BorderBrush" Value="{DynamicResource MahApps.Brushes.ThemeForeground}"/>
   <Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.IdealForeground}"/>
   <Setter Property="MinWidth" Value="120"/>
   <Setter Property="Height" Value="32"/>
   <Setter Property="Margin" Value="0,0,8,0"/>
   <Style.Triggers>
    <Trigger Property="IsEnabled" Value="False">
     <Setter Property="Background" Value="{DynamicResource MahApps.Brushes.ThemeBackground}"/>
     <Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.Gray.MouseOver}"/>
     <Setter Property="BorderBrush" Value="{DynamicResource MahApps.Brushes.Gray2}"/>
    </Trigger>
   </Style.Triggers>
  </Style>
  <!-- Selected items: white text (IdealForeground) on the highlight blue, in both themes. -->
  <Style x:Key="ThemedListBoxItemStyle" TargetType="ListBoxItem" BasedOn="{StaticResource MahApps.Styles.ListBoxItem}">
   <Setter Property="Padding" Value="16,10,16,10"/>
   <Setter Property="FontSize" Value="13"/>
   <Setter Property="Controls:ItemHelper.DisabledForegroundBrush" Value="{DynamicResource MahApps.Brushes.Gray.MouseOver}"/>
   <Style.Triggers>
    <Trigger Property="IsSelected" Value="True">
     <Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Highlight}"/>
     <Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.IdealForeground}"/>
    </Trigger>
   </Style.Triggers>
  </Style>
 </ResourceDictionary></Window.Resources>
 <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="190"/><ColumnDefinition Width="1"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <ListBox x:Name="lstNav" BorderThickness="0" Padding="0,8,0,0" ItemContainerStyle="{StaticResource ThemedListBoxItemStyle}"/>
  <Border Grid.Column="1" Background="{DynamicResource MahApps.Brushes.Gray8}"/>
  <ScrollViewer Grid.Column="2" VerticalScrollBarVisibility="Auto"><ContentControl x:Name="contentArea" Margin="20,18,20,18"/></ScrollViewer>
  <Border Grid.ColumnSpan="3" Grid.Row="1" BorderBrush="{DynamicResource MahApps.Brushes.Gray8}" BorderThickness="0,1,0,0"><StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="20,12,20,12">
   <Button x:Name="btnOK" Content="OK" IsDefault="True" Style="{StaticResource DialogAccentButton}"/>
   <Button x:Name="btnCancel" Content="Cancel" IsCancel="True" Style="{StaticResource DialogButton}"/>
  </StackPanel></Border>
 </Grid>
</Controls:MetroWindow>
'@
    $dialog = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new([xml]$xaml))
    $dialog.Owner = $window
    Set-DialogTheme -Dialog $dialog -IsDark $ui.toggleTheme.IsOn
    Install-TitleBarDragFallback -Window $dialog
    $lstNav = $dialog.FindName('lstNav'); $contentArea = $dialog.FindName('contentArea')

    # The titles of the site code and the SMS Provider are bold 14 pt in both themes. The values are plain text boxes.
    $connection = [Windows.Controls.StackPanel]::new()
    [void]$connection.Children.Add((New-PasOptionsText 'Configuration Manager Connection' 18 -Weight SemiBold -Margin '0,0,0,12'))
    [void]$connection.Children.Add((New-PasOptionsText 'Site Code' 14 -Bold -Margin '0,4,0,2'))
    $txtSite = [Windows.Controls.TextBox]::new(); $txtSite.Text = $script:prefs.SiteCode; $txtSite.MaxLength = 3; $txtSite.Width = 80; $txtSite.HorizontalAlignment = 'Left'; $txtSite.Height = 28; [Windows.Automation.AutomationProperties]::SetAutomationId($txtSite, 'txtSiteCode')
    [void]$connection.Children.Add($txtSite)
    [void]$connection.Children.Add((New-PasOptionsText 'SMS Provider' 14 -Bold -Margin '0,10,0,2'))
    $txtProvider = [Windows.Controls.TextBox]::new(); $txtProvider.Text = $script:prefs.SMSProvider; $txtProvider.Height = 28; [Windows.Automation.AutomationProperties]::SetAutomationId($txtProvider, 'txtSmsProvider')
    [MahApps.Metro.Controls.TextBoxHelper]::SetWatermark($txtProvider, 'server.fqdn')
    [void]$connection.Children.Add($txtProvider)
    [void]$connection.Children.Add((New-PasOptionsText 'A value saved here wins. The suite launcher fills an empty value. Enter the provider name that its certificate carries, normally the FQDN. Select Resolve Targets again after a change.' 11 -Margin '0,10,0,0' -Muted))

    $scripts = [Windows.Controls.StackPanel]::new()
    [void]$scripts.Children.Add((New-PasOptionsText 'Run Scripts' 18 -Weight SemiBold -Margin '0,0,0,12'))
    $chkApprove = [Windows.Controls.CheckBox]::new(); $chkApprove.Content = 'Approve scripts after submission'; $chkApprove.IsChecked = [bool]$script:prefs.ApproveAfterSubmit; [Windows.Automation.AutomationProperties]::SetAutomationId($chkApprove, 'chkApproveAfterSubmit')
    [void]$scripts.Children.Add($chkApprove)
    [void]$scripts.Children.Add((New-PasOptionsText 'Configuration Manager decides. By default, the site requires a second approver, and the author cannot approve. Microsoft recommends allowing authors to approve their own scripts only in a lab. When the site refuses, the script stays waiting for approval and the status line shows the reason.' 11 -Margin '0,10,0,0' -Muted))

    $about = [Windows.Controls.StackPanel]::new()
    [void]$about.Children.Add((New-PasOptionsText 'Pivots and Scripts' 18 -Weight SemiBold -Margin '0,0,0,12'))
    [void]$about.Children.Add((New-PasOptionsText ('Version ' + $script:appVersion)))
    $suiteVersion = ''
    try { $suiteVersion = Get-SuiteCommonVersion } catch { $null = Get-PasUserErrorText -ErrorRecord $_ -Fallback '' -LogDetail }
    [void]$about.Children.Add((New-PasOptionsText ('SuiteCommon ' + $suiteVersion)))
    [void]$about.Children.Add((New-PasOptionsText 'CMPivot queries and approved Run Scripts for Configuration Manager. Part of the AppPackager Suite.' 12 -Muted))
    [void]$about.Children.Add((New-PasOptionsText 'MIT License. Third-party library licenses are in the Lib folder.' 11 -Muted))

    $pages = @(@{Name='Connection';Element=$connection},@{Name='Run Scripts';Element=$scripts},@{Name='About';Element=$about})
    foreach ($page in $pages) { [void]$lstNav.Items.Add($page.Name) }
    $lstNav.Add_SelectionChanged({ $index = $lstNav.SelectedIndex; if ($index -ge 0) { $contentArea.Content = $pages[$index].Element } })
    $lstNav.SelectedIndex = 0

    $dialog.FindName('btnOK').Add_Click({
        try {
            $newSite = $txtSite.Text.Trim().ToUpperInvariant(); $newProvider = $txtProvider.Text.Trim()
            if ($newSite -and $newSite -notmatch '^[A-Z0-9]{3}$') { throw "Site code '$newSite' is invalid. A site code is 3 characters, A-Z or 0-9." }
            if ($newProvider -and $newProvider -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*$') { throw "SMS Provider '$newProvider' is invalid. Enter a host name or FQDN without a URL or path." }
            $changed = ($newSite -ne $script:prefs.SiteCode) -or ($newProvider -ne $script:prefs.SMSProvider)
            $settings = Get-PasSettingsToSave -Entered @{SiteCode=$newSite;SMSProvider=$newProvider;ApproveAfterSubmit=[bool]$chkApprove.IsChecked} -Session $script:prefs -Persisted $script:persisted
            if (-not (Save-SuiteSettings -Path $prefsPath -Settings $settings)) { throw "The options could not be saved to $prefsPath." }
            $script:persisted.SiteCode = $settings.SiteCode; $script:persisted.SMSProvider = $settings.SMSProvider
            $script:prefs.SiteCode = $newSite; $script:prefs.SMSProvider = $newProvider; $script:prefs.ApproveAfterSubmit = [bool]$chkApprove.IsChecked
            Update-PasConnectionInfo
            if ($changed) { $ui.targetSummary.Text = 'Connection changed. Select Resolve Targets again.'; $ui.status.Text = 'Options saved. Select Test Connection to check the new connection.' } else { $ui.status.Text = 'Options saved.' }
            $dialog.DialogResult = $true
        } catch { [void](Show-ThemedMessage -Owner $dialog -Title 'Options Error' -Message (Get-PasUserErrorText -ErrorRecord $_ -Fallback 'The options could not be saved. The log file has the details.' -LogDetail)) }
    })
    $dialog.FindName('btnCancel').Add_Click({ $dialog.Close() })
    if ($SmokeTest) {
        $optionsTimer = [Windows.Threading.DispatcherTimer]::new(); $optionsTimer.Interval = [TimeSpan]::FromMilliseconds(250)
        $optionsTimer.Add_Tick({ $optionsTimer.Stop(); $lstNav.SelectedIndex = 2; $dialog.Close() })
        $optionsTimer.Start()
    }
    [void]$dialog.ShowDialog()
}
