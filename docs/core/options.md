# Options dialog

The Options dialog sets the connection and the approval rule, and shows the version of the tool. The suite launcher chooses the site. See [Sites](#sites).

## What it does

The dialog has three pages: **Connection**, **Run Scripts** and **About**. **OK** saves the settings. **Cancel** closes the dialog without a change.

## When to use it

Use it at the first start, when the site or the provider changes, and to view the version.

## Requirements

None.

## Steps

### Set the connection

1. Select **Options** in the sidebar. The **Connection** page shows.

![The Connection page at the first start](../images/options-empty.png)

2. Type the **Site Code** and the **SMS Provider**. The two titles are bold 14 pt in both themes. The value boxes use normal text. These two boxes are the only place where you change the connection. The footer shows the saved values as read-only text.

![The Connection page with values](../images/options-connection.png)

3. Select **OK**. A site code that does not have 3 characters of A to Z or 0 to 9 gives a message, and the dialog stays open.

![The message for an invalid site code](../images/options-site-code-invalid.png)

When the suite launcher chose a site, the **Site Code** box is read-only. Point to it to see the reason: the site is chosen in the AppPackager Suite launcher, and you restart the tool after you change it. The **SMS Provider** stays editable and is saved with the site.

With no site chosen, a value that you saved wins. The suite launcher fills an empty value through the variables `SUITE_CM_SITECODE` and `SUITE_CM_PROVIDER`. The command-line parameters `-SiteCode` and `-SMSProvider` override both for one session. When the launcher chose a site, the tool ignores `-SiteCode` and writes a line to the log.

### Set the approval rule

1. Select **Run Scripts**.
2. Select or clear **Approve scripts after submission**. The default is off.

![The Run Scripts page](../images/options-run-scripts.png)

The setting works only where the site lets authors approve their own scripts. Microsoft recommends that site setting only for a lab. When the site refuses, the script stays waiting for approval and the status line shows the reason.

### View the version

Select **About**. The page shows the version of the tool and of the shared module, and the license note.

![The About page](../images/options-about.png)

### Switch the theme

Use the switch at the bottom of the sidebar. The label shows **Dark Theme** or **Light Theme**. The dialogs follow the theme. The light theme and the dark theme differ in colors only. Every blue box has white text in both themes. The tool does not save the theme: every start uses the dark theme.

![The Pivot view in the light theme](../images/light-pivot.png)

![The Options dialog in the light theme](../images/light-options.png)

## Sites

The AppPackager Suite launcher chooses the site. The tool keeps its site data under `%LOCALAPPDATA%\AppPackagerData\sites\<SITE>\tools\pivots-and-scripts`, for example `sites\AB1\tools\pivots-and-scripts` and `sites\CD2\tools\pivots-and-scripts`. The site folder holds the saved sessions (`sessions`), the site code and the SMS Provider (`prefs.json`). A site does not show the sessions or the provider of another site. The approval rule, the window position, the log files and the library stay global.

![The Site Code box when the launcher chose a site, with its tooltip](../images/options-site.png)

A tool that is open keeps its site until you restart it. When the launcher chooses another site, for example CD2 while the window uses AB1, the footer says `The launcher now uses site CD2. This window keeps site AB1 until you restart it.`

![The footer note after the launcher chose another site](../images/footer-site-note.png)

The first start after an update copies the old sessions and the old connection into the site folder. The tool keeps the old files in `%LOCALAPPDATA%\SignalRidgeLabs\PivotsAndScripts`. Sessions that name another site are not copied into this site.

## Options and settings of this page

| Setting | Effect | Default |
|---|---|---|
| Site Code | The 3-character site code. Read-only when the launcher chose a site. | Empty |
| SMS Provider | The host name of the SMS Provider, without a URL or a path. Saved with the site. | Empty |
| Approve scripts after submission | Approves each new script right after **Submit Script for Approval**. | Off |
| Theme | Dark or light. The tool does not save it. | Dark |

## Limits

- The provider name must be a host name or an FQDN. A URL or a path gives a message.
- After you change the connection, resolve the targets again.

## Troubleshooting

| Message or symptom | Cause | Fix |
|---|---|---|
| `Site code '<value>' is invalid. A site code is 3 characters, A-Z or 0-9.` | The site code has the wrong form. | Type a valid site code. |
| `SMS Provider '<value>' is invalid. Enter a host name or FQDN without a URL or path.` | The provider has a URL or a path. | Type the host name. |
| `The options could not be saved to <path>.` | The tool cannot write its data folder. | Check the rights. |

## Links

- [Getting started](../getting-started.md)
- [Settings](../reference/settings.md)
