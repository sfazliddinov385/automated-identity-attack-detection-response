[CmdletBinding()]
param(
    [string]$SearchBase = "OU=SOAR-Lab-Users,DC=lab,DC=local"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module ActiveDirectory

$Users = Get-ADUser `
    -SearchBase $SearchBase `
    -Filter 'SamAccountName -like "spray.user*"' `
    -Properties Enabled |
    Sort-Object SamAccountName |
    Select-Object SamAccountName, Enabled

$Users | Format-Table -AutoSize

if (($Users | Where-Object Enabled).Count -eq 0 -and $Users.Count -eq 5) {
    Write-Host "Verification passed: all five lab accounts are disabled."
    exit 0
}

Write-Error "Verification failed: expected five disabled lab accounts."
exit 1

