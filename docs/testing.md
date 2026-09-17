# Testing the lab

## Automated tests

The PowerShell tests simulate the results of `Get-ADUser` and `Disable-ADAccount`. They do not start the HTTP service, connect to AD, or change real accounts. They also check the scripts for syntax errors.

Run them with:

```powershell
./tests/response-tests.ps1
```

The connector tests use simulated API responses and temporary files:

```bash
python3 -m unittest discover -s tests -p 'test_*.py'
```

GitHub Actions runs the response tests in Windows PowerShell 5.1 and PowerShell 7. It runs the connector tests on Linux. Results are available in the repository's Actions tab and the pull request checks.

The tests check how the responder handles:

- Missing, forged, expired, or invalid approvals.
- Changes to the alert details.
- Incorrect usernames and accounts outside the allowed OU.
- Dry runs and successful account changes.
- Failed commands, accounts that remain enabled, and failed AD reads.
- Repeated requests and interrupted work.

## Checks on the VMs

The [September 17 test record](validation-2026-09-17.md) documents the checks completed in the lab. The checklist below also includes tests that still need to be run on the VMs. Record the result of each test as it is completed.

1. Install the responder in dry-run mode on the isolated lab DC. Check the listener, firewall restriction, scheduled task arguments, and permissions on the scripts and saved files.
2. Send requests with a wrong key and from an unapproved source host. Confirm both are rejected and logged.
3. Send a valid alert in dry-run mode. Confirm no accounts change and the response contains `success=false, status=dry_run, verified=false`.
4. Enable live mode and run the controlled five-account test. Confirm the first response is HTTP 202 and all five accounts remain enabled.
5. Add `approved=true` to the alert. Confirm it does not approve the request.
6. Review and approve the request on DC-01, including a reason. Resend the unchanged original alert from Shuffle.
7. Check the individual account results. Confirm `status=verified`, five verified accounts, the approval identity, reason and time, and `verified_at`.
8. Check the accounts directly in AD, then check Event ID 4725 in Splunk. Match the usernames, the account that made the changes, and the timestamps. Accounts that were already disabled will not generate a new disable event.
9. Send the completed request again. Confirm it returns the saved result marked as cached, with no additional account changes.
10. Test an expired approval and a controlled failure when changing or checking an account. Confirm neither is reported as a successful response.
11. Check that Shuffle keeps the response details when an account change fails and does not automatically retry the changes.

The responder checks account state directly in AD. It does not check whether Splunk received the audit events.

The automated tests check the script logic. They do not prove that Windows permissions, firewall rules, real AD changes, or the Shuffle connection work correctly. Those need to be checked on the VMs.

## Earlier test

The original lab test recorded five failed logins, one delivered detection, skipped duplicate alerts, five disabled test accounts, and five Event ID 4725 records.

The seven original screenshots directly under `evidence/` show that run. Screenshots of the updated approval process are under `evidence/2026-09-17/`.

Use the dated screenshots when explaining the current version. The original screenshots were taken before the approval step and automatic AD checks were added.
