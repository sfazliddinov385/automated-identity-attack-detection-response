# Active Directory responder with local approval

The responder accepts authenticated alerts from Shuffle, requires local approval
for live account changes, and verifies each account's state after the action.

## Files and installation

Keep these four files together on the lab DC:

- `SOAR-AD-Responder.ps1`: HTTP boundary and audit logging.
- `SOAR-ResponseCore.ps1`: approval, policy, execution, and verification logic.
- `Approve-SOARRequest.ps1`: local operator review and approval.
- `install-responder.ps1`: protected files, firewall, and startup task.

Install as Administrator with `./install-responder.ps1`. The default is dry-run.
The installer stops the old task on upgrade, protects the entire installation
and state directory for SYSTEM/Administrators, and passes the configured source
IP and listener port to the scheduled task.

After validating the dry-run, `./install-responder.ps1 -EnableLiveResponse`
enables approved changes. The task still runs as SYSTEM on the DC; restricted
AD delegation is a future production improvement.

## Workflow

1. Submit a valid alert to `POST /disable-users` with the existing
   `X-SOAR-RESPONSE-KEY` secret.
2. A live request returns HTTP 202 and a `request_id`, without changing AD.
3. Review it locally with `Approve-SOARRequest.ps1 -RequestId '<id>' -Reason '<reason>'`.
4. Resubmit the unchanged payload from Shuffle after approval.
5. Require `status: verified`, `success: true`, `dry_run: false`, and five
   verified accounts. Inspect errors and partial results.

The operator's approval is a protected local file with an identity, reason, and
expiry. HTTP JSON fields cannot grant approval. The request ID binds approval
to the source, event time, domain, detection, and exact user set.

## Alert contract

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

Other fields from the connector are accepted as context but grant no authority.
Never commit the response key, pending request data, approvals, or runtime logs.

Read [approval, resume, status, and recovery instructions](../docs/approval-and-verification.md)
before installing this revision. AD state readback is automatic; the independent
Splunk 4725 audit remains a separate check. Tests use fake AD, and a fresh VM
integration run is still required.

