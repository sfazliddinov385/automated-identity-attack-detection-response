# Testing and validation

## Current revision: automated tests

The PowerShell suite supplies fake Get-ADUser and Disable-ADAccount functions.
It imports neither ActiveDirectory nor the HTTP service, and never contacts a
domain controller or changes real accounts. It also parses every PowerShell
script to catch syntax errors.

```powershell
./tests/response-tests.ps1
```

The connector suite uses fake API results and temporary local state:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

GitHub Actions runs the response suite in Windows PowerShell 5.1 and PowerShell
7, and the connector suite on Linux. Test results are visible on the branch/PR.

Covered cases include unapproved and forged-approval requests, changed source
or event time, expired/malformed approvals, a user leaving the OU, invalid user
sets, dry-run behavior, successful readback, failed commands, unchanged accounts,
unavailable readback, repeated requests, and interrupted execution.

## VM integration checklist — core flow demonstrated, full checklist incomplete

See [the 2026-09-17 validation record](validation-2026-09-17.md) for observed
results. This list remains the broader checklist, not a claim that every item
passed in the live lab. Record evidence for each additional check.

1. Install in dry-run mode on the isolated lab DC. Verify the listener, firewall
   restriction, task arguments, and protected file/state ACLs.
2. Confirm wrong keys and unapproved source hosts are rejected and audited.
3. Submit a valid alert in dry-run mode. Verify no AD account changes and
   `success=false, status=dry_run, verified=false`.
4. Enable live mode and generate the controlled five-account test. Confirm the
   initial HTTP 202 and verify all five accounts are still enabled.
5. Try caller-supplied `approved=true`; confirm it grants no approval.
6. Review the pending request locally, record a reason, and resume its unchanged
   alert from Shuffle.
7. Confirm all individual results, `status=verified`, five verified accounts,
   approval identity/reason/time, and `verified_at`.
8. Independently check AD state and corresponding 4725 events in Splunk. Match
   target users, actor, and timestamps. Already-disabled accounts do not create
   new disable events.
9. Repeat the completed request. Confirm a cached historical result and no
   additional account changes.
10. Exercise an expired approval and a controlled readback/action failure. Verify
    neither is presented as successful containment.
11. Verify the Shuffle error path preserves partial-failure responses and does
    not retry them automatically.

The responder directly verifies AD state. It does not automatically verify
Splunk ingestion of the audit events. Unit tests do not establish Windows ACL,
firewall, real AD, or Shuffle integration behavior.

## Original v1 test: historical evidence

The earlier direct-response lab recorded five failed logons, one delivered
detection, duplicate suppression, five disabled lab accounts, and five 4725
events. The screenshots under `evidence/` document that original run.

Those screenshots do not prove the new approval flow or its verification code
was executed. Keep original results and new validation evidence clearly labeled.

