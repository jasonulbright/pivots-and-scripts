# Files and logs

This page lists every folder and file that Pivots and Scripts reads or writes.

## What it does

The tool writes its data to your user profile and writes the files that you pick. It writes nothing to the program folder, except the library files that you save.

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
| `%LOCALAPPDATA%\SignalRidgeLabs\PivotsAndScripts\Sessions\<id>.json` | One file for each session: every step with its targets, text, parameters, raw responses and results. |
| `Library\Pivots`, `Library\Scripts` | The queries and scripts of the library, in the program folder. **Save editor file** writes here when you pick this folder. |
| Files that you pick | The exports, the saved sessions and the imported lists. |

The tool writes no log file.

## Limits

- A session file holds the device names and the results of the runs. Treat it as data of your site.
- The tool never deletes a session file. Delete old files by hand.
- Script output of a run is limited to 4 KB for each device.

## Troubleshooting

| Message or symptom | Cause | Fix |
|---|---|---|
| `The options could not be saved to <path>.` | The folder is not writable. | Check the rights on the folder. |

## Links

- [Settings](settings.md)
- [Sessions](../core/sessions.md)
