function Show-PasParameterDialog {
    $definitions=@(Get-PasParameters $ui.editor.Text)
    $xaml=@'
<Controls:MetroWindow xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro" Title="Script parameters" Width="580" Height="500" WindowStartupLocation="CenterOwner" TitleCharacterCasing="Normal" ShowIconOnTitleBar="False">
 <Window.Resources><ResourceDictionary><ResourceDictionary.MergedDictionaries><ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Controls.xaml"/><ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Fonts.xaml"/><ResourceDictionary Source="pack://application:,,,/MahApps.Metro;component/Styles/Themes/Dark.Steel.xaml"/></ResourceDictionary.MergedDictionaries></ResourceDictionary></Window.Resources>
 <DockPanel Margin="18"><Button x:Name="apply" DockPanel.Dock="Bottom" Content="Use parameters" Height="34" Margin="0,12,0,0" Controls:ControlsHelper.ContentCharacterCasing="Normal"/><TextBlock x:Name="notice" DockPanel.Dock="Top" Text="Values are sent to the approved ConfigMgr script. Run Scripts accepts string and integer values without single quotes. No parameter expressions are evaluated locally." TextWrapping="Wrap" Margin="0,0,0,12"/><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="fields"/></ScrollViewer></DockPanel>
</Controls:MetroWindow>
'@
    $reader=[Xml.XmlNodeReader]::new([xml]$xaml)
    $dialog=[Windows.Markup.XamlReader]::Load($reader);$dialog.Owner=$window
    Set-DialogTheme -Dialog $dialog -IsDark $ui.toggleTheme.IsOn
    Install-TitleBarDragFallback -Window $dialog
    $panel=$dialog.FindName('fields');$notice=$dialog.FindName('notice')
    $controls=@{}
    $reuse=$script:parameterKey -eq (Get-PasParameterKey)
    foreach($p in $definitions){
        $label=[Windows.Controls.TextBlock]::new()
        $label.Text=$p.Name+' ('+$p.Type.Split('.')[-1]+')'+$(if($p.Mandatory){', required'}else{''})+$(if(-not $p.SiteType){', not supported by Run Scripts'}else{''})
        $label.Margin='0,8,0,4';$panel.Children.Add($label)|Out-Null
        $value=if($reuse -and $script:parameters.ContainsKey($p.Name)){$script:parameters[$p.Name]}else{$p.DefaultLiteral}
        if(@($p.Choices).Count){$control=[Windows.Controls.ComboBox]::new();$control.ItemsSource=@($p.Choices);$control.SelectedItem=[string]$value}
        else{$control=[Windows.Controls.TextBox]::new();$control.Text=[string]$value;$control.MinHeight=28}
        if(-not $p.SiteType){$control.IsEnabled=$false}
        $controls[$p.Name]=@{Control=$control;Definition=$p}
        $panel.Children.Add($control)|Out-Null
    }
    if(-not $controls.Count){$notice.Text='This script draft declares no parameters.'}
    $dialog.FindName('apply').Add_Click({
        try{
            $values=@{}
            foreach($name in $controls.Keys){
                $field=$controls[$name];$control=$field.Control;$definition=$field.Definition
                if(-not $definition.SiteType){throw "Parameter '$name' has type $($definition.Type). Run Scripts accepts string and integer parameters only."}
                $value=if($control -is [Windows.Controls.ComboBox]){[string]$control.SelectedItem}else{$control.Text}
                if([string]::IsNullOrEmpty($value)){if($definition.Mandatory -and -not $definition.DefaultLiteral){throw "Parameter '$name' is required."};continue}
                if($value.Contains("'")){throw "Parameter '$name' contains a single quote. Run Scripts cannot pass it."}
                if($definition.SiteType -eq 'System.Int32'){$number=0;if(-not [int]::TryParse($value,[ref]$number)){throw "Parameter '$name' needs a whole number."};$value=$number}
                $values[$name]=$value
            }
            $script:parameters=$values;$script:parameterKey=Get-PasParameterKey;$dialog.DialogResult=$true
        }catch{$notice.Text=$_.Exception.Message}
    })
    if($SmokeTest){
        $parameterTimer=[Windows.Threading.DispatcherTimer]::new();$parameterTimer.Interval=[TimeSpan]::FromMilliseconds(250)
        $parameterTimer.Add_Tick({$parameterTimer.Stop();$dialog.FindName('apply').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))})
        $parameterTimer.Start()
    }
    $dialog.ShowDialog()|Out-Null
}
