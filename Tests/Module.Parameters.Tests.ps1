#Requires -Modules Pester
# Script parameters: reading them from script text, checking them against what Run Scripts accepts,
# storing them as a site definition, and turning the typed values into the arguments of a run.

BeforeAll {
    . "$PSScriptRoot\TestHelpers.ps1"
    Import-AppModule
}

Describe 'Get-PasParameters' {
    It 'extracts parameters from the AST' {
        $params = @(Get-PasParameters 'param([string]$Name="CcmExec",[switch]$VerboseOutput) Get-Service $Name')
        $params.Count | Should -Be 2
        $params[0].Name | Should -Be 'Name'
        $params[0].DefaultLiteral | Should -Be 'CcmExec'
    }
    It 'rejects invalid script text' {
        { Get-PasParameters 'param( {' } | Should -Throw
    }
    It 'does not evaluate default expressions' {
        $marker = Join-Path ([IO.Path]::GetTempPath()) ('pas-marker-' + [guid]::NewGuid().ToString('N'))
        $params = @(Get-PasParameters ('param([string]$Path=$(Set-Content -LiteralPath ''{0}'' -Value x))' -f $marker))
        $params[0].DefaultLiteral | Should -Be ''
        Test-Path -LiteralPath $marker | Should -BeFalse
    }
    It 'reads Mandatory and ValidateSet' {
        $params = @(Get-PasParameters 'param([Parameter(Mandatory)][ValidateSet("A","B")][string]$Mode,[Parameter(Mandatory=$false)][int]$Count=2)')
        $params[0].Mandatory | Should -BeTrue
        $params[0].Choices | Should -Be @('A', 'B')
        $params[1].Mandatory | Should -BeFalse
        $params[1].SiteType | Should -Be 'System.Int32'
    }
    It 'returns no parameters for <Case>' -ForEach @(
        @{ Case = 'empty text';          Text = '' }
        @{ Case = 'null';                Text = $null }
        @{ Case = 'white space';         Text = "  `r`n" }
        @{ Case = 'script without param'; Text = 'Get-Service' }
        @{ Case = 'an empty param block'; Text = 'param() Get-Service' }
        @{ Case = 'a comment only';      Text = '# param([string]$x)' }
    ) {
        @(Get-PasParameters $Text).Count | Should -Be 0
    }
    It 'reports the syntax error message for script that does not parse: <Text>' -ForEach @(
        @{ Text = 'param([string]$a' }
        @{ Text = 'param($a,,$b)' }
        @{ Text = 'if (' }
    ) {
        { Get-PasParameters $Text } | Should -Throw
    }
    It 'reads <Case> as type <Type>, site type <SiteType>' -ForEach @(
        @{ Case = 'string';        Decl = '[string]$p';   Type = 'System.String';  SiteType = 'System.String' }
        @{ Case = 'int';           Decl = '[int]$p';      Type = 'System.Int32';   SiteType = 'System.Int32' }
        @{ Case = 'no type';       Decl = '$p';           Type = 'System.Object';  SiteType = 'System.String' }
        @{ Case = 'object';        Decl = '[object]$p';   Type = 'System.Object';  SiteType = 'System.String' }
        @{ Case = 'switch';        Decl = '[switch]$p';   Type = 'System.Management.Automation.SwitchParameter'; SiteType = '' }
        @{ Case = 'bool';          Decl = '[bool]$p';     Type = 'System.Boolean'; SiteType = '' }
        @{ Case = 'long';          Decl = '[long]$p';     Type = 'System.Int64';   SiteType = '' }
        @{ Case = 'string array';  Decl = '[string[]]$p'; Type = 'System.String[]'; SiteType = '' }
        @{ Case = 'datetime';      Decl = '[datetime]$p'; Type = 'System.DateTime'; SiteType = '' }
    ) {
        $p = @(Get-PasParameters "param($Decl)")
        $p.Count | Should -Be 1
        $p[0].Type | Should -Be $Type
        $p[0].SiteType | Should -Be $SiteType
    }
    It 'reads the default value as text: <Case>' -ForEach @(
        @{ Case = 'string';       Decl = '[string]$p = "abc"';    Literal = 'abc';  Extent = '"abc"' }
        @{ Case = 'int';          Decl = '[int]$p = 7';           Literal = '7';    Extent = '7' }
        @{ Case = 'negative int'; Decl = '[int]$p = -3';          Literal = '-3';   Extent = '-3' }
        @{ Case = 'null';         Decl = '[string]$p = $null';    Literal = '';     Extent = '$null' }
        @{ Case = 'none';         Decl = '[string]$p';            Literal = '';     Extent = '' }
        @{ Case = 'an expression'; Decl = '[string]$p = (Get-Date)'; Literal = ''; Extent = '(Get-Date)' }
        @{ Case = 'a variable';   Decl = '[string]$p = $env:TEMP'; Literal = ''; Extent = '$env:TEMP' }
    ) {
        $p = @(Get-PasParameters "param($Decl)")
        $p[0].DefaultLiteral | Should -Be $Literal
        $p[0].Default | Should -Be $Extent
    }
    It 'reads Mandatory in each spelling: <Decl>' -ForEach @(
        @{ Decl = '[Parameter(Mandatory)]$p';                 Expected = $true }
        @{ Decl = '[Parameter(Mandatory=$true)]$p';           Expected = $true }
        @{ Decl = '[Parameter(Mandatory=$TRUE)]$p';           Expected = $true }
        @{ Decl = '[Parameter(Mandatory=$false)]$p';          Expected = $false }
        @{ Decl = '[Parameter(Position=0)]$p';                Expected = $false }
        @{ Decl = '[Parameter()]$p';                          Expected = $false }
        @{ Decl = '$p';                                       Expected = $false }
    ) {
        (@(Get-PasParameters "param($Decl)"))[0].Mandatory | Should -Be $Expected
    }
    It 'reads the choices of a ValidateSet in order, and no choices for a parameter without one' {
        $p = @(Get-PasParameters 'param([ValidateSet("b","a","c")][string]$p, [string]$q)')
        $p[0].Choices | Should -Be @('b', 'a', 'c')
        @($p[1].Choices).Count | Should -Be 0
    }
    It 'reads parameters in order and one parameter per name' {
        $p = @(Get-PasParameters 'param([string]$Zeta, [int]$Alpha = 1, $Mid)')
        @($p | ForEach-Object Name) | Should -Be @('Zeta', 'Alpha', 'Mid')
    }
    It 'reads parameters of a script with a leading comment, a using line and a function' {
        $text = "# header`r`nparam([string]`$Name)`r`nfunction Inner { param([int]`$X) }`r`nGet-Service `$Name"
        $p = @(Get-PasParameters $text)
        $p.Count | Should -Be 1
        $p[0].Name | Should -Be 'Name'
    }
    It 'handles a very long parameter list and a long default' {
        $text = 'param(' + ((1..50 | ForEach-Object { "[string]`$P$_ = '" + ('x' * 100) + "'" }) -join ',') + ')'
        $p = @(Get-PasParameters $text)
        $p.Count | Should -Be 50
        $p[49].DefaultLiteral.Length | Should -Be 100
    }
}

Describe 'Get-PasSiteParameterType' {
    It 'maps <Type> to "<Expected>"' -ForEach @(
        @{ Type = [string];   Expected = 'System.String' }
        @{ Type = [object];   Expected = 'System.String' }
        @{ Type = [int];      Expected = 'System.Int32' }
        @{ Type = [bool];     Expected = '' }
        @{ Type = [long];     Expected = '' }
        @{ Type = [double];   Expected = '' }
        @{ Type = [string[]]; Expected = '' }
        @{ Type = [switch];   Expected = '' }
        @{ Type = [guid];     Expected = '' }
    ) {
        Get-PasSiteParameterType -Type $Type | Should -Be $Expected
    }
}

Describe 'Assert-PasScriptParameters' {
    It 'refuses switch and bool parameters, which the site rejects' {
        { Assert-PasScriptParameters @(Get-PasParameters 'param([switch]$Detailed)') } | Should -Throw '*string and integer*'
        { Assert-PasScriptParameters @(Get-PasParameters 'param([bool]$Flag)') } | Should -Throw '*string and integer*'
    }
    It 'refuses a single quote in a default value' {
        { Assert-PasScriptParameters @(Get-PasParameters "param([string]`$Name=""O'Brien"")") } | Should -Throw '*single quote*'
    }
    It 'refuses more than 10 parameters' {
        $text = 'param(' + ((1..11 | ForEach-Object { "[string]`$P$_" }) -join ',') + ')'
        { Assert-PasScriptParameters @(Get-PasParameters $text) } | Should -Throw '*at most 10*'
    }
    It 'accepts exactly 10 parameters' {
        $text = 'param(' + ((1..10 | ForEach-Object { "[string]`$P$_" }) -join ',') + ')'
        { Assert-PasScriptParameters @(Get-PasParameters $text) } | Should -Not -Throw
    }
    It 'accepts <Case>' -ForEach @(
        @{ Case = 'no parameters';  Params = @() }
        @{ Case = 'null';           Params = $null }
        @{ Case = 'a null element'; Params = @($null) }
    ) {
        { Assert-PasScriptParameters $Params } | Should -Not -Throw
    }
    It 'names every unsupported parameter with its type' {
        $params = @(Get-PasParameters 'param([switch]$A, [string]$B, [bool]$C)')
        $message = $null
        try { Assert-PasScriptParameters $params } catch { $message = $_.Exception.Message }
        $message | Should -Match 'A \(System\.Management\.Automation\.SwitchParameter\)'
        $message | Should -Match 'C \(System\.Boolean\)'
        $message | Should -Not -Match 'B \('
    }
    It 'names every parameter whose default holds a single quote' {
        $params = @(Get-PasParameters "param([string]`$A = ""it's"", [string]`$B = 'ok', [string]`$C = ""x'y"")")
        $message = $null
        try { Assert-PasScriptParameters $params } catch { $message = $_.Exception.Message }
        $message | Should -Match 'A, C'
    }
    It 'checks the type before the quote' {
        $params = @(Get-PasParameters "param([switch]`$A, [string]`$B = ""it's"")")
        { Assert-PasScriptParameters $params } | Should -Throw '*string and integer*'
    }
}

Describe 'ConvertTo-PasParamsDefinition and ConvertFrom-PasParamsDefinition' {
    It 'writes the site parameter definition and reads it back' {
        $params = @(Get-PasParameters 'param([Parameter(Mandatory)][string]$Name="A&B",[int]$Count=1)')
        $xml = ConvertTo-PasParamsDefinition $params
        $xml | Should -Match '^<\?xml version="1.0" encoding="utf-16"\?><ScriptParameters SchemaVersion="1">'
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($xml))
        $back = @(ConvertFrom-PasParamsDefinition $encoded)
        $back.Count | Should -Be 2
        $back[0].Name | Should -Be 'Name'
        $back[0].Type | Should -Be 'System.String'
        $back[0].Required | Should -BeTrue
        $back[0].Default | Should -Be 'A&B'
        $back[1].Type | Should -Be 'System.Int32'
    }
    It 'reads the definition format of the built-in CMPivot script' {
        $builtin = '<?xml version="1.0" encoding="utf-16"?><ScriptParameters SchemaVersion="1"><ScriptParameter Name="kustoquery" FriendlyName="kustoquery" Type="System.String" Description="" IsRequired="false" IsHidden="false" DefaultValue=""><Validators /></ScriptParameter></ScriptParameters>'
        $back = @(ConvertFrom-PasParamsDefinition ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($builtin))))
        $back[0].Name | Should -Be 'kustoquery'
    }
    It 'writes an empty definition for <Case>' -ForEach @(
        @{ Case = 'no parameters'; Params = @() }
        @{ Case = 'null';          Params = $null }
        @{ Case = 'null elements'; Params = @($null, $null) }
    ) {
        ConvertTo-PasParamsDefinition $Params | Should -Be '<?xml version="1.0" encoding="utf-16"?><ScriptParameters SchemaVersion="1"></ScriptParameters>'
    }
    It 'writes IsRequired as lower-case true or false' {
        $xml = ConvertTo-PasParamsDefinition @(Get-PasParameters 'param([Parameter(Mandatory)]$A,$B)')
        $xml | Should -Match 'Name="A"[^>]*IsRequired="true"'
        $xml | Should -Match 'Name="B"[^>]*IsRequired="false"'
    }
    It 'produces XML that parses, for markup and quote characters in a default value: <Case>' -ForEach @(
        @{ Case = 'angle brackets'; Value = '<a>' }
        @{ Case = 'ampersand';      Value = 'x&y' }
        @{ Case = 'double quote';   Value = 'say "hi"' }
        @{ Case = 'entity text';    Value = '&amp;' }
        @{ Case = 'CDATA end';      Value = ']]>' }
    ) {
        $p = [pscustomobject]@{ Name = 'P'; SiteType = 'System.String'; Mandatory = $false; DefaultLiteral = $Value }
        $xml = ConvertTo-PasParamsDefinition @($p)
        { [xml]($xml -replace '^<\?xml[^>]*\?>', '') } | Should -Not -Throw
        $back = @(ConvertFrom-PasParamsDefinition ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($xml))))
        $back[0].Default | Should -Be $Value
    }
    It 'keeps a name with markup characters apart from the attribute syntax' {
        $p = [pscustomobject]@{ Name = 'A"B<C'; SiteType = 'System.String'; Mandatory = $false; DefaultLiteral = '' }
        $xml = ConvertTo-PasParamsDefinition @($p)
        $back = @(ConvertFrom-PasParamsDefinition ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($xml))))
        $back[0].Name | Should -Be 'A"B<C'
    }
    It 'keeps line breaks and tabs of a default value through the site definition' {
        $p = [pscustomobject]@{ Name = 'P'; SiteType = 'System.String'; Mandatory = $false; DefaultLiteral = "line1`r`nline2`tend" }
        $xml = ConvertTo-PasParamsDefinition @($p)
        $back = @(ConvertFrom-PasParamsDefinition ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($xml))))
        $back[0].Default | Should -Be "line1`r`nline2`tend"
    }
    It 'keeps non-ASCII text of a default value' {
        $value = 'caf' + [char]0xE9 + ' ' + [char]0x20AC
        $p = [pscustomobject]@{ Name = 'P'; SiteType = 'System.String'; Mandatory = $false; DefaultLiteral = $value }
        $back = @(ConvertFrom-PasParamsDefinition ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((ConvertTo-PasParamsDefinition @($p))))))
        $back[0].Default | Should -Be $value
    }
    It 'reads nothing for an empty definition: <Case>' -ForEach @(
        @{ Case = 'empty';      Encoded = '' }
        @{ Case = 'null';       Encoded = $null }
        @{ Case = 'white space'; Encoded = '   ' }
    ) {
        @(ConvertFrom-PasParamsDefinition $Encoded).Count | Should -Be 0
    }
    It 'reads a definition with no parameters' {
        $xml = '<?xml version="1.0" encoding="utf-16"?><ScriptParameters SchemaVersion="1"></ScriptParameters>'
        @(ConvertFrom-PasParamsDefinition ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($xml)))).Count | Should -Be 0
    }
    It 'reads a definition that starts with a byte order mark' {
        $xml = [string][char]0xFEFF + '<?xml version="1.0" encoding="utf-16"?><ScriptParameters SchemaVersion="1"><ScriptParameter Name="A" Type="System.String" IsRequired="true" DefaultValue="d"/></ScriptParameters>'
        $back = @(ConvertFrom-PasParamsDefinition ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($xml))))
        $back[0].Name | Should -Be 'A'
        $back[0].Required | Should -BeTrue
    }
    It 'throws for a definition that is not valid <Case>' -ForEach @(
        @{ Case = 'Base64';  Encoded = 'not base64 !!' }
        @{ Case = 'XML';     Encoded = ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('<ScriptParameters><x></ScriptParameters>'))) }
    ) {
        { ConvertFrom-PasParamsDefinition $Encoded } | Should -Throw
    }
    It 'does not expand an entity that a stored definition declares' {
        $xml = '<!DOCTYPE ScriptParameters [<!ENTITY big "EXPANDED">]><ScriptParameters><ScriptParameter Name="A" Type="System.String" IsRequired="false" DefaultValue="&big;"/></ScriptParameters>'
        $text = $null
        try { $text = (@(ConvertFrom-PasParamsDefinition ([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($xml))))[0]).Default } catch { $text = 'rejected' }
        $text | Should -Be 'rejected'
    }
}

Describe 'ConvertTo-PasScriptArguments' {
    BeforeAll {
        $script:site = [pscustomobject]@{ScriptGuid = 'G'; Parameters = @([pscustomobject]@{Name = 'Name'; Type = 'System.String'; Required = $false; Default = 'CcmExec' }, [pscustomobject]@{Name = 'Count'; Type = 'System.Int32'; Required = $false; Default = '1' }) }
    }
    It 'sends integers as Int32; the site drops integer values sent as text' {
        $arguments = ConvertTo-PasScriptArguments -SiteScript $script:site -Parameters @{Count = '7'; Name = 'Spooler' }
        $arguments.Count | Should -BeOfType [int]
        $arguments.Count | Should -Be 7
    }
    It 'refuses a name the site does not define; the site drops it silently' {
        { ConvertTo-PasScriptArguments -SiteScript $script:site -Parameters @{Nope = 'x' } } | Should -Throw '*not defined*'
    }
    It 'refuses values when the site script has no definitions' {
        $bare = [pscustomobject]@{ScriptGuid = 'G'; Parameters = @() }
        { ConvertTo-PasScriptArguments -SiteScript $bare -Parameters @{Name = 'x' } } | Should -Throw '*no parameter definitions*'
    }
    It 'refuses a single quote; the client script fails on it' {
        { ConvertTo-PasScriptArguments -SiteScript $script:site -Parameters @{Name = "O'Brien" } } | Should -Throw '*single quote*'
    }
    It 'refuses to run when the stored definitions cannot be read' {
        $broken = [pscustomobject]@{ScriptGuid = 'G'; Parameters = @(); DefinitionError = 'The input is not a valid Base-64 string.' }
        { ConvertTo-PasScriptArguments -SiteScript $broken -Parameters @{} } | Should -Throw '*cannot be read*'
    }
    It 'refuses a missing required value without a default' {
        $required = [pscustomobject]@{ScriptGuid = 'G'; Parameters = @([pscustomobject]@{Name = 'Path'; Type = 'System.String'; Required = $true; Default = '' }) }
        { ConvertTo-PasScriptArguments -SiteScript $required -Parameters @{} } | Should -Throw '*required*'
    }
    It 'accepts a missing required value that has a default' {
        $required = [pscustomobject]@{ScriptGuid = 'G'; Parameters = @([pscustomobject]@{Name = 'Path'; Type = 'System.String'; Required = $true; Default = 'C:\' }) }
        (ConvertTo-PasScriptArguments -SiteScript $required -Parameters @{}).Count | Should -Be 0
    }
    It 'returns an empty table for no values' {
        (ConvertTo-PasScriptArguments -SiteScript $script:site -Parameters @{}).Count | Should -Be 0
    }
    It 'treats null values like an empty table' {
        (ConvertTo-PasScriptArguments -SiteScript $script:site -Parameters $null).Count | Should -Be 0
    }
    It 'refuses a whole number that is <Case>' -ForEach @(
        @{ Case = 'text';         Value = 'abc' }
        @{ Case = 'a decimal';    Value = '1.5' }
        @{ Case = 'too large';    Value = '99999999999' }
        @{ Case = 'empty';        Value = '' }
        @{ Case = 'hex';          Value = '0x10' }
        @{ Case = 'with a comma'; Value = '1,000' }
    ) {
        { ConvertTo-PasScriptArguments -SiteScript $script:site -Parameters @{ Count = $Value } } | Should -Throw '*whole number*'
    }
    It 'accepts the whole number <Value> as <Expected>' -ForEach @(
        @{ Value = '0';          Expected = 0 }
        @{ Value = '-5';         Expected = -5 }
        @{ Value = '2147483647'; Expected = 2147483647 }
        @{ Value = ' 8 ';        Expected = 8 }
        @{ Value = 9;            Expected = 9 }
    ) {
        (ConvertTo-PasScriptArguments -SiteScript $script:site -Parameters @{ Count = $Value }).Count | Should -Be $Expected
    }
    It 'keeps a text value as it is, including hostile text' -ForEach @(
        @{ Text = '$(Remove-Item C:\)' }, @{ Text = '"; calc; "' }, @{ Text = '<x>&' }, @{ Text = ('caf' + [char]0xE9) }, @{ Text = '' }
    ) {
        $arguments = ConvertTo-PasScriptArguments -SiteScript $script:site -Parameters @{ Name = $Text }
        $arguments.Name | Should -BeExactly $Text
        $arguments.Name | Should -BeOfType [string]
    }
    It 'refuses a parameter whose site type the run does not accept' {
        $odd = [pscustomobject]@{ScriptGuid = 'G'; Parameters = @([pscustomobject]@{Name = 'Flag'; Type = 'System.Boolean'; Required = $false; Default = '' }) }
        { ConvertTo-PasScriptArguments -SiteScript $odd -Parameters @{ Flag = 'true' } } | Should -Throw '*does not accept*'
    }
    It 'lists the defined names, sorted, when a name is unknown' {
        $message = $null
        try { ConvertTo-PasScriptArguments -SiteScript $script:site -Parameters @{ Zed = 'x' } } catch { $message = $_.Exception.Message }
        $message | Should -BeLike '*Defined: Count, Name.'
    }
    It 'matches parameter names without regard to case' {
        $arguments = ConvertTo-PasScriptArguments -SiteScript $script:site -Parameters @{ name = 'x' }
        $arguments['name'] | Should -Be 'x'
    }
    It 'reads a site script that has no DefinitionError property' {
        $plain = [pscustomobject]@{ScriptGuid = 'G'; Parameters = @() }
        (ConvertTo-PasScriptArguments -SiteScript $plain -Parameters @{}).Count | Should -Be 0
    }
}
