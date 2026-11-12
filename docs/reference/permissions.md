# Permissions

This page lists the rights that each action of Pivots and Scripts needs.

## What it does

The tool uses your Windows account for every call. It never asks for a password and it stores none. Configuration Manager checks each right.

## When to use it

Use it to ask for the right roles, or to find out why an action is refused.

## Requirements

An account that can use the Configuration Manager console and the SMS Provider.

## Steps

None.

## Options and settings of this page

The rights come from the Microsoft documentation of the features. The lab test of this guide used the lab administrator account, so it did not check a smaller role.

| Action | Right |
|---|---|
| Test Connection, Resolve Targets | Read access to the site, the devices and the collections. |
| Run CMPivot | **Run CMPivot** on the collection and **Read** on **Inventory Reports**. |
| Submit Script for Approval | **Create** on **SMS Scripts**. |
| Run Approved Script | **Run Script** on the collection. |
| Approve or Deny a script | **Approve** on **SMS Scripts**. |
| Remove a script | **Delete** on **SMS Scripts**. |
| Computer | Trust of the certificate of the SMS Provider, for the administration service. |
| Script results | Read access to the SMS Provider through WMI over DCOM. |

## Limits

- By default, the site does not let the author of a script approve it. A site setting can allow that. Microsoft recommends the setting only for a lab.
- The tool does not change hierarchy settings.

## Troubleshooting

| Message or symptom | Cause | Fix |
|---|---|---|
| A call returns HTTP 401 or 403. | The account has no right on the site, or the provider does not accept the account. | Add the role. Check the account. |
| The status line says that the site refused a self-approval. | The site requires a second approver. | Ask a second approver. |

## Links

- [Network](network.md)
- [External references](../external-references.md)
