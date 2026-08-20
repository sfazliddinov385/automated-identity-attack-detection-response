[CmdletBinding()]
param(
    [string]$TargetServer = "192.168.226.132",
    [string]$Domain = "LAB",
    [string]$UserPrefix = "spray.user",
    [ValidateRange(1, 10)]
    [int]$UserCount = 5,
    [string]$IncorrectPassword = "NotTheCorrectPassword2026",
    [switch]$ConfirmIsolatedLab
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $ConfirmIsolatedLab) {
    throw "Refusing to run. Supply -ConfirmIsolatedLab only in an authorized isolated lab."
}

if ($TargetServer -notmatch '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)') {
    throw "TargetServer must be an RFC1918 private address for this lab script."
}

$Target = "\\$TargetServer\IPC$"

Write-Warning "This script intentionally generates failed authentication events."
Write-Host "Target: $Target"

foreach ($Number in 1..$UserCount) {
    $Username = "{0}{1:D2}" -f $UserPrefix, $Number
    Write-Host "`nTesting $Domain\$Username"

    & cmd.exe /c "net use $Target /delete /y >nul 2>&1"
    Start-Sleep -Seconds 2

    $Arguments = @(
        "use",
        $Target,
        "/user:$Domain\$Username",
        $IncorrectPassword
    )

    Start-Process `
        -FilePath "$env:SystemRoot\System32\net.exe" `
        -ArgumentList $Arguments `
        -Wait `
        -NoNewWindow

    Start-Sleep -Seconds 2
}

& cmd.exe /c "net use $Target /delete /y >nul 2>&1"
Write-Host "`nAll controlled authentication attempts completed."

