# Lab test — September 17, 2026

Responder revision: `c356035b4dd0851e72810dd557eb010b33e22bd5`.

These notes record what I tested and the results I saved from the terminal, Shuffle, and Splunk. They describe this lab run, not a separate inspection of the VMs.

## What happened

- After resuming the VMs, I confirmed that fresh Windows logs from DC-01 were reaching Splunk.
- Five controlled failed logins from VICTIM-B (`192.168.226.133`) triggered a detection for `spray.user01` through `spray.user05`.
- Shuffle received the alert in webhook execution `9da05c60-44da-40a4-a4bb-5d8fd8c6fbb0`, which started at 08:12:19 CDT. The alert's event time was 13:12:13.661 UTC, with five failed attempts against five accounts. The responder returned HTTP 200 with `status=dry_run` and `verified=false`, reporting no account changes.
- After enabling live mode, I resent the same alert at 08:25:05 CDT. The responder returned HTTP 202 with `status=pending_approval` and reported no account changes.
- I approved the request on DC-01 as `LAB\Administrator` at 13:26:06.8848109 UTC. The approval expired at 13:41:06.8848109 UTC. The reason was: "Authorized lab test: disable the five spray.user test accounts".
- I resent the unchanged alert at 08:27:56 CDT. The responder returned HTTP 200 with `status=verified`, `success=true`, `verified=true`, `cached=false`, `requested_accounts=5`, `verified_accounts=5`, and `needs_review=false`. It checked AD through `localhost` and recorded the verification time as 13:28:01.8534737 UTC.

The approval and live response used the same request ID:

```text
fa9bfbdcd86f6032565c2f928df5b5b2187bd57ab694b75f3e4786267c3e9162
```

## Windows audit events in Splunk

I searched for EventCode 4725 on `WIN-3B0FE43Q9UR`. Splunk showed "A user account was disabled" for all five test accounts:

| Target | Splunk displayed time (CDT) |
| --- | --- |
| spray.user01 | 2026-09-17 08:28:01.694 |
| spray.user02 | 2026-09-17 08:28:01.728 |
| spray.user03 | 2026-09-17 08:28:01.758 |
| spray.user04 | 2026-09-17 08:28:01.785 |
| spray.user05 | 2026-09-17 08:28:01.814 |

The events identify SYSTEM through SID `S-1-5-18` and show the DC machine account, `WIN-3B0FE43Q9UR$`, as the account that made the changes. The administrator who approved the request is recorded separately in the response.

The `TargetUserName` and `SubjectUserName` columns were blank, but the account details were present in the Message field.

The responder checked AD automatically. I checked the audit events in Splunk manually.

## Screenshots

These are the original, unedited screenshots. The Shuffle captures cut off part of the request ID, so I included the full ID from the saved execution output above.

### Before approval

The responder was in live mode (`dry_run=false`) but returned HTTP 202 with `status=pending_approval`. It reported that no accounts had changed.

Shuffle's outer `success=true` refers to the HTTP action. It does not mean the accounts were disabled.

![Live request waiting for approval](../evidence/2026-09-17/01-pending-approval.png)

### After approval

The response shows who approved the request, their reason, and the approval time. It also confirms that all five accounts were verified as disabled.

The individual account results are collapsed in this screenshot. The Splunk screenshot below shows all five usernames.

![Approved response confirming five disabled accounts](../evidence/2026-09-17/02-approved-response.png)

### Account-disable events

The event messages show the five affected accounts, the SYSTEM identity that made the changes, and timestamps matching the approved response.

This screenshot shows the results table. The EventCode 4725 filter was part of the search used to produce it.

![Five account-disable events in Splunk](../evidence/2026-09-17/03-splunk-audit-4725.png)

## Notes and untested cases

During an individual action test, the previous HTTP body mapping returned "Missing alert field: detection". I changed the Shuffle HTTP body to `$exec`, and the next action test worked. The successful full workflow run also sent the unchanged original alert.

Approval still happens locally on DC-01, and the alert must be resent manually from Shuffle. There is no built-in Shuffle approval screen or automatic resume step in this setup.

This run tested a request waiting for approval, local approval, and a successful response. It did not test these cases on the live VMs:

- Forged approvals.
- Wrong response keys or unapproved source IPs.
- Expired approvals.
- Partial account-change failures.
- Recovery after a crash.
- Resending an already completed request.

I did not save a separate `Get-ADUser` check after the response. The saved evidence consists of the responder's AD verification and the five Windows audit events in Splunk.

The lab still runs the responder as SYSTEM on the DC, uses internal HTTP, and has a detection rule built around this specific test. The connector also remembers only its last delivered alert. These limits are covered in the main README.
