# Files and logs

This page lists every folder and file that Pivots and Scripts reads or writes.

## What it does

The tool writes its data and one log file for each day to your user profile, and writes the files that you pick. It writes nothing to the program folder, except the library files that you save.

## When to use it

Use it to find a saved session, to clean up, or to check what the tool leaves on a computer.

## Requirements

None.

## Steps

None.

## Options and settings of this page

| Path | Content |
|---|---|
| `%LOCALAPPDATA%\SignalRidgeLabs\PivotsAndScripts\preferences.json` | The connection and the approval rule. |
| `%LOCALAPPDATA%\SignalRidgeLabs\PivotsAndScripts\windowstate.json` | The window position and size. |
| `%LOCALAPPDATA%\SignalRidgeLabs\PivotsAndScripts\Logs\pivotsandscripts-yyyyMMdd.log` | The log file of one day. It holds the raw technical detail of errors. See below. |
| `%LOCALAPPDATA%\SignalRidgeLabs\PivotsAndScripts\Sessions\<id>.json` | One file for each session: every step with its targets, text, parameters, raw responses and results. |
| `Library\Pivots`, `Library\Scripts` | The queries and scripts of the library, in the program folder. **Save Editor File** writes here when you pick this folder. |
| Files that you pick | The exports, the saved sessions and the imported lists. |

The tool writes one log file for each day: `Logs\pivotsandscripts-yyyyMMdd.log` under `%LOCALAPPDATA%\SignalRidgeLabs\PivotsAndScripts`, for example `pivotsandscripts-20261112.log`. The file holds the raw technical detail of errors, such as exception text and the reply of the administration service. The window never shows that text. The window shows a fixed sentence that ends `The log file has the details.` See [Error messages](error-messages.md). The tool never deletes a log file. Delete old files by hand.

## Limits

- A session file holds the device names and the results of the runs. A log file can hold names of devices, scripts and servers. Treat both as data of your site.
- The tool never deletes a session file or a log file. Delete old files by hand.
- Script output of a run is limited to 4 KB for each device.

## Troubleshooting

| Message or symptom | Cause | Fix |
|---|---|---|
| `The options could not be saved to <path>.` | The folder is not writable. | Check the rights on the folder. |
| A message ends with `The log file has the details.` | The window shows a fixed sentence. The raw text is in the log file. | Open the newest file in `Logs`. See [Error messages](error-messages.md). |

## Links

- [Settings](settings.md)
- [Sessions](../core/sessions.md)
