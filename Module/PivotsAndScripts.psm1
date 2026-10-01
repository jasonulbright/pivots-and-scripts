Set-StrictMode -Version 2
Import-Module (Join-Path $PSScriptRoot '..\Lib\SuiteCommon\SuiteCommon.psd1') -DisableNameChecking

function Get-PasHash {
    param([string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Write-PasJson {
    param([string]$Path, $Value)
    $directory = Split-Path $Path -Parent
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $Value -Depth 40), [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($Path)) {
            $backup=$temp+'.bak'
            [IO.File]::Replace($temp,$Path,$backup)
            [IO.File]::Delete($backup)
        }
        else { [IO.File]::Move($temp,$Path) }
    } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}
function Assert-PasConnection {
    param([string]$SiteCode,[string]$SMSProvider)
    if ($SiteCode -notmatch '^[A-Za-z0-9]{3}$') { throw 'Enter a three-character site code.' }
    if ($SMSProvider -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*$') { throw 'Enter the SMS Provider hostname, without a URL or path.' }
    if (-not (Connect-CMSite -SiteCode $SiteCode -SMSProvider $SMSProvider)) { throw 'Configuration Manager connection failed. Check console installation, site and permissions.' }
    # Connect-CMSite returns success for a site code the provider does not host.
    if (@(Get-CMSite -SiteCode $SiteCode -ErrorAction SilentlyContinue).Count -ne 1) { throw "Site $SiteCode was not found on SMS Provider $SMSProvider." }
}
function Test-PasCollectionId {
    param([string]$Text)
    $Text -match '^[A-Za-z0-9]{3}[0-9A-Fa-f]{5}$'
}
function Resolve-PasTargets {
    param([ValidateSet('Collection','Device','Pattern','List')][string]$Kind,[string]$InputText)
    if ([string]::IsNullOrWhiteSpace($InputText)) { throw 'Enter a target.' }
    $devices = @(); $unknown = @()
    if ($Kind -eq 'Collection') {
        $text = $InputText.Trim()
        $collections = @()
        if (Test-PasCollectionId $text) { $collections = @(Get-CMDeviceCollection -Id $text -ErrorAction Stop) }
        if (-not $collections.Count) {
            # Get-CMDeviceCollection -Name always applies wildcards; the exact comparison keeps one literal match.
            $collections = @(Get-CMDeviceCollection -Name ([Management.Automation.WildcardPattern]::Escape($text)) -ErrorAction Stop | Where-Object { $_.Name -eq $text })
        }
        if ($collections.Count -ne 1) { throw "Collection '$text' must resolve to exactly one device collection." }
        $devices = @(Get-CMDevice -CollectionId $collections[0].CollectionID -Fast -ErrorAction Stop)
    } elseif ($Kind -eq 'Pattern') {
        $devices = @(Get-CMDevice -Name $InputText.Trim() -Fast -ErrorAction Stop)
    } else {
        $names = if ($Kind -eq 'Device') { @($InputText.Trim()) } else { @($InputText -split '[,;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique) }
        foreach ($name in $names) {
            $matched = @(Get-CMDevice -Name $name -DisableWildcardHandling -Fast -ErrorAction Stop)
            if ($matched.Count -eq 0) { $unknown += $name }
            $devices += $matched
        }
    }
    $snapshot = @($devices | Where-Object { $_.ResourceID -gt 0 } | Sort-Object ResourceID -Unique | ForEach-Object {
        [pscustomobject]@{Device=[string]$_.Name; ResourceID=[int]$_.ResourceID; Client=[bool]$_.IsClient; Active=[bool]$_.IsActive}
    })
    [pscustomobject]@{Targets=$snapshot; Unknown=$unknown; ResolvedAt=[DateTime]::UtcNow.ToString('o')}
}
function Invoke-PasAdminService {
    param([string]$SMSProvider,[string]$RelativePath,[ValidateSet('GET','POST')][string]$Method='GET',$Body)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $request = @{Uri="https://$SMSProvider/AdminService/v1.0/$RelativePath";Method=$Method;UseDefaultCredentials=$true;ErrorAction='Stop';TimeoutSec=30}
    if ($Method -eq 'POST') {
        # Without a charset, Windows PowerShell 5.1 sends non-ASCII query text as '?'.
        $request.Body = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 10 -Compress))
        $request.ContentType = 'application/json; charset=utf-8'
    }
    try { Invoke-RestMethod @request }
    catch [Net.WebException] {
        $response = $_.Exception.Response
        if ($null -eq $response) { throw }
        $code = [int]$response.StatusCode
        $detail = ''
        try {
            $reader = [IO.StreamReader]::new($response.GetResponseStream())
            try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
            try { $parsed = $text | ConvertFrom-Json -ErrorAction Stop; if ($parsed.PSObject.Properties['error'] -and $parsed.error.PSObject.Properties['message']) { $detail = [string]$parsed.error.message } else { $detail = $text } } catch { $detail = $text }
        } catch { $detail = '' }
        $message = "AdminService returned HTTP $code ($($response.StatusDescription))."
        if (-not [string]::IsNullOrWhiteSpace($detail)) { $message += ' ' + $detail.Trim() }
        elseif ($code -eq 400) { $message += ' The service returned no reason. Check the query syntax.' }
        $failure = [InvalidOperationException]::new($message, $_.Exception)
        $failure.Data['StatusCode'] = $code
        throw $failure
    }
}
function Start-PasPivot {
    param([string]$SMSProvider,[int]$ResourceID,[string]$Query)
    $raw = Invoke-PasAdminService -SMSProvider $SMSProvider -RelativePath "Device($ResourceID)/AdminService.RunCMPivot" -Method POST -Body @{InputQuery=$Query}
    $op = $null
    if ($null -ne $raw -and $raw -isnot [string]) {
        $op = $raw.PSObject.Properties['OperationId']
        if (-not $op -and $raw.PSObject.Properties['value'] -and $null -ne $raw.value) { $op = $raw.value.PSObject.Properties['OperationId'] }
    }
    if (-not $op -or [string]$op.Value -notmatch '^\d+$') { throw 'AdminService did not return a numeric OperationId.' }
    [pscustomobject]@{OperationID=[long]$op.Value; Raw=$raw}
}
function Get-PasPivotResult {
    param([string]$SMSProvider,[int]$ResourceID,[long]$OperationID)
    $raw = Invoke-PasAdminService -SMSProvider $SMSProvider -RelativePath "Device($ResourceID)/AdminService.CMPivotResult(OperationId=$OperationID)"
    # Windows PowerShell 5.1 returns an empty string for HTTP 204 and empty 200 bodies.
    if ($null -eq $raw -or ($raw -is [string] -and [string]::IsNullOrWhiteSpace($raw))) { return $null }
    $raw
}
function Test-PasEnvelope {
    param($Item)
    if ($null -eq $Item -or $Item -is [string] -or $Item -is [ValueType]) { return $false }
    $names = @($Item.PSObject.Properties.Name)
    if ($names -notcontains 'Result') { return $false }
    ($names.Count -eq 1) -or ($names -contains 'Status') -or ($names -contains 'MoreResult')
}
function ConvertFrom-PasText {
    param([string]$Text)
    $trimmed = $Text.Trim()
    if ($trimmed -notmatch '^[\[{"]' -and $trimmed -notmatch '^\{\\"|^\[\{\\"') { return $Text }
    try { $value = $trimmed | ConvertFrom-Json -ErrorAction Stop }
    catch {
        # Run Scripts stores JSON output with escaped quotes and no surrounding string delimiters.
        try { $value = ('"' + $trimmed + '"') | ConvertFrom-Json -ErrorAction Stop } catch { return $Text }
    }
    if ($value -is [string] -and $value.Trim() -match '^[\[{]') { try { return ($value | ConvertFrom-Json -ErrorAction Stop) } catch { return $value } }
    $value
}
function Convert-PasRows {
    param($Payload,[string]$Device,[int]$ResourceID)
    $data = $Payload
    if ($null -ne $data -and $data -isnot [string] -and $data.PSObject.Properties['value']) { $data = $data.value }
    if ($data -is [string]) { if ([string]::IsNullOrWhiteSpace($data)) { return }; $data = ConvertFrom-PasText $data }
    foreach ($entry in @($data)) {
        if ($null -eq $entry) { continue }
        if (Test-PasEnvelope $entry) {
            Convert-PasRows -Payload $entry.Result -Device $Device -ResourceID $ResourceID
            continue
        }
        if ($entry -is [string]) { $entry = ConvertFrom-PasText $entry }
        if ($entry -is [Array]) { Convert-PasRows -Payload $entry -Device $Device -ResourceID $ResourceID; continue }
        $row = [ordered]@{TargetDevice=$Device;TargetResourceID=$ResourceID}
        if ($entry -is [string] -or $entry -is [ValueType]) { $row.Output=$entry }
        else { foreach ($p in $entry.PSObject.Properties) { if ($p.Name -notin @('TargetDevice','TargetResourceID')) { $row[$p.Name]=$p.Value } } }
        [pscustomobject]$row
    }
}
function Get-PasParameters {
    param([string]$Text)
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw ($errors.Message -join "`n") }
    if ($ast.ParamBlock) { foreach ($p in $ast.ParamBlock.Parameters) {
        $choices = @(); $mandatory = $false
        foreach ($attribute in $p.Attributes) {
            if ($attribute -isnot [Management.Automation.Language.AttributeAst]) { continue }
            if ($attribute.TypeName.Name -eq 'ValidateSet') { foreach ($argument in $attribute.PositionalArguments) { try { $choices += [string]$argument.SafeGetValue() } catch { $null = $_ } } }
            if ($attribute.TypeName.Name -eq 'Parameter') { foreach ($named in $attribute.NamedArguments) { if ($named.ArgumentName -eq 'Mandatory') { $mandatory = $named.ExpressionOmitted -or $named.Argument.Extent.Text -match '^\$?true$' } } }
        }
        $literal = ''
        if ($p.DefaultValue) { try { $literal = [string]$p.DefaultValue.SafeGetValue() } catch { $literal = '' } }
        [pscustomobject]@{Name=$p.Name.VariablePath.UserPath;Type=$p.StaticType.FullName;Default=if($p.DefaultValue){$p.DefaultValue.Extent.Text}else{''};DefaultLiteral=$literal;Mandatory=$mandatory;Choices=$choices;SiteType=(Get-PasSiteParameterType $p.StaticType)}
    } }
}
function Get-PasSiteParameterType {
    param([Type]$Type)
    # Run Scripts accepts integer, string and list parameters; the site refuses SwitchParameter at submission.
    if ($Type -eq [string] -or $Type -eq [object]) { return 'System.String' }
    if ($Type -eq [int]) { return 'System.Int32' }
    ''
}
function Assert-PasScriptParameters {
    param([object[]]$Parameters)
    $Parameters = @($Parameters | Where-Object { $null -ne $_ })
    if ($Parameters.Count -gt 10) { throw 'Run Scripts supports at most 10 parameters.' }
    $unsupported = @($Parameters | Where-Object { -not $_.SiteType })
    if ($unsupported.Count) { throw ('Run Scripts supports string and integer parameters only. Change the type of: ' + (($unsupported | ForEach-Object { '{0} ({1})' -f $_.Name, $_.Type }) -join ', ') + '.') }
    $quoted = @($Parameters | Where-Object { $_.DefaultLiteral.Contains("'") })
    if ($quoted.Count) { throw ('Run Scripts cannot pass a single quote. Change the default of: ' + (($quoted | ForEach-Object Name) -join ', ') + '.') }
}
function ConvertTo-PasParamsDefinition {
    param([object[]]$Parameters)
    $builder = [Text.StringBuilder]::new('<?xml version="1.0" encoding="utf-16"?><ScriptParameters SchemaVersion="1">')
    foreach ($p in @($Parameters | Where-Object { $null -ne $_ })) {
        $name = [Security.SecurityElement]::Escape($p.Name)
        [void]$builder.Append(('<ScriptParameter Name="{0}" FriendlyName="{0}" Type="{1}" Description="" IsRequired="{2}" IsHidden="false" DefaultValue="{3}"><Validators /></ScriptParameter>' -f $name, $p.SiteType, ([string][bool]$p.Mandatory).ToLowerInvariant(), [Security.SecurityElement]::Escape($p.DefaultLiteral)))
    }
    [void]$builder.Append('</ScriptParameters>')
    $builder.ToString()
}
function ConvertFrom-PasParamsDefinition {
    param([string]$Encoded)
    if ([string]::IsNullOrWhiteSpace($Encoded)) { return }
    $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Encoded)).TrimStart([char]0xFEFF)
    $text = $text -replace '^<\?xml[^>]*\?>', ''
    $xml = [xml]$text
    foreach ($node in @($xml.ScriptParameters.ScriptParameter)) { if ($node) { [pscustomobject]@{Name=[string]$node.Name;Type=[string]$node.Type;Required=([string]$node.IsRequired -eq 'true');Default=[string]$node.DefaultValue} } }
}
function New-PasCimSession {
    param([string]$SMSProvider)
    New-CimSession -ComputerName $SMSProvider -SessionOption (New-CimSessionOption -Protocol Dcom) -ErrorAction Stop
}
function Get-PasSiteScript {
    param([string]$SMSProvider,[string]$SiteCode,[guid]$ScriptGuid)
    $cim = New-PasCimSession $SMSProvider
    try {
        $item = @(Get-CimInstance -CimSession $cim -Namespace ('root\SMS\site_'+$SiteCode) -ClassName SMS_Scripts -Filter ("ScriptGuid = '{0}'" -f $ScriptGuid.ToString().ToUpperInvariant()) -ErrorAction Stop)
        if (-not $item.Count) { return }
        $full = $item[0] | Get-CimInstance -ErrorAction Stop
        $parameters = @(); $definitionError = ''
        try { $parameters = @(ConvertFrom-PasParamsDefinition ([string]$full.ParamsDefinition)) } catch { $definitionError = $_.Exception.Message }
        [pscustomobject]@{ScriptGuid=[string]$full.ScriptGuid;ScriptName=[string]$full.ScriptName;ApprovalState=[int]$full.ApprovalState;Author=[string]$full.Author;Approver=[string]$full.Approver;Parameters=$parameters;DefinitionError=$definitionError}
    } finally { Remove-CimSession $cim }
}
function New-PasManagedScript {
    param([string]$Text,[string]$SMSProvider,[string]$SiteCode)
    $parameters = @(Get-PasParameters -Text $Text)
    Assert-PasScriptParameters $parameters
    $created = New-CMScript -ScriptName ('PivotsAndScripts-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + (Get-PasHash $Text).Substring(0,8)) -ScriptText $Text -Fast -ErrorAction Stop
    $guid = [string]$created.ScriptGuid
    if (-not $parameters.Count) { return [pscustomobject]@{ScriptGuid=$guid;Parameters=@()} }
    try {
        # New-CMScript stores no parameter definitions; without them Invoke-CMScript drops every value.
        # UpdateScript needs named arguments: positional arguments bind in another order and overwrite ScriptVersion with the script text.
        $definition = ConvertTo-PasParamsDefinition $parameters
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($definition))
        $cim = New-PasCimSession $SMSProvider
        try {
            $instance = @(Get-CimInstance -CimSession $cim -Namespace ('root\SMS\site_'+$SiteCode) -ClassName SMS_Scripts -Filter "ScriptGuid = '$guid'" -ErrorAction Stop)[0] | Get-CimInstance -ErrorAction Stop
            $result = Invoke-CimMethod -InputObject $instance -MethodName UpdateScript -ErrorAction Stop -Arguments @{ParamsDefinition=$encoded;Script=[string]$instance.Script;ScriptDescription=[string]$instance.ScriptDescription;ScriptName=[string]$instance.ScriptName;ScriptVersion=[string]$instance.ScriptVersion;Timeout=[uint32]$instance.Timeout}
            if ($result.ReturnValue -ne 0) { throw "SMS_Scripts.UpdateScript returned $($result.ReturnValue)." }
            $after = @(Get-CimInstance -CimSession $cim -Namespace ('root\SMS\site_'+$SiteCode) -ClassName SMS_Scripts -Filter "ScriptGuid = '$guid'" -ErrorAction Stop)[0] | Get-CimInstance -ErrorAction Stop
            if ([string]$after.ParamsDefinition -ne $encoded -or [string]$after.Script -ne [string]$instance.Script) { throw 'The parameter definitions read back from the site do not match.' }
        } finally { Remove-CimSession $cim }
    } catch {
        $reason = $_.Exception.Message
        try { Remove-CMScript -InputObject $created -Force -ErrorAction Stop; $cleanup = 'The incomplete script was removed.' } catch { $cleanup = "Remove script $guid in the console." }
        throw "Script parameters could not be stored: $reason $cleanup"
    }
    [pscustomobject]@{ScriptGuid=$guid;Parameters=@($parameters | ForEach-Object Name)}
}
function Get-PasSubmittedMessage {
    param([string]$Guid,[string[]]$Parameters,[bool]$Approved=$false,[string]$ApprovalError='')
    $stored = @($Parameters | Where-Object { $_ })
    $created = if ($stored.Count) { "Script $Guid created with parameters $($stored -join ', ')." } else { "Script $Guid created." }
    if ($Approved) { "$created Approved." }
    elseif ($ApprovalError) { "$created Not approved: $ApprovalError" }
    else { "$created Obtain approval in Configuration Manager before running." }
}
function ConvertTo-PasScriptArguments {
    param($SiteScript,[hashtable]$Parameters)
    if ($SiteScript.PSObject.Properties['DefinitionError'] -and $SiteScript.DefinitionError) { throw "The parameter definitions of script $($SiteScript.ScriptGuid) cannot be read: $($SiteScript.DefinitionError)" }
    $defined = @{}
    foreach ($p in @($SiteScript.Parameters)) { $defined[$p.Name] = $p }
    $arguments = @{}
    foreach ($name in @($Parameters.Keys)) {
        if (-not $defined.ContainsKey($name)) {
            if (-not $defined.Count) { throw "Script $($SiteScript.ScriptGuid) has no parameter definitions in Configuration Manager, so parameter values would be dropped. Submit the script from this app, or add its parameters in the console before approval." }
            throw "Parameter '$name' is not defined on script $($SiteScript.ScriptGuid). Defined: $((@($defined.Keys) | Sort-Object) -join ', ')."
        }
        $value = $Parameters[$name]
        if ([string]$value -match "'") { throw "Parameter '$name' contains a single quote. Run Scripts cannot pass it." }
        switch ($defined[$name].Type) {
            'System.Int32' { $number = 0; if (-not [int]::TryParse([string]$value, [ref]$number)) { throw "Parameter '$name' needs a whole number." }; $arguments[$name] = $number }
            'System.String' { $arguments[$name] = [string]$value }
            default { throw "Parameter '$name' has type $($defined[$name].Type), which Run Scripts does not accept." }
        }
    }
    foreach ($p in @($SiteScript.Parameters)) { if ($p.Required -and -not $arguments.ContainsKey($p.Name) -and [string]::IsNullOrEmpty($p.Default)) { throw "Parameter '$($p.Name)' is required." } }
    $arguments
}
function Invoke-PasManagedScript {
    param([guid]$ScriptGuid,[int]$ResourceID,[hashtable]$Arguments=@{})
    # Configuration Manager remains responsible for approval and collection RBAC.
    $device = Get-CMDevice -ResourceId $ResourceID -Fast -ErrorAction Stop
    if (-not $device) { throw 'The target no longer exists.' }
    $started = Invoke-CMScript -ScriptGuid $ScriptGuid.ToString() -Device $device -ScriptParameter $Arguments -PassThru -ErrorAction Stop
    $op = $null
    if ($null -ne $started) {
        foreach ($name in @('OperationID','ClientOperationID','ID')) {
            $property = $started.PSObject.Properties[$name]
            if ($property -and [string]$property.Value -match '^\d+$') { $op = [long]$property.Value; break }
        }
    }
    # The PassThru object is a WqlArrayItems wrapper that ConvertTo-Json cannot serialize.
    [pscustomobject]@{OperationID=$op;ReturnValue=$(if ($null -ne $started -and $started.PSObject.Properties['ReturnValue']) { $started.ReturnValue } else { $null })}
}
function Get-PasScriptStatus {
    param($CimSession,[string]$SiteCode,[long]$OperationID,[int]$ResourceID)
    $rows = @(Get-CimInstance -CimSession $CimSession -Namespace ('root\SMS\site_'+$SiteCode) -ClassName SMS_ScriptsExecutionStatus -Filter ('ClientOperationId = {0} AND ResourceId = {1}' -f $OperationID,$ResourceID) -ErrorAction Stop)
    if (-not $rows.Count) { return }
    $row = $rows[0]
    if (-not $row.PSObject.Properties['ScriptOutput']) { throw 'The provider returned an unsupported script-result schema. Inspect Raw.' }
    [pscustomobject]@{ClientOperationId=$row.ClientOperationId;ResourceId=$row.ResourceId;DeviceName=$row.DeviceName;ScriptExecutionState=$row.ScriptExecutionState;ScriptExitCode=$row.ScriptExitCode;ScriptOutput=$row.ScriptOutput;ScriptGuid=$row.ScriptGuid;ScriptName=$row.ScriptName;LastUpdateTime=$row.LastUpdateTime}
}
function Get-PasApprovalStateName {
    param([int]$State)
    switch ($State) { 0 { 'Waiting for approval' } 1 { 'Denied' } 3 { 'Approved' } default { "State $State" } }
}
function Get-PasSiteScripts {
    param([string]$SMSProvider,[string]$SiteCode)
    $cim = New-PasCimSession $SMSProvider
    try {
        # Feature 1 marks site-owned scripts such as the built-in CMPivot script; denying or removing it breaks CMPivot.
        @(Get-CimInstance -CimSession $cim -Namespace ('root\SMS\site_'+$SiteCode) -ClassName SMS_Scripts -Filter 'Feature = 0' -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{Name=[string]$_.ScriptName;State=(Get-PasApprovalStateName ([int]$_.ApprovalState));Author=[string]$_.Author;Approver=[string]$_.Approver;LastUpdated=$(if ($_.LastUpdateTime) { ([datetime]$_.LastUpdateTime).ToString('yyyy-MM-dd HH:mm') } else { '' });ScriptGuid=[string]$_.ScriptGuid;ApprovalState=[int]$_.ApprovalState}
        } | Sort-Object LastUpdated -Descending)
    } finally { Remove-CimSession $cim }
}
function Get-PasManagedScriptObject {
    param([guid]$ScriptGuid)
    $item = Get-CMScript -ScriptGuid $ScriptGuid.ToString() -Fast -ErrorAction Stop
    if (-not $item) { throw "Script $ScriptGuid does not exist in Configuration Manager." }
    if ([int]$item.Feature -ne 0) { throw "Script $ScriptGuid belongs to a Configuration Manager feature. The app does not change it." }
    $item
}
function Set-PasScriptApproval {
    param([guid]$ScriptGuid,[ValidateSet('Approve','Deny')][string]$Decision,[string]$Comment='')
    $item = Get-PasManagedScriptObject $ScriptGuid
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    try {
        if ($Decision -eq 'Approve') { Approve-CMScript -ScriptGuid $ScriptGuid.ToString() -Comment $Comment -ErrorAction Stop }
        else { Deny-CMScript -ScriptGuid $ScriptGuid.ToString() -Comment $Comment -ErrorAction Stop }
    } catch {
        # The provider reports only a generic error when an author approves or denies their own script.
        if ([string]$item.Author -eq $me) { throw "The site did not let you $($Decision.ToLowerInvariant()) your own script. By default, Configuration Manager requires a second approver (hierarchy setting 'Script authors require additional script approver')." }
        throw
    }
    $after = Get-CMScript -ScriptGuid $ScriptGuid.ToString() -Fast -ErrorAction Stop
    [pscustomobject]@{ScriptGuid=[string]$item.ScriptGuid;State=(Get-PasApprovalStateName ([int]$after.ApprovalState));Approver=[string]$after.Approver}
}
function Remove-PasManagedScript {
    param([guid]$ScriptGuid)
    $item = Get-PasManagedScriptObject $ScriptGuid
    Remove-CMScript -InputObject $item -Force -ErrorAction Stop
    [pscustomobject]@{ScriptGuid=[string]$item.ScriptGuid;State='Removed'}
}
function Get-PasVisibleRows {
    param($ItemsSource)
    # The comma keeps a one-row result an array; a single PSCustomObject has no Count in Windows PowerShell 5.1.
    ,@($ItemsSource | Where-Object { $null -ne $_ })
}
function New-PasDeviceTable {
    param([object[]]$Targets)
    # Device events carry no Client or Active value; the shell copies them from the target entry with the same key.
    $table = @{}
    foreach ($target in @($Targets | Where-Object { $null -ne $_ })) { $table[[string]$target.ResourceID] = $target }
    $table
}
function Sort-PasRows {
    param([object[]]$Rows,[string]$Property,[switch]$Descending)
    if (-not @($Rows | Where-Object { $null -ne $_ -and $_.PSObject.Properties[$Property] }).Count) { return $Rows }
    # AdminService returns CMPivot numbers as JSON strings; a column sorts as numbers only when every value parses as one.
    $values = @($Rows | ForEach-Object { if ($null -ne $_ -and $_.PSObject.Properties[$Property]) { $_.PSObject.Properties[$Property].Value } } | Where-Object { -not [string]::IsNullOrEmpty([string]$_) })
    $number = 0.0
    $numeric = $values.Count -gt 0 -and -not @($values | Where-Object { -not [double]::TryParse([string]$_, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) }).Count
    $key = if ($numeric) {
        { $text = [string]$_.PSObject.Properties[$Property].Value; $parsed = 0.0; if ([double]::TryParse($text, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) { $parsed } else { [double]::MinValue } }
    } else { { $_.PSObject.Properties[$Property].Value } }
    $Rows | Sort-Object -Property @{Expression=$key} -Descending:$Descending
}
function Get-PasSettingsToSave {
    param([hashtable]$Entered,[hashtable]$Session,[hashtable]$Persisted)
    # A connection value the dialog left unchanged can be a command-line override; the saved value is kept for it.
    $settings = @{}
    foreach ($key in $Entered.Keys) { $settings[$key] = $Entered[$key] }
    foreach ($key in @('SiteCode','SMSProvider')) { if ($Entered[$key] -ceq $Session[$key]) { $settings[$key] = $Persisted[$key] } }
    $settings
}
function Get-PasWorkerError {
    param([Management.Automation.PowerShell]$PowerShell)
    # HadErrors is also true for a cmdlet error the worker caught and already reported as an Error event; the stream is then empty.
    $text = (@($PowerShell.Streams.Error) | ForEach-Object { $_.ToString() }) -join "`n"
    if ($text) { $text }
}
Export-ModuleMember -Function *-Pas*
