# Network

This page lists every outbound call of Pivots and Scripts and the certificate that CMPivot needs.

## What it does

The tool talks to the SMS Provider in three ways. When it is installed by the suite installer, it also checks GitHub once a day for a newer suite version. The update check sends no user data and no telemetry.

## When to use it

Use it to open the firewall for the tool, to set up the certificate trust, or to check the traffic.

## Requirements

| Call | Target | When | Content |
|---|---|---|---|
| ConfigurationManager module | The SMS Provider in **Options > Connection**. | Test connection, Resolve targets, Submit, Run for scripts. | Device and collection reads, and the script commands of the console module. |
| Administration service over HTTPS | `https://<provider>/AdminService/v1.0/` | Run CMPivot and the result reads, every 3 seconds. | The query, the target list and the status reads. |
| WMI over DCOM (CIM) | The SMS Provider, namespace `root\SMS\site_<code>`. | Site scripts, script runs and script results. | Reads of `SMS_Scripts` and `SMS_ScriptsExecutionStatus`. |
| `https://api.github.com/repos/<repository>/releases/latest` | HTTPS to GitHub. | At the start, once a day, only when the suite installer installed the tool. | The check for a newer suite version. |

## Steps

### Trust the provider certificate

CMPivot fails when the computer does not trust the certificate that the administration service shows. By default, the site binds a certificate that the root `SMS Issuing` issued.

1. Find out which certificate the provider shows. The name must match the provider name that you typed in Options.
2. Add the issuer to the **Trusted Root Certification Authorities** store of the computer. Or bind a certificate of your PKI to the administration service and trust that root.
3. Select **Run CMPivot** again.

The lab of this guide used the first way: the `SMS Issuing` root of the site was added to the computer store of the client computer.

## Limits

- A plain extract of the zip (no `suite-manifest.json`) makes no call to GitHub. A failed update check is ignored.
- The tool does not change a proxy setting.

## Troubleshooting

| Message or symptom | Cause | Fix |
|---|---|---|
| The device detail shows a trust or TLS error. | The computer does not trust the provider certificate. | Trust the issuer as above. |
| `AdminService returned HTTP 401 ...` | The account is not accepted, or it has no right. | See [Permissions](permissions.md). |
| `AdminService returned HTTP 400 ...` | The query is not valid. | Check the query syntax. |

## Links

- [Permissions](permissions.md)
- [External references](../external-references.md)
