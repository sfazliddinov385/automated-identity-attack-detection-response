#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$RequestId,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Reason,
    [ValidateRange(1, 30)][int]$ValidForMinutes = 15,
    [string]$StateRoot = 'C:\SOAR\Response\state'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SOAR-ResponseCore.ps1')
$Saved = Get-Content -LiteralPath (Join-Path $StateRoot "requests/$RequestId.json") -Raw | ConvertFrom-Json
$Request = Get-SOARRequest $Saved.payload
if ($Request.request_id -cne $RequestId) { throw 'Stored request does not match its ID.' }
$Request.payload | Format-List
Write-Host "Reason: $Reason"
Write-Host 'Review the source, affected users, available logon evidence, and business impact before approving.'
$Operator = [Security.Principal.WindowsIdentity]::GetCurrent().Name
if ($PSCmdlet.ShouldProcess(($Request.payload.targeted_users -join ', '), "Approve account disabling for $ValidForMinutes minutes")) {
    New-SOARApproval -StateRoot $StateRoot -RequestId $RequestId -ApprovedBy $Operator -Reason $Reason -ValidForMinutes $ValidForMinutes
    Write-Host 'Approval recorded. Resume the original Shuffle response action with the unchanged alert payload.'
}
