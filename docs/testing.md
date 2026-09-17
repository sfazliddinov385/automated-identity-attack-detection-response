# Testing the lab

## Automated tests

The PowerShell tests use simulated `Get-ADUser` and `Disable-ADAccount` results.
They do not start the HTTP service, connect to AD, or change real accounts. They
also check the PowerShell scripts for syntax errors.

```powershell
./tests/response-tests.ps1
```

The connector tests use simulated API results and temporary files:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

GitHub Actions runs the response suite in Windows PowerShell 5.1 and PowerShell
7, and the connector suite on Linux. Test results are visible on the branch/PR.

The tests cover missing or forged approvals, changed alert details, expired or
invalid approvals, users outside the allowed OU, and incorrect usernames. They
also cover dry runs, successful AD checks, failed commands, accounts that remain
enabled, failed AD reads, repeated requests, and interrupted actions.

## Checks on the VMs

The [September 17 test record](validation-2026-09-17.md) shows which steps were
completed. The list below also includes checks that have not been run on the VMs.
Keep the results of each additional test.

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

## Earlier test

The earlier direct-response lab recorded five failed logons, one delivered
detection, duplicate suppression, five disabled lab accounts, and five 4725
events. The seven original screenshots directly under `evidence/` document that
original run. The new approval-flow captures are under `evidence/2026-09-17/`.

Use the dated screenshots when describing the updated response. The original
screenshots show the earlier version, before approval and automatic AD checks.

