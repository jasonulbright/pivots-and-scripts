#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }
# Pure functions of the module: hashing, ID checks, result parsing, sorting, settings. No site, no window.
# The first tests of each group are the tests that were in Core.Tests.ps1 before the suite was added.

BeforeAll {
    . "$PSScriptRoot\TestHelpers.ps1"
    Import-AppModule
}

Describe 'Get-PasHash' {
    It 'returns the lower-case SHA-256 of the UTF-8 text: <Case>' -ForEach @(
        @{ Case = 'empty';   Text = '';          Expected = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' }
        @{ Case = 'abc';     Text = 'abc';       Expected = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' }
        @{ Case = 'non-ASCII (UTF-8 bytes C3 A9)'; Text = ([string][char]0xE9); Expected = '4a99557e4033c3539de2eb65472017cad5f9557f7a0625a09f1c3f6e2ba69c4c' }
    ) {
        Get-PasHash -Text $Text | Should -BeExactly $Expected
    }
    It 'treats null as empty text' {
        Get-PasHash -Text $null | Should -Be (Get-PasHash -Text '')
    }
    It 'gives different hashes for text that differs only in case or in one character' {
        Get-PasHash 'Disk' | Should -Not -Be (Get-PasHash 'disk')
        Get-PasHash 'Disk ' | Should -Not -Be (Get-PasHash 'Disk')
    }
    It 'hashes a long text' {
        (Get-PasHash ('x' * 1000000)).Length | Should -Be 64
    }
}

Describe 'Test-PasCollectionId' {
    It 'accepts site IDs and rejects eight-character names' {
        Test-PasCollectionId 'SMS00001' | Should -BeTrue
        Test-PasCollectionId 'MCM0001A' | Should -BeTrue
        Test-PasCollectionId 'Desktops' | Should -BeFalse
        Test-PasCollectionId 'Servers1' | Should -BeFalse
    }
    It 'gives <Expected> for <Case>' -ForEach @(
        @{ Case = 'lower case hex';        Text = 'mcm0001a';        Expected = $true }
        @{ Case = 'seven characters';      Text = 'SMS0001';         Expected = $false }
        @{ Case = 'nine characters';       Text = 'SMS000011';       Expected = $false }
        @{ Case = 'empty';                 Text = '';                Expected = $false }
        @{ Case = 'null';                  Text = $null;             Expected = $false }
        @{ Case = 'spaces around';         Text = ' SMS00001 ';      Expected = $false }
        @{ Case = 'a quote';               Text = "SMS0001'";        Expected = $false }
        @{ Case = 'a path';                Text = 'SMS0/../01';      Expected = $false }
        @{ Case = 'a trailing line break'; Text = "SMS00001`n";      Expected = $false }
        @{ Case = 'a trailing carriage return'; Text = "SMS00001`r"; Expected = $false }
        @{ Case = 'non-hex tail';          Text = 'SMS0000G';        Expected = $false }
        @{ Case = 'non-ASCII letters';     Text = ('SM' + [char]0xE9 + '00001'); Expected = $false }
    ) {
        [bool](Test-PasCollectionId $Text) | Should -Be $Expected
    }
}

Describe 'Get-PasApprovalStateName' {
    It 'names the approval states seen on the site' {
        Get-PasApprovalStateName 0 | Should -Be 'Waiting for approval'
        Get-PasApprovalStateName 1 | Should -Be 'Denied'
        Get-PasApprovalStateName 3 | Should -Be 'Approved'
    }
    It 'names state <State> as "<Expected>"' -ForEach @(
        @{ State = 2;   Expected = 'State 2' }
        @{ State = 4;   Expected = 'State 4' }
        @{ State = -1;  Expected = 'State -1' }
        @{ State = 999; Expected = 'State 999' }
    ) {
        Get-PasApprovalStateName $State | Should -Be $Expected
    }
    It 'reads a missing state as 0' {
        Get-PasApprovalStateName | Should -Be 'Waiting for approval'
    }
}

Describe 'Get-PasSubmittedMessage' {
    It 'names the script GUID and the stored parameters' {
        Get-PasSubmittedMessage -Guid 'ACDC21DE-0DF7-41F6-A406-36772AFFD432' -Parameters @('ServiceName') | Should -Be 'Script ACDC21DE-0DF7-41F6-A406-36772AFFD432 created with parameters ServiceName. Obtain approval in Configuration Manager before running.'
        Get-PasSubmittedMessage -Guid 'G' -Parameters @() | Should -Be 'Script G created. Obtain approval in Configuration Manager before running.'
    }
    It 'reports the result of approval at submission' {
        Get-PasSubmittedMessage -Guid 'G' -Parameters @() -Approved $true | Should -Be 'Script G created. Approved.'
        Get-PasSubmittedMessage -Guid 'G' -Parameters @() -ApprovalError 'Refused.' | Should -Be 'Script G created. Not approved: Refused.'
    }
    It 'lists several parameters in order' {
        Get-PasSubmittedMessage -Guid 'G' -Parameters @('A', 'B', 'C') | Should -BeLike 'Script G created with parameters A, B, C.*'
    }
    It 'ignores null and empty parameter names' {
        Get-PasSubmittedMessage -Guid 'G' -Parameters @($null, '') | Should -Be 'Script G created. Obtain approval in Configuration Manager before running.'
        Get-PasSubmittedMessage -Guid 'G' -Parameters $null | Should -Be 'Script G created. Obtain approval in Configuration Manager before running.'
    }
    It 'reports approval over an approval error when both are given' {
        Get-PasSubmittedMessage -Guid 'G' -Parameters @() -Approved $true -ApprovalError 'x' | Should -Be 'Script G created. Approved.'
    }
}

Describe 'Convert-PasRows' {
    It 'normalizes nested CMPivot JSON and keeps the trusted target identity' {
        $rows = @(Convert-PasRows -Payload ([pscustomobject]@{value = @([pscustomobject]@{Result = '[{"FreeSpace":14,"TargetResourceID":999}]' }) }) -Device 'PC-1' -ResourceID 17)
        $rows.Count | Should -Be 1
        $rows[0].FreeSpace | Should -Be 14
        $rows[0].TargetResourceID | Should -Be 17
        $rows[0].TargetDevice | Should -Be 'PC-1'
    }
    It 'reads the AdminService CMPivot envelope' {
        $payload = '{"value":{"Status":"1","MoreResult":false,"Result":[{"Caption":"Windows 11","Device":"CLIENT01"},{"Caption":"Windows 11","Device":"CLIENT01"}]}}' | ConvertFrom-Json
        $rows = @(Convert-PasRows -Payload $payload -Device 'CLIENT01' -ResourceID 16777221)
        $rows.Count | Should -Be 2
        $rows[0].Caption | Should -Be 'Windows 11'
    }
    It 'keeps a data column named Result' {
        $rows = @(Convert-PasRows -Payload '{"Device":"PC1","Result":"OK","Code":5}' -Device 'PC1' -ResourceID 1)
        $rows[0].Result | Should -Be 'OK'
        $rows[0].Code | Should -Be 5
    }
    It 'splits Run Scripts output stored with escaped quotes into columns' {
        $stored = '{\"Device\":\"CLIENT01\",\"Name\":\"CcmExec\",\"Status\":4}'
        $rows = @(Convert-PasRows -Payload $stored -Device 'CLIENT01' -ResourceID 16777221)
        $rows[0].Name | Should -Be 'CcmExec'
        $rows[0].Status | Should -Be 4
    }
    It 'keeps plain script output as text' {
        (@(Convert-PasRows -Payload 'plain output' -Device 'PC-2' -ResourceID 18))[0].Output | Should -Be 'plain output'
    }
    It 'creates no row for empty script output from a failed run' {
        @(Convert-PasRows -Payload '' -Device 'PC-1' -ResourceID 17).Count | Should -Be 0
    }
    It 'creates no row for an empty result' {
        @(Convert-PasRows -Payload ([pscustomobject]@{value = @() }) -Device 'PC-1' -ResourceID 17).Count | Should -Be 0
    }
    It 'creates no row for <Case>' -ForEach @(
        @{ Case = 'null';                Payload = $null }
        @{ Case = 'white space only';    Payload = "  `r`n " }
        @{ Case = 'an empty JSON array'; Payload = '[]' }
        @{ Case = 'a null in an array';  Payload = @($null) }
    ) {
        @(Convert-PasRows -Payload $Payload -Device 'PC-1' -ResourceID 17).Count | Should -Be 0
    }
    It 'makes one row per array element and a text row per value: <Case>' -ForEach @(
        @{ Case = 'numbers';      Payload = '[1,2,3]';          Count = 3; Output = @(1, 2, 3) }
        @{ Case = 'a JSON string'; Payload = '"hello"';         Count = 1; Output = @('hello') }
        @{ Case = 'two objects';  Payload = '[{"A":1},{"A":2}]'; Count = 2; Output = $null }
    ) {
        $rows = @(Convert-PasRows -Payload $Payload -Device 'PC-1' -ResourceID 17)
        $rows.Count | Should -Be $Count
        if ($Output) { @($rows | ForEach-Object Output) | Should -Be $Output }
        else { @($rows | ForEach-Object A) | Should -Be @(1, 2) }
    }
    It 'flattens an array that holds arrays' {
        $rows = @(Convert-PasRows -Payload '[[{"A":1}],[{"A":2},{"A":3}]]' -Device 'D' -ResourceID 1)
        @($rows | ForEach-Object A) | Should -Be @(1, 2, 3)
    }
    It 'keeps text that only looks like JSON as one text row: <Text>' -ForEach @(
        @{ Text = '[WARNING] disk low' }
        @{ Text = '{not json' }
        @{ Text = '"unterminated' }
    ) {
        $rows = @(Convert-PasRows -Payload $Text -Device 'D' -ResourceID 1)
        $rows.Count | Should -Be 1
        $rows[0].Output | Should -Be $Text
    }
    It 'overwrites a spoofed device identity with the one it was given' {
        $rows = @(Convert-PasRows -Payload '{"TargetDevice":"spoof","TargetResourceID":5,"A":1}' -Device 'REAL' -ResourceID 9)
        $rows[0].TargetDevice | Should -Be 'REAL'
        $rows[0].TargetResourceID | Should -Be 9
        @($rows[0].PSObject.Properties.Name) | Should -Be @('TargetDevice', 'TargetResourceID', 'A')
    }
    It 'keeps columns whose names are numbers or look like members: <Name>' -ForEach @(
        @{ Name = '0' }, @{ Name = 'Count' }, @{ Name = 'Keys' }, @{ Name = 'Length' }, @{ Name = 'a b' }
    ) {
        $rows = @(Convert-PasRows -Payload (@{ $Name = 'v1' } | ConvertTo-Json) -Device 'D' -ResourceID 1)
        $rows.Count | Should -Be 1
        $rows[0].PSObject.Properties[$Name].Value | Should -Be 'v1'
    }
    It 'keeps hostile text as data: <Case>' -ForEach @(
        @{ Case = 'formula';  Text = '=cmd|"/c calc"!A1' }
        @{ Case = 'script';   Text = '$(Remove-Item C:\ -Recurse)' }
        @{ Case = 'markup';   Text = '<script>alert(1)</script>' }
        @{ Case = 'a quote';  Text = "O'Brien" }
        @{ Case = 'unicode';  Text = ([string][char]0x2018 + 'x' + [char]0x2019) }
    ) {
        $rows = @(Convert-PasRows -Payload $Text -Device 'D' -ResourceID 1)
        $rows[0].Output | Should -Be $Text
    }
    It 'converts a wide result with many rows' {
        $json = '[' + ((1..500 | ForEach-Object { '{"N":' + $_ + ',"S":"v' + $_ + '"}' }) -join ',') + ']'
        $rows = @(Convert-PasRows -Payload $json -Device 'D' -ResourceID 1)
        $rows.Count | Should -Be 500
        $rows[499].S | Should -Be 'v500'
    }
    It 'reads an envelope that carries only Result and an envelope with MoreResult' {
        $rows = @(Convert-PasRows -Payload '{"Result":[{"A":1}]}' -Device 'D' -ResourceID 1)
        $rows.Count | Should -Be 1
        $rows[0].A | Should -Be 1
        $rows = @(Convert-PasRows -Payload '{"MoreResult":true,"Result":[{"A":1}]}' -Device 'D' -ResourceID 1)
        $rows[0].A | Should -Be 1
    }
}

Describe 'Test-PasEnvelope' {
    It 'is <Expected> for <Case>' -ForEach @(
        @{ Case = 'null';                     Item = $null;                                          Expected = $false }
        @{ Case = 'a string';                 Item = 'Result';                                       Expected = $false }
        @{ Case = 'a number';                 Item = 5;                                              Expected = $false }
        @{ Case = 'an object without Result'; Item = [pscustomobject]@{ A = 1 };                     Expected = $false }
        @{ Case = 'Result alone';             Item = [pscustomobject]@{ Result = 1 };                Expected = $true }
        @{ Case = 'Result and Status';        Item = [pscustomobject]@{ Result = 1; Status = '1' };  Expected = $true }
        @{ Case = 'Result and MoreResult';    Item = [pscustomobject]@{ Result = 1; MoreResult = $false }; Expected = $true }
        @{ Case = 'Result with data columns'; Item = [pscustomobject]@{ Result = 'OK'; Code = 5 };   Expected = $false }
    ) {
        Test-PasEnvelope -Item $Item | Should -Be $Expected
    }
}

Describe 'ConvertFrom-PasText' {
    It 'returns <Case> unchanged' -ForEach @(
        @{ Case = 'plain text';      Text = 'hello' }
        @{ Case = 'a bare number';   Text = '42' }
        @{ Case = 'empty text';      Text = '' }
        @{ Case = 'spaces';          Text = '   ' }
        @{ Case = 'broken JSON';     Text = '{"a":' }
    ) {
        ConvertFrom-PasText -Text $Text | Should -Be $Text
    }
    It 'parses an object, an array and a JSON string' {
        (ConvertFrom-PasText -Text '{"a":1}').a | Should -Be 1
        @(ConvertFrom-PasText -Text '[1,2]').Count | Should -Be 2
        ConvertFrom-PasText -Text '"text"' | Should -Be 'text'
    }
    It 'parses JSON that holds JSON text (a string inside a string)' {
        $inner = '"{\"a\":1}"'
        (ConvertFrom-PasText -Text $inner).a | Should -Be 1
    }
    It 'parses JSON that the site stored with escaped quotes and no delimiters' {
        (ConvertFrom-PasText -Text '{\"Name\":\"x\"}').Name | Should -Be 'x'
        @(ConvertFrom-PasText -Text '[{\"Name\":\"x\"}]')[0].Name | Should -Be 'x'
    }
    It 'trims white space before it decides' {
        (ConvertFrom-PasText -Text "  `r`n{`"a`":2}  ").a | Should -Be 2
    }
}

Describe 'ConvertFrom-PasPivotOutput' {
    It 'reads CMPivot status output as rows with the trusted device identity' {
        $output = '<result ResultCode="0" moreResults="False"><e _i="0" Caption="Windows 11" Device="spoofed" /><e _i="1" Caption="Second" /></result>'
        $parsed = ConvertFrom-PasPivotOutput -Output $output -Device 'CLIENT01' -ResourceID 16777221
        $parsed.MoreResults | Should -BeFalse
        $parsed.Rows.Count | Should -Be 2
        $parsed.Rows[0].Caption | Should -Be 'Windows 11'
        $parsed.Rows[0].TargetResourceID | Should -Be 16777221
        $parsed.Rows[0].PSObject.Properties['_i'] | Should -BeNullOrEmpty
        (ConvertFrom-PasPivotOutput -Output '<result ResultCode="0" moreResults="True"></result>' -Device 'D' -ResourceID 1).MoreResults | Should -BeTrue
        (ConvertFrom-PasPivotOutput -Output '' -Device 'D' -ResourceID 1).Rows.Count | Should -Be 0
    }
    It 'returns no rows for <Case>' -ForEach @(
        @{ Case = 'null';       Output = $null }
        @{ Case = 'white space'; Output = " `r`n " }
        @{ Case = 'an empty result'; Output = '<result moreResults="False" />' }
    ) {
        $p = ConvertFrom-PasPivotOutput -Output $Output -Device 'D' -ResourceID 1
        @($p.Rows).Count | Should -Be 0
        $p.MoreResults | Should -BeFalse
    }
    It 'keeps the attribute values as text, in document order' {
        $p = ConvertFrom-PasPivotOutput -Output '<result><e _i="0" Z="1" A="2" /></result>' -Device 'D' -ResourceID 7
        @($p.Rows[0].PSObject.Properties.Name) | Should -Be @('TargetDevice', 'TargetResourceID', 'Z', 'A')
        $p.Rows[0].Z | Should -BeOfType [string]
    }
    It 'ignores child nodes that are not elements' {
        $p = ConvertFrom-PasPivotOutput -Output '<result><!-- note --><e _i="0" A="1" /></result>' -Device 'D' -ResourceID 1
        @($p.Rows).Count | Should -Be 1
    }
    It 'decodes escaped characters and keeps hostile values as text' {
        $p = ConvertFrom-PasPivotOutput -Output '<result><e A="&lt;b&gt; &amp; &quot;q&quot;" B="=1+1" /></result>' -Device 'D' -ResourceID 1
        $p.Rows[0].A | Should -Be '<b> & "q"'
        $p.Rows[0].B | Should -Be '=1+1'
    }
    It 'throws for output that is not XML' {
        { ConvertFrom-PasPivotOutput -Output 'not xml' -Device 'D' -ResourceID 1 } | Should -Throw
        { ConvertFrom-PasPivotOutput -Output '<result><e A="1"></result>' -Device 'D' -ResourceID 1 } | Should -Throw
    }
    It 'refuses a document type in the output, with an error about the document type' {
        $xml = '<!DOCTYPE result [<!ENTITY big "EXPANDED">]><result><e A="1" />&big;</result>'
        { ConvertFrom-PasPivotOutput -Output $xml -Device 'D' -ResourceID 1 } | Should -Throw '*DTD*'
    }
    It 'refuses an entity that points to a file, with an error about the document type' {
        $marker = Join-Path $TestDrive 'secret.txt'
        Set-Content -LiteralPath $marker -Value 'SECRET-CONTENT'
        $uri = ([Uri]$marker).AbsoluteUri
        $xml = '<!DOCTYPE result [<!ENTITY x SYSTEM "' + $uri + '">]><result>&x;</result>'
        $caught = $null
        try { Read-PasXml $xml } catch { $caught = $_.Exception.Message }
        $caught | Should -BeLike '*DTD*'
        $caught | Should -Not -Match 'SECRET-CONTENT'
    }
    It 'reads a plain document through Read-PasXml' {
        (Read-PasXml '<a b="1"><c/></a>').DocumentElement.GetAttribute('b') | Should -Be '1'
    }
}
Describe 'Get-PasVisibleRows' {
    It 'returns an array with Count 1 for one visible row' {
        $rows = Get-PasVisibleRows @([pscustomobject]@{Device = 'CLIENT01' })
        $rows.Count | Should -Be 1
        $rows[0].Device | Should -Be 'CLIENT01'
    }
    It 'returns an empty array for no rows or a null source' {
        (Get-PasVisibleRows @()).Count | Should -Be 0
        (Get-PasVisibleRows $null).Count | Should -Be 0
    }
    It 'drops null entries and keeps the order' {
        $rows = Get-PasVisibleRows @([pscustomobject]@{ N = 1 }, $null, [pscustomobject]@{ N = 2 })
        $rows.Count | Should -Be 2
        @($rows | ForEach-Object N) | Should -Be @(1, 2)
    }
    It 'accepts a single object that is not an array' {
        (Get-PasVisibleRows ([pscustomobject]@{ N = 1 })).Count | Should -Be 1
    }
}

Describe 'New-PasDeviceTable' {
    It 'keys every target by ResourceID text so a run keeps Client and Active' {
        $table = New-PasDeviceTable @([pscustomobject]@{Device = 'CLIENT01'; ResourceID = 16777221; Client = $true; Active = $true }, [pscustomobject]@{Device = 'x64 Unknown Computer'; ResourceID = 2046820353; Client = $false; Active = $false })
        $table.Count | Should -Be 2
        $table['16777221'].Client | Should -BeTrue
        $table['2046820353'].Client | Should -BeFalse
        (New-PasDeviceTable @()).Count | Should -Be 0
    }
    It 'returns an empty table for null and skips null targets' {
        (New-PasDeviceTable $null).Count | Should -Be 0
        (New-PasDeviceTable @($null, [pscustomobject]@{ ResourceID = 5; Device = 'A' })).Count | Should -Be 1
    }
    It 'keeps the last target when two share a ResourceID' {
        $table = New-PasDeviceTable @([pscustomobject]@{ ResourceID = 5; Device = 'first' }, [pscustomobject]@{ ResourceID = 5; Device = 'second' })
        $table.Count | Should -Be 1
        $table['5'].Device | Should -Be 'second'
    }
}

Describe 'Sort-PasRows' {
    It 'sorts Int32 and Int64 values from ConvertFrom-Json as numbers' {
        $rows = ConvertFrom-Json '[{"Device":"A","FreeSpace":5000000000},{"Device":"B","FreeSpace":7},{"Device":"C","FreeSpace":300}]'
        $rows[0].FreeSpace | Should -BeOfType [long]
        # Windows PowerShell reads 7 as Int32; PowerShell 7 reads every integer as Int64.
        ($rows[1].FreeSpace -is [int] -or $rows[1].FreeSpace -is [long]) | Should -BeTrue
        (@(Sort-PasRows -Rows $rows -Property FreeSpace) | ForEach-Object Device) -join ',' | Should -Be 'B,C,A'
        (@(Sort-PasRows -Rows $rows -Property FreeSpace -Descending) | ForEach-Object Device) -join ',' | Should -Be 'A,C,B'
    }
    It 'sorts numeric strings from AdminService as numbers and other text as text' {
        $rows = @([pscustomobject]@{Name = 'a'; WorkingSetSize = '9977856' }, [pscustomobject]@{Name = 'b'; WorkingSetSize = '90755072' }, [pscustomobject]@{Name = 'c'; WorkingSetSize = '' }, [pscustomobject]@{Name = 'd'; WorkingSetSize = '8192' })
        (@(Sort-PasRows -Rows $rows -Property WorkingSetSize -Descending) | ForEach-Object Name) -join ',' | Should -Be 'b,a,d,c'
        $text = @([pscustomobject]@{V = '10' }, [pscustomobject]@{V = '9' }, [pscustomobject]@{V = 'x' })
        (@(Sort-PasRows -Rows $text -Property V) | ForEach-Object V) -join ',' | Should -Be '10,9,x'
    }
    It 'keeps the input order for a column the rows do not have' {
        $rows = @([pscustomobject]@{Device = 'B' }, [pscustomobject]@{Device = 'A' })
        (@(Sort-PasRows -Rows $rows -Property Missing) | ForEach-Object Device) -join ',' | Should -Be 'B,A'
    }
    It 'sorts negative, decimal and exponent values as numbers' {
        $rows = @([pscustomobject]@{ V = '1e3' }, [pscustomobject]@{ V = '-5' }, [pscustomobject]@{ V = '2.5' }, [pscustomobject]@{ V = '10' })
        (@(Sort-PasRows -Rows $rows -Property V) | ForEach-Object V) -join ',' | Should -Be '-5,2.5,10,1e3'
    }
    It 'reads numbers with the invariant culture, whatever the current culture' {
        $old = [Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('de-DE')
            $rows = @([pscustomobject]@{ V = '1.5' }, [pscustomobject]@{ V = '10.25' }, [pscustomobject]@{ V = '2.5' })
            (@(Sort-PasRows -Rows $rows -Property V) | ForEach-Object V) -join ',' | Should -Be '1.5,2.5,10.25'
        }
        finally { [Threading.Thread]::CurrentThread.CurrentCulture = $old }
    }
    It 'sorts case-insensitively as text and keeps text that starts with a digit as text' {
        $rows = @([pscustomobject]@{ V = 'b' }, [pscustomobject]@{ V = 'A' }, [pscustomobject]@{ V = '1abc' })
        (@(Sort-PasRows -Rows $rows -Property V) | ForEach-Object V) -join ',' | Should -Be '1abc,A,b'
    }
    It 'returns nothing for no rows and ignores null rows' {
        @(Sort-PasRows -Rows @() -Property V).Count | Should -Be 0
        @(Sort-PasRows -Rows $null -Property V).Count | Should -Be 0
        $err = $null
        (@(Sort-PasRows -Rows @($null, [pscustomobject]@{ V = '2' }, [pscustomobject]@{ V = '1' }) -Property V -ErrorVariable err -ErrorAction SilentlyContinue) | ForEach-Object V) -join ',' | Should -Be '1,2'
        $err | Should -BeNullOrEmpty
    }
    It 'returns one row as one row' {
        @(Sort-PasRows -Rows @([pscustomobject]@{ V = '1' }) -Property V).Count | Should -Be 1
    }
    It 'sorts a column where only some rows have a value, without an error: <Case>' -ForEach @(
        @{ Case = 'numbers'; A = '3'; B = '1' }
        @{ Case = 'text';    A = 'c'; B = 'a' }
    ) {
        $rows = @([pscustomobject]@{ V = $A }, [pscustomobject]@{ W = 'x' }, [pscustomobject]@{ V = $B })
        $err = $null
        $sorted = @(Sort-PasRows -Rows $rows -Property V -ErrorVariable err -ErrorAction SilentlyContinue)
        $err | Should -BeNullOrEmpty
        $sorted.Count | Should -Be 3
        # A row without the column sorts as an empty value, so it comes first.
        $sorted[0].PSObject.Properties['V'] | Should -BeNullOrEmpty
        $sorted[1].V | Should -Be $B
        $sorted[2].V | Should -Be $A
    }
    It 'does not throw on hostile numeric text: <Text>' -ForEach @(
        @{ Text = 'NaN' }, @{ Text = 'Infinity' }, @{ Text = '-Infinity' }, @{ Text = '1e999' }, @{ Text = '0x10' }
    ) {
        $rows = @([pscustomobject]@{ V = $Text }, [pscustomobject]@{ V = '5' })
        { @(Sort-PasRows -Rows $rows -Property V) } | Should -Not -Throw
        @(Sort-PasRows -Rows $rows -Property V).Count | Should -Be 2
    }
}

Describe 'Get-PasSettingsToSave' {
    It 'keeps the saved connection when the dialog leaves a command-line override unchanged' {
        $settings = Get-PasSettingsToSave -Entered @{SiteCode = 'ZZ1'; SMSProvider = 'cm01.contoso.com'; ApproveAfterSubmit = $true } -Session @{SiteCode = 'ZZ1'; SMSProvider = 'cm01.contoso.com' } -Persisted @{SiteCode = 'MCM'; SMSProvider = 'cm01.contoso.com' }
        $settings.SiteCode | Should -Be 'MCM'
        $settings.SMSProvider | Should -Be 'cm01.contoso.com'
        $settings.ApproveAfterSubmit | Should -BeTrue
    }
    It 'saves a value the dialog changed' {
        $settings = Get-PasSettingsToSave -Entered @{SiteCode = 'ZZ2'; SMSProvider = 'cm02.contoso.com'; ApproveAfterSubmit = $false } -Session @{SiteCode = 'ZZ1'; SMSProvider = 'cm01.contoso.com' } -Persisted @{SiteCode = 'MCM'; SMSProvider = 'cm01.contoso.com' }
        $settings.SiteCode | Should -Be 'ZZ2'
        $settings.SMSProvider | Should -Be 'cm02.contoso.com'
    }
    It 'handles the two connection values one at a time' {
        $settings = Get-PasSettingsToSave -Entered @{SiteCode = 'ZZ1'; SMSProvider = 'new.contoso.com' } -Session @{SiteCode = 'ZZ1'; SMSProvider = 'old.contoso.com' } -Persisted @{SiteCode = 'MCM'; SMSProvider = 'old.contoso.com' }
        $settings.SiteCode | Should -Be 'MCM'
        $settings.SMSProvider | Should -Be 'new.contoso.com'
    }
    It 'passes other settings through and does not change its inputs' {
        $entered = @{SiteCode = 'A1B'; SMSProvider = 'p'; ApproveAfterSubmit = $true; Extra = 7 }
        $session = @{SiteCode = 'A1B'; SMSProvider = 'p' }
        $persisted = @{SiteCode = 'X1X'; SMSProvider = 'q' }
        $settings = Get-PasSettingsToSave -Entered $entered -Session $session -Persisted $persisted
        $settings.Extra | Should -Be 7
        $entered.SiteCode | Should -Be 'A1B'
        $persisted.SiteCode | Should -Be 'X1X'
    }
    It 'compares case-sensitively: a different case counts as a change' {
        $settings = Get-PasSettingsToSave -Entered @{SiteCode = 'mcm'; SMSProvider = 'p' } -Session @{SiteCode = 'MCM'; SMSProvider = 'p' } -Persisted @{SiteCode = 'ZZZ'; SMSProvider = 'p' }
        $settings.SiteCode | Should -BeExactly 'mcm'
    }
    It 'saves empty text when the user clears a value that was set on the command line' {
        $settings = Get-PasSettingsToSave -Entered @{SiteCode = ''; SMSProvider = '' } -Session @{SiteCode = 'ZZ1'; SMSProvider = 'p' } -Persisted @{SiteCode = 'MCM'; SMSProvider = 'p' }
        $settings.SiteCode | Should -Be ''
        $settings.SMSProvider | Should -Be ''
    }
    It 'keeps an empty saved value when the dialog leaves an empty value unchanged' {
        $settings = Get-PasSettingsToSave -Entered @{SiteCode = ''; SMSProvider = '' } -Session @{SiteCode = ''; SMSProvider = '' } -Persisted @{SiteCode = ''; SMSProvider = '' }
        $settings.SiteCode | Should -Be ''
        $settings.SMSProvider | Should -Be ''
    }
}

Describe 'Get-PasWorkerError' {
    It 'returns nothing for a cmdlet error the worker caught; HadErrors is still true' {
        $ps = [PowerShell]::Create()
        try {
            [void]$ps.AddScript('$ErrorActionPreference="Stop"; try { Get-Item -LiteralPath "C:\pas-no-such-path" } catch { }')
            $null = $ps.Invoke()
            $ps.HadErrors | Should -BeTrue
            Get-PasWorkerError $ps | Should -BeNullOrEmpty
        } finally { $ps.Dispose() }
    }
    It 'returns a fixed sentence for an uncaught non-terminating error and logs its text' {
        $log = Join-Path $TestDrive 'worker-error.log'
        Set-PasLogPath $log
        $ps = [PowerShell]::Create()
        try {
            [void]$ps.AddScript('Write-Error "worker failed"')
            $null = $ps.Invoke()
            Get-PasWorkerError $ps | Should -Be 'The worker reported an error. The log file has the details.'
        } finally { $ps.Dispose(); Set-PasLogPath '' }
        (Get-Content -LiteralPath $log -Raw) | Should -Match 'worker failed'
    }
    It 'logs several errors joined with line breaks' {
        $log = Join-Path $TestDrive 'worker-errors.log'
        Set-PasLogPath $log
        $ps = [PowerShell]::Create()
        try {
            [void]$ps.AddScript('Write-Error "first"; Write-Error "second"')
            $null = $ps.Invoke()
            Get-PasWorkerError $ps | Should -Be 'The worker reported an error. The log file has the details.'
        } finally { $ps.Dispose(); Set-PasLogPath '' }
        (Get-Content -LiteralPath $log -Raw) | Should -Match 'first\r?\nsecond'
    }
    It 'returns nothing when the worker had no error' {
        $ps = [PowerShell]::Create()
        try {
            [void]$ps.AddScript('1 + 1')
            $null = $ps.Invoke()
            Get-PasWorkerError $ps | Should -BeNullOrEmpty
        } finally { $ps.Dispose() }
    }
}

Describe 'Write-PasLog and Set-PasLogPath' {
    BeforeEach { Set-PasLogPath '' }
    AfterEach { Set-PasLogPath '' }
    It 'does nothing and does not throw when no log path is set' {
        { Write-PasLog 'text' } | Should -Not -Throw
        { Write-PasLog -Message 'text' -Level WARN } | Should -Not -Throw
    }
    It 'appends one line with the time, the level and the text' {
        $log = Join-Path $TestDrive 'a.log'
        Set-PasLogPath $log
        Write-PasLog 'first' -Level WARN
        Write-PasLog 'second' -Level INFO
        $lines = @(Get-Content -LiteralPath $log)
        $lines.Count | Should -Be 2
        $lines[0] | Should -Match '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[WARN\] first$'
        $lines[1] | Should -Match '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[INFO\] second$'
    }
    It 'uses the level ERROR when no level is given' {
        $log = Join-Path $TestDrive 'b.log'
        Set-PasLogPath $log
        Write-PasLog 'text'
        (Get-Content -LiteralPath $log -Raw) | Should -Match '\[ERROR\] text'
    }
    It 'refuses a level that is not INFO, WARN or ERROR' {
        Set-PasLogPath (Join-Path $TestDrive 'c.log')
        { Write-PasLog 'text' -Level 'DEBUG' } | Should -Throw
    }
    It 'creates the folder of the log file' {
        $log = Join-Path $TestDrive 'new folder\inner\d.log'
        Set-PasLogPath $log
        Write-PasLog 'text'
        Test-Path -LiteralPath $log | Should -BeTrue
    }
    It 'writes while another reader or writer holds the file open' {
        $log = Join-Path $TestDrive 'e.log'
        [IO.File]::WriteAllText($log, '')
        $other = [IO.File]::Open($log, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
        try {
            Set-PasLogPath $log
            Write-PasLog 'shared'
        }
        finally { $other.Dispose() }
        (Get-Content -LiteralPath $log -Raw) | Should -Match 'shared'
    }
    It 'swallows a failure, such as a path that is a folder' {
        Set-PasLogPath $TestDrive
        { Write-PasLog 'text' } | Should -Not -Throw
    }
    It 'stops writing after the path is cleared' {
        $log = Join-Path $TestDrive 'f.log'
        Set-PasLogPath $log
        Write-PasLog 'one'
        Set-PasLogPath ''
        Write-PasLog 'two'
        (Get-Content -LiteralPath $log -Raw) | Should -Not -Match 'two'
    }
}

Describe 'Get-PasUserErrorText' {
    BeforeAll {
        function script:Get-Record { param([scriptblock]$Block) try { & $Block } catch { return $_ } }
    }
    BeforeEach { Set-PasLogPath '' }
    AfterEach { Set-PasLogPath '' }
    It 'passes the message of a plain throw through and writes no log line' {
        $log = Join-Path $TestDrive 'u1.log'
        Set-PasLogPath $log
        $record = Get-Record { throw 'Enter a target.' }
        Get-PasUserErrorText -ErrorRecord $record -Fallback 'Fallback.' -LogDetail | Should -Be 'Enter a target.'
        Test-Path -LiteralPath $log | Should -BeFalse
    }
    It 'gives the fallback and logs the raw text and the type for a typed exception' {
        $log = Join-Path $TestDrive 'u2.log'
        Set-PasLogPath $log
        $record = Get-Record { throw [System.IO.IOException]::new('raw io detail') }
        Get-PasUserErrorText -ErrorRecord $record -Fallback 'Fallback.' -LogDetail | Should -Be 'Fallback.'
        $text = Get-Content -LiteralPath $log -Raw
        $text | Should -Match 'raw io detail'
        $text | Should -Match 'System\.IO\.IOException'
    }
    It 'gives the fallback for a RuntimeException that has an inner exception' {
        $log = Join-Path $TestDrive 'u3.log'
        Set-PasLogPath $log
        $record = Get-Record { throw [System.Management.Automation.RuntimeException]::new('outer detail', [System.InvalidOperationException]::new('inner detail')) }
        Get-PasUserErrorText -ErrorRecord $record -Fallback 'Fallback.' -LogDetail | Should -Be 'Fallback.'
        (Get-Content -LiteralPath $log -Raw) | Should -Match 'outer detail'
    }
    It 'gives the fallback for a cmdlet error and logs its text' {
        $log = Join-Path $TestDrive 'u4.log'
        Set-PasLogPath $log
        $missing = Join-Path $TestDrive 'no-such-file-here.txt'
        $record = Get-Record { Get-Item -LiteralPath $missing -ErrorAction Stop }
        Get-PasUserErrorText -ErrorRecord $record -Fallback 'Fallback.' -LogDetail | Should -Be 'Fallback.'
        (Get-Content -LiteralPath $log -Raw) | Should -Match 'no-such-file-here'
    }
    It 'gives the fallback for an engine error' {
        $record = Get-Record { $null.Missing() }
        Get-PasUserErrorText -ErrorRecord $record -Fallback 'Fallback.' | Should -Be 'Fallback.'
    }
    It 'writes no log line without -LogDetail' {
        $log = Join-Path $TestDrive 'u5.log'
        Set-PasLogPath $log
        $record = Get-Record { throw [System.IO.IOException]::new('raw io detail') }
        Get-PasUserErrorText -ErrorRecord $record -Fallback 'Fallback.' | Should -Be 'Fallback.'
        Test-Path -LiteralPath $log | Should -BeFalse
    }
    It 'does not throw when no log path is set' {
        $record = Get-Record { throw [System.IO.IOException]::new('raw io detail') }
        { Get-PasUserErrorText -ErrorRecord $record -Fallback 'Fallback.' -LogDetail } | Should -Not -Throw
        Get-PasUserErrorText -ErrorRecord $record -Fallback 'Fallback.' -LogDetail | Should -Be 'Fallback.'
    }
}
