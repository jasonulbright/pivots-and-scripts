function Show-PasParameterDialog {
    $definitions=@(Get-PasParameters $ui.editor.Text)
    $xaml=@'
<Controls:MetroWindow xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:Controls="clr-namespace:MahApps.Metro.Controls;assembly=MahApps.Metro" Title="Script Parameters" Width="580" Height="500" WindowStartupLocation="CenterOwner" TitleCharacterCasing="Normal" ShowIconOnTitleBar="False">
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
  <!-- Selected and highlighted items: white text (IdealForeground) on the highlight blue, in both themes. -->
  <Style x:Key="ThemedComboBoxItemStyle" TargetType="ComboBoxItem" BasedOn="{StaticResource MahApps.Styles.ComboBoxItem}">
   <Style.Triggers>
    <Trigger Property="IsHighlighted" Value="True">
     <Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Highlight}"/>
     <Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.IdealForeground}"/>
    </Trigger>
    <Trigger Property="IsSelected" Value="True">
     <Setter Property="Background" Value="{DynamicResource MahApps.Brushes.Highlight}"/>
     <Setter Property="Foreground" Value="{DynamicResource MahApps.Brushes.IdealForeground}"/>
    </Trigger>
   </Style.Triggers>
  </Style>
 </ResourceDictionary></Window.Resources>
 <DockPanel Margin="18"><StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0"><Button x:Name="apply" Content="Use Parameters" IsDefault="True" Style="{StaticResource DialogAccentButton}"/><Button x:Name="btnCancel" Content="Cancel" IsCancel="True" Style="{StaticResource DialogButton}"/></StackPanel><TextBlock x:Name="notice" DockPanel.Dock="Top" Text="Values are sent to the approved ConfigMgr script. Run Scripts accepts string and integer values without single quotes. No parameter expressions are evaluated locally." TextWrapping="Wrap" Margin="0,0,0,12"/><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="fields"/></ScrollViewer></DockPanel>
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
        $label.FontWeight=[Windows.FontWeights]::Bold;$label.Margin='0,8,0,4';$panel.Children.Add($label)|Out-Null
        $value=if($reuse -and $script:parameters.ContainsKey($p.Name)){$script:parameters[$p.Name]}else{$p.DefaultLiteral}
        if(@($p.Choices).Count){$control=[Windows.Controls.ComboBox]::new();$control.SetResourceReference([Windows.Controls.ItemsControl]::ItemContainerStyleProperty,'ThemedComboBoxItemStyle');$control.ItemsSource=@($p.Choices);$control.SelectedItem=[string]$value}
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
        }catch{$notice.Text=Get-PasUserErrorText -ErrorRecord $_ -Fallback 'The parameters could not be applied. The log file has the details.' -LogDetail}
    })
    if($SmokeTest){
        $parameterTimer=[Windows.Threading.DispatcherTimer]::new();$parameterTimer.Interval=[TimeSpan]::FromMilliseconds(250)
        $parameterTimer.Add_Tick({$parameterTimer.Stop();$dialog.FindName('apply').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))})
        $parameterTimer.Start()
    }
    $dialog.ShowDialog()|Out-Null
}
