# Lab test — September 17, 2026

Responder revision: `c356035b4dd0851e72810dd557eb010b33e22bd5`.
These notes use the terminal output, Shuffle results, and screenshots saved
during the lab test. They document that test rather than a separate review of
the VMs.

## What happened

- DC-01 forwarded fresh Windows logs into Splunk after the VM pause.
- Five controlled failed logins from VICTIM-B (`192.168.226.133`) produced
  a detection targeting `spray.user01` through `spray.user05`.
- Shuffle webhook execution `9da05c60-44da-40a4-a4bb-5d8fd8c6fbb0`
  began at 08:12:19 CDT. Its event time was 13:12:13.661 UTC and it
  reported five failed attempts against five accounts. The responder returned
  HTTP 200, `status=dry_run`, `verified=false`, with no changes reported.
- After enabling live mode, the same alert was replayed at 08:25:05 CDT.
  HTTP 202 returned `pending_approval` and reported no account changes.
- `LAB\Administrator` approved the exact request at 13:26:06.8848109 UTC,
  expiring at 13:41:06.8848109 UTC, with reason:
  "Authorized lab test: disable the five spray.user test accounts".
- The unchanged alert was replayed at 08:27:56 CDT. The response was HTTP 200,
  `status=verified`, `success=true`, `verified=true`, `cached=false`,
  `requested_accounts=5`, `verified_accounts=5`, and `needs_review=false`.
  AD readback used `localhost`; verification time was
  13:28:01.8534737 UTC.

Request ID throughout approval and live execution:
`fa9bfbdcd86f6032565c2f928df5b5b2187bd57ab694b75f3e4786267c3e9162`.

## Windows audit events in Splunk

The Splunk search used EventCode 4725 on `WIN-3B0FE43Q9UR`.
Its results showed "A user account was disabled" for each target:

| Target | Splunk displayed time (CDT) |
| --- | --- |
| spray.user01 | 2026-09-17 08:28:01.694 |
| spray.user02 | 2026-09-17 08:28:01.728 |
| spray.user03 | 2026-09-17 08:28:01.758 |
| spray.user04 | 2026-09-17 08:28:01.785 |
| spray.user05 | 2026-09-17 08:28:01.814 |

The events show SYSTEM (SID `S-1-5-18`) and the DC machine account
`WIN-3B0FE43Q9UR$` as the account that performed the action. The administrator who
approved the request is recorded separately. `TargetUserName` and `SubjectUserName`
were blank in the table, but the Message field contained those details. The
Splunk check was manual; the responder checked AD automatically.

## Screenshots

These screenshots have not been edited. The Shuffle screenshots cut off part of
the long request ID; the full ID above comes from the saved execution output.

### Before approval

The live responder returned HTTP 202 and reported no account changes before
approval. `dry_run=false` distinguishes this from a preview. Shuffle's outer
`success=true` describes the HTTP action, not completed containment.

![Live request pending local approval](../evidence/2026-09-17/01-pending-approval.png)

### After approval

The response includes the approving operator, reason, and approval time, followed
by five verified accounts. Individual account results are collapsed in this
capture; the separate audit screenshot names all five affected accounts.

![Approved request with five verified accounts](../evidence/2026-09-17/02-approved-response.png)

### Account-disable events

The messages show five account-disable events, their target users, SYSTEM actor,
and timestamps matching the approved response. The screenshot is the results
table; the EventCode 4725 filter was supplied in the search used for this check.

![Five Windows account-disable events in Splunk](../evidence/2026-09-17/03-splunk-audit-4725.png)

## Notes and untested cases

The deployed Shuffle HTTP body was changed to `$exec` after an isolated action
test returned "Missing alert field: detection" with the previous mapping.
A subsequent action test succeeded. The successful approved full workflow run
also contained the unchanged alert. Local approval and explicit resubmission
are manual steps, not a native Shuffle approval/resume interface.

This test covered approval and a successful account response. It did not cover
forged approvals, wrong keys or source IPs, expired approvals, partial failures,
crash recovery, or resending a completed request on the live VMs. There was no
separate `Get-ADUser` output after the action; the saved evidence is the
responder's AD check and the five Windows audit events.

The lab still uses SYSTEM on the DC, internal HTTP, a narrow detection rule, and
a connector that remembers only its last delivered alert. Those limits are
described in the main README.
