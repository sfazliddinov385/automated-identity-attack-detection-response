# Active Directory responder with local approval

The responder receives authenticated alerts from Shuffle. It waits for approval
on DC-01 before disabling accounts, then checks AD to confirm each account is
disabled.

## Files and installation

Keep these four files together on the lab DC:

- `SOAR-AD-Responder.ps1`: handles HTTP requests and writes the response log.
- `SOAR-ResponseCore.ps1`: checks approvals and allowed accounts, disables accounts, and verifies the result.
- `Approve-SOARRequest.ps1`: displays a pending request and records local approval.
- `install-responder.ps1`: sets file permissions, the firewall rule, and the startup task.

Install as Administrator with `./install-responder.ps1`. It starts in dry-run
mode. On an upgrade, the installer stops the old task first. It limits access to
the installation and state files to SYSTEM and Administrators, and gives the
scheduled task the configured source IP and listening port.

After checking the dry-run result, `./install-responder.ps1 -EnableLiveResponse`
allows approved requests to change accounts. The task runs as SYSTEM on the DC
and uses internal HTTP. A production version would need a less privileged
account and encrypted transport.

## Workflow

1. Submit a valid alert to `POST /disable-users` with the existing
   `X-SOAR-RESPONSE-KEY` secret.
2. A new live request without approval returns HTTP 202 and a `request_id`,
   without changing AD.
3. Review it locally with `Approve-SOARRequest.ps1 -RequestId '<id>' -Reason '<reason>'`.
4. Manually resend the unchanged alert from Shuffle after approval.
5. Check for `status: verified`, `success: true`, `dry_run: false`, and five
   verified accounts. If these checks fail, review the errors and account results.

Approval is stored in a protected local file with the approving Windows account,
reason, and expiration time. Adding an approval field to the HTTP request does
not approve it. The request ID ties approval to that alert's source, event time,
domain, detection, and exact set of users.

## Alert format

```json
{
  "detection": "Password Spraying Detected",
  "severity": "High",
  "domain": "LAB",
  "event_time": "2026-08-20T18:16:00Z",
  "source_ip": "192.168.226.133",
  "targeted_accounts": 5,
  "targeted_users": ["spray.user01", "spray.user02", "spray.user03", "spray.user04", "spray.user05"]
}
```

Extra fields from the connector can provide context, but cannot approve changes.
Never commit the response key, pending request data, approvals, or runtime logs.

Read the [approval, resume, status, and recovery instructions](../docs/approval-and-verification.md)
before installing. The responder checks AD state automatically. Checking
Event ID 4725 in Splunk is a separate, manual step.

The [September 17 lab test](../docs/validation-2026-09-17.md) confirmed the flow
from an unapproved request to five verified disabled accounts, with matching
Splunk audit events. Automated tests use fake AD; the lab test did not cover
every failure and recovery scenario.
