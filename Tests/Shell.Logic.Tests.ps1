#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }
# Logic of start-pivotsandscripts.ps1. The script cannot be dot-sourced (it opens the window), so each
# function and each event handler is cut out of its syntax tree and run here, with plain objects in place
# of the window controls and a stub module in place of the site. The functions run for real; the dialogs,
# the file pickers and the confirmation are test functions that record what they were asked.

BeforeAll {
    . "$PSScriptRoot\TestHelpers.ps1"
    Import-AppModule
    # AvalonEdit text documents work on any thread; the replace handler edits one.
    foreach ($dll in 'ICSharpCode.AvalonEdit.dll') { [void][System.Reflection.Assembly]::LoadFrom((Join-Path $script:AppRoot "Lib\$dll")) }
    $script:ShellPath = Join-Path $script:AppRoot 'start-pivotsandscripts.ps1'
    $wanted = 'Show-PasError', 'Set-PasMode', 'Refresh-PasResults', 'Save-PasSession', 'Update-PasConnectionInfo', 'Get-PasRunScope',
    'Get-PasParameterKey', 'Get-PasStepState', 'Start-PasWork', 'Send-PasSelection'
    foreach ($text in @(Get-ScriptFunctionText -Path $script:ShellPath -Name $wanted)) { . ([scriptblock]::Create($text)) }
    $script:RealText = @{}
    foreach ($n in 'Update-Library', 'Set-PasHighlighting') { $script:RealText[$n] = (Get-ScriptFunctionText -Path $script:ShellPath -Name $n) }
    $script:Tick = Get-EventHandlerBlock -Path $script:ShellPath -Target '$timer' -EventName 'Add_Tick'

    # Handlers that the tests run, by name.
    $script:Handler = @{}
    foreach ($h in @(
            @('btnPivot', 'Add_Click'), @('btnScript', 'Add_Click'), @('btnCheck', 'Add_Click'), @('btnOpen', 'Add_Click'), @('btnSave', 'Add_Click'),
            @('btnConnect', 'Add_Click'), @('btnResolve', 'Add_Click'), @('btnTargets', 'Add_Click'), @('btnImport', 'Add_Click'), @('btnRun', 'Add_Click'),
            @('btnStop', 'Add_Click'), @('btnSubmit', 'Add_Click'), @('btnCsv', 'Add_Click'), @('btnJson', 'Add_Click'), @('btnCopy', 'Add_Click'),
            @('btnSaveSession', 'Add_Click'), @('btnNewSession', 'Add_Click'), @('btnHistory', 'Add_Click'), @('btnFind', 'Add_Click'),
            @('btnReplace', 'Add_Click'), @('targetInput', 'Add_TextChanged'), @('targetKind', 'Add_SelectionChanged'), @('library', 'Add_MouseDoubleClick'),
            @('btnSelectionScript', 'Add_Click'), @('btnSelectionPivot', 'Add_Click'))) {
        $script:Handler[$h[0] + '.' + $h[1]] = Get-EventHandlerBlock -Path $script:ShellPath -Target ('$ui.' + $h[0]) -EventName $h[1]
    }
    $script:Handler['window.Add_Closing'] = Get-EventHandlerBlock -Path $script:ShellPath -Target '$window' -EventName 'Add_Closing'
    $script:Handler['results.Add_Sorting'] = Get-EventHandlerBlock -Path $script:ShellPath -Target '$ui.results' -EventName 'Add_Sorting'
    $script:Handler['results.Add_ColumnReordered'] = Get-EventHandlerBlock -Path $script:ShellPath -Target '$ui.results' -EventName 'Add_ColumnReordered'

    $script:ControlNames = @('btnPivot', 'btnScript', 'btnHistory', 'toggleTheme', 'txtThemeLabel', 'library', 'libraryFilter', 'btnOpen', 'btnSave', 'btnSaveSession', 'btnNewSession', 'heading', 'connectionInfo', 'connectionPair', 'txtSiteCode', 'txtSmsProvider', 'btnOptions', 'btnSiteScripts', 'btnConnect', 'targetKind', 'targetInput', 'btnImport', 'btnResolve', 'targetSummary', 'btnTargets', 'editor', 'editorLabel', 'editorPosition', 'btnCheck', 'btnFind', 'findText', 'replaceText', 'btnReplace', 'btnRun', 'btnStop', 'btnSubmit', 'guidLabel', 'scriptGuid', 'btnParameters', 'resultFilter', 'btnCsv', 'btnJson', 'btnCopy', 'btnGrid', 'btnSelectionScript', 'btnSelectionPivot', 'results', 'devices', 'raw', 'pipeline', 'resultTabs', 'status')

    function script:New-FakeControl {
        $c = [pscustomobject]@{ Text = ''; IsEnabled = $true; Content = ''; Visibility = 'Visible'; ItemsSource = $null; SelectedItem = $null; SelectedIndex = 0; IsOn = $true; SelectedItems = @(); SelectionStart = 0; SelectionLength = 0; Focused = $false; Selected = $null; SyntaxHighlighting = $null }
        $c | Add-Member -MemberType ScriptMethod -Name Clear -Value { $this.Text = '' }
        $c | Add-Member -MemberType ScriptMethod -Name AppendText -Value { param($s) $this.Text += $s }
        $c | Add-Member -MemberType ScriptMethod -Name Select -Value { param($start, $length) $this.SelectionStart = $start; $this.SelectionLength = $length; $this.Selected = @($start, $length) }
        $c | Add-Member -MemberType ScriptMethod -Name Focus -Value { $this.Focused = $true; $true }
        $c
    }

    # Replaces the dialogs. Each records its call; the answers are set per test.
    function script:Show-ThemedMessage { param($Title, $Message, $Owner) $script:Shown.Add([pscustomobject]@{ Title = $Title; Message = $Message }) }
    function script:Show-ConfirmDialog { param($Title, $Message, $Owner) $script:Confirms.Add([pscustomobject]@{ Title = $Title; Message = $Message }); $script:ConfirmAnswer }
    function script:Get-PasFilePath { param([string]$Filter, [switch]$Save) $script:FilePrompts.Add([pscustomobject]@{ Filter = $Filter; Save = [bool]$Save }); $script:PathAnswer }
    function script:Update-Library { $script:Calls.Add('Update-Library') }
    function script:Set-PasHighlighting { $script:Calls.Add('Set-PasHighlighting') }
    function script:Update-SidebarButtonTheme { $script:Calls.Add('Update-SidebarButtonTheme') }

    function script:Invoke-Handler {
        param([string]$Name, $First = $null, $Second = $null)
        $text = $script:Handler[$Name]
        if (-not $text) { throw "no handler $Name" }
        & ([scriptblock]::Create($text)) $First $Second
    }
    function script:Wait-Work {
        param([int]$Tries = 200)
        for ($i = 0; $i -lt $Tries -and $script:work; $i++) { & ([scriptblock]::Create($script:Tick)); if ($script:work) { Start-Sleep -Milliseconds 50 } }
        if ($script:work) { throw 'The worker did not finish.' }
    }

    # The worker runs against this stub module: no site, fixed answers.
    $overrides = @'
function Assert-PasConnection { param($SiteCode,$SMSProvider) if ($SiteCode -eq 'BAD') { throw 'Configuration Manager connection failed.' } }
function Resolve-PasTargets { param($Kind,$InputText) [pscustomobject]@{Targets=@([pscustomobject]@{Device='PC-11';ResourceID=11;Client=$true;Active=$true},[pscustomobject]@{Device='PC-12';ResourceID=12;Client=$false;Active=$false});Unknown=@('ghost');CollectionID='SMS00001';ResolvedAt='t'} }
function Get-PasSiteScripts { param($SMSProvider,$SiteCode) [pscustomobject]@{Name='S1';ScriptGuid='G1'},[pscustomobject]@{Name='S2';ScriptGuid='G2'} }
function Start-PasPivotRun { [CmdletBinding(SupportsShouldProcess)] param($SMSProvider,$Query,$CollectionId,$ResourceIds) [pscustomobject]@{OperationID=900;Raw=[pscustomobject]@{OperationId=900}} }
function Get-PasPivotStatus { param($SMSProvider,$OperationID) [pscustomobject]@{ResourceId=11;DeviceName='PC-11';ScriptExecutionState=1;ScriptExitCode=0;ErrorMessage='';ScriptOutput='<result moreResults="False"><e _i="0" Caption="Windows 11" /></result>'} }
'@
    $script:StubModule = New-StubModule -Path (Join-Path $TestDrive 'Stub.psm1') -Overrides $overrides
}

Describe 'Start script' {
BeforeEach {
    $script:Shown = [System.Collections.Generic.List[object]]::new()
    $script:Confirms = [System.Collections.Generic.List[object]]::new()
    $script:FilePrompts = [System.Collections.Generic.List[object]]::new()
    $script:Calls = [System.Collections.Generic.List[string]]::new()
    $script:ConfirmAnswer = $true
    $script:PathAnswer = $null
    $ui = @{}
    foreach ($n in $script:ControlNames) { $ui[$n] = New-FakeControl }
    $ui.editor | Add-Member -NotePropertyName Document -NotePropertyValue ([ICSharpCode.AvalonEdit.Document.TextDocument]::new()) -Force
    $ui.targetKind.SelectedItem = [pscustomobject]@{ Content = 'List' }
    $window = New-FakeControl
    $module = $script:StubModule
    $dataRoot = Join-Path $TestDrive ('data-' + [guid]::NewGuid().ToString('N'))
    $logPath = Join-Path $dataRoot 'Logs\test.log'
    $script:prefs = @{ SiteCode = 'MCM'; SMSProvider = 'cm01.contoso.com'; ApproveAfterSubmit = $false }
    $script:persisted = @{ SiteCode = 'MCM'; SMSProvider = 'cm01.contoso.com' }
    $script:session = [pscustomobject]@{ SchemaVersion = 1; ID = [guid]::NewGuid().ToString(); Created = [DateTime]::UtcNow.ToString('o'); Steps = @() }
    $script:rows = [Collections.Generic.List[object]]::new(); $script:states = @{}; $script:rawRecords = [Collections.Generic.List[object]]::new()
    $script:sort = $null; $script:columnOrder = @{}
    $script:targets = @(); $script:targetCollectionId = ''; $script:resolvedConnection = ''; $script:mode = 'Pivot'; $script:parameters = @{}; $script:parameterKey = ''
    $script:submitted = @{}; $script:work = $null; $script:step = $null; $script:siteScripts = @(); $script:scriptsGrid = $null
    $script:drafts = @{ Pivot = 'Disk | project Device, Name, FreeSpace'; Script = '' }
    $ui.editor.Text = 'Disk | project Device, Name, FreeSpace'
}

AfterEach {
    if ($script:work) { $script:work.Control.Stop = $true; try { $script:work.PS.Stop() } catch { $null = $_ }; try { $script:work.PS.Dispose(); $script:work.Runspace.Dispose() } catch { $null = $_ }; $script:work = $null }
}

Describe 'Show-PasError' {
    It 'puts the message in the status line and shows it in a message with its own title' {
        Show-PasError 'Something failed.'
        $ui.status.Text | Should -Be 'Something failed.'
        $script:Shown.Count | Should -Be 1
        $script:Shown[0].Message | Should -Be 'Something failed.'
        $script:Shown[0].Title | Should -Not -Be 'Pivots and Scripts'
    }
    It 'shows an error record as its message text' {
        try { throw 'record text' } catch { Show-PasError $_ }
        $script:Shown[0].Message | Should -Be 'record text'
    }
    It 'shows a null message as empty text' {
        Show-PasError $null
        $script:Shown[0].Message | Should -Be ''
    }
    It 'keeps the raw text of another error out of the window and writes it to the log file' {
        $log = Join-Path $TestDrive 'show-error.log'
        Set-PasLogPath $log
        try {
            try { throw [System.IO.IOException]::new('raw disk detail') } catch { Show-PasError $_ }
        }
        finally { Set-PasLogPath '' }
        $script:Shown[0].Message | Should -Be 'The action failed. The log file has the details.'
        $ui.status.Text | Should -Be 'The action failed. The log file has the details.'
        (Get-Content -LiteralPath $log -Raw) | Should -Match 'raw disk detail'
    }
}

Describe 'Set-PasMode' {
    It 'shows the script controls and names the view for the script mode' {
        Set-PasMode 'Script'
        $ui.heading.Text | Should -Be 'PowerShell'
        $ui.editorLabel.Text | Should -Be 'Script Draft Editor'
        $ui.btnRun.Content | Should -Be 'Run Approved Script'
        foreach ($n in 'btnSubmit', 'guidLabel', 'scriptGuid', 'btnParameters', 'btnSiteScripts') { $ui[$n].Visibility | Should -Be 'Visible' }
        $script:mode | Should -Be 'Script'
    }
    It 'hides the script controls and names the view for the pivot mode' {
        Set-PasMode 'Script'
        Set-PasMode 'Pivot'
        $ui.heading.Text | Should -Be 'CMPivot'
        $ui.editorLabel.Text | Should -Be 'Query Editor'
        $ui.btnRun.Content | Should -Be 'Run CMPivot'
        foreach ($n in 'btnSubmit', 'guidLabel', 'scriptGuid', 'btnParameters', 'btnSiteScripts') { $ui[$n].Visibility | Should -Be 'Collapsed' }
    }
    It 'keeps a separate draft for each mode' {
        $ui.editor.Text = 'query one'
        Set-PasMode 'Script'
        $ui.editor.Text | Should -Be ''
        $ui.editor.Text = 'script one'
        Set-PasMode 'Pivot'
        $ui.editor.Text | Should -Be 'query one'
        Set-PasMode 'Script'
        $ui.editor.Text | Should -Be 'script one'
    }
    It 'keeps the editor text when the mode does not change' {
        $ui.editor.Text = 'same'
        Set-PasMode 'Pivot'
        $ui.editor.Text | Should -Be 'same'
    }
    It 'refreshes the library, the highlighting and the buttons' {
        Set-PasMode 'Script'
        $script:Calls | Should -Be @('Update-Library', 'Set-PasHighlighting', 'Update-SidebarButtonTheme')
    }
    It 'switches mode when the sidebar buttons are clicked' {
        Invoke-Handler 'btnScript.Add_Click'
        $script:mode | Should -Be 'Script'
        Invoke-Handler 'btnPivot.Add_Click'
        $script:mode | Should -Be 'Pivot'
    }
}

Describe 'Update-Library' {
    BeforeEach {
        $lib = $script:RealText['Update-Library']
        $script:RunLibrary = { param($text) & { . ([scriptblock]::Create($text)); Update-Library } }
        $script:LibText = $lib
    }
    It 'lists the files of the library folder of the mode' {
        $script:mode = 'Pivot'
        & $script:RunLibrary $script:LibText
        $names = @($ui.library.ItemsSource | ForEach-Object Name)
        $names | Should -Contain 'Free disk.cmpivot'
        @($names | Where-Object { $_ -notlike '*.cmpivot' }).Count | Should -Be 0
        $script:mode = 'Script'
        & $script:RunLibrary $script:LibText
        @($ui.library.ItemsSource | ForEach-Object Name) | Should -Contain 'Uptime.ps1'
    }
    It 'filters by part of the name without regard to case' {
        $script:mode = 'Pivot'
        $ui.libraryFilter.Text = 'DISK'
        & $script:RunLibrary $script:LibText
        @($ui.library.ItemsSource | ForEach-Object BaseName) | Should -Be @('Free disk')
    }
    It 'treats filter characters as plain text: <Filter>' -ForEach @(
        @{ Filter = '*' }, @{ Filter = '[' }, @{ Filter = '.*' }, @{ Filter = '%' }
    ) {
        $script:mode = 'Pivot'
        $ui.libraryFilter.Text = $Filter
        & $script:RunLibrary $script:LibText
        @($ui.library.ItemsSource).Count | Should -Be 0
    }
    It 'lists every file for an empty filter' {
        $script:mode = 'Script'
        & $script:RunLibrary $script:LibText
        @($ui.library.ItemsSource).Count | Should -Be @(Get-ChildItem (Join-Path $script:AppRoot 'Library\Scripts') -File).Count
    }
}

Describe 'Set-PasHighlighting' {
    BeforeEach { $script:HlText = $script:RealText['Set-PasHighlighting'] }
    It 'builds a definition that AvalonEdit loads, in <Theme>' -ForEach @(@{ Theme = 'dark'; On = $true; Accent = '#72B7EB' }, @{ Theme = 'light'; On = $false; Accent = '#006CBE' }) {
        $ui.toggleTheme.IsOn = $On
        $ui.editor.SyntaxHighlighting = $null
        & { . ([scriptblock]::Create($script:HlText)); Set-PasHighlighting }
        $ui.editor.SyntaxHighlighting | Should -Not -BeNullOrEmpty
        $ui.editor.SyntaxHighlighting.Name | Should -Be 'Workbench'
        $kw = $ui.editor.SyntaxHighlighting.GetNamedColor('Keyword')
        $kw.Foreground.GetColor($null).ToString() | Should -Be ('#FF' + $Accent.Substring(1))
    }
}

Describe 'Update-PasConnectionInfo' {
    It 'shows the site and the provider values and hides the hint' {
        Update-PasConnectionInfo
        $ui.txtSiteCode.Text | Should -Be 'MCM'
        $ui.txtSmsProvider.Text | Should -Be 'cm01.contoso.com'
        $ui.connectionPair.Visibility | Should -Be 'Visible'
        $ui.connectionInfo.Visibility | Should -Be 'Collapsed'
    }
    It 'asks for the options when <Case>' -ForEach @(
        @{ Case = 'the site code is missing'; Site = ''; Provider = 'cm01' }
        @{ Case = 'the provider is missing'; Site = 'MCM'; Provider = '' }
        @{ Case = 'both are missing'; Site = ''; Provider = '' }
    ) {
        $script:prefs.SiteCode = $Site; $script:prefs.SMSProvider = $Provider
        Update-PasConnectionInfo
        $ui.connectionInfo.Text | Should -Be 'Connection not set. Open Options.'
        $ui.connectionInfo.Visibility | Should -Be 'Visible'
        $ui.connectionPair.Visibility | Should -Be 'Collapsed'
        $ui.txtSiteCode.Text | Should -Be $Site
        $ui.txtSmsProvider.Text | Should -Be $Provider
    }
}

Describe 'Get-PasRunScope and Get-PasParameterKey' {
    It 'names the collection or the device list' {
        Get-PasRunScope @{ CollectionId = 'SMS00001' } | Should -Be 'Configuration Manager receives one operation for collection SMS00001.'
        Get-PasRunScope @{ CollectionId = '' } | Should -Be 'Configuration Manager receives one operation for this device list.'
    }
    It 'hashes the editor text, so changed text gives another key' {
        $ui.editor.Text = 'a'
        $one = Get-PasParameterKey
        $ui.editor.Text = 'b'
        Get-PasParameterKey | Should -Not -Be $one
        $ui.editor.Text = 'a'
        Get-PasParameterKey | Should -Be $one
        $one | Should -Be (Get-PasHash 'a')
    }
}

Describe 'Get-PasStepState' {
    BeforeEach { $script:work = @{ Stopped = $false; HadError = $false } }
    AfterEach { $script:work = $null }
    It 'is <Expected> when <Case>' -ForEach @(
        @{ Case = 'the user stopped waiting'; Stopped = $true;  Err = $false; States = @('Response received'); Expected = 'Stopped waiting' }
        @{ Case = 'the user stopped and it also failed'; Stopped = $true; Err = $true; States = @(); Expected = 'Stopped waiting' }
        @{ Case = 'the worker failed';        Stopped = $false; Err = $true;  States = @('Response received'); Expected = 'Error' }
        @{ Case = 'every device answered';    Stopped = $false; Err = $false; States = @('Response received', 'Response received'); Expected = 'Completed' }
        @{ Case = 'there is no device';       Stopped = $false; Err = $false; States = @(); Expected = 'Completed' }
        @{ Case = 'one device has an error';  Stopped = $false; Err = $false; States = @('Response received', 'Query failed'); Expected = 'Completed with errors' }
        @{ Case = 'a device never answered';  Stopped = $false; Err = $false; States = @('Response received', 'No response within timeout'); Expected = 'Completed with errors' }
        @{ Case = 'a device is no client';    Stopped = $false; Err = $false; States = @('Not a client'); Expected = 'Completed with errors' }
    ) {
        $script:work.Stopped = $Stopped; $script:work.HadError = $Err
        $script:states = @{}
        $i = 0
        foreach ($s in $States) { $script:states[[string]$i] = [pscustomobject]@{ State = $s }; $i++ }
        Get-PasStepState | Should -Be $Expected
    }
    It 'ignores a device that has no state yet' {
        $script:states = @{ '1' = [pscustomobject]@{ Device = 'A' }; '2' = [pscustomobject]@{ State = 'Response received' } }
        Get-PasStepState | Should -Be 'Completed'
    }
}

Describe 'Refresh-PasResults' {
    It 'shows every row with every column that any row has' {
        $script:rows.Add([pscustomobject]@{ TargetDevice = 'A'; X = 1 })
        $script:rows.Add([pscustomobject]@{ TargetDevice = 'B'; Y = 2 })
        Refresh-PasResults
        $r = @($ui.results.ItemsSource)
        $r.Count | Should -Be 2
        @($r[0].PSObject.Properties.Name) | Should -Be @('TargetDevice', 'X', 'Y')
        $r[0].Y | Should -BeNullOrEmpty
        $r[1].Y | Should -Be 2
    }
    It 'shows an empty list for no rows' {
        Refresh-PasResults
        @($ui.results.ItemsSource).Count | Should -Be 0
    }
    It 'filters by text in any column without regard to case: <Filter>' -ForEach @(
        @{ Filter = 'beta'; Count = 1 }
        @{ Filter = 'ALPHA'; Count = 1 }
        @{ Filter = '42'; Count = 1 }
        @{ Filter = 'zzz'; Count = 0 }
        @{ Filter = ''; Count = 2 }
        @{ Filter = '*'; Count = 0 }
        @{ Filter = '['; Count = 0 }
    ) {
        $script:rows.Add([pscustomobject]@{ Name = 'Alpha'; N = 7 })
        $script:rows.Add([pscustomobject]@{ Name = 'Beta'; N = 42 })
        $ui.resultFilter.Text = $Filter
        Refresh-PasResults
        @($ui.results.ItemsSource).Count | Should -Be $Count
    }
    It 'sorts by the chosen column in the chosen direction' {
        foreach ($v in '10', '9', '100') { $script:rows.Add([pscustomobject]@{ V = $v }) }
        $script:sort = @{ Column = 'V'; Descending = $false }
        Refresh-PasResults
        @($ui.results.ItemsSource | ForEach-Object V) | Should -Be @('9', '10', '100')
        $script:sort = @{ Column = 'V'; Descending = $true }
        Refresh-PasResults
        @($ui.results.ItemsSource | ForEach-Object V) | Should -Be @('100', '10', '9')
    }
    It 'lists the devices sorted by name with the fixed columns' {
        $script:states = @{ '2' = [pscustomobject]@{ Device = 'B'; ResourceID = 2; State = 'Waiting'; Extra = 'x' }; '1' = [pscustomobject]@{ Device = 'A'; ResourceID = 1; Client = $true; Active = $true; State = 'Response received' } }
        Refresh-PasResults
        $d = @($ui.devices.ItemsSource)
        @($d | ForEach-Object Device) | Should -Be @('A', 'B')
        @($d[0].PSObject.Properties.Name) | Should -Be @('Device', 'ResourceID', 'Client', 'Active', 'State', 'OperationID', 'ExitCode', 'Detail')
        $d[1].Client | Should -BeNullOrEmpty
    }
    It 'lists the steps of the session' {
        $script:session.Steps = @([pscustomobject]@{ Number = 1; Mode = 'Pivot'; Started = 's'; State = 'Completed'; TargetCount = 3; ResultCount = 5; Text = 'hidden' })
        Refresh-PasResults
        $p = @($ui.pipeline.ItemsSource)
        $p.Count | Should -Be 1
        @($p[0].PSObject.Properties.Name) | Should -Be @('Number', 'Mode', 'Started', 'State', 'TargetCount', 'ResultCount')
    }
    It 'keeps a cell with a formula or markup as text' {
        $script:rows.Add([pscustomobject]@{ V = '=1+1'; W = '<b>' })
        Refresh-PasResults
        @($ui.results.ItemsSource)[0].V | Should -Be '=1+1'
    }
}

Describe 'Save-PasSession' {
    It 'writes nothing for a session without a step' {
        Save-PasSession
        Test-Path -LiteralPath $dataRoot | Should -BeFalse
    }
    It 'writes the session to a file named after its ID' {
        $script:session.Steps = @([pscustomobject]@{ Number = 1; Text = 'OS' })
        Save-PasSession
        $file = Join-Path $dataRoot ('Sessions\' + $script:session.ID + '.json')
        Test-Path -LiteralPath $file | Should -BeTrue
        $saved = [IO.File]::ReadAllText($file) | ConvertFrom-Json
        $saved.ID | Should -Be $script:session.ID
        @($saved.Steps).Count | Should -Be 1
    }
    It 'stores the live rows, devices and raw records of a running step' {
        $script:step = [pscustomobject]@{ Number = 1; Results = @(); Devices = @(); Raw = @(); ResultCount = 0 }
        $script:session.Steps = @($script:step)
        $script:work = @{ Action = 'Run' }
        $script:rows.Add([pscustomobject]@{ A = 1 }); $script:rows.Add([pscustomobject]@{ A = 2 })
        $script:states = @{ '1' = [pscustomobject]@{ Device = 'A' } }
        $script:rawRecords.Add([pscustomobject]@{ Phase = 'Submit' })
        Save-PasSession
        $script:step.ResultCount | Should -Be 2
        @($script:step.Results).Count | Should -Be 2
        @($script:step.Devices).Count | Should -Be 1
        @($script:step.Raw).Count | Should -Be 1
        $script:work = $null
    }
    It 'does not touch the step when the running work is not a run' {
        $script:step = [pscustomobject]@{ Number = 1; Results = @('keep'); Devices = @(); Raw = @(); ResultCount = 9 }
        $script:session.Steps = @($script:step)
        $script:work = @{ Action = 'Scripts' }
        $script:rows.Add([pscustomobject]@{ A = 1 })
        Save-PasSession
        $script:step.ResultCount | Should -Be 9
        $script:work = $null
    }
    It 'passes a write error up' {
        $script:session.Steps = @([pscustomobject]@{ Number = 1 })
        New-Item -ItemType File -Path $dataRoot -Force | Out-Null
        { Save-PasSession } | Should -Throw
    }
}

Describe 'Start-PasWork guards' {
    It 'refuses a second operation' {
        $script:work = @{ Action = 'Run' }
        { Start-PasWork 'Connect' } | Should -Throw '*already running*'
        $script:work = $null
    }
    It 'asks for the connection when <Case>' -ForEach @(
        @{ Case = 'the site code is missing'; Site = ''; Provider = 'cm01' }
        @{ Case = 'the provider is missing'; Site = 'MCM'; Provider = '' }
    ) {
        $script:prefs.SiteCode = $Site; $script:prefs.SMSProvider = $Provider
        { Start-PasWork 'Connect' } | Should -Throw '*Set the site code and SMS Provider*'
        $script:work | Should -BeNullOrEmpty
    }
    It 'refuses a run without targets' {
        { Start-PasWork 'Run' } | Should -Throw '*Select Resolve Targets first*'
    }
    It 'refuses a run after the connection changed' {
        $script:targets = @([pscustomobject]@{ Device = 'A'; ResourceID = 1; Client = $true })
        $script:resolvedConnection = 'OTHER|cm01.contoso.com'
        { Start-PasWork 'Run' } | Should -Throw '*Connection changed*'
    }
    It 'refuses a run with an empty editor: <Case>' -ForEach @(@{ Case = 'empty'; Text = '' }, @{ Case = 'white space'; Text = " `r`n" }) {
        $script:targets = @([pscustomobject]@{ Device = 'A'; ResourceID = 1; Client = $true })
        $script:resolvedConnection = 'MCM|cm01.contoso.com'
        $ui.editor.Text = $Text
        { Start-PasWork 'Run' } | Should -Throw '*editor is empty*'
    }
    It 'refuses a script run without a GUID: <Text>' -ForEach @(@{ Text = '' }, @{ Text = 'not a guid' }, @{ Text = '1234' }) {
        $script:targets = @([pscustomobject]@{ Device = 'A'; ResourceID = 1; Client = $true })
        $script:resolvedConnection = 'MCM|cm01.contoso.com'
        $script:mode = 'Script'; $ui.editor.Text = 'Get-Date'; $ui.scriptGuid.Text = $Text
        { Start-PasWork 'Run' } | Should -Throw '*Enter the GUID of an approved*'
    }
    It 'refuses a script that changed after it was submitted' {
        $guid = [guid]::NewGuid().ToString()
        $script:targets = @([pscustomobject]@{ Device = 'A'; ResourceID = 1; Client = $true })
        $script:resolvedConnection = 'MCM|cm01.contoso.com'
        $script:mode = 'Script'; $ui.editor.Text = 'edited'; $ui.scriptGuid.Text = $guid
        $script:submitted[$guid.ToUpperInvariant()] = Get-PasHash 'original'
        { Start-PasWork 'Run' } | Should -Throw '*draft changed after submission*'
    }
    It 'accepts a submitted script whose GUID differs only in case' {
        $guid = [guid]::NewGuid().ToString()
        $script:targets = @([pscustomobject]@{ Device = 'A'; ResourceID = 1; Client = $true })
        $script:resolvedConnection = 'MCM|cm01.contoso.com'
        $script:mode = 'Script'; $ui.editor.Text = 'same'; $ui.scriptGuid.Text = $guid.ToUpperInvariant()
        $script:submitted[$guid] = Get-PasHash 'same'
        $script:ConfirmAnswer = $false
        { Start-PasWork 'Run' } | Should -Not -Throw
        $script:Confirms.Count | Should -Be 1
    }
    It 'refuses parameters that were set for other script text' {
        $script:targets = @([pscustomobject]@{ Device = 'A'; ResourceID = 1; Client = $true })
        $script:resolvedConnection = 'MCM|cm01.contoso.com'
        $script:mode = 'Script'; $ui.editor.Text = 'Get-Date'; $ui.scriptGuid.Text = [guid]::NewGuid().ToString()
        $script:parameters = @{ A = '1' }; $script:parameterKey = Get-PasHash 'older text'
        { Start-PasWork 'Run' } | Should -Throw '*parameters were set for different script text*'
    }
}

Describe 'Start-PasWork run' {
    BeforeEach {
        $script:targets = @([pscustomobject]@{ Device = 'PC-11'; ResourceID = 11; Client = $true; Active = $true }, [pscustomobject]@{ Device = 'NC'; ResourceID = 13; Client = $false; Active = $false })
        $script:resolvedConnection = 'MCM|cm01.contoso.com'
    }
    It 'asks for the confirmation with the text, the count and the scope, and starts nothing when the user cancels' {
        $script:ConfirmAnswer = $false
        $ui.editor.Text = 'Disk | project Name'
        Start-PasWork 'Run'
        $script:Confirms.Count | Should -Be 1
        $script:Confirms[0].Title | Should -Be 'Confirm Target Snapshot'
        $script:Confirms[0].Message | Should -BeLike 'Run this CMPivot query on 2 resolved devices?*one operation for this device list*Disk | project Name'
        $script:work | Should -BeNullOrEmpty
        @($script:session.Steps).Count | Should -Be 0
        Test-Path -LiteralPath $dataRoot | Should -BeFalse
    }
    It 'names the script, the scope and the parameters of a script run' {
        $guid = [guid]::NewGuid()
        $script:mode = 'Script'; $ui.editor.Text = 'param($B,$A)'; $ui.scriptGuid.Text = $guid.ToString()
        $script:parameters = @{ B = '2'; A = '1' }; $script:parameterKey = Get-PasParameterKey
        $script:targetCollectionId = 'SMS00001'
        $script:ConfirmAnswer = $false
        Start-PasWork 'Run'
        $m = $script:Confirms[0].Message
        $m | Should -BeLike ("Run ConfigMgr script $($guid.ToString().ToUpperInvariant()) on 2 resolved devices?*collection SMS00001*Parameters:*  A = 1*  B = 2*An unsubmitted editor draft is not executed.")
    }
    It 'says so when a script run has no parameters' {
        $script:mode = 'Script'; $ui.editor.Text = 'Get-Date'; $ui.scriptGuid.Text = [guid]::NewGuid().ToString()
        $script:ConfirmAnswer = $false
        Start-PasWork 'Run'
        $script:Confirms[0].Message | Should -BeLike '*(none; the script defaults apply)*'
    }
    It 'starts the worker, records the step, saves the session first and locks the controls' {
        Start-PasWork 'Run'
        $script:work | Should -Not -BeNullOrEmpty
        $script:step.State | Should -Be 'Running'
        $script:step.Number | Should -Be 1
        $script:step.TargetCount | Should -Be 2
        $script:step.Hash | Should -Be (Get-PasHash 'Disk | project Device, Name, FreeSpace')
        Test-Path -LiteralPath (Join-Path $dataRoot ('Sessions\' + $script:session.ID + '.json')) | Should -BeTrue
        $ui.btnRun.IsEnabled | Should -BeFalse
        $ui.btnPivot.IsEnabled | Should -BeFalse
        $ui.btnStop.IsEnabled | Should -BeTrue
        $ui.status.Text | Should -Be 'Working...'
        Wait-Work
    }
    It 'launches no worker and keeps no new step when the history cannot be saved' {
        New-Item -ItemType File -Path $dataRoot -Force | Out-Null
        { Start-PasWork 'Run' } | Should -Throw
        $script:work | Should -BeNullOrEmpty
        @($script:session.Steps).Count | Should -Be 0
        $script:step | Should -BeNullOrEmpty
    }
    It 'runs to the end: rows, device states, step state, saved history and unlocked controls' {
        Start-PasWork 'Run'
        Wait-Work
        $script:step.State | Should -Be 'Completed with errors'
        $script:step.Ended | Should -Not -BeNullOrEmpty
        $script:rows.Count | Should -Be 1
        $script:rows[0].Caption | Should -Be 'Windows 11'
        $script:states['11'].State | Should -Be 'Response received'
        $script:states['11'].Client | Should -BeTrue
        $script:states['13'].State | Should -Be 'Not a client'
        $ui.status.Text | Should -Be 'Completed with errors. 1 rows; 2 device statuses. Review Devices for errors and nonresponses.'
        $ui.btnRun.IsEnabled | Should -BeTrue
        $ui.btnStop.IsEnabled | Should -BeFalse
        $saved = [IO.File]::ReadAllText((Join-Path $dataRoot ('Sessions\' + $script:session.ID + '.json'))) | ConvertFrom-Json
        @($saved.Steps)[0].State | Should -Be 'Completed with errors'
        @(@($saved.Steps)[0].Results).Count | Should -Be 1
        @($ui.results.ItemsSource).Count | Should -Be 1
        $ui.raw.Text | Should -BeLike '*Submit*'
        $script:work | Should -BeNullOrEmpty
    }
    It 'numbers the next step and resets the sort for another query' {
        Start-PasWork 'Run'; Wait-Work
        $script:sort = @{ Column = 'Caption'; Descending = $false }; $script:columnOrder = @{ Caption = 0 }
        Start-PasWork 'Run'; Wait-Work
        $script:session.Steps.Count | Should -Be 2
        $script:step.Number | Should -Be 2
        $script:sort | Should -Not -BeNullOrEmpty
        $ui.editor.Text = 'OS | project Caption'
        Start-PasWork 'Run'; Wait-Work
        $script:sort | Should -BeNullOrEmpty
        $script:columnOrder.Count | Should -Be 0
    }
    It 'stops waiting on the stop button and does not hide that the operation can still run' {
        $script:work = @{ Control = [hashtable]::Synchronized(@{ Stop = $false }); Stopped = $false }
        Invoke-Handler 'btnStop.Add_Click'
        $script:work.Control.Stop | Should -BeTrue
        $script:work.Stopped | Should -BeTrue
        $ui.status.Text | Should -BeLike '*Operations already sent may continue on clients*'
        $script:work = $null
    }
    It 'does nothing on the stop button when no work runs' {
        { Invoke-Handler 'btnStop.Add_Click' } | Should -Not -Throw
    }
    It 'refuses to close while work runs, and asks the worker to stop' {
        $script:work = @{ Control = [hashtable]::Synchronized(@{ Stop = $false }); Stopped = $false }
        $e = [pscustomobject]@{ Cancel = $false }
        Invoke-Handler 'window.Add_Closing' $null $e
        $e.Cancel | Should -BeTrue
        $script:work.Control.Stop | Should -BeTrue
        $script:work = $null
    }
}

Describe 'Start-PasWork other actions' {
    It 'connects and says so' {
        Start-PasWork 'Connect'; Wait-Work
        $ui.status.Text | Should -Be 'Connected to site MCM.'
    }
    It 'reports a failed connection in the status line' {
        $script:prefs.SiteCode = 'BAD'
        Start-PasWork 'Connect'; Wait-Work
        $ui.status.Text | Should -BeLike '*connection failed*'
        $ui.btnConnect.IsEnabled | Should -BeTrue
    }
    It 'resolves targets, keeps the snapshot and summarises it' {
        Start-PasWork 'Resolve'; Wait-Work
        $script:targets.Count | Should -Be 2
        $script:targetCollectionId | Should -Be 'SMS00001'
        $script:resolvedConnection | Should -Be 'MCM|cm01.contoso.com'
        $ui.targetSummary.Text | Should -Be 'Matched: 2 | Active: 1 | Not clients: 1 | Unknown: 1'
        $ui.status.Text | Should -Be 'Unmatched: ghost'
        $script:states.Count | Should -Be 2
    }
    It 'lists the site scripts' {
        Start-PasWork 'Scripts'; Wait-Work
        $script:siteScripts.Count | Should -Be 2
        $ui.status.Text | Should -Be '2 scripts on the site.'
    }
    It 'clears the targets when the target text or the kind changes' {
        $script:targets = @([pscustomobject]@{ ResourceID = 1 }); $script:targetCollectionId = 'SMS00001'
        Invoke-Handler 'targetInput.Add_TextChanged'
        $script:targets.Count | Should -Be 0
        $script:targetCollectionId | Should -Be ''
        $ui.targetSummary.Text | Should -Be 'Targets changed. Select Resolve Targets again.'
        $script:targets = @([pscustomobject]@{ ResourceID = 1 })
        Invoke-Handler 'targetKind.Add_SelectionChanged'
        $script:targets.Count | Should -Be 0
        $ui.targetSummary.Text | Should -Be 'Target mode changed. Select Resolve Targets again.'
    }
    It 'shows the connection error from a button instead of throwing: <Name>' -ForEach @(
        @{ Name = 'btnConnect' }, @{ Name = 'btnResolve' }, @{ Name = 'btnRun' }
    ) {
        $script:prefs.SiteCode = ''
        { Invoke-Handler "$Name.Add_Click" } | Should -Not -Throw
        $script:Shown.Count | Should -Be 1
        $script:Shown[0].Message | Should -BeLike '*Set the site code and SMS Provider*'
        $ui.status.Text | Should -BeLike '*Set the site code*'
    }
    It 'shows the target summary tab for the snapshot button' {
        Invoke-Handler 'btnTargets.Add_Click'
        $ui.resultTabs.SelectedIndex | Should -Be 1
    }
}

Describe 'Check syntax button' {
    It 'reports the parameter count of a valid script' {
        $script:mode = 'Script'; $ui.editor.Text = 'param([string]$A,[int]$B) 1'
        Invoke-Handler 'btnCheck.Add_Click'
        $ui.status.Text | Should -Be 'PowerShell syntax valid. 2 parameters.'
    }
    It 'shows the syntax error of an invalid script' {
        $script:mode = 'Script'; $ui.editor.Text = 'param([string]$A'
        Invoke-Handler 'btnCheck.Add_Click'
        $script:Shown.Count | Should -Be 1
        $ui.status.Text | Should -Not -BeNullOrEmpty
    }
    It 'tells that the site validates a CMPivot query' {
        Invoke-Handler 'btnCheck.Add_Click'
        $ui.status.Text | Should -BeLike 'CMPivot syntax is validated by Configuration Manager*'
    }
}

Describe 'Submit button' {
    It 'shows the parameter problem and asks for no confirmation: <Case>' -ForEach @(
        @{ Case = 'a switch'; Text = 'param([switch]$A)'; Pattern = '*string and integer*' }
        @{ Case = 'a quote'; Text = "param([string]`$A = ""it's"")"; Pattern = '*single quote*' }
    ) {
        $script:mode = 'Script'; $ui.editor.Text = $Text
        Invoke-Handler 'btnSubmit.Add_Click'
        $script:Confirms.Count | Should -Be 0
        $script:Shown[0].Message | Should -BeLike $Pattern
        $script:work | Should -BeNullOrEmpty
    }
    It 'asks, with the stored parameters named, and starts nothing when the user cancels' {
        $script:mode = 'Script'; $ui.editor.Text = 'param([string]$A,[int]$B) 1'
        $script:ConfirmAnswer = $false
        Invoke-Handler 'btnSubmit.Add_Click'
        $script:Confirms[0].Title | Should -Be 'Create ConfigMgr Script'
        $script:Confirms[0].Message | Should -BeLike '*Parameters stored with the script: A (String), B (Int32)'
        $script:work | Should -BeNullOrEmpty
    }
    It 'starts the submission when the user confirms' {
        $script:mode = 'Script'; $ui.editor.Text = 'Get-Date'
        Invoke-Handler 'btnSubmit.Add_Click'
        $script:work.Action | Should -Be 'Submit'
        $script:work.Control.Stop = $true
    }
}

Describe 'Export buttons' {
    BeforeEach {
        $script:out = Join-Path $TestDrive ('out-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:out | Out-Null
    }
    It 'refuses to export when there are no results: <Name>' -ForEach @(@{ Name = 'btnCsv' }, @{ Name = 'btnJson' }, @{ Name = 'btnCopy' }) {
        $ui.results.ItemsSource = @()
        Invoke-Handler "$Name.Add_Click"
        $script:Shown.Count | Should -Be 1
        $script:Shown[0].Message | Should -BeLike 'There are no results to *'
        $script:FilePrompts.Count | Should -Be 0
    }
    It 'writes the CSV with a leading apostrophe on a value that a spreadsheet would run as a formula' {
        $script:PathAnswer = Join-Path $script:out 'r.csv'
        $ui.results.ItemsSource = @(
            [pscustomobject]@{ A = '=cmd|"/c calc"!A1'; B = '+1'; C = '-2'; D = '@SUM(A1)'; E = "`tTab"; F = "`rCR"; G = 'safe'; H = 5; I = $null }
            [pscustomobject]@{ A = 'x=y'; B = ''; C = 'a-b'; D = 'name@host'; E = 'Tab'; F = 'CR'; G = "line1`nline2"; H = 6; I = 'v' })
        Invoke-Handler 'btnCsv.Add_Click'
        $script:Shown.Count | Should -Be 0
        $csv = @(Import-Csv -LiteralPath $script:PathAnswer)
        $csv.Count | Should -Be 2
        $csv[0].A | Should -Be "'=cmd|`"/c calc`"!A1"
        $csv[0].B | Should -Be "'+1"
        $csv[0].C | Should -Be "'-2"
        $csv[0].D | Should -Be "'@SUM(A1)"
        $csv[0].E | Should -Be "'`tTab"
        $csv[0].G | Should -Be 'safe'
        $csv[0].H | Should -Be '5'
        $csv[1].A | Should -Be 'x=y'
        $csv[1].C | Should -Be 'a-b'
        $csv[1].D | Should -Be 'name@host'
        $csv[1].G | Should -Be "line1`nline2"
        $script:FilePrompts[0].Save | Should -BeTrue
        $script:FilePrompts[0].Filter | Should -Be 'CSV|*.csv'
    }
    It 'writes the CSV in UTF-8 with non-ASCII text intact' {
        $script:PathAnswer = Join-Path $script:out 'u.csv'
        $text = 'caf' + [char]0xE9 + ' ' + [char]0x20AC
        $ui.results.ItemsSource = @([pscustomobject]@{ A = $text })
        Invoke-Handler 'btnCsv.Add_Click'
        @(Import-Csv -LiteralPath $script:PathAnswer -Encoding UTF8)[0].A | Should -Be $text
    }
    It 'writes nothing when the user closes the file dialog' {
        $script:PathAnswer = $null
        $ui.results.ItemsSource = @([pscustomobject]@{ A = 1 })
        Invoke-Handler 'btnCsv.Add_Click'
        Invoke-Handler 'btnJson.Add_Click'
        $script:FilePrompts.Count | Should -Be 2
        @(Get-ChildItem -LiteralPath $script:out).Count | Should -Be 0
    }
    It 'writes the JSON as an array, also for one row' {
        $script:PathAnswer = Join-Path $script:out 'r.json'
        $ui.results.ItemsSource = @([pscustomobject]@{ A = 1 })
        Invoke-Handler 'btnJson.Add_Click'
        ([IO.File]::ReadAllText($script:PathAnswer) -replace '\s', '') | Should -Be '[{"A":1}]'
    }
    It 'shows a write error instead of throwing' {
        $script:PathAnswer = Join-Path $script:out 'folder'
        New-Item -ItemType Directory -Path $script:PathAnswer | Out-Null
        $ui.results.ItemsSource = @([pscustomobject]@{ A = 1 })
        { Invoke-Handler 'btnJson.Add_Click' } | Should -Not -Throw
        $script:Shown.Count | Should -Be 1
    }
    It 'copies the rows as a PowerShell command that carries the data as Base64' {
        $script:Clip = $null
        $text = $script:Handler['btnCopy.Add_Click'].Replace('[Windows.Clipboard]::SetText(', 'Set-TestClipboard(')
        function script:Set-TestClipboard { param([string]$Text) $script:Clip = $Text }
        $hostile = "O'Brien " + [char]0x2018 + 'x' + [char]0x2019 + ' "q" $(calc)'
        $ui.results.ItemsSource = @([pscustomobject]@{ A = $hostile; B = 1 })
        & ([scriptblock]::Create($text))
        $script:Clip | Should -Match "^\[Text\.Encoding\]::UTF8\.GetString\(\[Convert\]::FromBase64String\('[A-Za-z0-9+/=]+'\)\) \| ConvertFrom-Json$"
        $script:Clip | Should -Not -Match '[\u2018\u2019'']\s*x'
        $b64 = [regex]::Match($script:Clip, "FromBase64String\('([^']+)'\)").Groups[1].Value
        $back = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) | ConvertFrom-Json
        @($back)[0].A | Should -Be $hostile
        $ui.status.Text | Should -Be '1 rows copied as PowerShell.'
    }
}

Describe 'Session buttons' {
    It 'starts a new session and clears the results' {
        $script:session.Steps = @([pscustomobject]@{ Number = 1; Text = 'x' })
        $old = $script:session.ID
        $script:rows.Add([pscustomobject]@{ A = 1 }); $script:states = @{ '1' = 1 }; $script:rawRecords.Add(1); $ui.raw.Text = 'raw'
        Invoke-Handler 'btnNewSession.Add_Click'
        $script:session.ID | Should -Not -Be $old
        @($script:session.Steps).Count | Should -Be 0
        $script:rows.Count | Should -Be 0
        $script:states.Count | Should -Be 0
        $ui.raw.Text | Should -Be ''
        Test-Path -LiteralPath (Join-Path $dataRoot "Sessions\$old.json") | Should -BeTrue
    }
    It 'saves the session to the file the user picks' {
        $script:session.Steps = @([pscustomobject]@{ Number = 1; Text = 'x' })
        $script:PathAnswer = Join-Path $TestDrive 'mysession.json'
        Invoke-Handler 'btnSaveSession.Add_Click'
        ([IO.File]::ReadAllText($script:PathAnswer) | ConvertFrom-Json).ID | Should -Be $script:session.ID
    }
    It 'opens a saved session: steps, rows, devices, mode and text' {
        $session = [pscustomobject]@{ SchemaVersion = 1; ID = [guid]::NewGuid().ToString(); Created = 'c'; Steps = @([pscustomobject]@{ Number = 1; Mode = 'Pivot'; Text = 'OS | take 1'; Results = @([pscustomobject]@{ Caption = 'W11' }); Devices = @([pscustomobject]@{ ResourceID = 7; State = 'Response received' }); Raw = @([pscustomobject]@{ Phase = 'Submit' }) }) }
        $script:PathAnswer = Join-Path $TestDrive 'open.json'
        [IO.File]::WriteAllText($script:PathAnswer, ($session | ConvertTo-Json -Depth 10))
        Invoke-Handler 'btnHistory.Add_Click'
        $script:Shown.Count | Should -Be 0
        $script:session.ID | Should -Be $session.ID
        $script:rows.Count | Should -Be 1
        $script:states['7'].State | Should -Be 'Response received'
        $ui.editor.Text | Should -Be 'OS | take 1'
        $ui.targetSummary.Text | Should -Be 'Historical session opened. Resolve fresh targets before running.'
        $script:targets.Count | Should -Be 0
    }
    It 'opens a saved session without steps' {
        $session = [pscustomobject]@{ SchemaVersion = 1; ID = [guid]::NewGuid().ToString(); Created = 'c'; Steps = @() }
        $script:PathAnswer = Join-Path $TestDrive 'empty-session.json'
        [IO.File]::WriteAllText($script:PathAnswer, ($session | ConvertTo-Json -Depth 10))
        Invoke-Handler 'btnHistory.Add_Click'
        $script:Shown.Count | Should -Be 0
        $script:rows.Count | Should -Be 0
    }
    It 'refuses a file that is not a session: <Case>' -ForEach @(
        @{ Case = 'another schema version'; Json = '{"SchemaVersion":2,"ID":"11111111-2222-3333-4444-555555555555","Steps":[]}'; Pattern = '*Unsupported session file*' }
        @{ Case = 'no ID';                  Json = '{"SchemaVersion":1,"Steps":[]}'; Pattern = '*Unsupported session file*' }
        @{ Case = 'an ID that is a path';   Json = '{"SchemaVersion":1,"ID":"..\\..\\evil","Steps":[]}'; Pattern = '*Unsupported session file*' }
        @{ Case = 'a short ID';             Json = '{"SchemaVersion":1,"ID":"abc","Steps":[]}'; Pattern = '*Unsupported session file*' }
        @{ Case = 'an object that is not JSON'; Json = 'this is not json'; Pattern = '*' }
        @{ Case = 'an empty file';          Json = ''; Pattern = '*' }
    ) {
        $keep = $script:session.ID
        $script:PathAnswer = Join-Path $TestDrive 'bad.json'
        [IO.File]::WriteAllText($script:PathAnswer, $Json)
        Invoke-Handler 'btnHistory.Add_Click'
        $script:Shown.Count | Should -Be 1
        $script:Shown[0].Message | Should -BeLike $Pattern
        $script:session.ID | Should -Be $keep
    }
    It 'does nothing when the user closes the open dialog' {
        $script:PathAnswer = $null
        Invoke-Handler 'btnHistory.Add_Click'
        $script:Shown.Count | Should -Be 0
    }
}

Describe 'Selection buttons' {
    BeforeEach {
        $script:step = [pscustomobject]@{ SiteCode = 'MCM'; Provider = 'cm01.contoso.com' }
        $ui.results.SelectedItems = @([pscustomobject]@{ TargetDevice = 'B'; TargetResourceID = 2 }, [pscustomobject]@{ TargetDevice = 'A'; TargetResourceID = 1 }, [pscustomobject]@{ TargetDevice = 'A'; TargetResourceID = 1 })
    }
    It 'turns the selected rows into targets, once per device, and switches the mode' {
        $ui.editor.Text = 'old'; $script:parameters = @{ X = 1 }; $ui.scriptGuid.Text = 'g'
        Invoke-Handler 'btnSelectionScript.Add_Click'
        $script:Shown.Count | Should -Be 0
        @($script:targets | ForEach-Object ResourceID) | Should -Be @(1, 2)
        $script:targets[0].Client | Should -BeTrue
        $script:targets[0].ResourceID | Should -BeOfType [int]
        $script:mode | Should -Be 'Script'
        $ui.editor.Text | Should -Be ''
        $script:parameters.Count | Should -Be 0
        $ui.scriptGuid.Text | Should -Be ''
        $ui.targetSummary.Text | Should -Be '2 devices selected from previous results.'
        $script:targetCollectionId | Should -Be ''
        $script:resolvedConnection | Should -Be 'MCM|cm01.contoso.com'
    }
    It 'refuses with no selection' {
        $ui.results.SelectedItems = @()
        Invoke-Handler 'btnSelectionPivot.Add_Click'
        $script:Shown[0].Message | Should -BeLike '*Select result rows first*'
    }
    It 'refuses results that belong to another connection' {
        $script:prefs.SMSProvider = 'other.contoso.com'
        Invoke-Handler 'btnSelectionPivot.Add_Click'
        $script:Shown[0].Message | Should -BeLike '*belong to another connection*'
        $script:targets.Count | Should -Be 0
    }
    It 'refuses results when no run happened' {
        $script:step = $null
        Invoke-Handler 'btnSelectionPivot.Add_Click'
        $script:Shown[0].Message | Should -BeLike '*belong to another connection*'
    }
    It 'refuses while work runs' {
        $script:work = @{ Action = 'Run' }
        Invoke-Handler 'btnSelectionPivot.Add_Click'
        $script:Shown[0].Message | Should -BeLike '*Wait for the current operation*'
        $script:work = $null
    }
}

Describe 'Open, save and import buttons' {
    It 'opens a script file in the script mode and a query file in the pivot mode' {
        $ps1 = Join-Path $TestDrive 'a.ps1'; $kql = Join-Path $TestDrive 'a.cmpivot'
        [IO.File]::WriteAllText($ps1, 'Get-Date'); [IO.File]::WriteAllText($kql, 'Disk')
        $script:PathAnswer = $ps1
        Invoke-Handler 'btnOpen.Add_Click'
        $script:mode | Should -Be 'Script'; $ui.editor.Text | Should -Be 'Get-Date'
        $script:PathAnswer = $kql
        Invoke-Handler 'btnOpen.Add_Click'
        $script:mode | Should -Be 'Pivot'; $ui.editor.Text | Should -Be 'Disk'
    }
    It 'reads a file with a byte order mark without the mark' {
        $p = Join-Path $TestDrive 'bom.ps1'
        [IO.File]::WriteAllText($p, 'Get-Date', [Text.UTF8Encoding]::new($true))
        $script:PathAnswer = $p
        Invoke-Handler 'btnOpen.Add_Click'
        $ui.editor.Text | Should -BeExactly 'Get-Date'
    }
    It 'shows an error for a file that cannot be read' {
        $script:PathAnswer = Join-Path $TestDrive 'missing.ps1'
        Invoke-Handler 'btnOpen.Add_Click'
        $script:Shown.Count | Should -Be 1
    }
    It 'saves the editor text as UTF-8 with a byte order mark and refreshes the library' {
        $p = Join-Path $TestDrive 'save.cmpivot'
        $script:PathAnswer = $p
        $ui.editor.Text = 'Disk | project Name ' + [char]0xE9
        Invoke-Handler 'btnSave.Add_Click'
        $bytes = [IO.File]::ReadAllBytes($p)
        $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
        [IO.File]::ReadAllText($p) | Should -Be ('Disk | project Name ' + [char]0xE9)
        $script:FilePrompts[0].Filter | Should -Be 'CMPivot|*.cmpivot'
        $script:Calls | Should -Contain 'Update-Library'
    }
    It 'offers the script filter in the script mode' {
        $script:mode = 'Script'
        $script:PathAnswer = Join-Path $TestDrive 'save.ps1'
        Invoke-Handler 'btnSave.Add_Click'
        $script:FilePrompts[0].Filter | Should -Be 'PowerShell|*.ps1'
    }
    It 'imports a text list as list targets' {
        $p = Join-Path $TestDrive 'list.txt'
        [IO.File]::WriteAllText($p, "A`r`nB`r`n")
        $script:PathAnswer = $p
        Invoke-Handler 'btnImport.Add_Click'
        $ui.targetKind.SelectedIndex | Should -Be 3
        $ui.targetInput.Text | Should -Be "A`r`nB`r`n"
    }
    It 'imports the Device column of a CSV' {
        $p = Join-Path $TestDrive 'list.csv'
        [IO.File]::WriteAllText($p, "Device,Other`r`nPC-1,x`r`nPC-2,y`r`n")
        $script:PathAnswer = $p
        Invoke-Handler 'btnImport.Add_Click'
        $ui.targetInput.Text | Should -Be "PC-1`r`nPC-2"
    }
    It 'refuses a CSV without a Device column' {
        $p = Join-Path $TestDrive 'nodevice.csv'
        [IO.File]::WriteAllText($p, "Name,Other`r`nPC-1,x`r`n")
        $script:PathAnswer = $p
        Invoke-Handler 'btnImport.Add_Click'
        $script:Shown[0].Message | Should -BeLike '*CSV requires a Device column*'
        $ui.targetInput.Text | Should -Be ''
    }
    It 'opens a library file on double click' {
        $ui.library.SelectedItem = Get-Item -LiteralPath (Join-Path $script:AppRoot 'Library\Pivots\Free disk.cmpivot')
        Invoke-Handler 'library.Add_MouseDoubleClick'
        $ui.editor.Text | Should -Be ([IO.File]::ReadAllText($ui.library.SelectedItem.FullName))
    }
    It 'does nothing on a double click without a selection' {
        $ui.library.SelectedItem = $null
        $ui.editor.Text = 'keep'
        Invoke-Handler 'library.Add_MouseDoubleClick'
        $ui.editor.Text | Should -Be 'keep'
    }
}

Describe 'Find and replace buttons' {
    BeforeEach { $ui.editor.Text = 'Disk | where Disk > 1 | project disk' }
    It 'selects the next match after the selection, without regard to case, and wraps' {
        $ui.findText.Text = 'disk'
        Invoke-Handler 'btnFind.Add_Click'
        $ui.editor.Selected | Should -Be @(0, 4)
        $ui.editor.SelectionStart = 0; $ui.editor.SelectionLength = 4
        Invoke-Handler 'btnFind.Add_Click'
        $ui.editor.Selected | Should -Be @(13, 4)
        $ui.editor.SelectionStart = 32; $ui.editor.SelectionLength = 4
        Invoke-Handler 'btnFind.Add_Click'
        $ui.editor.Selected | Should -Be @(0, 4)
        $ui.editor.Focused | Should -BeTrue
    }
    It 'selects nothing when the text is not found or empty' {
        $ui.findText.Text = 'zzz'
        Invoke-Handler 'btnFind.Add_Click'
        $ui.editor.Selected | Should -BeNullOrEmpty
        $ui.findText.Text = ''
        Invoke-Handler 'btnFind.Add_Click'
        $ui.editor.Selected | Should -BeNullOrEmpty
    }
    It 'replaces every match, case-sensitively, and counts them' {
        $ui.editor.Document.Text = 'Disk | where Disk > 1 | project disk'
        $ui.findText.Text = 'Disk'; $ui.replaceText.Text = 'OS'
        Invoke-Handler 'btnReplace.Add_Click'
        $ui.editor.Document.Text | Should -Be 'OS | where OS > 1 | project disk'
        $ui.status.Text | Should -Be '2 replacements.'
    }
    It 'replaces with an empty text and with a longer text' {
        $ui.editor.Document.Text = 'aXbXc'
        $ui.findText.Text = 'X'; $ui.replaceText.Text = ''
        Invoke-Handler 'btnReplace.Add_Click'
        $ui.editor.Document.Text | Should -Be 'abc'
        $ui.editor.Document.Text = 'aXbXc'
        $ui.replaceText.Text = 'XXX'
        Invoke-Handler 'btnReplace.Add_Click'
        $ui.editor.Document.Text | Should -Be 'aXXXbXXXc'
    }
    It 'does not loop on a replacement that contains the find text' {
        $ui.editor.Document.Text = 'aa'
        $ui.findText.Text = 'a'; $ui.replaceText.Text = 'aa'
        Invoke-Handler 'btnReplace.Add_Click'
        $ui.editor.Document.Text | Should -Be 'aaaa'
    }
    It 'changes nothing for an empty find text or no match' {
        $ui.editor.Document.Text = 'abc'
        $ui.findText.Text = ''; $ui.replaceText.Text = 'x'
        Invoke-Handler 'btnReplace.Add_Click'
        $ui.editor.Document.Text | Should -Be 'abc'
        $ui.findText.Text = 'q'
        Invoke-Handler 'btnReplace.Add_Click'
        $ui.editor.Document.Text | Should -Be 'abc'
        $ui.status.Text | Should -Be '0 replacements.'
    }
}

Describe 'Result grid handlers' {
    It 'sorts by the clicked column and flips the direction' {
        $e = [pscustomobject]@{ Handled = $false; Column = [pscustomobject]@{ SortMemberPath = 'V'; SortDirection = $null } }
        Invoke-Handler 'results.Add_Sorting' $null $e
        $e.Handled | Should -BeTrue
        $script:sort.Column | Should -Be 'V'
        $script:sort.Descending | Should -BeFalse
        $e.Column.SortDirection = 'Ascending'
        Invoke-Handler 'results.Add_Sorting' $null $e
        $script:sort.Descending | Should -BeTrue
    }
    It 'remembers the display order of the columns by name' {
        $ui.results | Add-Member -NotePropertyName Columns -NotePropertyValue @([pscustomobject]@{ Header = 'B'; DisplayIndex = 0 }, [pscustomobject]@{ Header = 'A'; DisplayIndex = 1 }) -Force
        Invoke-Handler 'results.Add_ColumnReordered'
        $script:columnOrder['B'] | Should -Be 0
        $script:columnOrder['A'] | Should -Be 1
    }
}

Describe 'Timer tick' {
    BeforeEach {
        $queue = [Collections.Concurrent.ConcurrentQueue[object]]::new()
        $ps = [PowerShell]::Create()
        $script:work = @{ PS = $ps; Runspace = $null; Handle = [pscustomobject]@{ IsCompleted = $false }; Queue = $queue; Control = @{ Stop = $false }; Action = 'Scripts'; Text = ''; HadError = $false; Stopped = $false }
        $script:TickPs = $ps
    }
    AfterEach { $script:TickPs.Dispose() }
    It 'does nothing without work' {
        $script:work = $null
        { & ([scriptblock]::Create($script:Tick)) } | Should -Not -Throw
    }
    It 'applies each kind of event to the window state' {
        $q = $script:work.Queue
        $q.Enqueue([pscustomobject]@{ Kind = 'Targets'; Value = [pscustomobject]@{ Targets = @([pscustomobject]@{ Device = 'A'; ResourceID = 1; Client = $true; Active = $true }); Unknown = @('x', 'y'); CollectionID = 'SMS00001' } })
        $q.Enqueue([pscustomobject]@{ Kind = 'Row'; Value = [pscustomobject]@{ Caption = 'W11' } })
        $q.Enqueue([pscustomobject]@{ Kind = 'Device'; Value = [pscustomobject]@{ Device = 'A'; ResourceID = 1; State = 'Waiting' } })
        $q.Enqueue([pscustomobject]@{ Kind = 'Raw'; Value = [pscustomobject]@{ Device = 'A'; Phase = 'Result'; Response = 'r' } })
        $q.Enqueue([pscustomobject]@{ Kind = 'ScriptChanged'; Value = [pscustomobject]@{ ScriptGuid = 'G'; State = 'Approved' } })
        & ([scriptblock]::Create($script:Tick))
        $script:targets.Count | Should -Be 1
        $script:targetCollectionId | Should -Be 'SMS00001'
        $script:rows.Count | Should -Be 1
        $script:states['1'].State | Should -Be 'Waiting'
        $script:states['1'].Client | Should -BeTrue
        $script:states['1'].Active | Should -BeTrue
        $script:rawRecords.Count | Should -Be 1
        $ui.raw.Text | Should -Match '"Phase":\s+"Result"'
        $ui.status.Text | Should -Be 'Script G: Approved.'
        $ui.targetSummary.Text | Should -Be 'Matched: 1 | Active: 1 | Not clients: 0 | Unknown: 2'
    }
    It 'shows the submitted script: GUID, hash and status text' {
        $script:work.Queue.Enqueue([pscustomobject]@{ Kind = 'Submitted'; Value = [pscustomobject]@{ Guid = 'GUID-1'; Hash = 'h1'; Parameters = @('A'); Approved = $true; ApprovalError = '' } })
        & ([scriptblock]::Create($script:Tick))
        $ui.scriptGuid.Text | Should -Be 'GUID-1'
        $script:submitted['GUID-1'] | Should -Be 'h1'
        $ui.status.Text | Should -Be 'Script GUID-1 created with parameters A. Approved.'
    }
    It 'marks the work as failed on an error event and shows the message' {
        $script:work.Queue.Enqueue([pscustomobject]@{ Kind = 'Error'; Value = 'It broke.' })
        & ([scriptblock]::Create($script:Tick))
        $script:work.HadError | Should -BeTrue
        $ui.status.Text | Should -Be 'It broke.'
    }
    It 'shows a raw record that cannot be serialized as a message instead of failing' {
        $bad = [pscustomobject]@{ Device = 'A'; Phase = 'Result' }
        $bad | Add-Member -MemberType ScriptProperty -Name Boom -Value { throw 'cannot read' }
        $script:work.Queue.Enqueue([pscustomobject]@{ Kind = 'Raw'; Value = $bad })
        { & ([scriptblock]::Create($script:Tick)) } | Should -Not -Throw
        $script:rawRecords.Count | Should -Be 1
        $ui.raw.Text | Should -Not -Match 'cannot read'
    }
    It 'ignores an event of a kind it does not know' {
        $script:work.Queue.Enqueue([pscustomobject]@{ Kind = 'Mystery'; Value = 1 })
        { & ([scriptblock]::Create($script:Tick)) } | Should -Not -Throw
    }
    It 'keeps the work while the worker has not finished' {
        & ([scriptblock]::Create($script:Tick))
        $script:work | Should -Not -BeNullOrEmpty
    }
}
}
