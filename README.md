# Automated Identity Attack Detection and Response

I built this lab to practice detecting password spraying and responding to it with Splunk, Shuffle, and Active Directory. I used five test accounts and generated failed SMB logins from a Windows VM.

Splunk detects the failed-login pattern, and a Python script sends the alert to Shuffle. A PowerShell responder on the domain controller handles the account changes. It requires approval first, then checks Active Directory to confirm that all five accounts are disabled.

![Lab diagram showing detection, approval, account changes, and the audit check](diagrams/architecture-diagram.png)

[Open the diagram](diagrams/architecture-diagram.png) · [SVG version](diagrams/architecture-diagram.svg)

## How it works

1. **Generate the test activity.** VICTIM-B tries an incorrect password against `spray.user01` through `spray.user05`.
2. **Collect the logs.** The domain controller records failed logins as Windows Event ID `4625`. Its Splunk Universal Forwarder sends the events to the Splunk server.
3. **Detect the pattern.** Splunk looks for one source IP failing to log in to five or more different lab accounts within a rolling five-minute window.
4. **Send the alert.** The Python connector checks Splunk every 60 seconds and sends a matching result to Shuffle. It remembers the last alert it sent so it can skip an identical result on the next check.
5. **Approve the request.** Shuffle checks the alert and sends it to the responder. The responder returns `pending_approval` without changing accounts. I review and approve the request on DC-01, then resend the same alert from Shuffle.
6. **Disable and check the accounts.** The responder checks the approval, usernames, and organizational unit (OU). It disables the allowed accounts and reads their status back from AD. It reports success only when all five are confirmed disabled.
7. **Check the audit events.** I search Splunk for Event ID `4725` to confirm Windows recorded the account changes. This is a separate manual check.

The detection maps to **MITRE ATT&CK T1110.003 — Password Spraying**. Failed logins alone do not prove that an account was compromised, which is why the response requires approval.

## Lab setup

| Machine | What it does | IP address |
| --- | --- | --- |
| VICTIM-B | Generates the failed logins | `192.168.226.133` |
| DC-01 (`WIN-3B0FE43Q9UR`) | Runs Active Directory, DNS, and the PowerShell responder | `192.168.226.132` |
| SIEM-01 | Runs Splunk and the Python connector | `192.168.226.129` |
| SOAR-01 | Runs Shuffle in Docker | `192.168.226.134` |

The lab runs in VMware on a private network. It uses Windows Server, Ubuntu, Splunk Enterprise, Splunk Universal Forwarder, Shuffle, Python, and PowerShell.

## What I changed after the first version

The first version disabled the test accounts automatically. I added a local approval step so the responder would wait for a decision before making changes. Approval applies to one specific request and expires after 15 minutes by default. Approving it does not send it again; I still have to resend the same alert from Shuffle.

I also changed how the responder reports success. An HTTP `200` response alone does not prove that an account was disabled. The responder now checks each account in AD and reports any failure. If a completed request is sent again, it returns the saved result without repeating the account changes.

The response is limited to the five named test users in the `SOAR-Lab-Users` OU. It uses separate keys for the two integrations, restricts requests to the SOAR server's IP, and starts in dry-run mode when installed.

## Test results

On September 17, 2026, I tested the updated flow in the lab:

- Fresh failed logins reached Splunk and triggered a Shuffle workflow.
- Dry-run mode returned a preview without changing accounts.
- Live mode returned `pending_approval` before approval.
- After I approved and resent the same alert, the responder reported `success: true`, `verified: true`, and `verified_accounts: 5`.
- Splunk showed five matching Event ID `4725` records at about 08:28 CDT.

| Result | Screenshot |
| --- | --- |
| Request waiting for approval | [Pending response](evidence/2026-09-17/01-pending-approval.png) |
| Five accounts verified disabled | [Approved response](evidence/2026-09-17/02-approved-response.png) |
| Five account-disable events in Splunk | [Audit events](evidence/2026-09-17/03-splunk-audit-4725.png) |

The [test record](docs/validation-2026-09-17.md) includes the timestamps and results. There are also automated tests for the connector and responder. Those use simulated API and AD results; I have not run every failure scenario against the live VMs.

## Problems I worked through

- The target username was inside Splunk's multivalue `Account_Name` field. I had to extract the right value before counting users.
- Shuffle's HTTP worker needed access to the correct Docker network before it could finish the request.
- Splunk kept returning the same detection, so the connector needed to remember which alert it had already sent.
- A successful HTTP request was not enough to confirm the response. I added an AD check and compared the result with Windows audit events.

More detail is in [what I learned](docs/lessons-learned.md).

## Limits

This is a small lab with a narrow detection rule. It can miss slow or distributed password spraying, and the search returns only the latest matching result. The connector remembers one delivered alert, not a full history.

The responder still runs as SYSTEM on the domain controller and uses internal HTTP. The username and OU checks limit what the script does, but they do not reduce the Windows account's privileges. Approval, resubmission, and the Splunk audit check are manual.

Before using this outside the lab, I would add trusted HTTPS, reduce the service account's permissions, and test failures and recovery more thoroughly. Disabling an account also does not prove that existing sessions have ended or that an entire attack has been stopped.

## Files and setup

| Folder | Contents |
| --- | --- |
| [`splunk/`](splunk/README.md) | Detection and account-disable audit searches |
| [`connector/`](connector/README.md) | Python connector and its systemd service |
| [`shuffle/`](shuffle/README.md) | Workflow notes and a reference JSON file |
| [`windows-responder/`](windows-responder/README.md) | PowerShell responder, installer, and approval script |
| [`testing/`](testing/README.md) | Scripts for the controlled lab test |
| [`docs/`](docs/architecture.md) | Setup notes, test results, and troubleshooting |
| [`diagrams/`](diagrams/README.md) | Current and original lab diagrams |
| `evidence/` | Screenshots from both versions |

Start with the component guides above, then follow the [approval and verification steps](docs/approval-and-verification.md). The Shuffle JSON is a reference for building the workflow, not a ready-to-import export.

## Original test

The seven screenshots directly inside [`evidence/`](evidence/) and the [original diagram](diagrams/architecture-diagram-v1.png) show the first version, before local approval and automatic AD checks were added. The September screenshots linked above show the updated response.

## Author

**Sarvarbek “Bek” Fazliddinov**  
Information Security Graduate Student at Georgia Tech
