# Architecture

The lab detects failed logins and sends the alert to Shuffle. Before it can
disable any accounts, an administrator must approve the request on DC-01 and
send the same alert again from Shuffle. The responder then checks Active
Directory to confirm the accounts are disabled. Event 4725 is checked
separately in Splunk.

![Current architecture and approval flow](../diagrams/architecture-diagram.png)

[SVG version](../diagrams/architecture-diagram.svg) ·
[Lab results and screenshots](validation-2026-09-17.md)

## Network design

The four VMs share the isolated `192.168.226.0/24` lab network.

| Host | Address | What it runs |
| --- | --- | --- |
| VICTIM-B | `192.168.226.133` | Failed SMB login test against the five lab users |
| DC-01 | `192.168.226.132` | AD DS, DNS, Windows Security logs, PowerShell responder on TCP 8081 |
| SIEM-01 | `192.168.226.129` | Splunk, Universal Forwarder receiving port 9997, Python connector |
| SOAR-01 | `192.168.226.134` | Shuffle SOAR in Docker, webhook that accepts alerts from the connector |

## Detection and response

1. VICTIM-B makes failed SMB login attempts against the lab accounts. DC-01 records
   Event 4625, and its Universal Forwarder sends the logs to Splunk.
2. Splunk looks for failed logins against five different lab accounts from one
   source within a rolling five-minute window. The Python connector checks the
   search every 60 seconds and sends a matching result to Shuffle's webhook.
3. Shuffle checks detection name, severity, and account count, then submits the
   alert to the DC responder using a separate key. A live request without
   approval returns HTTP 202, `pending_approval`, with no account changes.
4. An administrator reviews and approves the pending request on DC-01. Approval
   applies only to that request's source, event time, domain, detection, severity,
   and account list. The record includes who approved it, why, and when approval
   expires: 15 minutes by default.
5. The administrator sends the unchanged alert again from Shuffle. Approval
   alone does not resume the workflow or disable accounts.
6. The responder checks the approval and all five users' OU membership, records
   that processing has started, then disables the accounts that are still
   enabled. It reads each account's state from the same DC. It returns
   `success=true` and `status=verified` only when all five are confirmed disabled.
7. Windows records Event 4725 for account-disable actions. These events are
   forwarded to Splunk, where the account names, actor, and times are checked
   manually. This is a separate check from the responder's automatic AD check.

## Access and limits

- **Splunk access:** The connector uses credentials for Splunk's REST API. It
  saves a fingerprint of the last delivered alert to avoid sending it again.
  It does not keep a queue or a history of every delivered alert.
- **Authentication:** The Shuffle webhook and DC responder use separate keys.
  The responder accepts requests only from SOAR-01's IP. The HTTP connection
  does not encrypt the key or alert data.
- **Approval:** HTTP callers cannot approve requests. Approval is stored in
  protected files on DC-01 and expires after a short period.
- **Accounts:** The responder accepts only `spray.user01` through `spray.user05`
  in the dedicated lab OU. These restrictions are in the code. The task still
  runs as SYSTEM on the DC, so its underlying permissions are much broader.
- **Repeated requests:** A completed request returns its saved result when sent
  again. It does not check the accounts again. If processing was interrupted,
  an administrator must inspect what happened before trying to recover it.
- **Detection:** The query returns only the latest matching result. Slow attacks
  or attacks spread across several source IPs can miss the five-minute threshold.

## How the services run

The connector runs as an enabled systemd user service. The Windows responder
runs as a scheduled task under SYSTEM at startup. Shuffle runs in Docker.
A running service does not prove that alerts are reaching the next system.
The [lab test record](validation-2026-09-17.md) shows the flow that was checked.

## Original design

The [original v1 diagram](../diagrams/architecture-diagram-v1.png) documents the
previous version, which disabled accounts without a separate approval step.
The diagram at the top of this page shows the current version.
