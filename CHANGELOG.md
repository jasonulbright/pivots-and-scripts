# Changelog

## [2026.11.06.0006] - 2026-11-06

## 17 defects fixed

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
- Read result pages that hold no rows.
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
