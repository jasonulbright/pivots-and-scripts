# Error messages

This page lists the messages of Pivots and Scripts with cause and fix. A message shows in a box titled `Error` and in the status line. The Options dialog uses the box title `Options Error`. The Site Scripts dialog uses `Site Scripts Error`.

## What it does

It explains each message and says what to do.

## When to use it

Use it when the tool shows a message that you do not know.

## Requirements

None.

## Steps

Find the message in the table. Do the fix.

## Options and settings of this page

### Connection and options

| Message | Cause | Fix |
|---|---|---|
| `Set the site code and SMS Provider in Options > Connection.` | The connection is empty. | Set the connection. |
| `Site <code> was not found on SMS Provider <name>.` | The provider does not host that site. | Correct the site code. |
| `Site <code> could not be checked on SMS Provider <name>: <reason>` | The provider did not answer the site check. | Read the reason. Check the name and the account. |
| `Configuration Manager connection failed. Check console installation, site and permissions.` | The console is missing, or the account has no right. | Install the console. Check the account. |
| `Site code '<value>' is invalid. A site code is 3 characters, A-Z or 0-9.` | The site code has the wrong form. | Type a valid site code. |
| `SMS Provider '<value>' is invalid. Enter a host name or FQDN without a URL or path.` | The provider has a URL or a path. | Type the host name. |

### Targets and runs

| Message | Cause | Fix |
|---|---|---|
| `Enter a target.` | The target box is empty. | Type a target. |
| `Select Resolve Targets first.` | No snapshot exists. | Select **Resolve Targets**. |
| `Connection changed. Select Resolve Targets again.` | You changed the connection after Resolve. | Select **Resolve Targets**. |
| `None of the targets exists in Configuration Manager any more.` | The devices were deleted after Resolve. | Resolve again. |
| `The editor is empty.` | No query or script text. | Type or open text. |
| `An operation is already running.` or `Wait for the current operation to finish.` | A run is active. | Wait, or select **Stop Waiting**. |

### Scripts

| Message | Cause | Fix |
|---|---|---|
| `Enter the GUID of an approved ConfigMgr script, or submit this draft first.` | The GUID box is empty. | Type a GUID, or submit the draft. |
| `The draft changed after submission. Submit the edited script and obtain approval.` | The text changed after the submission. | Select **Submit Script for Approval** again. |
| `The parameters were set for different script text or another script GUID. Open Parameters again.` | The text or GUID changed. | Select **Parameters** again. |
| `Run Scripts supports at most 10 parameters.` | The `param()` block has more than 10 parameters. | Remove parameters. |
| `The script is empty. Enter the script text first.` | **Submit Script for Approval** with an empty editor. | Type the script. |
| `Select a script first.` | A site script button without a selected row. | Select a script. |

### Results and sessions

| Message | Cause | Fix |
|---|---|---|
| `Select result rows first.` | **Selection to Pivot** or **Selection to Script** without a row. | Select rows. |
| `Results belong to another connection. Restore that connection before selecting targets.` | The connection changed after the run. | Restore the connection. |
| `There are no results to export.` (also `copy`, `show`) | The grid is empty. | Run a query first. |
| `CSV requires a Device column.` | The imported CSV has no `Device` column. | Add the column. |
| `Unsupported session file.` | The file is not a session of this tool. | Pick another file. |

### Administration service

| Message | Cause | Fix |
|---|---|---|
| `AdminService returned HTTP <code>. The log file has the details.` | The service refused the call. | 400: check the query. 401 or 403: check the rights. Read the log file for the text of the service. |
| `AdminService did not return a numeric OperationId.` | The reply has an unknown form. | Read the **Raw** tab. |
| `AdminService sent a next page link that this app cannot follow.` | A result page points to another host. | Check the provider. |

### Messages with a fixed sentence

The tool writes a message itself, for example `Enter a target.`, and shows it as it is. Any other error is raw technical text, for example an exception text, an HTTP reply or a message of Windows. The window never shows that text. The window shows one fixed sentence instead, and the tool writes the raw text to the log file of the day. See [Files and logs](files-and-logs.md).

| Fixed sentence | Where it shows | Fix |
|---|---|---|
| `The action failed. The log file has the details.` | A message box, from a button of the Site Scripts dialog or from the main window. | Read the log file. |
| `The operation failed. The log file has the details.` | The status line, when a background operation fails. | Read the log file. |
| `The worker could not start. The log file has the details.` | The status line, when the background worker does not start. | Read the log file. |
| `The worker reported an error. The log file has the details.` | The status line, when the background worker reports an error. | Read the log file. |
| `The approval failed. The log file has the details.` | The status line, when the approval of a new script fails. | Read the log file. |
| `The run could not be submitted. The log file has the details.` | The status line and the Devices tab, when the submission fails. | Read the log file. |
| `The result could not be requested from the site. The log file has the details.` | The Devices tab, when the request for a result fails. | Read the log file. |
| `The result could not be read. The log file has the details.` | The Devices tab, when a result page cannot be read. | Read the log file. |
| `AdminService returned HTTP <code>. The log file has the details.` | The status line and the Devices tab, when the administration service refuses a call. | 400: check the query. 401 or 403: check the rights. Read the log file. |
| `The options could not be saved. The log file has the details.` | The box `Options Error`. | Read the log file. Check the rights on the data folder. |
| `The parameters could not be applied. The log file has the details.` | The Script Parameters dialog. | Read the log file. |
| `The site scripts could not be listed. The log file has the details.` | The status line of the Site Scripts dialog. | Select **Refresh**. Read the log file. |
| `The history could not be saved. The log file has the details.` | The status line. | Read the log file. Check the rights on the data folder. |
| `The raw record could not be shown. The log file has the details.` | The **Raw** tab. | Read the log file. |

## Limits

The first tables list the messages that the tool writes itself. These messages show as they are. A message of Configuration Manager or of Windows never shows as it comes: the window shows a fixed sentence from the last table, and the log file holds the raw text.

## Troubleshooting

See [Troubleshooting](../troubleshooting.md).

## Links

- [Troubleshooting](../troubleshooting.md)
