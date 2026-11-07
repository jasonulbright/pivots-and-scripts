# App-specific names for Window.Tests.ps1.
# The main window has one layout and two views. The sidebar buttons btnPivot and btnScript switch the
# mode: Set-PasMode in the start script changes the heading, the editor label, the run button text
# and the visibility of five controls. Each view lists the mode (the active view name the theme uses),
# the sidebar button, and the heading that the mode shows.
$script:AppConfig = @{
    Title          = 'Pivots and Scripts'
    Shell          = 'start-pivotsandscripts.ps1'
    Xaml           = 'MainWindow.xaml'
    OptionsButtons = @('btnHistory', 'btnOptions')
    # Functions of the start script that switch the view; the tests run the real ones.
    ModeFunctions  = @('Set-PasMode', 'Update-Library', 'Set-PasHighlighting')
    DialogFiles    = @('Module\OptionsDialog.ps1', 'Module\ParameterDialog.ps1', 'Module\ScriptsDialog.ps1')
    Views          = @(
        @{ Name = 'Pivot';  Mode = 'Pivot';  Button = 'btnPivot';  Heading = 'CMPivot' }
        @{ Name = 'Script'; Mode = 'Script'; Button = 'btnScript'; Heading = 'PowerShell' }
    )
}
