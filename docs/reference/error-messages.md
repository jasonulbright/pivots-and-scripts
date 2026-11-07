# Error messages

This page lists the messages of Pivots and Scripts with cause and fix. A message shows in a box titled `Error` and in the status line.

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
| `Resolve targets first.` | No snapshot exists. | Select **Resolve targets**. |
| `Connection changed. Resolve targets again.` | You changed the connection after Resolve. | Resolve again. |
| `None of the targets exists in Configuration Manager any more.` | The devices were deleted after Resolve. | Resolve again. |
| `The editor is empty.` | No query or script text. | Type or open text. |
| `An operation is already running.` or `Wait for the current operation to finish.` | A run is active. | Wait, or select **Stop waiting**. |

### Scripts

| Message | Cause | Fix |
|---|---|---|
| `Enter the GUID of an approved ConfigMgr script, or submit this draft first.` | The GUID box is empty. | Type a GUID, or submit the draft. |
| `The draft changed after submission. Submit the edited script and obtain approval.` | The text changed after the submission. | Submit again. |
| `The parameters were set for different script text or another script GUID. Open Parameters again.` | The text or GUID changed. | Select **Parameters** again. |
| `Run Scripts supports at most 10 parameters.` | The `param()` block has more than 10 parameters. | Remove parameters. |
| `The script is empty. Enter the script text first.` | Submit with an empty editor. | Type the script. |
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
| `AdminService returned HTTP <code> (<text>).` | The service refused the call. | 400: check the query. 401 or 403: check the rights. |
| `AdminService did not return a numeric OperationId.` | The reply has an unknown form. | Read the **Raw** tab. |
| `AdminService sent a next page link that this app cannot follow.` | A result page points to another host. | Check the provider. |

## Limits

The table lists the messages that the tool writes itself. A message of Configuration Manager or of Windows shows as it comes.

## Troubleshooting

See [Troubleshooting](../troubleshooting.md).

## Links

- [Troubleshooting](../troubleshooting.md)
