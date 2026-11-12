#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.1.0' }
# The AdminService calls of the module: the request builder and error mapping (Invoke-PasAdminService),
# the CMPivot start (Start-PasPivotRun) and the status pages (Get-PasPivotStatus). Invoke-RestMethod is
# mocked; a mock body reads its fixtures from $global:Fx.

BeforeAll {
    . "$PSScriptRoot\TestHelpers.ps1"
    Import-AppModule
}

AfterAll { Remove-Variable -Name Fx -Scope Global -ErrorAction SilentlyContinue }

Describe 'Invoke-PasAdminService' {
    BeforeEach {
        $global:Fx = @{ Last = $null; Response = $null; Throw = $null; Calls = 0 }
        Mock Invoke-RestMethod {
            $global:Fx.Calls++
            $global:Fx.Last = @{} + $PesterBoundParameters
            if ($global:Fx.Throw) { throw $global:Fx.Throw }
            $global:Fx.Response
        } -ModuleName PivotsAndScripts
    }
    It 'sends a GET to the versioned URL of the provider with the caller credential' {
        $global:Fx.Response = [pscustomobject]@{ value = @(1) }
        $r = Invoke-PasAdminService -SMSProvider 'cm01.contoso.com' -RelativePath 'SMS_CMPivotStatus'
        $r.value | Should -Be 1
        $l = $global:Fx.Last
        $l.Uri | Should -Be 'https://cm01.contoso.com/AdminService/v1.0/SMS_CMPivotStatus'
        $l.Method | Should -Be 'GET'
        $l.UseDefaultCredentials | Should -BeTrue
        # PowerShell 7.4 and later name the parameter differently and keep TimeoutSec as an alias.
        $timeoutKeys = @($l.Keys | Where-Object { $_ -like '*Timeout*' })
        $timeoutKeys.Count | Should -Be 1
        $l[$timeoutKeys[0]] | Should -Be 30
        [string]$l.ErrorAction | Should -Be 'Stop'
        $l.ContainsKey('Body') | Should -BeFalse
        $l.ContainsKey('ContentType') | Should -BeFalse
    }
    It 'sends a POST with a compact UTF-8 JSON body and a charset' {
        Invoke-PasAdminService -SMSProvider 'cm01' -RelativePath 'X/AdminService.RunCMPivot' -Method POST -Body @{ InputQuery = 'OS'; ResourceIds = '1,2' } | Out-Null
        $l = $global:Fx.Last
        $l.Method | Should -Be 'POST'
        $l.ContentType | Should -Be 'application/json; charset=utf-8'
        $l.Body | Should -BeOfType [byte]
        $json = [Text.Encoding]::UTF8.GetString($l.Body)
        $json | Should -Not -Match '\s{2,}|\r|\n'
        $o = $json | ConvertFrom-Json
        $o.InputQuery | Should -Be 'OS'
        $o.ResourceIds | Should -Be '1,2'
    }
    It 'sends non-ASCII query text as UTF-8, not as question marks' {
        $q = 'Device | where Name == ''caf' + [char]0xE9 + ' ' + [char]0x20AC + ' ' + [char]0x4E2D + ''''
        Invoke-PasAdminService -SMSProvider 'cm01' -RelativePath 'p' -Method POST -Body @{ InputQuery = $q } | Out-Null
        $json = [Text.Encoding]::UTF8.GetString($global:Fx.Last.Body)
        ($json | ConvertFrom-Json).InputQuery | Should -Be $q
    }
    It 'keeps quotes and markup in the query intact' {
        $q = 'where Name == "a\b" and X =~ ''<&>'''
        Invoke-PasAdminService -SMSProvider 'cm01' -RelativePath 'p' -Method POST -Body @{ InputQuery = $q } | Out-Null
        (([Text.Encoding]::UTF8.GetString($global:Fx.Last.Body)) | ConvertFrom-Json).InputQuery | Should -Be $q
    }
    It 'turns TLS 1.2 on for the process' {
        Invoke-PasAdminService -SMSProvider 'cm01' -RelativePath 'p' | Out-Null
        ([int][Net.ServicePointManager]::SecurityProtocol -band [int][Net.SecurityProtocolType]::Tls12) | Should -Be ([int][Net.SecurityProtocolType]::Tls12)
    }
    It 'refuses a method other than GET and POST' {
        { Invoke-PasAdminService -SMSProvider 'cm01' -RelativePath 'p' -Method DELETE } | Should -Throw
        $global:Fx.Calls | Should -Be 0
    }
    It 'maps an HTTP error to a fixed message and writes the text of the service to the log file: <Case>' -ForEach @(
        @{ Case = 'OData error object'; Body = '{"error":{"code":"x","message":"Invalid query near ''foo''."}}'; Detail = "Invalid query near 'foo'." }
        @{ Case = 'plain text';         Body = 'Something broke.';           Detail = 'Something broke.' }
        @{ Case = 'JSON without error'; Body = '{"other":1}';                Detail = '{"other":1}' }
        @{ Case = 'JSON error without message'; Body = '{"error":{"code":"x"}}'; Detail = '{"error":{"code":"x"}}' }
        @{ Case = 'padded text';        Body = "  spaced  `r`n";             Detail = 'spaced' }
        @{ Case = 'no body';            Body = '';                           Detail = '' }
        @{ Case = 'white space body';   Body = '   ';                        Detail = '' }
    ) {
        $log = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.log')
        Set-PasLogPath $log
        $global:Fx.Throw = New-FakeWebException -StatusCode 400 -Description 'Bad Request' -Body $Body
        $e = $null
        try { Invoke-PasAdminService -SMSProvider 'cm01' -RelativePath 'p' } catch { $e = $_.Exception } finally { Set-PasLogPath '' }
        $e | Should -BeOfType [InvalidOperationException]
        $e.Message | Should -Be 'AdminService returned HTTP 400. The log file has the details.'
        $e.Data['StatusCode'] | Should -Be 400
        $e.InnerException | Should -BeOfType [Net.WebException]
        $text = Get-Content -LiteralPath $log -Raw
        $text | Should -Match '\[ERROR\] AdminService returned HTTP 400 \(Bad Request\) for p: '
        $text | Should -BeLike "*for p: $Detail*"
    }
    It 'puts the status code and no text of the service in the message of status <Code>' -ForEach @(@{ Code = 401 }, @{ Code = 404 }, @{ Code = 500 }) {
        $global:Fx.Throw = New-FakeWebException -StatusCode $Code -Description 'Status' -Body 'raw service text'
        $e = $null
        try { Invoke-PasAdminService -SMSProvider 'cm01' -RelativePath 'p' } catch { $e = $_.Exception }
        $e.Message | Should -Be "AdminService returned HTTP $Code. The log file has the details."
        $e.Message | Should -Not -BeLike '*raw service text*'
        $e.Data['StatusCode'] | Should -Be $Code
    }
    It 'still reports the status when the error body cannot be read' {
        $global:Fx.Throw = New-FakeWebException -StatusCode 503 -Description 'Service Unavailable' -Body 'x' -BrokenStream
        $e = $null
        try { Invoke-PasAdminService -SMSProvider 'cm01' -RelativePath 'p' } catch { $e = $_.Exception }
        $e.Message | Should -Be 'AdminService returned HTTP 503. The log file has the details.'
        $e.Data['StatusCode'] | Should -Be 503
    }
    It 'rethrows a failure that has no response, such as a timeout, as it is' {
        $global:Fx.Throw = New-FakeWebException -NoResponse
        $e = $null
        try { Invoke-PasAdminService -SMSProvider 'cm01' -RelativePath 'p' } catch { $e = $_.Exception }
        $e | Should -BeOfType [Net.WebException]
        $e.Message | Should -BeLike '*timed out*'
    }
    It 'does not wrap an error that is not a web error' {
        $global:Fx.Throw = [System.InvalidCastException]::new('bad cast')
        $e = $null
        try { Invoke-PasAdminService -SMSProvider 'cm01' -RelativePath 'p' } catch { $e = $_.Exception }
        $e | Should -BeOfType [InvalidCastException]
    }
    It 'keeps a hostile error body out of the message and writes it to the log file as text only' {
        $log = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '.log')
        Set-PasLogPath $log
        $global:Fx.Throw = New-FakeWebException -StatusCode 400 -Description 'Bad Request' -Body '<script>alert(1)</script> $(calc)'
        $e = $null
        try { Invoke-PasAdminService -SMSProvider 'cm01' -RelativePath 'p' } catch { $e = $_.Exception } finally { Set-PasLogPath '' }
        $e.Message | Should -Be 'AdminService returned HTTP 400. The log file has the details.'
        (Get-Content -LiteralPath $log -Raw) | Should -BeLike '*<script>alert(1)</script> $(calc)*'
    }
    It 'returns nothing for an empty answer' {
        $global:Fx.Response = $null
        Invoke-PasAdminService -SMSProvider 'cm01' -RelativePath 'p' | Should -BeNullOrEmpty
    }
}

Describe 'Start-PasPivotRun' {
    BeforeEach {
        $global:Fx = @{ Calls = [System.Collections.Generic.List[object]]::new(); Response = $null; Throw = $null }
        $global:Fx.Response = [pscustomobject]@{ OperationId = 101 }
        Mock Invoke-PasAdminService {
            $global:Fx.Calls.Add([pscustomobject]@{ Provider = $PesterBoundParameters.SMSProvider; Path = $PesterBoundParameters.RelativePath; Method = $PesterBoundParameters.Method; Body = $PesterBoundParameters.Body })
            if ($global:Fx.Throw) { throw $global:Fx.Throw }
            $global:Fx.Response
        } -ModuleName PivotsAndScripts
    }
    It 'sends one CMPivot request for a collection and one for a device list' {
        $ops = @(Start-PasPivotRun -SMSProvider 'p' -Query 'OS' -CollectionId 'SMS00001')
        $ops.Count | Should -Be 1
        $global:Fx.Calls.Count | Should -Be 1
        $global:Fx.Calls[0].Path | Should -Be "Collections('SMS00001')/AdminService.RunCMPivot"
        $global:Fx.Calls[0].Body.InputQuery | Should -Be 'OS'
        $global:Fx.Calls[0].Body.ContainsKey('ResourceIds') | Should -BeFalse
        $global:Fx.Calls.Clear()
        $ops = @(Start-PasPivotRun -SMSProvider 'p' -Query 'OS' -ResourceIds (1..1201))
        $ops.Count | Should -Be 1
        $global:Fx.Calls.Count | Should -Be 1
        @($global:Fx.Calls[0].Body.ResourceIds -split ',').Count | Should -Be 1201
        $global:Fx.Calls[0].Path | Should -Be 'SMS_CMPivotStatus/AdminService.RunCMPivot'
    }
    It 'posts to the provider and does not send a malformed collection ID' {
        $failed = $false
        try { Start-PasPivotRun -SMSProvider 'p' -Query 'OS' -CollectionId "SMS00001')/x" } catch { $failed = $true }
        $failed | Should -BeTrue
        $global:Fx.Calls.Count | Should -Be 0
        Start-PasPivotRun -SMSProvider 'cm01.contoso.com' -Query 'OS' -CollectionId 'SMS00001' | Out-Null
        $global:Fx.Calls[0].Provider | Should -Be 'cm01.contoso.com'
        $global:Fx.Calls[0].Method | Should -Be 'POST'
    }
    It 'refuses a collection ID with a trailing line break' {
        { Start-PasPivotRun -SMSProvider 'p' -Query 'OS' -CollectionId "SMS00001`n" } | Should -Throw '*is not a collection ID*'
        $global:Fx.Calls.Count | Should -Be 0
    }
    It 'refuses a run without a collection and without devices' {
        { Start-PasPivotRun -SMSProvider 'p' -Query 'OS' -ResourceIds $null } | Should -Throw '*at least one device*'
        { Start-PasPivotRun -SMSProvider 'p' -Query 'OS' -ResourceIds @($null) } | Should -Throw '*at least one device*'
        { Start-PasPivotRun -SMSProvider 'p' -Query 'OS' } | Should -Throw '*at least one device*'
        { Start-PasPivotRun -SMSProvider 'p' -Query 'OS' -ResourceIds @() } | Should -Throw '*at least one device*'
        $global:Fx.Calls.Count | Should -Be 0
    }
    It 'returns the operation ID as a number and describes the target' {
        $r = Start-PasPivotRun -SMSProvider 'p' -Query 'OS' -CollectionId 'SMS00001'
        $r.OperationID | Should -BeOfType [long]
        $r.OperationID | Should -Be 101
        $r.Raw.OperationId | Should -Be 101
        $r.Raw.Target | Should -Be 'Collection SMS00001'
        (Start-PasPivotRun -SMSProvider 'p' -Query 'OS' -ResourceIds @(5, 6, 7)).Raw.Target | Should -Be '3 devices'
        (Start-PasPivotRun -SMSProvider 'p' -Query 'OS' -ResourceIds @(5)).Raw.Target | Should -Be '1 devices'
    }
    It 'reads the operation ID from <Case>' -ForEach @(
        @{ Case = 'the top level';     Response = [pscustomobject]@{ OperationId = 7 };                          Expected = 7 }
        @{ Case = 'a value wrapper';   Response = [pscustomobject]@{ value = [pscustomobject]@{ OperationId = 8 } }; Expected = 8 }
        @{ Case = 'text';              Response = [pscustomobject]@{ OperationId = '9' };                        Expected = 9 }
        @{ Case = 'a large number';    Response = [pscustomobject]@{ OperationId = 16777216123 };                Expected = 16777216123 }
    ) {
        $global:Fx.Response = $Response
        (Start-PasPivotRun -SMSProvider 'p' -Query 'OS' -CollectionId 'SMS00001').OperationID | Should -Be $Expected
    }
    It 'refuses an answer without a numeric operation ID: <Case>' -ForEach @(
        @{ Case = 'null';          Response = $null }
        @{ Case = 'a string';      Response = 'ok' }
        @{ Case = 'no ID';         Response = [pscustomobject]@{ Other = 1 } }
        @{ Case = 'a text ID';     Response = [pscustomobject]@{ OperationId = 'abc' } }
        @{ Case = 'a negative ID'; Response = [pscustomobject]@{ OperationId = -4 } }
        @{ Case = 'a decimal ID';  Response = [pscustomobject]@{ OperationId = '1.5' } }
        @{ Case = 'an empty ID';   Response = [pscustomobject]@{ OperationId = '' } }
        @{ Case = 'a null value';  Response = [pscustomobject]@{ value = $null } }
        @{ Case = 'a value without an ID'; Response = [pscustomobject]@{ value = [pscustomobject]@{ X = 1 } } }
    ) {
        $global:Fx.Response = $Response
        { Start-PasPivotRun -SMSProvider 'p' -Query 'OS' -CollectionId 'SMS00001' } | Should -Throw '*numeric OperationId*'
    }
    It 'sends the query text as it is, also when it is hostile: <Case>' -ForEach @(
        @{ Case = 'empty';   Query = '' }
        @{ Case = 'quotes';  Query = "Device | where Name == 'a' and X == ""b""" }
        @{ Case = 'unicode'; Query = ('Device | where Name == ''' + [char]0x4E2D + '''') }
        @{ Case = 'markup';  Query = '<x>&%27' }
    ) {
        Start-PasPivotRun -SMSProvider 'p' -Query $Query -CollectionId 'SMS00001' | Out-Null
        $global:Fx.Calls[0].Body.InputQuery | Should -BeExactly $Query
    }
    It 'passes a request error up' {
        $global:Fx.Throw = 'AdminService returned HTTP 403 (Forbidden).'
        { Start-PasPivotRun -SMSProvider 'p' -Query 'OS' -CollectionId 'SMS00001' } | Should -Throw '*HTTP 403*'
    }
    It 'sends nothing under -WhatIf' {
        Start-PasPivotRun -SMSProvider 'p' -Query 'OS' -CollectionId 'SMS00001' -WhatIf | Should -BeNullOrEmpty
        Start-PasPivotRun -SMSProvider 'p' -Query 'OS' -ResourceIds @(1) -WhatIf | Should -BeNullOrEmpty
        $global:Fx.Calls.Count | Should -Be 0
    }
}

Describe 'Get-PasPivotStatus' {
    BeforeEach {
        $global:Fx = @{ Pages = @(); Calls = [System.Collections.Generic.List[string]]::new(); Throw = $null; Max = 40 }
        Mock Invoke-PasAdminService {
            $global:Fx.Calls.Add($PesterBoundParameters.RelativePath)
            if ($global:Fx.Throw) { throw $global:Fx.Throw }
            if ($global:Fx.Calls.Count -gt $global:Fx.Max) { throw 'runaway paging: more than 40 requests' }
            $i = $global:Fx.Calls.Count - 1
            if ($i -lt $global:Fx.Pages.Count) { $global:Fx.Pages[$i] } else { $global:Fx.Pages[-1] }
        } -ModuleName PivotsAndScripts
    }
    It 'asks for the rows of the operation with an encoded filter' {
        $global:Fx.Pages = @([pscustomobject]@{ value = @() })
        Get-PasPivotStatus -SMSProvider 'p' -OperationID 123 | Out-Null
        $global:Fx.Calls[0] | Should -BeExactly 'SMS_CMPivotStatus?$filter=ClientOperationId%20eq%20123'
    }
    It 'returns the rows of one page' {
        $global:Fx.Pages = @([pscustomobject]@{ value = @([pscustomobject]@{ ResourceId = 1 }, [pscustomobject]@{ ResourceId = 2 }) })
        @(Get-PasPivotStatus -SMSProvider 'p' -OperationID 1 | ForEach-Object ResourceId) | Should -Be @(1, 2)
        $global:Fx.Calls.Count | Should -Be 1
    }
    It 'follows the next-page links to the end and returns the rows in order' {
        $global:Fx.Pages = @(
            [pscustomobject]@{ value = @([pscustomobject]@{ ResourceId = 1 }); '@odata.nextLink' = 'https://cm01.contoso.com/AdminService/v1.0/SMS_CMPivotStatus?$skiptoken=2' }
            [pscustomobject]@{ value = @([pscustomobject]@{ ResourceId = 2 }); '@odata.nextLink' = 'https://cm01.contoso.com/AdminService/v1.0/SMS_CMPivotStatus?$skiptoken=3' }
            [pscustomobject]@{ value = @([pscustomobject]@{ ResourceId = 3 }) })
        @(Get-PasPivotStatus -SMSProvider 'p' -OperationID 1 | ForEach-Object ResourceId) | Should -Be @(1, 2, 3)
        $global:Fx.Calls.Count | Should -Be 3
        $global:Fx.Calls[1] | Should -BeExactly 'SMS_CMPivotStatus?$skiptoken=2'
        $global:Fx.Calls[2] | Should -BeExactly 'SMS_CMPivotStatus?$skiptoken=3'
    }
    It 'stops at a page whose next-page link is empty' {
        $global:Fx.Pages = @([pscustomobject]@{ value = @([pscustomobject]@{ ResourceId = 1 }); '@odata.nextLink' = '' })
        @(Get-PasPivotStatus -SMSProvider 'p' -OperationID 1).Count | Should -Be 1
        $global:Fx.Calls.Count | Should -Be 1
    }
    It 'returns nothing for <Case>' -ForEach @(
        @{ Case = 'a null page';        Page = $null }
        @{ Case = 'a text page';        Page = 'text' }
        @{ Case = 'an empty value';     Page = [pscustomobject]@{ value = @() } }
        @{ Case = 'a null value';       Page = [pscustomobject]@{ value = $null } }
    ) {
        $global:Fx.Pages = @($Page)
        $err = $null
        $rows = @(Get-PasPivotStatus -SMSProvider 'p' -OperationID 1 -ErrorVariable err -ErrorAction SilentlyContinue)
        $err | Should -BeNullOrEmpty
        $rows.Count | Should -Be 0
    }
    It 'refuses a page without a value list as a schema error' {
        $global:Fx.Pages = @([pscustomobject]@{ other = 1 })
        { Get-PasPivotStatus -SMSProvider 'p' -OperationID 1 } | Should -Throw '*without a value list*'
    }
    It 'skips a null row' {
        $global:Fx.Pages = @([pscustomobject]@{ value = @($null, [pscustomobject]@{ ResourceId = 4 }) })
        @(Get-PasPivotStatus -SMSProvider 'p' -OperationID 1).Count | Should -Be 1
    }
    It 'stops when the service sends the same next-page link again' {
        $global:Fx.Pages = @([pscustomobject]@{ value = @([pscustomobject]@{ ResourceId = 1 }); '@odata.nextLink' = 'https://p/AdminService/v1.0/SMS_CMPivotStatus?$skiptoken=9' })
        { Get-PasPivotStatus -SMSProvider 'p' -OperationID 1 } | Should -Throw '*same next page*'
        $global:Fx.Calls.Count | Should -BeLessOrEqual 5
    }
    It 'refuses a next-page link that is not a link of the AdminService' {
        $global:Fx.Pages = @([pscustomobject]@{ value = @(); '@odata.nextLink' = 'https://evil.example/steal?x=1' })
        { Get-PasPivotStatus -SMSProvider 'p' -OperationID 1 } | Should -Throw '*next page*'
        $global:Fx.Calls.Count | Should -Be 1
    }
    It 'passes a request error up' {
        $global:Fx.Throw = 'AdminService returned HTTP 404 (Not Found).'
        { Get-PasPivotStatus -SMSProvider 'p' -OperationID 1 } | Should -Throw '*HTTP 404*'
    }
    It 'uses a large operation ID without a thousands separator' {
        $global:Fx.Pages = @([pscustomobject]@{ value = @() })
        Get-PasPivotStatus -SMSProvider 'p' -OperationID 16777216123 | Out-Null
        $global:Fx.Calls[0] | Should -BeLike '*eq%2016777216123'
    }
}
