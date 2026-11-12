# Troubleshooting

This page lists the most common problems of Pivots and Scripts with cause and fix. See [Error messages](reference/error-messages.md) for every message.

## What it does

It gives a short fix for each common problem.

## When to use it

Use it when a connection, a run or an export does not work.

## Requirements

None.

## Problems

| Message or symptom | Cause | Fix |
|---|---|---|
| A message says `Set the site code and SMS Provider in Options > Connection.` | The connection is empty. | Set the connection. See [Getting started](getting-started.md). |
| `Site <code> was not found on SMS Provider <name>.` | The provider does not host that site code. | Correct the site code. |
| `Configuration Manager connection failed. Check console installation, site and permissions.` | The console is not installed on this computer, or the account has no right. | Install the console. Check the account. |
| A CMPivot run shows a trust or TLS error on each device. | The computer does not trust the certificate of the SMS Provider. | Trust the issuer. See [Network](reference/network.md). |
| The provider answers HTTP 401. The message reads `AdminService returned HTTP 401. The log file has the details.` | The account is not accepted by the administration service. | Check the role of the account. See [Permissions](reference/permissions.md). |
| A message ends with `The log file has the details.` | The tool shows a fixed sentence for an error that it did not write itself. The window never shows the raw error text. | Open the newest file in `%LOCALAPPDATA%\SignalRidgeLabs\PivotsAndScripts\Logs`. See [Files and logs](reference/files-and-logs.md). |
| A device shows `Not a client`. | The device has no Configuration Manager client. | Install the client. |
| A device shows `No response within timeout`. | No result in 300 seconds. | Run again. The device can still run the operation. |
| **Selection to Script** or **Selection to Pivot** gives a message. | No row is selected, or the connection changed after the run. | Select rows. Restore the connection. |
| The grid is empty after **Open Session**. | The last step of that session has no results. | Open another session. |
| The tool starts in the dark theme. | The tool does not save the theme. | Use the theme switch. The light theme and the dark theme differ in colors only. Every blue box has white text in both themes. |

## Links

- [Error messages](reference/error-messages.md)
- [Getting started](getting-started.md)
