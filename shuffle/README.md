# Shuffle workflow reference

The public JSON is a sanitized design reference, not an importable or deployed
Shuffle export. Installation-specific app, webhook, authentication, and action
IDs must be configured in the lab.

## Current response flow

1. Receive the authenticated connector webhook.
2. Check the expected detection, High severity, and at least five targets.
3. Submit the unchanged alert to the restricted responder.
4. Treat HTTP 202 / `pending_approval` as **waiting for review**. Save the
   original alert and the returned request ID.
5. A local operator reviews and approves that request on DC-01.
6. Explicitly resubmit the same response action with the saved original alert.
7. Check the actual response body, not just HTTP 200. Record verified results,
   or retain failures for investigation.

The connector does not resend a duplicate alert to resume this workflow. Use a
manual resume path or a dedicated workflow that takes the saved original alert.
This reference does not include a ticketing integration or an installed pause UI.

## HTTP request

```text
POST http://<DC-01>:8081/disable-users
Content-Type: application/json
X-SOAR-RESPONSE-KEY: <secret outside Git>
Body: original normalized alert, including domain, event_time, and targeted_users
```

There is no HTTP approval route. Never put an approval secret or a privileged
file-writing capability in Shuffle to bypass the local review boundary.

## Result routing

| Status | Route |
| --- | --- |
| pending_approval | Wait; no accounts changed |
| dry_run | Preview; never mark containment complete |
| verified | Require success=true, verified=true, dry_run=false, and 5 verified users |
| already_processed | Display previous_result and its time as historical evidence |
| partial_failure | Escalate per-account failures; do not mark complete or retry automatically |
| rejected / approval_rejected / preflight_failed / requires_review | Stop and investigate |

Handle non-2xx bodies on the error path of the HTTP app. A 500 can describe
partial account changes and must not be dropped. Expired or refused approval
does not authorize changes.

See the [operator guide](../docs/approval-and-verification.md) for setup, exact
status codes, approval expiry, and recovery after interrupted execution.

