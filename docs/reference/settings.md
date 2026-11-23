# Settings

This page lists what Pivots and Scripts saves and where.

## What it does

The tool saves a small set of settings in your user profile. It saves no password.

## When to use it

Use it to reset the tool, to move the settings or to check what the tool keeps.

## Requirements

None.

## Steps

### Reset the tool

Close the tool and delete the folder `%LOCALAPPDATA%\SignalRidgeLabs\PivotsAndScripts`. To reset one site, also delete the folder `%LOCALAPPDATA%\AppPackagerData\sites\<SITE>\tools\pivots-and-scripts`, for example for site AB1. The next start uses the defaults.

## Options and settings of this page

| Setting | File | Default |
|---|---|---|
| `SiteCode` | `prefs.json` of the site (`preferences.json` with no site chosen) | Empty |
| `SMSProvider` | `prefs.json` of the site (`preferences.json` with no site chosen) | Empty |
| `ApproveAfterSubmit` | `preferences.json` | `false` |
| Window position, size and state | `windowstate.json` | Centered, 1400 by 900 |

The suite launcher chooses the site, and the site code and the provider belong to that site. See [Sites](../core/options.md#sites). With no site chosen, the launcher variables `SUITE_CM_SITECODE` and `SUITE_CM_PROVIDER` fill an empty site code or provider. The command-line parameters `-SiteCode` and `-SMSProvider` override both for one session and are not saved. When the launcher chose a site, the tool ignores `-SiteCode`.

## Limits

- The theme is not saved.
- The tool does not read settings from the registry.

## Troubleshooting

| Message or symptom | Cause | Fix |
|---|---|---|
| The window opens at the wrong place. | `windowstate.json` holds old values. | Delete `windowstate.json`. |

## Links

- [Files and logs](files-and-logs.md)
- [Options dialog](../core/options.md)
