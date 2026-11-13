# Changelog

## [Unreleased]

### Fixed

- Restore the weight of the Options headers to SemiBold. The light theme change had made them bold. Show the Dark Theme label in the normal weight again. Show the page heading, the Library header, the Query Editor label and the selected tab header in SemiBold. Only field titles and the sidebar app title are bold.

### Added

- Add FontWeight.Guard.Tests.ps1 and FontWeightGuardHelpers.ps1. They fail when a bold weight is set on a label that is not a field title or an app title, in XAML, in the XAML of the scripts and in code that sets a weight at run time.

## [2026.11.12.0010] - 2026-11-12

## 1 shared button style for every button, with readable text in every state

### Fixed

- Show white text on blue buttons, selected rows and selected items in light mode.
- Show field titles in bold 14 pt. Field values keep the normal style.
- Keep the button text readable on hover and when pressed.
- Show selected states in the theme highlight color.
- Raise the dark mode button border to a contrast of 3:1.
- Show a fixed sentence instead of raw error text. Keep the AdminService HTTP status.

### Changed

- Use one shared themed style for every button and every dialog button.
- Write button, dialog and heading titles in Title Case.
- Write a log file for each day in the Logs folder of the data folder.
- Add a Cancel button to the Script Parameters dialog.
- Retake the guide images.

### Added

- Add tests that guard the button styles, the contrast pairs and the error sentences.

## [2026.11.07.0009] - 2026-11-07

## 1 opt-in variable that decides whether the window tests run

### Changed

- Check that both placeholder lists hold at least one case.
- Run window tests only when the SUITE_ALLOW_WINDOW_TESTS opt-in is set to `1`.

## [2026.11.07.0008] - 2026-11-07

## 1 shared library refresh and window tests that cannot steal focus

### Added

- Skip the window tests on the development PC and without the opt-in. The console shows the reason.
- Add tests that check the guard and that every window test carries it.
- Print one line when Invoke-Checks skips the window tests.

### Changed

- Update the shared library to version 2026.11.07.0075.
- Check the coverage floor only when the window tests run.

## [2026.11.07.0007] - 2026-11-07

## 2 fixes and a user guide with 58 images

### Fixed

- Show the result tab headers in the theme text color, bold when selected, at size 13.
- Give the message boxes of Options and Site scripts a title that differs from their dialog.

### Added

- Add the user guide (docs/index.md) with images of the running window.
- Add tools/guide-capture, one command that regenerates every image of the guide on a lab computer.

## [2026.11.06.0006] - 2026-11-06

## 19 defects fixed

### Fixed

- Refuse a site code, provider name or collection ID that ends with a line break.
- Report the real error when the site lookup fails instead of "site not found".
- Read CMPivot results and stored script parameters without document type processing.
- Keep line breaks and tabs in the default values of script parameters.
- Read a script whose stored parameter list is empty.
- Run a script when no parameter values are set.
- Show the site message when it refuses a self-approval.
- Refuse to run on no devices and no collection.
- Refuse to create an empty script.
- Report a status page without a value list as an error.
- Show a script as not approved when the site keeps another state.
- Drop the new history step when the session cannot be saved.
- Stop reading result pages when the service repeats a page or sends a foreign link.
- Sort a result column when some rows lack the column.
- Save a null value as valid JSON.
- Report a run that returns no operation ID instead of waiting for it.
- Keep the other devices when one device returns unreadable CMPivot output.
- Title error messages Error, not Pivots and Scripts.
- Open the window at 1024 pixels wide.

### Added

- Add -WhatIf to script creation, approval, removal and runs.
## [2026.10.12.0005] - 2026-10-12

## 1 PowerShell 7 fix

### Fixed

- Keep the PowerShell 7 module roots when the tool runs under PowerShell 7.

## [2026.10.11.0004] - 2026-10-11

## 1 window fix

### Fixed

- Double-click the title bar to maximize or restore the window.

## [2026.10.11.0003] - 2026-10-11

## 1 suite update notice

### Added

- Show a notice when a newer suite release is available; the launcher installs it.

## [2026.10.01.0002] - 2026-10-01

### Fixed

- CMPivot runs once per query instead of once per device
- Script runner runs once per query instead of once per device

## [2026.10.01.0001] - 2026-10-01

- Initial release.
