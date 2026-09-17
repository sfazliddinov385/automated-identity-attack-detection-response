# Approve a request and check the result

The responder now waits for approval before disabling accounts and checks AD
afterward. These changes address two problems in the first version: acting on
failed logins alone and reporting success before checking the account changes.
The SPL detection has not changed.

## What the responder does

- A request with the correct key can submit an alert. It cannot approve itself.
- An administrator reviews the request on DC-01 and uses
  `Approve-SOARRequest.ps1` to approve it, with a reason and an expiration time.
- When the same request is sent again, the responder checks its approval and all
  five users before making changes.
- The responder reads each account back from the same DC after the action.
- It reports success only when all five accounts are confirmed disabled.
- It returns different results for pending requests, expired approvals, failed
  account changes, and interrupted work. Those results do not count as success.

## Install and try a dry run

Copy all four files from `windows-responder/` to the lab domain controller. Run
`install-responder.ps1` as an administrator to install in dry-run mode. During an
upgrade, the installer stops the existing task before replacing the scripts.

The installer limits access to `C:\SOAR\Response` and its contents to SYSTEM
and Administrators. The HTTP service must not run with files or state writable
by ordinary users or the Shuffle automation account. Keep the response key out
of the repository.

Send a valid alert in dry-run mode and check the preview. It returns
`status: dry_run`, `success: false`, and `verified: false` because no accounts have
been changed. It does not use up an approval.

After checking the dry run in your lab, install with `-EnableLiveResponse`.
The responder will still require approval for each request.

## Review a pending request

Shuffle sends the alert JSON and the response key. The JSON includes `domain`,
`event_time`, and the five `targeted_users`. Without approval, a live request
returns HTTP 202, `status: pending_approval`, and a 64-character `request_id`.
No accounts are changed.

The responder saves the request here:

```text
C:\SOAR\Response\state\requests\<request_id>.json
```

The ID is based on the detection, severity, domain, source IP, event time, and
usernames. The responder formats the IP and timestamp and sorts the usernames
before calculating it. Changing those details creates a different request.
Adding `approved`, `approval`, or `approved_by` to the HTTP message does not
approve anything; approval must come from the protected file on DC-01.

Before approving, review:

1. Is the source expected to authenticate as these users?
2. Do failure reasons and surrounding activity support a security concern?
3. Are there relevant successful logons or other alerts? A successful logon is
   useful context, not a required condition for every justified response.
4. Who or what would be affected if these accounts were disabled?
5. Is this the intended controlled test, and is account disabling authorized?

Write down why you are approving the request. The query always labels matching
results `High`; that label is not a separate assessment of the activity. The
script does not gather supporting evidence from other sources, so that review
is up to the administrator.

On the lab DC, run the local tool with the returned ID:

```powershell
C:\SOAR\Response\Approve-SOARRequest.ps1 -RequestId '<request_id>' -Reason 'Reviewed controlled test and impact on the five lab users.'
```

The tool displays the request, asks for confirmation, records the current Windows
identity, and writes a 15-minute approval by default (maximum 30 minutes). It does
not itself disable accounts. Use `-WhatIf` to preview approval without writing it.

If the evidence does not justify disabling accounts, leave the request
unapproved and record your decision in your investigation notes. This lab does
not include a ticketing system or a separate interface for rejecting requests.

## Send the approved request again

Resubmit the **unchanged original alert JSON** through the response HTTP action
after local approval. Preserve the event time and user set. A fresh detector
result is a separate request and requires its own approval.

The connector skips a result matching its last delivered alert. It does not send
an alert again after approval. Resend the saved original alert from Shuffle;
the completed lab test used this manual step. The repository's workflow JSON
explains the intended setup, but cannot be imported as a working workflow.

There is no HTTP route for approving requests. The response key alone cannot
create an approval.

## Read the result

| HTTP | Status | Meaning and next step |
| --- | --- | --- |
| 202 | `pending_approval` | No accounts changed. Review locally, then resend after approval. |
| 200 | `dry_run` | Preview only; no account changes. |
| 200 | `verified` | All five accounts read back as disabled on the configured DC. |
| 200 | `already_processed` | Historical result with its verification time; no new action or fresh state check. Inspect `previous_result`. |
| 400 | `rejected` | Invalid alert or account set; correct the input. |
| 401/403 | `rejected` | Caller authentication or source failed. |
| 403 | `approval_rejected` | Invalid or expired local approval; review locally. |
| 409 | `preflight_failed` | An account could not be read or left the OU. No accounts changed in this attempt. |
| 409 | `requires_review` | A saved record shows processing already started, or the saved state needs checking. |
| 500 | `partial_failure` | At least one account was not confirmed disabled. Check each result. |
| 500 | `requires_review` | An unexpected error occurred while processing or saving the result. Check AD and the saved files. |

For a new response to count as successful, all of these should be true:

```text
HTTP 200
status == verified
success == true
verified == true
dry_run == false
verified_accounts == requested_accounts == 5
```

Keep the request ID, approval details, verification time, and individual account
results with the workflow run. HTTP 2xx alone does not mean the accounts were
disabled. If Shuffle marks an HTTP 500 as an action error, keep the response body
so you can see what failed. Do not automatically retry the account changes.

## Check AD and the Windows audit logs

Each `Disable-ADAccount` is followed by `Get-ADUser` on the same configured DC.
Enabled accounts are checked up to three times. A successful command with an
unchanged enabled account, a failed command, or an unreadable account produces a
failed result. Previously disabled accounts are verified without disabling again.

The AD check shows the account state on that DC at `verified_at`. It does not
show that existing sessions ended, that every other DC received the change, or
that an entire attack was stopped.

Event ID 4725 remains a separate audit check using
`splunk/account-disable-audit.spl`. Compare the target user, actor, and timestamps
with the response record. Already-disabled accounts will not generate a fresh
disable event. This revision does not automatically query Splunk for 4725.

## Repeated requests and failed actions

Before changing accounts, the service creates `processing/<request_id>.lock`.
This file records that work has started and prevents another copy of the request
from starting the same actions. It stays in place if the service stops
unexpectedly. Once processing finishes, the result is saved separately. Sending
the request again returns the saved result, including a failed result.

After a crash or partial failure, check AD and the audit events before deciding
what to do next. Keep the lock and result files; do not delete them just to make
automatic retries work. Before attempting manual recovery, review and authorize
the action again and record the current account state.

An expired, unused approval is intentionally not overwritten by the approval
tool. A local administrator may archive that expired approval outside the active
`approvals` directory and then review the still-pending request again. Never do
this for a request with a processing lock or saved result.

## Limits

The responder runs as SYSTEM on the lab DC. The username and OU checks limit
what the script does, but do not reduce its Windows permissions. Work remains
on trusted HTTPS, narrower service permissions, protected central logs, service
monitoring, and a simpler approval process. Detection is still limited to one
source, a short time window, and the latest matching result (`head 1`).

The original screenshots show the first version. The
[September 17 test record](validation-2026-09-17.md) shows the updated approval
and account response. The full list of failure scenarios has not been tested
on the live VMs.
