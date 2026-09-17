# Review before response, then verify the outcome

This revision addresses two gaps: automatically disabling users based only on
failed logons, and treating an accepted request as proof of a completed response.
The SPL detection itself is unchanged.

## What is implemented

- An authenticated HTTP alert can create a pending request, but cannot approve it.
- A local administrator reviews the exact request and records a reason and a
  short-lived approval with `Approve-SOARRequest.ps1`.
- On resubmission, the responder validates the approval and all five users before
  making any AD changes.
- The responder reads each account back from the same DC after the action.
- An overall success requires every account to be verified disabled.
- Per-account failures, pending requests, expired approvals, and interrupted work
  are explicit outcomes; none is silently treated as verified containment.

## Install and start safely

Copy all four files from `windows-responder/` to the lab domain controller. Run
`install-responder.ps1` as an administrator to install in dry-run mode. Upgrade
installation stops the existing scheduled task before replacing its scripts.

The installer protects `C:\SOAR\Response` and its children for SYSTEM and
Administrators only. The HTTP service must not run with files or state writable
by ordinary users or the Shuffle automation account. Keep the response key out
of the repository.

Submit a valid alert in dry-run mode and inspect the preview. It returns
`status: dry_run`, `success: false`, and `verified: false` deliberately: previewing
an action is not completing it. No approval is consumed.

Only after validating this on the isolated lab, install with
`-EnableLiveResponse`. This enables approved live actions; it does not bypass
per-request approval.

## Review a pending request

Shuffle sends the same authenticated JSON contract as before, including
`domain`, `event_time`, and the exact five `targeted_users`. The initial live
response is HTTP 202, with `status: pending_approval` and a 64-character
`request_id`. It makes no account changes.

The canonical request is saved under:

```text
C:\SOAR\Response\state\requests\<request_id>.json
```

The request ID includes the detection, severity, domain, normalized source IP,
event time, and sorted exact user set. Altering any of those changes the ID.
Extra caller fields such as `approved`, `approval`, or `approved_by` grant no
authority. Only a protected local approval file is accepted.

Before approving, review:

1. Is the source expected to authenticate as these users?
2. Do failure reasons and surrounding activity support a security concern?
3. Are there relevant successful logons or other alerts? A successful logon is
   useful context, not a required condition for every justified response.
4. What is the operational impact of disabling these accounts?
5. Is this the intended controlled test, and is account disabling authorized?

Record a specific reason. Severity `High` is a fixed label in this lab's query,
not an independent risk assessment. The code does not automatically enrich the
alert with other sources; review of that context is an operator step.

On the lab DC, run the local tool with the returned ID:

```powershell
C:\SOAR\Response\Approve-SOARRequest.ps1 -RequestId '<request_id>' -Reason 'Reviewed controlled test and impact on the five lab users.'
```

The tool displays the request, asks for confirmation, records the current Windows
identity, and writes a 15-minute approval by default (maximum 30 minutes). It does
not itself disable accounts. Use `-WhatIf` to preview approval without writing it.

If response is not justified, do not approve or resume. Record that decision in
your investigation notes. A ticketing system, dedicated rejection UI, and
automatic context enrichment are not included in this lab reference.

## Resume the response in Shuffle

Resubmit the **unchanged original alert JSON** through the response HTTP action
after local approval. Preserve the event time and user set. A fresh detector
result is a separate request and requires its own approval.

The connector suppresses already-delivered results; it does not perform this
resume step. Configure a review/resume path in Shuffle or start a dedicated
resume workflow with the saved original alert. The public workflow JSON is a
design reference, not a directly importable or deployed Shuffle workflow.

There is no HTTP approval endpoint. Possessing the normal response key does not
permit creating an approval record.

## Interpret the result

| HTTP | Status | Meaning and next step |
| --- | --- | --- |
| 202 | `pending_approval` | No action. Await local review, then explicitly resume. |
| 200 | `dry_run` | Preview only. Never label this containment. |
| 200 | `verified` | All five accounts read back as disabled on the configured DC. |
| 200 | `already_processed` | Historical result with its verification time; no new action or fresh state check. Inspect `previous_result`. |
| 400 | `rejected` | Invalid alert or account set; correct the input. |
| 401/403 | `rejected` | Caller authentication or source failed. |
| 403 | `approval_rejected` | Invalid or expired local approval; review locally. |
| 409 | `preflight_failed` | An account could not be read or left the OU. No accounts changed in this attempt. |
| 409 | `requires_review` | An existing processing claim or an unsafe state prevents execution. |
| 500 | `partial_failure` | At least one account did not verify disabled. Inspect every result and escalate. |
| 500 | `requires_review` | Unexpected processing or persistence failure; inspect AD and protected state. |

For a fresh successful action, require all of:

```text
HTTP 200
status == verified
success == true
verified == true
dry_run == false
verified_accounts == requested_accounts == 5
```

Keep `request_id`, approval identity/reason/time, `verified_at`, and the individual
results in the workflow record. Do not route every HTTP 2xx response to success.
If the HTTP app treats a 500 as an execution error, route that failure to review;
do not discard its response body or automatically retry account changes.

## Automatic verification and independent audit

Each `Disable-ADAccount` is followed by `Get-ADUser` on the same configured DC.
Enabled accounts are checked up to three times. A successful command with an
unchanged enabled account, a failed command, or an unreadable account produces a
failed result. Previously disabled accounts are verified without disabling again.

The automatic check proves the observed AD state at `verified_at` on that DC.
It does not prove termination of existing sessions, enterprise-wide replication,
or complete eradication of an intrusion.

Event ID 4725 remains a separate audit check using
`splunk/account-disable-audit.spl`. Compare the target user, actor, and timestamps
with the response record. Already-disabled accounts will not generate a fresh
disable event. This revision does not automatically query Splunk for 4725.

## Replay, failure, and recovery

Before any live AD action, the service creates an exclusive persistent
`processing/<request_id>.lock` record. Concurrent or interrupted execution cannot
silently start another disable loop. The completed result is saved separately.
Repeated submissions return that historical result, including failures.

After an ambiguous crash or partial failure, inspect account state and audit
evidence before deciding on another action. Do not delete locks or results as an
automatic retry mechanism. Preserve the records. Any deliberate manual recovery
needs a new reviewed authorization and a documented account-state check.

An expired, unused approval is intentionally not overwritten by the approval
tool. A local administrator may archive that expired approval outside the active
`approvals` directory and then review the still-pending request again. Never do
this for a request that already has a processing claim or result.

## Remaining boundaries

This is still an isolated lab. The responder still runs as SYSTEM on a DC; the
OU and account checks are application restrictions, not least-privilege AD
delegation. Trusted TLS, delegated service permissions, protected central logs,
health monitoring, and a richer review interface remain production work. The
original single-source detection, short window, and `head 1` limit also remain.

Existing screenshots document v1. Run the new validation checklist before
claiming this revision has been demonstrated end to end in Windows/AD/Shuffle.
