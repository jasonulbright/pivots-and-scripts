$script:appVersion = ''
$versionLine = Select-String -LiteralPath (Join-Path (Split-Path $PSScriptRoot) 'start-pivotsandscripts.ps1') -Pattern '^\s*Version\s*:\s*(\S+)' | Select-Object -First 1
if ($versionLine) { $script:appVersion = $versionLine.Matches[0].Groups[1].Value }

function New-PasOptionsText {
    param([string]$Text,[double]$Size=12,[string]$Weight='Normal',[string]$Margin='0,0,0,8',[switch]$Muted)
    $block = [Windows.Controls.TextBlock]::new()
    $block.Text = $Text; $block.FontSize = $Size; $block.FontWeight = $Weight; $block.Margin = $Margin; $block.TextWrapping = 'Wrap'
    if ($Muted) { $block.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'MahApps.Brushes.Gray1') }
    $block
}
function Show-PasOptionsDialog {
    $xaml = @'
<Controls:MetroWindow xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro" Title="Options" Width="760" Height="500" MinWidth="640" MinHeight="420" WindowStartupLocation="CenterOwner" TitleCharacterCasing="Normal" ShowIconOnTitleBar="False" GlowBrush="{DynamicResource MahApps.Brushes.Accent}" BorderThickness="1">
 <Window.Resources><ResourceDictionary><ResourceDictionary.MergedDictionaries><ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml"/><ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml"/><ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Themes/Dark.Steel.xaml"/></ResourceDictionary.MergedDictionaries></ResourceDictionary></Window.Resources>
 <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="190"/><ColumnDefinition Width="1"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <ListBox x:Name="lstNav" BorderThickness="0" Padding="0,8,0,0"><ListBox.ItemContainerStyle><Style TargetType="ListBoxItem"><Setter Property="Padding" Value="16,10,16,10"/><Setter Property="FontSize" Value="13"/></Style></ListBox.ItemContainerStyle></ListBox>
  <Border Grid.Column="1" Background="{DynamicResource MahApps.Brushes.Gray8}"/>
  <ScrollViewer Grid.Column="2" VerticalScrollBarVisibility="Auto"><ContentControl x:Name="contentArea" Margin="20,18,20,18"/></ScrollViewer>
  <Border Grid.ColumnSpan="3" Grid.Row="1" BorderBrush="{DynamicResource MahApps.Brushes.Gray8}" BorderThickness="0,1,0,0"><StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="20,12,20,12">
   <Button x:Name="btnOK" Content="OK" MinWidth="90" Height="32" Margin="0,0,8,0" IsDefault="True" Style="{DynamicResource MahApps.Styles.Button.Square.Accent}" Controls:ControlsHelper.ContentCharacterCasing="Normal"/>
   <Button x:Name="btnCancel" Content="Cancel" MinWidth="90" Height="32" IsCancel="True" Style="{DynamicResource MahApps.Styles.Button.Square}" Controls:ControlsHelper.ContentCharacterCasing="Normal"/>
  </StackPanel></Border>
 </Grid>
</Controls:MetroWindow>
'@
    $dialog = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new([xml]$xaml))
    $dialog.Owner = $window
    Set-DialogTheme -Dialog $dialog -IsDark $ui.toggleTheme.IsOn
    Install-TitleBarDragFallback -Window $dialog
    $lstNav = $dialog.FindName('lstNav'); $contentArea = $dialog.FindName('contentArea')

    $connection = [Windows.Controls.StackPanel]::new()
    [void]$connection.Children.Add((New-PasOptionsText 'Configuration Manager Connection' 18 'SemiBold' '0,0,0,12'))
    [void]$connection.Children.Add((New-PasOptionsText 'Site code:' 12 'Normal' '0,4,0,2'))
    $txtSite = [Windows.Controls.TextBox]::new(); $txtSite.Text = $script:prefs.SiteCode; $txtSite.MaxLength = 3; $txtSite.Width = 80; $txtSite.HorizontalAlignment = 'Left'; $txtSite.Height = 28
    [void]$connection.Children.Add($txtSite)
    [void]$connection.Children.Add((New-PasOptionsText 'SMS Provider:' 12 'Normal' '0,10,0,2'))
    $txtProvider = [Windows.Controls.TextBox]::new(); $txtProvider.Text = $script:prefs.SMSProvider; $txtProvider.Height = 28
    [MahApps.Metro.Controls.TextBoxHelper]::SetWatermark($txtProvider, 'server.fqdn')
    [void]$connection.Children.Add($txtProvider)
    [void]$connection.Children.Add((New-PasOptionsText 'A value saved here wins. The suite launcher fills an empty value. Enter the provider name that its certificate carries, normally the FQDN. Resolve targets again after a change.' 11 'Normal' '0,10,0,0' -Muted))

    $scripts = [Windows.Controls.StackPanel]::new()
    [void]$scripts.Children.Add((New-PasOptionsText 'Run Scripts' 18 'SemiBold' '0,0,0,12'))
    $chkApprove = [Windows.Controls.CheckBox]::new(); $chkApprove.Content = 'Approve scripts after submission'; $chkApprove.IsChecked = [bool]$script:prefs.ApproveAfterSubmit
    [void]$scripts.Children.Add($chkApprove)
    [void]$scripts.Children.Add((New-PasOptionsText 'Configuration Manager decides. By default, the site requires a second approver, and the author cannot approve. Microsoft recommends allowing authors to approve their own scripts only in a lab. When the site refuses, the script stays waiting for approval and the status line shows the reason.' 11 'Normal' '0,10,0,0' -Muted))

    $about = [Windows.Controls.StackPanel]::new()
    [void]$about.Children.Add((New-PasOptionsText 'Pivots and Scripts' 18 'SemiBold' '0,0,0,12'))
    [void]$about.Children.Add((New-PasOptionsText ('Version ' + $script:appVersion)))
    $suiteVersion = ''
    try { $suiteVersion = Get-SuiteCommonVersion } catch { $suiteVersion = '' }
    [void]$about.Children.Add((New-PasOptionsText ('SuiteCommon ' + $suiteVersion)))
    [void]$about.Children.Add((New-PasOptionsText 'CMPivot queries and approved Run Scripts for Configuration Manager. Part of the AppPackager Suite.' 12 'Normal' '0,0,0,8' -Muted))
    [void]$about.Children.Add((New-PasOptionsText 'MIT License. Third-party library licenses are in the Lib folder.' 11 'Normal' '0,0,0,8' -Muted))

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
            if ($changed) { $ui.targetSummary.Text = 'Connection changed. Resolve targets again.'; $ui.status.Text = 'Options saved. Select Test connection to check the new connection.' } else { $ui.status.Text = 'Options saved.' }
            $dialog.DialogResult = $true
        } catch { [void](Show-ThemedMessage -Owner $dialog -Title 'Options' -Message $_.Exception.Message) }
    })
    $dialog.FindName('btnCancel').Add_Click({ $dialog.Close() })
    if ($SmokeTest) {
        $optionsTimer = [Windows.Threading.DispatcherTimer]::new(); $optionsTimer.Interval = [TimeSpan]::FromMilliseconds(250)
        $optionsTimer.Add_Tick({ $optionsTimer.Stop(); $lstNav.SelectedIndex = 2; $dialog.Close() })
        $optionsTimer.Start()
    }
    [void]$dialog.ShowDialog()
}
