function Show-PasScriptsDialog {
    $xaml = @'
<Controls:MetroWindow xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro" Title="Site Scripts" Width="1180" Height="560" MinWidth="900" MinHeight="400" WindowStartupLocation="CenterOwner" TitleCharacterCasing="Normal" ShowIconOnTitleBar="False" GlowBrush="{DynamicResource MahApps.Brushes.Accent}" BorderThickness="1">
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
  <!-- Selected rows and cells: white text (IdealForeground) on the highlight blue, in both themes. -->
  <Style x:Key="ThemedDataGridRow" TargetType="DataGridRow" BasedOn="{StaticResource MahApps.Styles.DataGridRow}">
   <Style.Triggers>
    <Trigger Property="IsSelected" Value="True">
     <Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Highlight}"/>
     <Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.IdealForeground}"/>
    </Trigger>
   </Style.Triggers>
  </Style>
  <Style x:Key="ThemedDataGridStyle" TargetType="DataGrid" BasedOn="{StaticResource MahApps.Styles.DataGrid}">
   <Setter Property="RowStyle" Value="{StaticResource ThemedDataGridRow}"/>
  </Style>
  <Style x:Key="GridCellStyle" TargetType="DataGridCell" BasedOn="{StaticResource MahApps.Styles.DataGridCell}">
   <Style.Triggers>
    <Trigger Property="IsSelected" Value="True">
     <Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Highlight}"/>
     <Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.IdealForeground}"/>
    </Trigger>
   </Style.Triggers>
  </Style>
 </ResourceDictionary></Window.Resources>
 <DockPanel Margin="16">
  <TextBlock DockPanel.Dock="Top" TextWrapping="Wrap" Margin="0,0,0,10" Text="Scripts in Run Scripts on this site. Configuration Manager enforces approval rules: by default, an author cannot approve their own script. Scripts that belong to a Configuration Manager feature, such as CMPivot, are not listed."/>
  <DockPanel DockPanel.Dock="Bottom" Margin="0,10,0,0">
   <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
    <Button x:Name="btnRefresh" Content="Refresh" Style="{StaticResource DialogButton}"/>
    <Button x:Name="btnUse" Content="Use GUID" Style="{StaticResource DialogButton}"/>
    <Button x:Name="btnApprove" Content="Approve" Style="{StaticResource DialogButton}"/>
    <Button x:Name="btnDeny" Content="Deny" Style="{StaticResource DialogButton}"/>
    <Button x:Name="btnRemove" Content="Remove" Style="{StaticResource DialogButton}"/>
   </StackPanel>
   <TextBox x:Name="comment" Margin="3" Controls:TextBoxHelper.Watermark="Approval or denial comment"/>
  </DockPanel>
  <DataGrid x:Name="grid" Style="{StaticResource ThemedDataGridStyle}" CellStyle="{StaticResource GridCellStyle}" IsReadOnly="True" AutoGenerateColumns="False" SelectionMode="Single" CanUserAddRows="False">
   <DataGrid.Columns>
    <DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="*" MinWidth="200"/>
    <DataGridTextColumn Header="State" Binding="{Binding State}" Width="Auto"/>
    <DataGridTextColumn Header="Author" Binding="{Binding Author}" Width="Auto"/>
    <DataGridTextColumn Header="Approver" Binding="{Binding Approver}" Width="Auto"/>
    <DataGridTextColumn Header="Last Updated" Binding="{Binding LastUpdated}" Width="Auto"/>
    <DataGridTextColumn Header="GUID" Binding="{Binding ScriptGuid}" Width="Auto"/>
   </DataGrid.Columns>
  </DataGrid>
 </DockPanel>
</Controls:MetroWindow>
'@
    $dialog = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new([xml]$xaml))
    $dialog.Owner = $window
    Set-DialogTheme -Dialog $dialog -IsDark $ui.toggleTheme.IsOn
    Install-TitleBarDragFallback -Window $dialog
    $grid = $dialog.FindName('grid'); $comment = $dialog.FindName('comment')
    $script:scriptsGrid = $grid
    $grid.ItemsSource = @($script:siteScripts)
    $selected = {
        if ($script:work) { throw 'Wait for the current operation to finish.' }
        $item = $grid.SelectedItem
        if (-not $item) { throw 'Select a script first.' }
        $item
    }
    $dialog.FindName('btnRefresh').Add_Click({ try { Start-PasWork 'Scripts' } catch { Show-ThemedMessage -Owner $dialog -Title 'Site Scripts Error' -Message (Get-PasUserErrorText -ErrorRecord $_ -Fallback 'The action failed. The log file has the details.' -LogDetail) } })
    $dialog.FindName('btnUse').Add_Click({ try { $item = & $selected; $ui.scriptGuid.Text = $item.ScriptGuid; $ui.status.Text = "Script GUID set to $($item.ScriptGuid) ($($item.Name), $($item.State))."; $dialog.Close() } catch { Show-ThemedMessage -Owner $dialog -Title 'Site Scripts Error' -Message (Get-PasUserErrorText -ErrorRecord $_ -Fallback 'The action failed. The log file has the details.' -LogDetail) } })
    $dialog.FindName('btnApprove').Add_Click({ try { $item = & $selected; if (Show-ConfirmDialog -Owner $dialog -Title 'Approve Script' -Message "Approve script '$($item.Name)'?`n`nAuthor: $($item.Author)`nGUID: $($item.ScriptGuid)`n`nAn approved script can run on any device you have Run Script permission for.") { Start-PasWork 'Approve' -Extra @{ScriptGuid=$item.ScriptGuid;Comment=$comment.Text.Trim()} } } catch { Show-ThemedMessage -Owner $dialog -Title 'Site Scripts Error' -Message (Get-PasUserErrorText -ErrorRecord $_ -Fallback 'The action failed. The log file has the details.' -LogDetail) } })
    $dialog.FindName('btnDeny').Add_Click({ try { $item = & $selected; if (Show-ConfirmDialog -Owner $dialog -Title 'Deny Script' -Message "Deny script '$($item.Name)'?`n`nGUID: $($item.ScriptGuid)`n`nA denied script cannot run until it is approved again.") { Start-PasWork 'Deny' -Extra @{ScriptGuid=$item.ScriptGuid;Comment=$comment.Text.Trim()} } } catch { Show-ThemedMessage -Owner $dialog -Title 'Site Scripts Error' -Message (Get-PasUserErrorText -ErrorRecord $_ -Fallback 'The action failed. The log file has the details.' -LogDetail) } })
    $dialog.FindName('btnRemove').Add_Click({ try { $item = & $selected; if (Show-ConfirmDialog -Owner $dialog -Title 'Remove Script' -Message "Permanently remove script '$($item.Name)' from Configuration Manager?`n`nGUID: $($item.ScriptGuid)`n`nThis cannot be undone. Its run history in Script Status is removed with it.") { Start-PasWork 'Remove' -Extra @{ScriptGuid=$item.ScriptGuid} } } catch { Show-ThemedMessage -Owner $dialog -Title 'Site Scripts Error' -Message (Get-PasUserErrorText -ErrorRecord $_ -Fallback 'The action failed. The log file has the details.' -LogDetail) } })
    $dialog.Add_Closed({ $script:scriptsGrid = $null })
    if (-not $script:work) { try { Start-PasWork 'Scripts' } catch { $ui.status.Text = Get-PasUserErrorText -ErrorRecord $_ -Fallback 'The site scripts could not be listed. The log file has the details.' -LogDetail } }
    if ($SmokeTest) {
        $scriptsTimer = [Windows.Threading.DispatcherTimer]::new(); $scriptsTimer.Interval = [TimeSpan]::FromMilliseconds(250)
        $scriptsTimer.Add_Tick({ $scriptsTimer.Stop(); $dialog.Close() })
        $scriptsTimer.Start()
    }
    [void]$dialog.ShowDialog()
}
