# Runs ON the lab site server (Windows PowerShell 5.1). Started by Invoke-PasLab.ps1.
#
# Creates ZZTEST- scripts through the module (with a parameter definition), approves, denies and removes
# them, resolves targets, and runs one CMPivot query and one script on the lab client. It compares every
# other script with a snapshot taken before the first change and removes everything it created, also when
# a step fails. Only scripts named ZZTEST-PAS-<tag>-* change. A script that belongs to a site feature is
# only asked with -WhatIf, never changed.
param(
    [Parameter(Mandatory)][string]$ModuleRoot,
    [Parameter(Mandatory)][string]$SiteCode,
    [Parameter(Mandatory)][string]$Provider,
    [string]$ClientName = 'CLIENT01',
    [int]$RunTimeoutSeconds = 240
)

$ErrorActionPreference = 'Stop'
$results = [System.Collections.Generic.List[object]]::new()
function Add-Result {
    param([string]$Step, [bool]$Ok, [string]$Detail = '')
    $results.Add([PSCustomObject]@{ Step = $Step; Ok = $Ok; Detail = $Detail })
    Add-Content -LiteralPath (Join-Path $ModuleRoot 'progress.txt') -Value ('{0} | {1} | {2}' -f $Ok, $Step, $Detail)
}

$tag = [guid]::NewGuid().ToString('N').Substring(0, 8)
$name1 = "ZZTEST-PAS-$tag-script"
$name2 = "ZZTEST-PAS-$tag-deny"
$ns = "root\SMS\site_$SiteCode"
$snapshot = $null
$snapshotTaken = $false
$cim = $null

function Get-Snapshot {
    # Every script that is not a test script: GUID, name, approval state and approver.
    @(Get-CimInstance -Namespace $ns -ClassName SMS_Scripts -Filter 'Feature = 0' | Where-Object { $_.ScriptName -notlike 'ZZTEST-*' } |
            ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.ScriptGuid, $_.ScriptName, $_.ApprovalState, $_.Approver } | Sort-Object)
}
function Test-Throws {
    param([scriptblock]$Script, [string]$Pattern)
    try { $null = & $Script; return $false } catch { return ($_.Exception.Message -like $Pattern) }
}
function Wait-Until {
    param([scriptblock]$Condition, [int]$Seconds)
    $deadline = (Get-Date).AddSeconds($Seconds)
    do { $value = & $Condition; if ($value) { return $value }; Start-Sleep -Seconds 5 } while ((Get-Date) -lt $deadline)
    return $null
}

try {
    Import-Module (Join-Path $ModuleRoot 'Lib\SuiteCommon\SuiteCommon.psd1') -Global -DisableNameChecking
    Import-Module (Join-Path $ModuleRoot 'Module\PivotsAndScripts.psm1') -Force -DisableNameChecking
    Initialize-Logging -LogPath (Join-Path $ModuleRoot 'lab.log')

    # One lab run at a time across all sessions: any ZZTEST- object or task of another run stops this one.
    $others = @(Get-CimInstance -Namespace $ns -ClassName SMS_Scripts -Filter "ScriptName LIKE 'ZZTEST-%'") +
    @(Get-CimInstance -Namespace $ns -ClassName SMS_Collection -Filter "Name LIKE 'ZZTEST-%'") +
    @(Get-CimInstance -Namespace $ns -ClassName SMS_Package -Filter "Name LIKE 'ZZTEST-%'")
    $tasks = @(Get-ScheduledTask -TaskName 'ZZTEST-*' -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -notlike 'ZZTEST-PAS-*' })
    if ($others.Count -gt 0 -or $tasks.Count -gt 0) { throw 'ZZTEST- objects already exist. Another test may be running.' }

    # --- connection and targets (read only) --------------------------------------------------------------
    $connected = $true
    try { Assert-PasConnection -SiteCode $SiteCode -SMSProvider $Provider } catch { $connected = $false; Add-Result 'connect' $false $_.Exception.Message }
    if (-not $connected) { throw 'No connection.' }
    Add-Result 'connect and site check' $true ''
    Add-Result 'a site code the provider does not host is refused' (Test-Throws { Assert-PasConnection -SiteCode 'ZZ9' -SMSProvider $Provider } '*Site ZZ9*') ''
    Add-Result 'the connection is checked again after the refusal' ($null -eq (Assert-PasConnection -SiteCode $SiteCode -SMSProvider $Provider)) ''
    $snapshot = Get-Snapshot
    $snapshotTaken = $true

    $r = Resolve-PasTargets -Kind Device -InputText $ClientName
    $client = @($r.Targets)[0]
    Add-Result "device $ClientName resolves to one client" (@($r.Targets).Count -eq 1 -and $client.Client -and [int]$client.ResourceID -gt 0) ("ResourceID=" + $client.ResourceID)
    $r = Resolve-PasTargets -Kind List -InputText "$ClientName, ZZTEST-NoSuchPC-$tag, $ClientName"
    Add-Result 'a list gives each device once and names the unknown one' (@($r.Targets).Count -eq 1 -and @($r.Unknown) -contains "ZZTEST-NoSuchPC-$tag") (@($r.Unknown) -join ',')
    $r = Resolve-PasTargets -Kind Pattern -InputText ($ClientName.Substring(0, 5) + '*')
    Add-Result 'a pattern matches the client' (@($r.Targets | Where-Object ResourceID -eq $client.ResourceID).Count -eq 1) ''
    $r = Resolve-PasTargets -Kind Collection -InputText 'All Systems'
    Add-Result 'a collection name gives its ID and its members' ($r.CollectionID -eq 'SMS00001' -and @($r.Targets | Where-Object ResourceID -eq $client.ResourceID).Count -eq 1) $r.CollectionID
    $r = Resolve-PasTargets -Kind Collection -InputText 'SMS00001'
    Add-Result 'a collection ID gives the same ID' ($r.CollectionID -eq 'SMS00001') ''
    Add-Result 'a collection name that does not exist is refused' (Test-Throws { Resolve-PasTargets -Kind Collection -InputText "ZZTEST-NoSuchCollection-$tag" } '*exactly one device collection*') ''

    # --- create, read back, list ---------------------------------------------------------------------------
    $text = "param([string]`$Name = 'zz', [int]`$Count = 1)`r`n[pscustomobject]@{ Name = `$Name; Count = `$Count; Marker = 'ZZTEST' } | ConvertTo-Json -Compress"
    $wi = New-PasManagedScript -Text $text -SMSProvider $Provider -SiteCode $SiteCode -ScriptName $name1 -WhatIf
    Add-Result 'create under WhatIf makes nothing' ($null -eq $wi -and @(Get-CimInstance -Namespace $ns -ClassName SMS_Scripts -Filter "ScriptName = '$name1'").Count -eq 0) ''
    $created = New-PasManagedScript -Text $text -SMSProvider $Provider -SiteCode $SiteCode -ScriptName $name1 -Confirm:$false
    $guid = [guid]$created.ScriptGuid
    Add-Result 'create a script with two parameters' ([bool]$created.ScriptGuid -and @($created.Parameters).Count -eq 2) $created.ScriptGuid
    $site = Get-PasSiteScript -SMSProvider $Provider -SiteCode $SiteCode -ScriptGuid $guid
    $defs = @($site.Parameters)
    Add-Result 'the site holds the name, the approval state and no definition error' ($site.ScriptName -eq $name1 -and $site.ApprovalState -eq 0 -and $site.DefinitionError -eq '') "state=$($site.ApprovalState)"
    Add-Result 'the site holds the parameter definitions' ($defs.Count -eq 2 -and $defs[0].Name -eq 'Name' -and $defs[0].Type -eq 'System.String' -and $defs[0].Default -eq 'zz' -and $defs[1].Name -eq 'Count' -and $defs[1].Type -eq 'System.Int32') (($defs | ForEach-Object { "$($_.Name):$($_.Type)=$($_.Default)" }) -join ';')
    $listed = @(Get-PasSiteScripts -SMSProvider $Provider -SiteCode $SiteCode | Where-Object ScriptGuid -eq $created.ScriptGuid)
    Add-Result 'the list shows the script as waiting for approval' ($listed.Count -eq 1 -and $listed[0].State -eq 'Waiting for approval' -and $listed[0].Name -eq $name1) ''
    $featureCount = @(Get-CimInstance -Namespace $ns -ClassName SMS_Scripts -Filter 'Feature = 1').Count
    $all = @(Get-PasSiteScripts -SMSProvider $Provider -SiteCode $SiteCode)
    Add-Result 'the list leaves out the scripts of site features' ($featureCount -ge 1 -and $all.Count -eq @(Get-CimInstance -Namespace $ns -ClassName SMS_Scripts -Filter 'Feature = 0').Count) "feature scripts=$featureCount"
    $args1 = ConvertTo-PasScriptArguments -SiteScript $site -Parameters @{ Count = '3'; Name = 'ZZ' }
    Add-Result 'the arguments are typed: Count is a number' ($args1.Count -is [int] -and $args1.Count -eq 3 -and $args1.Name -ceq 'ZZ') ''
    Add-Result 'an undefined parameter is refused' (Test-Throws { ConvertTo-PasScriptArguments -SiteScript $site -Parameters @{ Nope = '1' } } '*not defined*') ''

    # --- approval -----------------------------------------------------------------------------------------
    $wi = Set-PasScriptApproval -ScriptGuid $guid -Decision Approve -Comment 'ZZTEST' -WhatIf
    Add-Result 'approve under WhatIf changes nothing' ($null -eq $wi -and (Get-PasSiteScript -SMSProvider $Provider -SiteCode $SiteCode -ScriptGuid $guid).ApprovalState -eq 0) ''
    $a = Set-PasScriptApproval -ScriptGuid $guid -Decision Approve -Comment 'ZZTEST approve' -Confirm:$false
    Add-Result 'approve gives the state the site holds' ($a.State -eq 'Approved' -and $a.ScriptGuid -eq $created.ScriptGuid) "$($a.State) by $($a.Approver)"
    Add-Result 'the site shows the script as approved' ((Get-PasSiteScript -SMSProvider $Provider -SiteCode $SiteCode -ScriptGuid $guid).ApprovalState -eq 3) ''

    # --- script run on the lab client ----------------------------------------------------------------------
    $cim = New-PasCimSession $Provider
    $ops = @(Start-PasScriptRun -ScriptGuid $guid -Arguments $args1 -ResourceIds @([int]$client.ResourceID) -Confirm:$false)
    $opId = $ops[0].OperationID
    Add-Result 'a script run on the client returns one operation ID' ($ops.Count -eq 1 -and $opId -gt 0) "OperationID=$opId"
    $status = Wait-Until -Seconds $RunTimeoutSeconds -Condition {
        $s = @(Get-PasScriptRunStatus -CimSession $cim -SiteCode $SiteCode -OperationID $opId | Where-Object { [int]$_.ScriptExecutionState -ne 0 })
        if ($s.Count) { $s }
    }
    $row = if ($status) { @($status)[0] } else { $null }
    Add-Result 'the client reports the script run' ($null -ne $row -and [int]$row.ResourceId -eq [int]$client.ResourceID -and [int]$row.ScriptExitCode -eq 0) $(if ($row) { "state=$($row.ScriptExecutionState) exit=$($row.ScriptExitCode)" } else { 'no result before the timeout' })
    if ($row) {
        $out = @(Convert-PasRows -Payload ([string]$row.ScriptOutput) -Device $client.Device -ResourceID $client.ResourceID)
        Add-Result 'the script output becomes a row with the typed argument values' ($out.Count -eq 1 -and $out[0].Name -eq 'ZZ' -and [int]$out[0].Count -eq 3 -and $out[0].Marker -eq 'ZZTEST' -and $out[0].TargetDevice -eq $client.Device) ([string]$row.ScriptOutput)
    }
    Add-Result 'a script run with a quote in a value never reaches the site' (Test-Throws { ConvertTo-PasScriptArguments -SiteScript $site -Parameters @{ Name = "O'Brien" } } '*single quote*') ''

    # --- CMPivot run on the lab client ----------------------------------------------------------------------
    $pivot = Start-PasPivotRun -SMSProvider $Provider -Query 'OS | project Caption' -ResourceIds @([int]$client.ResourceID) -Confirm:$false
    Add-Result 'a CMPivot run on the client returns one operation ID' ($pivot.OperationID -gt 0) "OperationID=$($pivot.OperationID)"
    $prow = Wait-Until -Seconds $RunTimeoutSeconds -Condition {
        $s = @(Get-PasPivotStatus -SMSProvider $Provider -OperationID $pivot.OperationID | Where-Object { [int]$_.ScriptExecutionState -ne 0 })
        if ($s.Count) { $s[0] }
    }
    Add-Result 'the client reports the CMPivot result' ($null -ne $prow -and [int]$prow.ResourceId -eq [int]$client.ResourceID -and [int]$prow.ScriptExitCode -eq 0) $(if ($prow) { "state=$($prow.ScriptExecutionState) exit=$($prow.ScriptExitCode)" } else { 'no result before the timeout' })
    if ($prow) {
        $parsed = ConvertFrom-PasPivotOutput -Output ([string]$prow.ScriptOutput) -Device $client.Device -ResourceID $client.ResourceID
        Add-Result 'the CMPivot output becomes rows with a Caption' (@($parsed.Rows).Count -ge 1 -and [bool]@($parsed.Rows)[0].Caption) ([string]@($parsed.Rows)[0].Caption)
    }

    # --- deny, feature guard, removal ------------------------------------------------------------------------
    $second = New-PasManagedScript -Text 'Get-Date' -SMSProvider $Provider -SiteCode $SiteCode -ScriptName $name2 -Confirm:$false
    Add-Result 'create a script without parameters' ([bool]$second.ScriptGuid -and @($second.Parameters).Count -eq 0) $second.ScriptGuid
    $d = Set-PasScriptApproval -ScriptGuid ([guid]$second.ScriptGuid) -Decision Deny -Comment 'ZZTEST deny' -Confirm:$false
    Add-Result 'deny gives the state the site holds' ($d.State -eq 'Denied') $d.State
    $feature = @(Get-CimInstance -Namespace $ns -ClassName SMS_Scripts -Filter 'Feature = 1') | Select-Object -First 1
    if ($feature) {
        $fg = [guid]$feature.ScriptGuid
        Add-Result 'a site feature script is protected from deny and removal' ((Test-Throws { Set-PasScriptApproval -ScriptGuid $fg -Decision Deny -WhatIf } '*belongs to a Configuration Manager feature*') -and (Test-Throws { Remove-PasManagedScript -ScriptGuid $fg -WhatIf } '*belongs to a Configuration Manager feature*')) $feature.ScriptName
    }
    $wi = Remove-PasManagedScript -ScriptGuid ([guid]$second.ScriptGuid) -WhatIf
    Add-Result 'remove under WhatIf keeps the script' ($null -eq $wi -and @(Get-CimInstance -Namespace $ns -ClassName SMS_Scripts -Filter "ScriptGuid = '$($second.ScriptGuid.ToUpperInvariant())'").Count -eq 1) ''
    $rm = Remove-PasManagedScript -ScriptGuid ([guid]$second.ScriptGuid) -Confirm:$false
    Add-Result 'remove reports the script as removed' ($rm.State -eq 'Removed' -and @(Get-CimInstance -Namespace $ns -ClassName SMS_Scripts -Filter "ScriptGuid = '$($second.ScriptGuid.ToUpperInvariant())'").Count -eq 0) ''
    Add-Result 'removing a script that is gone is refused' (Test-Throws { Remove-PasManagedScript -ScriptGuid ([guid]$second.ScriptGuid) -Confirm:$false } '*does not exist*') ''
}
catch {
    Add-Result 'run' $false $_.Exception.Message
}
finally {
    if ($cim) { try { Remove-CimSession $cim } catch { $null = $_ } }
    try {
        if (-not (Test-CMConnection)) { [void](Connect-CMSite -SiteCode $SiteCode -SMSProvider $Provider) }
        for ($pass = 1; $pass -le 3; $pass++) {
            foreach ($s in @(Get-CimInstance -Namespace $ns -ClassName SMS_Scripts -Filter "ScriptName LIKE 'ZZTEST-PAS-$tag-%'")) {
                if ($s.ScriptName -notlike "ZZTEST-PAS-$tag-*") { continue }
                try { Remove-CMScript -InputObject (Get-CMScript -ScriptGuid $s.ScriptGuid -Fast -ErrorAction Stop) -Force -ErrorAction Stop } catch { if ($pass -eq 3) { Add-Result "cleanup script $($s.ScriptName)" $false $_.Exception.Message } }
            }
        }
    } catch { Add-Result 'cleanup' $false $_.Exception.Message }
    try {
        $left = @(Get-CimInstance -Namespace $ns -ClassName SMS_Scripts -Filter "ScriptName LIKE 'ZZTEST-PAS-$tag-%'")
        Add-Result 'no ZZTEST- script of this run remains' ($left.Count -eq 0) ''
        if ($snapshotTaken) {
            $after = Get-Snapshot
            Add-Result 'other scripts are unchanged' ((@($snapshot) -join "`n") -ceq (@($after) -join "`n")) ''
        }
    } catch { Add-Result 'verify cleanup' $false $_.Exception.Message }
}

# The caller polls for results.json: write a temporary file and rename it, so the caller never reads a half-written file.
$resultsTemp = Join-Path $ModuleRoot 'results.json.tmp'
$results.ToArray() | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $resultsTemp -Encoding UTF8
Move-Item -LiteralPath $resultsTemp -Destination (Join-Path $ModuleRoot 'results.json') -Force
