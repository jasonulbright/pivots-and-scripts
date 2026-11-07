# Shared helpers for the Pivots and Scripts tests. Dot-source from BeforeAll.

$script:AppRoot = Split-Path -Parent $PSScriptRoot

function Import-AppModule {
    Import-Module (Join-Path $script:AppRoot 'Module\PivotsAndScripts.psm1') -Force -DisableNameChecking
}

# SuiteCommon in the global scope, so tests can call and mock its functions the way the shell does.
function Import-SuiteCommonGlobal {
    # SuiteCommon parameter types name MahApps classes; load them so the signatures resolve.
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction SilentlyContinue
    foreach ($dll in 'Microsoft.Xaml.Behaviors.dll', 'ControlzEx.dll', 'MahApps.Metro.dll') {
        [void][System.Reflection.Assembly]::LoadFrom((Join-Path $script:AppRoot "Lib\$dll"))
    }
    Import-Module (Join-Path $script:AppRoot 'Lib\SuiteCommon\SuiteCommon.psd1') -Global -DisableNameChecking
}

# Defines a global stub function for each named ConfigMgr command, so Pester can
# mock it the same way on every machine. A function beats a cmdlet in command
# lookup, so the stub also shadows the real cmdlet on a machine that has the
# ConfigMgr console. Call Remove-CmStub afterwards so the stubs never outlive
# the test file. The stub declares the parameters that the code under test and
# the tests use; the real signatures are checked in CmCmdlet.Contract.Tests.ps1.
$script:CmStubDefinition = {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]$InputObject,
        $SiteCode, $ScriptGuid, $ScriptName, $ScriptText, $ScriptParameter, $Comment,
        $Id, $Name, $CollectionId, $Device, $Query, $Option,
        [switch]$Fast, [switch]$Force, [switch]$PassThru, [switch]$DisableWildcardHandling
    )
    process { }
}

$script:CmStubNames = 'Get-CMSite', 'Get-CMDeviceCollection', 'Get-CMDevice', 'New-CMScript', 'Remove-CMScript',
'Invoke-CMScript', 'Invoke-CMWmiQuery', 'Get-CMScript', 'Approve-CMScript', 'Deny-CMScript'

function New-CmStub {
    param(
        [Parameter(Mandatory)][string[]]$Name,
        [scriptblock]$Definition = $script:CmStubDefinition
    )
    foreach ($n in $Name) { Set-Item -Path "function:global:$n" -Value $Definition }
    return $Name
}

function Remove-CmStub {
    param([string[]]$Name)
    foreach ($n in $Name) { Remove-Item -Path "function:global:$n" -ErrorAction SilentlyContinue }
}

# A client-side CimInstance with the given properties. Typed CIM parameters (Get-CimInstance -InputObject,
# Invoke-CimMethod -InputObject) accept only real CimInstance objects; a mock cannot use a plain object there.
function New-CimFixture {
    param([Parameter(Mandatory)][string]$ClassName, [Parameter(Mandatory)][hashtable]$Property)
    $instance = [Microsoft.Management.Infrastructure.CimInstance]::new($ClassName, 'root/cimv2')
    foreach ($key in $Property.Keys) {
        $value = $Property[$key]
        $type = if ($value -is [int]) { 'SInt32' } elseif ($value -is [uint32]) { 'UInt32' } elseif ($value -is [long]) { 'SInt64' } elseif ($value -is [datetime]) { 'DateTime' } elseif ($value -is [bool]) { 'Boolean' } else { 'String' }
        $instance.CimInstanceProperties.Add([Microsoft.Management.Infrastructure.CimProperty]::Create($key, $value, $type, 'Property'))
    }
    return $instance
}

# A WebException that carries an HTTP response, for the AdminService error path. The type is created
# once per session. HttpWebResponse cannot be built, so the fake derives from WebResponse and adds the
# two properties that the module reads.
function New-FakeWebException {
    param([int]$StatusCode = 400, [string]$Description = 'Bad Request', [string]$Body = '', [switch]$NoResponse, [switch]$BrokenStream)
    if (-not ('PasFakeWebResponse' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Net;
using System.Text;
public class PasFakeWebResponse : WebResponse {
    public int StatusCode { get; set; }
    public string StatusDescription { get; set; }
    public string Body { get; set; }
    public bool Broken { get; set; }
    public override Stream GetResponseStream() {
        if (Broken) { throw new IOException("stream failed"); }
        return new MemoryStream(Encoding.UTF8.GetBytes(Body ?? ""));
    }
}
'@
    }
    if ($NoResponse) { return [System.Net.WebException]::new('The operation has timed out.') }
    $r = [PasFakeWebResponse]::new()
    $r.StatusCode = $StatusCode; $r.StatusDescription = $Description; $r.Body = $Body; $r.Broken = [bool]$BrokenStream
    return [System.Net.WebException]::new('The remote server returned an error.', $null, [System.Net.WebExceptionStatus]::ProtocolError, $r)
}

# The parameter names of one command call: the ones written as -Name, and the keys of a splatted
# hashtable (@params) that the same function or script block builds with a literal or with
# $params['Key'] / $params.Key assignments.
function Get-CommandParameterName {
    param([Parameter(Mandatory)][System.Management.Automation.Language.CommandAst]$Command)
    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($e in $Command.CommandElements) {
        if ($e -is [System.Management.Automation.Language.CommandParameterAst]) { $names.Add($e.ParameterName) }
        elseif ($e -is [System.Management.Automation.Language.VariableExpressionAst] -and $e.Splatted) {
            $var = $e.VariablePath.UserPath
            $scope = $Command.Parent
            while ($scope -and $scope -isnot [System.Management.Automation.Language.FunctionDefinitionAst] -and $scope -isnot [System.Management.Automation.Language.ScriptBlockAst]) { $scope = $scope.Parent }
            if (-not $scope) { continue }
            $assigns = $scope.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)
            foreach ($a in $assigns) {
                $left = $a.Left
                if ($left -is [System.Management.Automation.Language.VariableExpressionAst] -and $left.VariablePath.UserPath -eq $var -and $a.Right.Expression -is [System.Management.Automation.Language.HashtableAst]) {
                    foreach ($kv in $a.Right.Expression.KeyValuePairs) { if ($kv.Item1 -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $names.Add($kv.Item1.Value) } }
                }
                elseif ($left -is [System.Management.Automation.Language.IndexExpressionAst] -and $left.Target -is [System.Management.Automation.Language.VariableExpressionAst] -and $left.Target.VariablePath.UserPath -eq $var -and $left.Index -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    $names.Add($left.Index.Value)
                }
                elseif ($left -is [System.Management.Automation.Language.MemberExpressionAst] -and $left.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and $left.Expression.VariablePath.UserPath -eq $var -and $left.Member -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    $names.Add($left.Member.Value)
                }
            }
        }
    }
    return @($names | Select-Object -Unique)
}

# Lists the ConfigMgr cmdlet calls of a script file with the parameter names of each call.
function Get-CmCmdletCall {
    param([Parameter(Mandatory)][string]$Path)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    $calls = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -match '^(Get|Set|New|Remove|Start|Invoke|Add|Copy|Convert|Export|Import|Approve|Deny)-CM' -and $n.GetCommandName() -ne 'Get-CMConnectionInfo' }, $true)
    foreach ($c in $calls) {
        @{ Command = $c.GetCommandName(); Parameters = @(Get-CommandParameterName -Command $c); Line = $c.Extent.StartLineNumber }
    }
}

# Cuts the named functions out of a script file and defines them in the caller's scope (dot-source this call).
# A function cut out of the script has no $PSScriptRoot; the repository folder replaces it.
function Get-ScriptFunctionText {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$Name)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    foreach ($n in $Name) {
        $def = $ast.Find({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true)
        if (-not $def) { throw "function $n not found in $Path" }
        $def.Extent.Text.Replace('$PSScriptRoot', "'$($script:AppRoot -replace "'", "''")'")
    }
}

# The script block of an event handler such as $ui.btnCsv.Add_Click({ ... }) in a script file.
function Get-EventHandlerBlock {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Target, [Parameter(Mandatory)][string]$EventName)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    $call = $ast.Find({
            param($x)
            $x -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $x.Member.Value -eq $EventName -and $x.Expression.Extent.Text -eq $Target
        }, $true)
    if (-not $call) { throw "handler $Target.$EventName not found in $Path" }
    $block = $call.Arguments | Where-Object { $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst] } | Select-Object -First 1
    if (-not $block) { throw "handler $Target.$EventName has no script block" }
    # The extent includes the braces; the body is what a handler runs.
    $body = $block.ScriptBlock.Extent.Text
    $body = $body.Substring(1, $body.Length - 2)
    $body.Replace('$PSScriptRoot', "'$($script:AppRoot -replace "'", "''")'")
}

# A copy of the real module in which the site calls are replaced by the functions in $Overrides, for tests
# that start the worker (Module\Execute.ps1) in its own runspace. Every function that $Overrides does not
# name is the real one. Returns the path of the copy.
function New-StubModule {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Overrides)
    $real = [IO.File]::ReadAllText((Join-Path $script:AppRoot 'Module\PivotsAndScripts.psm1'))
    $needle = "Join-Path `$PSScriptRoot '..\Lib\SuiteCommon\SuiteCommon.psd1'"
    if (-not $real.Contains($needle)) { throw 'The module no longer imports SuiteCommon with the expected text; update this helper.' }
    $real = $real.Replace($needle, "'" + (Join-Path $script:AppRoot 'Lib\SuiteCommon\SuiteCommon.psd1') + "'")
    $marker = 'Export-ModuleMember -Function *-Pas*'
    if (-not $real.Contains($marker)) { throw 'The module no longer ends with the expected export line; update this helper.' }
    Set-Content -LiteralPath $Path -Value ($real.Replace($marker, $Overrides + "`r`n" + $marker))
    return $Path
}
