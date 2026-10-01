<#
.SYNOPSIS
    Main window of Pivots and Scripts, a Configuration Manager workbench for CMPivot queries and approved Run Scripts.

.NOTES
    Version    : 2026.10.01.0001
    Requires   : Windows PowerShell 5.1, .NET Framework 4.8, Configuration Manager console
#>
param([string]$SiteCode='', [string]$SMSProvider='', [switch]$SmokeTest)
$ErrorActionPreference='Stop'
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Launch with Windows PowerShell -STA -File start-pivotsandscripts.ps1.' }
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms
foreach($dll in @('Microsoft.Xaml.Behaviors.dll','ControlzEx.dll','MahApps.Metro.dll','ICSharpCode.AvalonEdit.dll')) { [Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot ('Lib\'+$dll))) | Out-Null }
$module=Join-Path $PSScriptRoot 'Module\PivotsAndScripts.psm1'
Import-Module $module -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'Lib\SuiteCommon\SuiteCommon.psd1') -DisableNameChecking
$dataRoot=if($SmokeTest){Join-Path ([IO.Path]::GetTempPath()) ('PivotsAndScripts-smoke-'+[guid]::NewGuid().ToString('N'))}else{Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'SignalRidgeLabs\PivotsAndScripts'}
$prefsPath=Join-Path $dataRoot 'preferences.json'
$script:session=[pscustomobject]@{SchemaVersion=1;ID=[guid]::NewGuid().ToString();Created=[DateTime]::UtcNow.ToString('o');Steps=@()}
$script:rows=[Collections.Generic.List[object]]::new();$script:states=@{};$script:rawRecords=[Collections.Generic.List[object]]::new()
$script:sort=$null;$script:columnOrder=@{}
$script:targets=@();$script:resolvedConnection='';$script:mode='Pivot';$script:parameters=@{};$script:parameterKey='';$script:submitted=@{};$script:work=$null;$script:step=$null;$script:siteScripts=@();$script:scriptsGrid=$null
$script:drafts=@{Pivot='Disk | project Device, Name, FreeSpace';Script=''}
$reader=[Xml.XmlNodeReader]::new([xml][IO.File]::ReadAllText((Join-Path $PSScriptRoot 'MainWindow.xaml')))
$window=[Windows.Markup.XamlReader]::Load($reader)
$ui=@{}
foreach($name in @('btnPivot','btnScript','btnHistory','toggleTheme','txtThemeLabel','library','libraryFilter','btnOpen','btnSave','btnSaveSession','btnNewSession','heading','connectionInfo','btnOptions','btnSiteScripts','btnConnect','targetKind','targetInput','btnImport','btnResolve','targetSummary','btnTargets','editor','editorLabel','editorPosition','btnCheck','btnFind','findText','replaceText','btnReplace','btnRun','btnStop','btnSubmit','guidLabel','scriptGuid','btnParameters','resultFilter','btnCsv','btnJson','btnCopy','btnGrid','btnSelectionScript','btnSelectionPivot','results','devices','raw','pipeline','resultTabs','status')) { $ui[$name]=$window.FindName($name) }
$script:prefs=Read-SuiteSettings -Path $prefsPath -Defaults @{SiteCode='';SMSProvider='';ApproveAfterSubmit=$false}
# The suite launcher hands its site code and provider to each tool it starts.
# A value saved in this tool wins; the launcher value fills an empty one; command-line values override both for this session only.
if(-not $script:prefs.SiteCode -and $env:SUITE_CM_SITECODE){$script:prefs.SiteCode=[string]$env:SUITE_CM_SITECODE}
if(-not $script:prefs.SMSProvider -and $env:SUITE_CM_PROVIDER){$script:prefs.SMSProvider=[string]$env:SUITE_CM_PROVIDER}
$script:prefs.SiteCode=([string]$script:prefs.SiteCode).Trim().ToUpperInvariant();$script:prefs.SMSProvider=([string]$script:prefs.SMSProvider).Trim()
$script:persisted=@{SiteCode=$script:prefs.SiteCode;SMSProvider=$script:prefs.SMSProvider}
if($SiteCode){$script:prefs.SiteCode=$SiteCode.Trim().ToUpperInvariant()}
if($SMSProvider){$script:prefs.SMSProvider=$SMSProvider.Trim()}
Initialize-SuiteTheme -Window $window -IsDarkGetter { $ui.toggleTheme.IsOn } -ActiveViewGetter {$script:mode} -ViewButtons @(@{Name='Pivot';Button=$ui.btnPivot},@{Name='Script';Button=$ui.btnScript}) -WorkflowButtons @($ui.btnPivot,$ui.btnScript) -OptionsButtons @($ui.btnHistory,$ui.btnOptions)
[void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($window,'Dark.Steel')
Install-TitleBarDragFallback -Window $window
function Show-PasError { param($Message) $ui.status.Text=[string]$Message; Show-ThemedMessage -Title 'Pivots and Scripts' -Message ([string]$Message) -Owner $window }
function Save-PasPreview {
    param([string]$Name)
    $window.UpdateLayout()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($window)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream=[IO.File]::Create((Join-Path $PSScriptRoot ('work\'+$Name+'.png')))
    try{$encoder.Save($stream)}finally{$stream.Dispose()}
}
function Update-Library {
    $folder=if($script:mode -eq 'Pivot'){'Pivots'}else{'Scripts'}
    $items=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot ('Library\'+$folder)) -File | Where-Object { $_.BaseName.IndexOf($ui.libraryFilter.Text,[StringComparison]::OrdinalIgnoreCase) -ge 0 })
    $ui.library.ItemsSource=$items
}
function Set-PasHighlighting {
    $accent=if($ui.toggleTheme.IsOn){'#72B7EB'}else{'#006CBE'}
    $comment=if($ui.toggleTheme.IsOn){'#B0B0B0'}else{'#595959'}
    $definition=@"
<SyntaxDefinition name="Workbench" xmlns="http://icsharpcode.net/sharpdevelop/syntaxdefinition/2008">
 <Color name="Keyword" foreground="$accent" fontWeight="bold"/><Color name="Comment" foreground="$comment"/>
 <RuleSet><Span color="Comment" begin="\#"/><Span color="Comment" begin="//"/>
 <Span color="Keyword" begin="&quot;" end="&quot;"/><Span color="Keyword" begin="'" end="'"/>
 <Keywords color="Keyword"><Word>param</Word><Word>function</Word><Word>if</Word><Word>else</Word><Word>foreach</Word><Word>try</Word><Word>catch</Word><Word>finally</Word><Word>return</Word><Word>where</Word><Word>project</Word><Word>summarize</Word><Word>count</Word><Word>join</Word><Word>order</Word><Word>by</Word><Word>take</Word><Word>distinct</Word><Word>Disk</Word><Word>OS</Word><Word>Bios</Word><Word>User</Word><Word>Service</Word><Word>Process</Word><Word>InstalledSoftware</Word></Keywords>
 </RuleSet>
</SyntaxDefinition>
"@
    $xmlReader=[Xml.XmlReader]::Create([IO.StringReader]::new($definition))
    try{$ui.editor.SyntaxHighlighting=[ICSharpCode.AvalonEdit.Highlighting.Xshd.HighlightingLoader]::Load($xmlReader,[ICSharpCode.AvalonEdit.Highlighting.HighlightingManager]::Instance)}finally{$xmlReader.Dispose()}
}
function Set-PasMode {
    param([string]$Mode)
    if($Mode -ne $script:mode){$script:drafts[$script:mode]=$ui.editor.Text;$ui.editor.Text=$script:drafts[$Mode]}
    $script:mode=$Mode
    $scriptView=$Mode -eq 'Script'
    $ui.heading.Text=if($scriptView){'PowerShell'}else{'CMPivot'}
    $ui.editorLabel.Text=if($scriptView){'Script draft editor'}else{'Query editor'}
    $ui.btnRun.Content=if($scriptView){'Run approved script'}else{'Run CMPivot'}
    foreach($name in @('btnSubmit','guidLabel','scriptGuid','btnParameters','btnSiteScripts')) { $ui[$name].Visibility=if($scriptView){'Visible'}else{'Collapsed'} }
    Update-Library
    Set-PasHighlighting
    Update-SidebarButtonTheme
}
function Get-PasFilePath {
    param([string]$Filter,[switch]$Save)
    $dlg=if($Save){[Microsoft.Win32.SaveFileDialog]::new()}else{[Microsoft.Win32.OpenFileDialog]::new()}
    $dlg.Filter=$Filter
    if($dlg.ShowDialog($window)){return $dlg.FileName}
}
function Refresh-PasResults {
    $needle=$ui.resultFilter.Text
    $columns=@($script:rows | ForEach-Object {$_.PSObject.Properties.Name} | Select-Object -Unique)
    $table=@(foreach($row in $script:rows){$record=[ordered]@{};foreach($column in $columns){$record[$column]=$row.PSObject.Properties[$column].Value};[pscustomobject]$record})
    $visible=@($table | Where-Object {
        -not $needle -or (($_.PSObject.Properties.Value | ForEach-Object {[string]$_}) -join ' ').IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0
    })
    if($script:sort){$visible=@(Sort-PasRows -Rows $visible -Property $script:sort.Column -Descending:$script:sort.Descending)}
    $ui.results.ItemsSource=$visible
    $deviceColumns=@('Device','ResourceID','Client','Active','State','OperationID','ExitCode','Detail')
    $ui.devices.ItemsSource=@($script:states.Values | Sort-Object Device | ForEach-Object {$item=$_;$record=[ordered]@{};foreach($column in $deviceColumns){$record[$column]=if($item.PSObject.Properties[$column]){$item.$column}else{$null}};[pscustomobject]$record})
    $ui.pipeline.ItemsSource=@($script:session.Steps | Select-Object Number,Mode,Started,State,TargetCount,ResultCount)
}
function Save-PasSession {
    if(-not @($script:session.Steps).Count){return}
    if($script:step -and $script:work -and $script:work.Action -eq 'Run'){$script:step.Results=@($script:rows);$script:step.Devices=@($script:states.Values);$script:step.Raw=@($script:rawRecords);$script:step.ResultCount=$script:rows.Count}
    Write-PasJson -Path (Join-Path $dataRoot ('Sessions\'+$script:session.ID+'.json')) -Value $script:session
}
function Update-PasConnectionInfo { $ui.connectionInfo.Text=if($script:prefs.SiteCode -and $script:prefs.SMSProvider){'Site '+$script:prefs.SiteCode+' on '+$script:prefs.SMSProvider}else{'Connection not set. Open Options.'} }
function Get-PasParameterKey { Get-PasHash $ui.editor.Text }
function Get-PasStepState {
    if($script:work.Stopped){return 'Stopped waiting'}
    if($script:work.HadError){return 'Error'}
    $bad=@($script:states.Values|Where-Object{$_.PSObject.Properties['State'] -and $_.State -notin @('Response received')})
    if($bad.Count){'Completed with errors'}else{'Completed'}
}
function Start-PasWork {
    param([string]$Action,[hashtable]$Extra=@{})
    if($script:work){throw 'An operation is already running.'}
    $request=@{Module=$module;SiteCode=$script:prefs.SiteCode;Provider=$script:prefs.SMSProvider;Action=$Action;Kind=[string]$ui.targetKind.SelectedItem.Content;InputText=$ui.targetInput.Text;Mode=$script:mode;Text=$ui.editor.Text;Targets=@($script:targets);ScriptGuid=$ui.scriptGuid.Text;Parameters=$script:parameters.Clone();TimeoutSeconds=300;AutoApprove=[bool]$script:prefs.ApproveAfterSubmit;Comment=''}
    foreach($key in $Extra.Keys){$request[$key]=$Extra[$key]}
    if(-not $request.SiteCode -or -not $request.Provider){throw 'Set the site code and SMS Provider in Options > Connection.'}
    if($Action -eq 'Run'){
        if(-not $request.Targets.Count){throw 'Resolve targets first.'}
        if($script:resolvedConnection -ne ($request.SiteCode+'|'+$request.Provider)){throw 'Connection changed. Resolve targets again.'}
        if([string]::IsNullOrWhiteSpace($request.Text)){throw 'The editor is empty.'}
        if($script:mode -eq 'Script'){
            $guid=[guid]::Empty
            if(-not [guid]::TryParse($request.ScriptGuid,[ref]$guid)){throw 'Enter the GUID of an approved ConfigMgr script, or submit this draft first.'}
            if($script:submitted.ContainsKey($guid.ToString()) -and $script:submitted[$guid.ToString()] -ne (Get-PasHash $request.Text)){throw 'The draft changed after submission. Submit the edited script and obtain approval.'}
            if($request.Parameters.Count -and $script:parameterKey -ne (Get-PasParameterKey)){throw 'The parameters were set for different script text or another script GUID. Open Parameters again.'}
            $parameterText=if($request.Parameters.Count){($request.Parameters.Keys|Sort-Object|ForEach-Object{'  {0} = {1}' -f $_,$request.Parameters[$_]}) -join "`n"}else{'  (none; the script defaults apply)'}
            $message="Run ConfigMgr script $($guid.ToString().ToUpperInvariant()) on $($request.Targets.Count) resolved devices?`n`nParameters:`n$parameterText`n`nConfigMgr executes the approved site script identified by this GUID. An unsubmitted editor draft is not executed."
        } else {$message="Run this CMPivot query on $($request.Targets.Count) resolved devices?`n`n$($request.Text)"}
        if(-not (Show-ConfirmDialog -Title 'Confirm target snapshot' -Message $message -Owner $window)){return}
        # Column order and sort apply to one query; another query has other columns.
        if(-not $script:step -or $script:step.Text -ne $request.Text){$script:columnOrder=@{};$script:sort=$null}
        $script:rows.Clear();$script:states=New-PasDeviceTable $request.Targets;$script:rawRecords.Clear();$ui.raw.Clear()
        $script:step=[pscustomobject]@{Number=$script:session.Steps.Count+1;Mode=$script:mode;Started=[DateTime]::UtcNow.ToString('o');Ended=$null;State='Running';TargetCount=$request.Targets.Count;ResultCount=0;Text=$request.Text;Hash=(Get-PasHash $request.Text);SiteCode=$request.SiteCode;Provider=$request.Provider;User=[Security.Principal.WindowsIdentity]::GetCurrent().Name;Targets=$request.Targets;Parameters=$request.Parameters;ScriptGuid=$request.ScriptGuid;Results=@();Devices=@();Raw=@()}
        $script:session.Steps+= $script:step
        Save-PasSession # Require history to be writable before submitting any operation.
    }
    $queue=[Collections.Concurrent.ConcurrentQueue[object]]::new();$control=[hashtable]::Synchronized(@{Stop=$false})
    $rs=[RunspaceFactory]::CreateRunspace();$rs.Open()
    $ps=[PowerShell]::Create();$ps.Runspace=$rs
    [void]$ps.AddScript([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Module\Execute.ps1'))).AddArgument($request).AddArgument($queue).AddArgument($control)
    $script:work=@{PS=$ps;Runspace=$rs;Handle=$ps.BeginInvoke();Queue=$queue;Control=$control;Action=$Action;Text=$request.Text;HadError=$false;Stopped=$false}
    foreach($name in @('btnRun','btnResolve','btnConnect','btnSubmit','btnHistory','btnNewSession','btnOptions','btnSiteScripts','targetInput','targetKind','btnImport','btnPivot','btnScript','btnOpen','library','editor','scriptGuid','btnParameters')){$ui[$name].IsEnabled=$false}
    $ui.btnStop.IsEnabled=$true;$ui.status.Text='Working...';Refresh-PasResults
}
$timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(200)
$timer.Add_Tick({
    if(-not $script:work){return}
    # Read completion before draining: events queued after the last drain are otherwise lost.
    $completed=$script:work.Handle.IsCompleted
    $item=$null;$changed=$false
    while($script:work.Queue.TryDequeue([ref]$item)){
        switch($item.Kind){
            'Targets' {$script:targets=@($item.Value.Targets);$script:resolvedConnection=$script:prefs.SiteCode+'|'+$script:prefs.SMSProvider;$ui.targetSummary.Text=('Matched: {0} | Active: {1} | Not clients: {2} | Unknown: {3}' -f $script:targets.Count,@($script:targets|Where-Object Active).Count,@($script:targets|Where-Object {-not $_.Client}).Count,@($item.Value.Unknown).Count);$ui.status.Text=if(@($item.Value.Unknown).Count){'Unmatched: '+($item.Value.Unknown -join ', ')}else{'Target snapshot ready.'};$script:states=New-PasDeviceTable $script:targets;$changed=$true}
            'Submitted' {$ui.scriptGuid.Text=$item.Value.Guid;$script:submitted[$item.Value.Guid]=$item.Value.Hash;$ui.status.Text=Get-PasSubmittedMessage -Guid $item.Value.Guid -Parameters $item.Value.Parameters -Approved ([bool]$item.Value.Approved) -ApprovalError ([string]$item.Value.ApprovalError)}
            'Scripts' {$script:siteScripts=@($item.Value);if($script:scriptsGrid){$script:scriptsGrid.ItemsSource=$script:siteScripts};$ui.status.Text=[string]$script:siteScripts.Count+' scripts on the site.'}
            'ScriptChanged' {$ui.status.Text='Script '+$item.Value.ScriptGuid+': '+$item.Value.State+'.'}
            'Row' {$script:rows.Add($item.Value);$changed=$true}
            'Device' {$previous=$script:states[[string]$item.Value.ResourceID];$next=$item.Value;if($previous -and $previous.PSObject.Properties['Client']){$next|Add-Member -NotePropertyName Client -NotePropertyValue $previous.Client -Force;$next|Add-Member -NotePropertyName Active -NotePropertyValue $previous.Active -Force};$script:states[[string]$next.ResourceID]=$next;$changed=$true}
            'Raw' {$script:rawRecords.Add($item.Value);try{$ui.raw.AppendText((ConvertTo-Json -InputObject $item.Value -Depth 20)+"`r`n")}catch{$ui.raw.AppendText("Raw record for $($item.Value.Device) could not be shown: $($_.Exception.Message)`r`n")}}
            'Notice' {$ui.status.Text=[string]$item.Value}
            'Error' {$script:work.HadError=$true;$ui.status.Text=[string]$item.Value}
        }
    }
    if($changed){Refresh-PasResults}
    if($completed){
        try {$null=$script:work.PS.EndInvoke($script:work.Handle);$streamError=Get-PasWorkerError $script:work.PS;if($streamError){$script:work.HadError=$true;$ui.status.Text=$streamError}}
        catch {$script:work.HadError=$true;$ui.status.Text=$_.Exception.Message}
        if($script:work.Action -eq 'Run'){
            $script:step.State=Get-PasStepState;$script:step.Ended=[DateTime]::UtcNow.ToString('o')
            try {Save-PasSession} catch {$ui.status.Text='History save failed: '+$_.Exception.Message}
            if(-not $script:work.HadError){$ui.status.Text=('{0}. {1} rows; {2} device statuses. Review Devices for errors and nonresponses.' -f $script:step.State,$script:rows.Count,$script:states.Count)}
        }
        $script:work.PS.Dispose();$script:work.Runspace.Dispose();$script:work=$null
        foreach($name in @('btnRun','btnResolve','btnConnect','btnSubmit','btnHistory','btnNewSession','btnOptions','btnSiteScripts','targetInput','targetKind','btnImport','btnPivot','btnScript','btnOpen','library','editor','scriptGuid','btnParameters')){$ui[$name].IsEnabled=$true}
        $ui.btnStop.IsEnabled=$false;Refresh-PasResults
    }
})
$ui.btnPivot.Add_Click({Set-PasMode 'Pivot'})
$ui.btnScript.Add_Click({Set-PasMode 'Script'})
$ui.libraryFilter.Add_TextChanged({Update-Library})
$ui.library.Add_MouseDoubleClick({if($ui.library.SelectedItem){$ui.editor.Text=[IO.File]::ReadAllText($ui.library.SelectedItem.FullName)}})
$ui.editor.TextArea.Caret.Add_PositionChanged({$ui.editorPosition.Text='Ln '+$ui.editor.TextArea.Caret.Line+', Col '+$ui.editor.TextArea.Caret.Column})
$ui.btnFind.Add_Click({if($ui.findText.Text){$start=$ui.editor.SelectionStart+$ui.editor.SelectionLength;$index=$ui.editor.Text.IndexOf($ui.findText.Text,$start,[StringComparison]::OrdinalIgnoreCase);if($index -lt 0){$index=$ui.editor.Text.IndexOf($ui.findText.Text,[StringComparison]::OrdinalIgnoreCase)};if($index -ge 0){$ui.editor.Select($index,$ui.findText.Text.Length);$ui.editor.Focus()|Out-Null}}})
$ui.btnReplace.Add_Click({if($ui.findText.Text){
    # Document edits keep the undo stack; assigning Text clears it.
    $document=$ui.editor.Document;$needle=$ui.findText.Text;$offsets=[Collections.Generic.List[int]]::new();$index=$document.Text.IndexOf($needle,[StringComparison]::Ordinal)
    while($index -ge 0){$offsets.Add($index);$index=$document.Text.IndexOf($needle,$index+$needle.Length,[StringComparison]::Ordinal)}
    $document.BeginUpdate();try{for($i=$offsets.Count-1;$i -ge 0;$i--){$document.Replace($offsets[$i],$needle.Length,$ui.replaceText.Text)}}finally{$document.EndUpdate()}
    $ui.status.Text=[string]$offsets.Count+' replacements.'
}})
$ui.editor.Options.HighlightCurrentLine=$false
$ui.editor.Add_PreviewKeyDown({param($sender,$e)
    if($e.Key -eq 'Space' -and ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control)){
        $menu=[Windows.Controls.ContextMenu]::new()
        $words=if($script:mode -eq 'Pivot'){@('Bios','Disk','OS','User','Service','Process','InstalledSoftware','where','project','summarize','count()','distinct','take','order by')}else{@('param()','Get-CimInstance','Get-Service','Select-Object','Where-Object','ConvertTo-Json -Compress','foreach','try','catch','[pscustomobject]')}
        foreach($word in $words){$item=[Windows.Controls.MenuItem]::new();$item.Header=$word;$item.Add_Click({param($sender,$e) $ui.editor.Document.Insert($ui.editor.CaretOffset,[string]$sender.Header)});$menu.Items.Add($item)|Out-Null}
        $menu.PlacementTarget=$ui.editor;$menu.IsOpen=$true;$e.Handled=$true
    }
})
$ui.btnCheck.Add_Click({try{if($script:mode -eq 'Script'){$params=@(Get-PasParameters $ui.editor.Text);$ui.status.Text='PowerShell syntax valid. '+$params.Count+' parameters.'}else{$ui.status.Text='CMPivot syntax is validated by Configuration Manager at submission. Ctrl+Space shows starter entities and operators.'}}catch{Show-PasError $_}})
$ui.btnOpen.Add_Click({try{$path=Get-PasFilePath 'Queries and scripts|*.cmpivot;*.kql;*.ps1|All files|*.*';if($path){Set-PasMode $(if([IO.Path]::GetExtension($path) -eq '.ps1'){'Script'}else{'Pivot'});$ui.editor.Text=[IO.File]::ReadAllText($path)}}catch{Show-PasError $_}})
$ui.btnSave.Add_Click({try{$filter=if($script:mode -eq 'Script'){'PowerShell|*.ps1'}else{'CMPivot|*.cmpivot'};$path=Get-PasFilePath $filter -Save;if($path){[IO.File]::WriteAllText($path,$ui.editor.Text,[Text.UTF8Encoding]::new($true));Update-Library}}catch{Show-PasError $_}})
$ui.btnConnect.Add_Click({try{Start-PasWork 'Connect'}catch{Show-PasError $_}})
$ui.btnResolve.Add_Click({try{Start-PasWork 'Resolve'}catch{Show-PasError $_}})
$ui.targetInput.Add_TextChanged({$script:targets=@();$ui.targetSummary.Text='Targets changed. Resolve again.'})
$ui.targetKind.Add_SelectionChanged({$script:targets=@();$ui.targetSummary.Text='Target mode changed. Resolve again.'})
$ui.btnTargets.Add_Click({$ui.resultTabs.SelectedIndex=1})
$ui.btnImport.Add_Click({try{$path=Get-PasFilePath 'Device lists|*.txt;*.csv';if($path){$text=if([IO.Path]::GetExtension($path) -eq '.csv'){$csv=@(Import-Csv -LiteralPath $path);if($csv.Count -and -not $csv[0].PSObject.Properties['Device']){throw 'CSV requires a Device column.'};($csv.Device -join "`r`n")}else{[IO.File]::ReadAllText($path)};$ui.targetKind.SelectedIndex=3;$ui.targetInput.Text=$text}}catch{Show-PasError $_}})
$ui.btnRun.Add_Click({try{Start-PasWork 'Run'}catch{Show-PasError $_}})
$ui.btnStop.Add_Click({if($script:work){$script:work.Control.Stop=$true;$script:work.Stopped=$true;$ui.status.Text='Stopping local waiting. Operations already sent may continue on clients.'}})
$ui.btnSubmit.Add_Click({try{$params=@(Get-PasParameters $ui.editor.Text);Assert-PasScriptParameters $params;$names=if($params.Count){"`n`nParameters stored with the script: "+(($params|ForEach-Object{'{0} ({1})' -f $_.Name,$_.SiteType.Split('.')[-1]}) -join ', ')}else{''};if(Show-ConfirmDialog -Title 'Create ConfigMgr script' -Message ("Create a managed script from the editor text? It will require the approval configured by your site."+$names) -Owner $window){Start-PasWork 'Submit'}}catch{Show-PasError $_}})
. (Join-Path $PSScriptRoot 'Module\ParameterDialog.ps1')
$ui.btnParameters.Add_Click({try{Show-PasParameterDialog}catch{Show-PasError $_}})
. (Join-Path $PSScriptRoot 'Module\OptionsDialog.ps1')
. (Join-Path $PSScriptRoot 'Module\ScriptsDialog.ps1')
$ui.btnOptions.Add_Click({try{Show-PasOptionsDialog}catch{Show-PasError $_}})
$ui.btnSiteScripts.Add_Click({try{Show-PasScriptsDialog}catch{Show-PasError $_}})
$ui.resultFilter.Add_TextChanged({Refresh-PasResults})
$ui.results.Add_AutoGeneratingColumn({param($sender,$e)
    # Columns generated from PSObject rows have property type Object, which turns sorting off.
    $e.Column.CanUserSort=$true
    if($script:sort -and $script:sort.Column -eq $e.PropertyName){$e.Column.SortDirection=if($script:sort.Descending){'Descending'}else{'Ascending'}}
})
$ui.results.Add_AutoGeneratedColumns({
    # Every ItemsSource assignment regenerates the columns; the user's order is restored by column name.
    $columns=@($ui.results.Columns)
    $ordered=@($columns | Sort-Object @{Expression={if($script:columnOrder.ContainsKey([string]$_.Header)){$script:columnOrder[[string]$_.Header]}else{[int]::MaxValue}}},@{Expression={[array]::IndexOf($columns,$_)}})
    for($i=0;$i -lt $ordered.Count;$i++){$ordered[$i].DisplayIndex=$i}
})
$ui.results.Add_ColumnReordered({foreach($column in $ui.results.Columns){$script:columnOrder[[string]$column.Header]=$column.DisplayIndex}})
$ui.results.Add_Sorting({param($sender,$e)
    # The collection view comparer throws on Int32 and Int64 values in one column.
    $e.Handled=$true
    $script:sort=@{Column=$e.Column.SortMemberPath;Descending=($e.Column.SortDirection -eq 'Ascending')}
    Refresh-PasResults
})
function Send-PasSelection {param([string]$Mode) if($script:work){throw 'Wait for the current operation to finish.'};$selected=@($ui.results.SelectedItems|Sort-Object TargetResourceID -Unique);if(-not $selected.Count){throw 'Select result rows first.'};if(-not $script:step -or ($script:step.SiteCode+'|'+$script:step.Provider) -ne ($script:prefs.SiteCode+'|'+$script:prefs.SMSProvider)){throw 'Results belong to another connection. Restore that connection before selecting targets.'};$script:targets=@($selected|ForEach-Object{[pscustomobject]@{Device=$_.TargetDevice;ResourceID=[int]$_.TargetResourceID;Client=$true;Active=$null}});$ui.targetSummary.Text=[string]$script:targets.Count+' devices selected from previous results.';$script:resolvedConnection=$script:prefs.SiteCode+'|'+$script:prefs.SMSProvider;Set-PasMode $Mode;$ui.editor.Text='';$script:parameters=@{};$ui.scriptGuid.Clear()}
$ui.btnSelectionScript.Add_Click({try{Send-PasSelection 'Script'}catch{Show-PasError $_}})
$ui.btnSelectionPivot.Add_Click({try{Send-PasSelection 'Pivot'}catch{Show-PasError $_}})
$ui.btnCsv.Add_Click({try{$rows=Get-PasVisibleRows $ui.results.ItemsSource;if(-not $rows.Count){throw 'There are no results to export.'};$path=Get-PasFilePath 'CSV|*.csv' -Save;if($path){
    # Endpoint data starting with = + - @ is a spreadsheet formula when the CSV opens.
    $safe=@($rows|ForEach-Object{$record=[ordered]@{};foreach($p in $_.PSObject.Properties){$value=$p.Value;if($value -is [string] -and $value -match '^[=+\-@\t\r]'){$value="'"+$value};$record[$p.Name]=$value};[pscustomobject]$record})
    $safe|Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8}}catch{Show-PasError $_}})
$ui.btnJson.Add_Click({try{$rows=Get-PasVisibleRows $ui.results.ItemsSource;if(-not $rows.Count){throw 'There are no results to export.'};$path=Get-PasFilePath 'JSON|*.json' -Save;if($path){Write-PasJson $path @($rows)}}catch{Show-PasError $_}})
$ui.btnCopy.Add_Click({try{$rows=Get-PasVisibleRows $ui.results.ItemsSource;if(-not $rows.Count){throw 'There are no results to copy.'}
    # Base64 keeps endpoint text out of PowerShell quoting; U+2018/U+2019 also close single-quoted strings.
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $rows -Depth 20 -Compress)))
    [Windows.Clipboard]::SetText("[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded')) | ConvertFrom-Json");$ui.status.Text=[string]$rows.Count+' rows copied as PowerShell.'}catch{Show-PasError $_}})
$ui.btnGrid.Add_Click({try{$rows=Get-PasVisibleRows $ui.results.ItemsSource;if(-not $rows.Count){throw 'There are no results to show.'};$rows|Out-GridView -Title 'Pivots and Scripts results'}catch{Show-PasError $_}})
$ui.btnSaveSession.Add_Click({try{Save-PasSession;$path=Get-PasFilePath 'Session JSON|*.json' -Save;if($path){Write-PasJson $path $script:session}}catch{Show-PasError $_}})
$ui.btnNewSession.Add_Click({try{Save-PasSession;$script:session=[pscustomobject]@{SchemaVersion=1;ID=[guid]::NewGuid().ToString();Created=[DateTime]::UtcNow.ToString('o');Steps=@()};$script:step=$null;$script:rows.Clear();$script:states=@{};$script:rawRecords.Clear();$ui.raw.Clear();Refresh-PasResults}catch{Show-PasError $_}})
$ui.btnHistory.Add_Click({try{$path=Get-PasFilePath 'Session JSON|*.json';if($path){$loaded=[IO.File]::ReadAllText($path)|ConvertFrom-Json;if($loaded.SchemaVersion -ne 1 -or [string]$loaded.ID -notmatch '^[a-fA-F0-9-]{36}$'){throw 'Unsupported session file.'};$script:session=$loaded;$script:step=@($loaded.Steps)|Select-Object -Last 1;$script:rows.Clear();$script:states=@{};$script:rawRecords.Clear();if($script:step){foreach($row in @($script:step.Results)){$script:rows.Add($row)};foreach($item in @($script:step.Devices)){$script:states[[string]$item.ResourceID]=$item};Set-PasMode $script:step.Mode;$ui.editor.Text=$script:step.Text;$ui.raw.Text=$script:step.Raw|ConvertTo-Json -Depth 20};$script:targets=@();$ui.targetSummary.Text='Historical session opened. Resolve fresh targets before running.';Refresh-PasResults}}catch{Show-PasError $_}})
$ui.toggleTheme.Add_Toggled({$dark=$ui.toggleTheme.IsOn;[void][ControlzEx.Theming.ThemeManager]::Current.ChangeTheme($window,$(if($dark){'Dark.Steel'}else{'Light.Blue'}));$ui.txtThemeLabel.Text=if($dark){'Dark Theme'}else{'Light Theme'};Set-ButtonTheme -IsDark $dark;Update-SidebarButtonTheme;Update-TitleBarBrushes;Set-PasHighlighting})
$window.Add_SourceInitialized({Set-ButtonTheme -IsDark $ui.toggleTheme.IsOn;Update-SidebarButtonTheme;Update-TitleBarBrushes})
$window.Add_Closing({param($sender,$e) if($script:work){$e.Cancel=$true;$script:work.Control.Stop=$true;$script:work.Stopped=$true;$ui.status.Text='Stopping local waiting. Close again after the worker finishes.';return};try{Save-PasSession;Save-WindowState -Window $window -Path (Join-Path $dataRoot 'windowstate.json')}catch{if($SmokeTest){[IO.File]::AppendAllText((Join-Path $PSScriptRoot 'work\smoke.log'),$_.ToString())}else{$e.Cancel=$true;Show-PasError $_}}})
Restore-WindowState -Window $window -Path (Join-Path $dataRoot 'windowstate.json')
Update-PasConnectionInfo;Set-PasMode 'Pivot';$ui.editor.Text='Disk | project Device, Name, FreeSpace';$timer.Start()
if($SmokeTest){$smokeLog=Join-Path $PSScriptRoot 'work\smoke.log';[IO.Directory]::CreateDirectory((Split-Path $smokeLog))|Out-Null;[IO.File]::WriteAllText($smokeLog,'');$window.Dispatcher.Add_UnhandledException({param($s,$e) [IO.File]::AppendAllText($smokeLog,$e.Exception.ToString());$e.Handled=$true});$smokeTimer=[Windows.Threading.DispatcherTimer]::new();$smokeTimer.Interval=[TimeSpan]::FromSeconds(1);$smokeTimer.Add_Tick({try{$smokeTimer.Stop();[IO.File]::AppendAllText($smokeLog,"tick`r`n");if($ui.btnNewSession.TranslatePoint([Windows.Point]::new(0,$ui.btnNewSession.ActualHeight),$window).Y -gt $ui.txtThemeLabel.TranslatePoint([Windows.Point]::new(0,0),$window).Y){throw 'The sidebar buttons overlap the theme switch.'};Save-PasPreview 'dark';$ui.toggleTheme.IsOn=$false;Set-PasMode 'Script';$ui.editor.Text=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Library\Scripts\Service state.ps1'));Show-PasParameterDialog;if($script:parameters.ServiceName -ne 'CcmExec'){throw 'Parameter dialog default value failed.'};Show-PasOptionsDialog;Show-PasScriptsDialog;if($ui.connectionInfo.Text -notmatch 'Connection not set|Site '){throw 'Connection label missing.'};Save-PasPreview 'light';$ui.toggleTheme.IsOn=$true;Set-PasMode 'Pivot';[IO.File]::AppendAllText($smokeLog,"close`r`n");$window.Close()}catch{[IO.File]::AppendAllText($smokeLog,$_.Exception.ToString());$window.Dispatcher.InvokeShutdown()}});$smokeTimer.Start()}
try{$window.ShowDialog()|Out-Null}finally{$timer.Stop()}
if($SmokeTest){$log=[IO.File]::ReadAllText($smokeLog);if(($log -replace 'tick|close|\s','').Length){throw $log};Write-Output 'PASS: WPF startup, dark/light themes, mode switches, editor, window close and session persistence.'}
