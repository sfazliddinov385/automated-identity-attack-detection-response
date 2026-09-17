# Approve a request and check the result

I added an approval step so the responder does not disable accounts based only on failed logins. It also checks Active Directory after making changes and only reports success when all five accounts are disabled. The SPL detection query is unchanged.

## What the responder does

- Accepts an alert with the correct response key from the allowed source. The key does not grant approval.
- Waits for an administrator to approve the request on DC-01 using `Approve-SOARRequest.ps1`.
- Checks the approval and all five accounts when the original alert is sent again.
- Disables the approved accounts and checks their state on the same domain controller.
- Reports success only when all five accounts are confirmed disabled.
- Reports pending approvals, expired approvals, failed changes, and interrupted work separately.

## Install and try a dry run

Copy the four PowerShell scripts from `windows-responder/` to the lab domain controller. Run `install-responder.ps1` as an administrator. It installs in dry-run mode by default. When upgrading, it stops the existing scheduled task before replacing the scripts.

The installer restricts `C:\SOAR\Response` and its contents to SYSTEM and Administrators. Ordinary users and the Shuffle automation account must not be able to change the scripts, approvals, or saved results. Keep the response key out of Git.

Send a valid alert and check the dry-run preview. The response should contain:

- `status: dry_run`
- `success: false`
- `verified: false`

These values are expected because the responder has not changed any accounts. A dry run does not use up an approval.

Once the preview looks right, run the installer with `-EnableLiveResponse`. Each request will still need approval before accounts can be disabled.

## Review a pending request

Shuffle sends the alert JSON and response key. The alert includes `domain`, `event_time`, and the five `targeted_users`.

If live response is enabled but the request has no approval, the responder returns HTTP 202 with `status: pending_approval` and a 64-character `request_id`. No accounts are changed.

The request is saved here:

```text
C:\SOAR\Response\state\requests\<request_id>.json
```

The request ID is calculated from the detection name, severity, domain, source IP, event time, and usernames. Before calculating it, the responder puts the IP address and timestamp into a consistent format and sorts the usernames. Changes to those values produce a different ID.

Adding `approved`, `approval`, or `approved_by` to the alert does not approve it. The responder checks for a local approval file on DC-01.

Before approving, check:

1. Should this source be signing in as these users?
2. What caused the failed logins, and what else happened around that time?
3. Are there related successful logins or other alerts? A successful login can help explain the activity, but it is not required for every response.
4. What would stop working if these accounts were disabled?
5. Is this the intended lab test, and are you authorized to disable these accounts?

Record why you are approving the request. The query labels every matching result `High`; that label alone does not establish how serious the activity is. The script does not collect other evidence for you.

On DC-01, run this command with the returned request ID:

```powershell
C:\SOAR\Response\Approve-SOARRequest.ps1 -RequestId '<request_id>' -Reason 'Reviewed controlled test and impact on the five lab users.'
```

The tool shows the request and asks for confirmation. It records your Windows identity and creates an approval that lasts 15 minutes by default, with a maximum of 30 minutes.

Approving the request does not disable the accounts. You can use `-WhatIf` to preview the approval without saving it.

If the evidence does not justify disabling the accounts, leave the request unapproved and record your reason in your investigation notes. This lab does not have a ticketing system or a separate rejection screen.

## Send the approved request again

After approving it, resend the **unchanged original alert JSON** through the HTTP action in Shuffle. Keep the original event time and usernames. An alert with different details will have a different request ID and need its own approval.

The connector skips a result that matches its last delivered alert. It does not resend that alert when approval is recorded. In the completed lab test, I manually resent the original alert from Shuffle.

The workflow JSON in this repository describes the setup. It cannot be imported directly as a working Shuffle workflow.

Requests cannot be approved over HTTP. Having the response key is not enough to approve an account change.

## Read the result

| HTTP | Status | Meaning and next step |
| --- | --- | --- |
| 202 | `pending_approval` | No accounts changed. Review the request on DC-01, approve it if appropriate, then resend it. |
| 200 | `dry_run` | Preview only. No accounts changed. |
| 200 | `verified` | All five accounts were checked and confirmed disabled on the configured DC. |
| 200 | `already_processed` | This request already has a saved result. Check `previous_result` and its verification time. No new action or account check took place. |
| 400 | `rejected` | The alert or account list is invalid. Check the input. |
| 401/403 | `rejected` | The caller failed the authentication or source check. |
| 403 | `approval_rejected` | The local approval is invalid or expired. Review it on DC-01. |
| 409 | `preflight_failed` | An account could not be read or was outside the allowed OU. No accounts changed in this attempt. |
| 409 | `requires_review` | Processing already started, or the saved request state needs checking. |
| 500 | `partial_failure` | At least one account could not be confirmed disabled. Check the result for each account. |
| 500 | `requires_review` | An unexpected error occurred while processing the request or saving the result. Check AD and the saved files. |

A newly completed response should meet all of these conditions:

```text
HTTP 200
status == verified
success == true
verified == true
dry_run == false
verified_accounts == requested_accounts == 5
```

Keep the request ID, approval details, verification time, and account results with the workflow run.

An HTTP 2xx response alone does not prove that accounts were disabled. If Shuffle marks an HTTP 500 response as an action error, check the response body for the actual failure. Do not automatically retry account changes after an error.

## Check AD and the Windows audit logs

After calling `Disable-ADAccount`, the responder uses `Get-ADUser` to check the account on the same configured DC. It checks up to three times if the account still appears enabled.

A failed command, an unreadable account, or an account that remains enabled counts as a failure. If an account is already disabled, the responder verifies its state without disabling it again.

This confirms the account state on that DC at `verified_at`. It does not confirm that existing sessions ended, that the change reached every other DC, or that all attacker activity stopped.

Use `splunk/account-disable-audit.spl` to check Event ID 4725 separately. Compare the affected users, the account that made the changes, and the timestamps with the response record.

An account that was already disabled will not produce a new disable event. The responder does not automatically search Splunk for these events.

## Repeated requests and failed actions

Before changing any accounts, the responder creates this lock file:

```text
processing/<request_id>.lock
```

The file records that processing has started and prevents another copy of the request from running the same actions. It remains in place if the service stops unexpectedly.

When processing finishes, the responder saves the result separately. Sending the same request again returns that saved result, even if the original attempt failed.

After a crash or partial failure, check AD and the audit events before taking another action. Keep the lock and result files. Deleting them just to force a retry could cause the same work to run again without understanding what already happened.

Before manual recovery, record the current account state and review and authorize the recovery action.

The approval tool will not overwrite an expired, unused approval. An administrator can move that expired file outside the active `approvals` directory and review the pending request again. Do this only if the request has no processing lock or saved result.

## Limits

The responder runs as SYSTEM on the lab domain controller. The username and OU checks restrict which accounts the script will change, but the process still has SYSTEM permissions.

Further work includes HTTPS with a trusted certificate, a service account with fewer permissions, protected central logs, service monitoring, and an easier approval process.

The detection looks for activity from a single source within a short time window. The query also returns only the latest matching result because it uses `head 1`.

The original screenshots show the first version. The [September 17 test record](validation-2026-09-17.md) shows the approval step and the confirmed account changes. The full set of failure scenarios has not been tested on the live VMs.
