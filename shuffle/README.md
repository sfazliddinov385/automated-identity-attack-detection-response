# Shuffle workflow reference

The JSON in this folder shows how the workflow is arranged. It is not an
importable Shuffle export. Set up the apps, webhook, credentials, and action IDs
in your own lab.

## Current response flow

1. Receive the alert through the authenticated connector webhook.
2. Check the detection name, High severity, and at least five target accounts.
3. Send the unchanged alert to the responder on DC-01.
4. HTTP 202 / `pending_approval` means **waiting for approval**. Save the
   original alert and the returned request ID.
5. Review and approve that request locally on DC-01.
6. Manually run the response action again with the saved original alert.
7. Check the response body to see whether the accounts were disabled and
   verified. HTTP 200 alone does not tell you this. Keep any errors for review.

The connector skips duplicate alerts, so it will not resend the request after
approval. Resume it manually in Shuffle, or use a separate workflow that takes
the saved original alert. This reference does not include a ticketing system or
an approval screen in Shuffle.

## HTTP request

```text
POST http://<DC-01>:8081/disable-users
Content-Type: application/json
X-SOAR-RESPONSE-KEY: <secret outside Git>
Body: original normalized alert, including domain, event_time, and targeted_users
```

Approval is available only on DC-01; there is no HTTP endpoint for it. Keep
Shuffle's access limited to submitting alerts. It must not be able to create or
change the local approval files.

## What to do with each result

| Status | Next step |
| --- | --- |
| pending_approval | Wait; no accounts changed |
| dry_run | Preview; never mark containment complete |
| verified | Check success=true, verified=true, dry_run=false, and 5 verified users |
| already_processed | Show previous_result and its timestamp; this is the saved result of an earlier response |
| partial_failure | Review the failed accounts; do not mark complete or retry automatically |
| rejected / approval_rejected / preflight_failed / requires_review | Stop and investigate |

Read the response body even when the HTTP app returns an error. HTTP 500 can
mean that some accounts changed and others failed. Expired or refused approval
does not allow account changes.

See the [setup and approval guide](../docs/approval-and-verification.md) for setup, exact
status codes, approval expiry, and recovery after interrupted execution.
