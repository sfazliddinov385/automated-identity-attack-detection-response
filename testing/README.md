# Controlled testing

These scripts exist only to reproduce the project inside an authorized,
isolated lab.

## Generate the test events

Run on the designated Windows test endpoint:

```powershell
.\password-spray-simulation.ps1 `
    -TargetServer "192.168.226.132" `
    -ConfirmIsolatedLab
```

The required confirmation switch and private-address check are intentional
safety controls. The script uses an incorrect password against the five
purpose-built `spray.userNN` accounts. Expected output is Windows system error
`1326` for each attempt.

## Validate containment

Run on the domain controller after the Shuffle workflow completes:

```powershell
.\verify-disabled-users.ps1
```

The test passes only when exactly five matching accounts are found and all are
disabled.

## Reset for another controlled test

Re-enable only the lab OU accounts from Administrator PowerShell:

```powershell
Get-ADUser `
  -SearchBase "OU=SOAR-Lab-Users,DC=lab,DC=local" `
  -Filter 'SamAccountName -like "spray.user*"' |
  Enable-ADAccount
```

Do not run these scripts against production, public, or third-party systems.

