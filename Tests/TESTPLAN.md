# Pivots and Scripts: test plan

Measured 2026-11-06 with `Invoke-Checks.ps1` (Pester 5.7.1, PSScriptAnalyzer 1.25.0). Counts are tests as run; each data row counts as one test. Coverage is the share of module commands that the tests run.

| | Before | After |
|---|---|---|
| Tests | 51 | 798 on Windows PowerShell 5.1; 798 on PowerShell 7 (16 skip on 7: the contract tests need the console) |
| Module coverage | 69.0% (420 of 609 commands) | 99.9% (686 of 687 commands) |
| Lab steps | none | 35 (`Tests/Lab`) |

Run: `.\Invoke-Checks.ps1` (lint, tests, coverage floor 80%). It runs in CI on both hosts (`.github/workflows/checks.yml`).

Window tests: `Window.Tests.ps1` and `Shell.Smoke.Tests.ps1` open a window only when `SUITE_ALLOW_WINDOW_TESTS` is `1`. CI sets it in both jobs; set it by hand to run the window tests on a desktop. Without it, a direct Pester run reports those tests as Skipped, not as Failed, with the reason `SUITE_ALLOW_WINDOW_TESTS is not 1`. Pester does not store the reason, so `Window.Tests.ps1` prints it to the console when it runs alone. `Invoke-Checks.ps1` prints the reason and leaves both window test files out of the Pester run, so Pester does not count them as Skipped. `Test-WindowTestsAllowed` in `Tests/WindowHarness.ps1` makes the decision from the opt-in value only, and `Get-WpfSession` refuses to create a runspace when it says no. When the guard says no, `Window.Tests.ps1` evaluates nothing derived from the shell script. In that case the run still passes. The coverage floor is checked only when the window tests ran; a run without them prints the coverage as informational. `WindowGuard.Tests.ps1` tests the guard with injected values, checks that the guard has no computer-name parameter, scans every test file in the repository (nested folders included) for window code, checks that each top-level `Describe` of such a file carries the guard, and checks the `Get-WpfSession` refusal. It opens no window.

## What is covered

| Area | File | Contents |
|---|---|---|
| Pure functions | `Module.Parsing.Tests.ps1` | Hash, collection ID check, approval state names, result parsing (JSON, escaped JSON, CMPivot XML), sort, settings to save, worker error text |
| Script parameters | `Module.Parameters.Tests.ps1` | Reading parameters from script text, site type mapping, limits, the site definition (write and read back), typed run arguments |
| Site reads | `Module.Site.Tests.ps1` | Connection check, target resolution (collection, device, pattern, list), CIM reads of site scripts and run status |
| Write actions | `Module.Write.Tests.ps1` | Create a script with its parameters, approve, deny, remove, start a script run, save a JSON file. Success, failure, partial failure, `-WhatIf`, hostile input |
| AdminService | `Module.AdminService.Tests.ps1` | Request builder, error mapping, CMPivot start, status paging |
| Worker | `Execute.Tests.ps1` | Every action of the background worker, with a stub module in place of the site: connect, resolve, submit, approve, deny, remove, list, CMPivot run, script run, stop, timeout, errors |
| Start script logic | `Shell.Logic.Tests.ps1` | Every helper function and the event handlers of the start script (cut out of the syntax tree), the run flow with the worker, export, session, find and replace |
| Existing tests | `Execute.Tests.ps1`, `Module.*.Tests.ps1`, `Shell.Smoke.Tests.ps1` | The 51 tests of `Core.Tests.ps1` moved into these files with their checks unchanged |
| Calls | `Script.Contract.Tests.ps1` | Every call from the start script, the dialogs and the module into an app function or SuiteCommon names only parameters that exist |
| Real cmdlet signatures | `CmCmdlet.Contract.Tests.ps1` | Every ConfigMgr call names only parameters that the real cmdlet has. Runs where the console is installed |
| Start without the console | `Startup.Tests.ps1` | Plain message, `$false`, no raw exception |
| Windows | `Window.Tests.ps1` | Main window in both views (CMPivot and PowerShell): names, titles, no clipped text and nothing off screen at 1024x720 and 1440x900 in both themes, text and control contrast. The three dialogs: XAML, names, titles, layout |
| Window start | `Shell.Smoke.Tests.ps1` | The real start script in `-SmokeTest` mode: themes, modes, the three dialogs, close |
| Window guard | `WindowGuard.Tests.ps1` | The rule that lets window tests run (`Test-WindowTestsAllowed`): opt-in, with injected values. Every test file that opens a window uses the guard. Opens no window |
| Lab | `Lab/Invoke-PasLab.ps1` | ZZTEST- scripts on the lab site server: create with parameters, read back, list, approve, deny, remove, a script run and a CMPivot run on a lab client, feature script guard, `-WhatIf`. Checks that no other script changed |

## Defects found and fixed

Each has a failing test in the first commit and the fix in the second. The fix commit makes the tests pass.

| # | Defect | Test |
|---|---|---|
| 1 | A site code, provider name or collection ID that ended with a line break was accepted | `Assert-PasConnection`, `Test-PasCollectionId`, `Start-PasPivotRun` |
| 2 | The site lookup failure was reported as "site not found" | `Assert-PasConnection` |
| 3 | CMPivot output and stored parameter definitions were parsed with document type processing on (entities expand) | `ConvertFrom-PasPivotOutput`, `ConvertFrom-PasParamsDefinition` |
| 4 | Line breaks and tabs in a parameter default were stored as spaces | `ConvertTo-PasParamsDefinition` |
| 5 | A stored parameter list with no parameter could not be read, so the script could not run | `ConvertFrom-PasParamsDefinition`, `Get-PasSiteScript` |
| 6 | Run arguments failed when the value table was null | `ConvertTo-PasScriptArguments` |
| 7 | The message for a refused self-approval hid the message of the site | `Set-PasScriptApproval` |
| 8 | A run with no devices and no collection was sent to the site | `Start-PasPivotRun`, `Start-PasScriptRun` |
| 9 | An empty script was created on the site | `New-PasManagedScript` |
| 10 | A status page with no `value` property raised a property error; it is now a clear schema error | `Get-PasPivotStatus` |
| 11 | A repeated or foreign next-page link was followed (an endless loop that ignores the stop button) | `Get-PasPivotStatus` |
| 12 | A sort failed when some rows lack the column; a null row list returned a null row | `Sort-PasRows` |
| 13 | A null value wrote an empty file on Windows PowerShell 5.1 | `Write-PasJson` |
| 14 | A run that returned nothing polled operation 0 until the timeout | `Execute.Tests.ps1` |
| 15 | One device with unreadable output stopped the whole run | `Execute.Tests.ps1` |
| 16 | The error message had the same title as the main window | `Window.Tests.ps1`, `Shell.Logic.Tests.ps1` |
| 17 | The window could not open at 1024 pixels wide (minimum width 1100) | `Window.Tests.ps1` |
| 18 | Approval at submission was reported as done without a check of the state that the site holds | `Execute.Tests.ps1` |
| 19 | A failed history save left a new step in the session although no worker started | `Shell.Logic.Tests.ps1` |

Also changed: the mutating functions (`New-PasManagedScript`, `Set-PasScriptApproval`, `Remove-PasManagedScript`, `Start-PasPivotRun`, `Start-PasScriptRun`, `Write-PasJson`) support `-WhatIf` and `-Confirm`. The worker passes `-Confirm:$false` because the window already asked. `New-PasManagedScript` takes an optional `-ScriptName`, which the lab test uses to name its scripts. Lint findings were fixed with suppression attributes that state why (function names and in-window helpers), and with the rename of the unused `$sender` parameter of five handlers.

## Not covered, and why

- Contrast of disabled controls, the sidebar button border, the light text boxes and the unselected tab headers misses the standard (text 4.5:1, borders 3:1). The cause is the shared SuiteCommon palette and the MahApps styles. `Tests/KnownContrastDefects.ps1` lists each violation. The window test fails on a new one and on a listed one that is fixed. The fix belongs in `app-packager-suite`.
- The dialogs are measured from their XAML only. The Options pages, the parameter fields and the grid rows of the site scripts dialog are built at run time and are not measured. The smoke test opens them.
- The AvalonEdit editor text (colors, caret, highlighting rendering) is not measured. The highlighting definition is loaded in a test.
- `Out-GridView` and the file dialogs are not run. The handlers are tested with a stand-in for the file picker.
- One command of the module is not run: the catch branch for a `ValidateSet` value that is not a constant (the parser rejects such a script first).
- The AdminService error path is tested with a stand-in response. Windows PowerShell 5.1 raises `WebException`; PowerShell 7 raises another exception type and the app does not target it.
- The settings save in SuiteCommon is not atomic. The fix belongs in `app-packager-suite`.
