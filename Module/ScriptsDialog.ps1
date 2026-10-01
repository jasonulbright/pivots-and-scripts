function Show-PasScriptsDialog {
    $xaml = @'
<Controls:MetroWindow xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro" Title="Site scripts" Width="1180" Height="560" MinWidth="760" MinHeight="400" WindowStartupLocation="CenterOwner" TitleCharacterCasing="Normal" ShowIconOnTitleBar="False" GlowBrush="{DynamicResource MahApps.Brushes.Accent}" BorderThickness="1">
 <Window.Resources><ResourceDictionary><ResourceDictionary.MergedDictionaries><ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml"/><ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml"/><ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Themes/Dark.Steel.xaml"/></ResourceDictionary.MergedDictionaries></ResourceDictionary></Window.Resources>
 <DockPanel Margin="16">
  <TextBlock DockPanel.Dock="Top" TextWrapping="Wrap" Margin="0,0,0,10" Text="Scripts in Run Scripts on this site. Configuration Manager enforces approval rules: by default, an author cannot approve their own script. Scripts that belong to a Configuration Manager feature, such as CMPivot, are not listed."/>
  <DockPanel DockPanel.Dock="Bottom" Margin="0,10,0,0">
   <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
    <Button x:Name="btnRefresh" Content="Refresh" MinWidth="80" Margin="3" Controls:ControlsHelper.ContentCharacterCasing="Normal"/>
    <Button x:Name="btnUse" Content="Use GUID" MinWidth="80" Margin="3" Controls:ControlsHelper.ContentCharacterCasing="Normal"/>
    <Button x:Name="btnApprove" Content="Approve" MinWidth="80" Margin="3" Controls:ControlsHelper.ContentCharacterCasing="Normal"/>
    <Button x:Name="btnDeny" Content="Deny" MinWidth="80" Margin="3" Controls:ControlsHelper.ContentCharacterCasing="Normal"/>
    <Button x:Name="btnRemove" Content="Remove" MinWidth="80" Margin="3" Controls:ControlsHelper.ContentCharacterCasing="Normal"/>
   </StackPanel>
   <TextBox x:Name="comment" Margin="3" Controls:TextBoxHelper.Watermark="Approval or denial comment"/>
  </DockPanel>
  <DataGrid x:Name="grid" IsReadOnly="True" AutoGenerateColumns="False" SelectionMode="Single" CanUserAddRows="False">
   <DataGrid.Columns>
    <DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="*" MinWidth="200"/>
    <DataGridTextColumn Header="State" Binding="{Binding State}" Width="Auto"/>
    <DataGridTextColumn Header="Author" Binding="{Binding Author}" Width="Auto"/>
    <DataGridTextColumn Header="Approver" Binding="{Binding Approver}" Width="Auto"/>
    <DataGridTextColumn Header="Last updated" Binding="{Binding LastUpdated}" Width="Auto"/>
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
    $dialog.FindName('btnRefresh').Add_Click({ try { Start-PasWork 'Scripts' } catch { Show-ThemedMessage -Owner $dialog -Title 'Site scripts' -Message $_.Exception.Message } })
    $dialog.FindName('btnUse').Add_Click({ try { $item = & $selected; $ui.scriptGuid.Text = $item.ScriptGuid; $ui.status.Text = "Script GUID set to $($item.ScriptGuid) ($($item.Name), $($item.State))."; $dialog.Close() } catch { Show-ThemedMessage -Owner $dialog -Title 'Site scripts' -Message $_.Exception.Message } })
    $dialog.FindName('btnApprove').Add_Click({ try { $item = & $selected; if (Show-ConfirmDialog -Owner $dialog -Title 'Approve script' -Message "Approve script '$($item.Name)'?`n`nAuthor: $($item.Author)`nGUID: $($item.ScriptGuid)`n`nAn approved script can run on any device you have Run Script permission for.") { Start-PasWork 'Approve' -Extra @{ScriptGuid=$item.ScriptGuid;Comment=$comment.Text.Trim()} } } catch { Show-ThemedMessage -Owner $dialog -Title 'Site scripts' -Message $_.Exception.Message } })
    $dialog.FindName('btnDeny').Add_Click({ try { $item = & $selected; if (Show-ConfirmDialog -Owner $dialog -Title 'Deny script' -Message "Deny script '$($item.Name)'?`n`nGUID: $($item.ScriptGuid)`n`nA denied script cannot run until it is approved again.") { Start-PasWork 'Deny' -Extra @{ScriptGuid=$item.ScriptGuid;Comment=$comment.Text.Trim()} } } catch { Show-ThemedMessage -Owner $dialog -Title 'Site scripts' -Message $_.Exception.Message } })
    $dialog.FindName('btnRemove').Add_Click({ try { $item = & $selected; if (Show-ConfirmDialog -Owner $dialog -Title 'Remove script' -Message "Permanently remove script '$($item.Name)' from Configuration Manager?`n`nGUID: $($item.ScriptGuid)`n`nThis cannot be undone. Its run history in Script Status is removed with it.") { Start-PasWork 'Remove' -Extra @{ScriptGuid=$item.ScriptGuid} } } catch { Show-ThemedMessage -Owner $dialog -Title 'Site scripts' -Message $_.Exception.Message } })
    $dialog.Add_Closed({ $script:scriptsGrid = $null })
    if (-not $script:work) { try { Start-PasWork 'Scripts' } catch { $ui.status.Text = $_.Exception.Message } }
    if ($SmokeTest) {
        $scriptsTimer = [Windows.Threading.DispatcherTimer]::new(); $scriptsTimer.Interval = [TimeSpan]::FromMilliseconds(250)
        $scriptsTimer.Add_Tick({ $scriptsTimer.Stop(); $dialog.Close() })
        $scriptsTimer.Start()
    }
    [void]$dialog.ShowDialog()
}
