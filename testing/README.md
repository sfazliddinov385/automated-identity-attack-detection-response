# Run the lab test

These scripts reproduce the test in an isolated lab you control.

## Generate the test events

Run on VICTIM-B, the Windows test endpoint:

```powershell
.\password-spray-simulation.ps1 `
    -TargetServer "192.168.226.132" `
    -ConfirmIsolatedLab
```

The script requires the confirmation switch and checks that the target has a
private IP address. It tries an incorrect password against the five
`spray.userNN` test accounts. Expect Windows system error `1326` for each attempt.

## Check that the accounts are disabled

For a live test, approve the pending request on DC-01 and resend the same alert
from Shuffle. After the responder reports verified success, run this on DC-01:

```powershell
.\verify-disabled-users.ps1
```

The test passes only when exactly five matching accounts are found and all are
disabled.

## Reset the accounts for another test

Re-enable only the lab OU accounts from Administrator PowerShell:

```powershell
Get-ADUser `
  -SearchBase "OU=SOAR-Lab-Users,DC=lab,DC=local" `
  -Filter 'SamAccountName -like "spray.user*"' |
  Enable-ADAccount
```

Do not run these scripts against production, public, or third-party systems.

