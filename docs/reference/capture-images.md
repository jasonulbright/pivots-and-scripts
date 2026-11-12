# Capture the images again

One command regenerates every image of this guide.

## What it does

`tools\guide-capture\Invoke-GuideCapture.ps1` copies the tool to a lab computer, starts it in an interactive session of a lab account, walks the views, the dialogs and the settings with Windows UI Automation, takes the screenshots at 1440 by 900 pixels, copies the PNG files back to `docs\images` and removes its files from the lab computer. It replaces only the images that exist already. With `-AddNew` it also adds new images.

## When to use it

Use it after a change that alters the window, and before a release.

## Requirements

- A lab computer with the Configuration Manager console, an SMS Provider that you can read, and PowerShell remoting for an account.
- A script, outside the repository, that sets `$LabCredential` to the credential of that account.
- A domain account that has an interactive session on the lab computer. The capture runs as a scheduled task with an interactive logon.
- A lab computer that trusts the certificate of the SMS Provider, so that CMPivot runs. See [Network](network.md).
- Lab data only. The capture runs one CMPivot query on one device. It opens the confirmations of **Submit Script for Approval** and **Run Approved Script** for a script and selects **No**. It never submits, approves, denies, removes or runs a script.

## Steps

1. Run this command from the repository folder:

```powershell
.\tools\guide-capture\Invoke-GuideCapture.ps1 -CredentialScript C:\lab\credentials.local.ps1 -Target CLIENT01 -LogonUser contoso\labadmin -SmsProvider cm01.contoso.com
```

2. Wait for the command to end. It prints a warning for each step that failed and keeps the captured files for you to read.
3. Open every changed image and check it. Look for clipped text, empty grids and stale version strings.
4. Run the documentation test: `Invoke-Pester .\Tests\Documentation.Tests.ps1`.

A second run inside the command does the missing-console test on a copy of the tool whose module lookup returns nothing. It deletes the saved settings of the lab account (`%LOCALAPPDATA%\SignalRidgeLabs\PivotsAndScripts`) before and after each run.

### Parameter LockWaitMinutes

`-LockWaitMinutes` sets how long the command waits for the capture of another guide to end. The default is 90 minutes. When the wait is over, the command stops with the message `Another capture holds C:\guide\capture.lock. The wait of <n> minutes is over.`

```powershell
.\tools\guide-capture\Invoke-GuideCapture.ps1 -CredentialScript C:\lab\credentials.local.ps1 -Target CLIENT01 -LogonUser contoso\labadmin -SmsProvider cm01.contoso.com -LockWaitMinutes 120
```

### One capture at a time

Only one capture runs at a time on a lab computer. The command takes the lock file `C:\guide\capture.lock` before it starts. It waits while another capture holds the file. It refreshes the file every 5 seconds while its capture runs. It removes a lock file that is older than 60 minutes, because that lock is stale. It removes the lock file at the end.

Each guide has its own names, so that two captures never meet:

| Item | Name for this tool |
|---|---|
| Folder on the lab computer | `C:\guide\pivots-and-scripts` |
| Scheduled task | `GuideShots-pivots-and-scripts` |

The command never removes the folder `C:\guide`.

## Limits

- The capture needs an interactive session on the lab computer. A locked session breaks it.
- A second capture on the same lab computer waits for the lock file. See "One capture at a time" above.
- The images show the data of the lab site.

## Troubleshooting

| Message or symptom | Cause | Fix |
|---|---|---|
| `The capture did not finish` | The session is locked or a window did not show. | Unlock the session and run again. |
| `Another capture holds C:\guide\capture.lock.` | Another capture ran longer than the wait. | Wait, or run again with a larger `-LockWaitMinutes`. |
| A step shows `control not found`. | The window changed. | Update the step in `steps-guide.ps1`. |
| The run ends with `Timeout: the app stayed busy`. | CMPivot did not finish. | Check the trust of the provider certificate. |

## Links

- [Index](../index.md)
