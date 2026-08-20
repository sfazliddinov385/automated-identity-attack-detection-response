#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$SoarHostIP = "192.168.226.134",
    [int]$ListenPort = 8081,
    [switch]$EnableLiveResponse
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$InstallDirectory = "C:\SOAR\Response"
$ResponderSource = Join-Path $PSScriptRoot "SOAR-AD-Responder.ps1"
$ResponderPath = Join-Path $InstallDirectory "SOAR-AD-Responder.ps1"
$KeyPath = Join-Path $InstallDirectory "response.key"
$TaskName = "SOAR AD Responder"
$FirewallName = "SOAR AD Responder from SOAR-01"

if (-not (Test-Path $ResponderSource)) {
    throw "SOAR-AD-Responder.ps1 must be in the same directory as this installer."
}

New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
Copy-Item -Path $ResponderSource -Destination $ResponderPath -Force

if (-not (Test-Path $KeyPath)) {
    $Bytes = New-Object byte[] 32
    $Generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    $Generator.GetBytes($Bytes)
    $Generator.Dispose()
    $ResponseKey = -join ($Bytes | ForEach-Object { $_.ToString("x2") })
    [IO.File]::WriteAllText($KeyPath, $ResponseKey)
    Remove-Variable ResponseKey, Bytes
}

& icacls $InstallDirectory /inheritance:r | Out-Null
& icacls $InstallDirectory /grant:r `
    "SYSTEM:(OI)(CI)F" `
    "Administrators:(OI)(CI)F" | Out-Null

Get-NetFirewallRule -DisplayName $FirewallName -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule

New-NetFirewallRule `
    -DisplayName $FirewallName `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalPort $ListenPort `
    -RemoteAddress $SoarHostIP `
    -Profile Any | Out-Null

$Arguments = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", ('"{0}"' -f $ResponderPath)
)

if ($EnableLiveResponse) {
    $Arguments += "-LiveResponse"
}

$Action = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument ($Arguments -join " ")
$Trigger = New-ScheduledTaskTrigger -AtStartup
$Principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $Principal `
    -Settings $Settings `
    -Force | Out-Null

Start-ScheduledTask -TaskName $TaskName

Write-Host "Responder installed at: $ResponderPath"
Write-Host "Response key stored at: $KeyPath"
Write-Host "Allowed SOAR host: $SoarHostIP"
Write-Host "Live response enabled: $EnableLiveResponse"
Write-Host "Copy the key securely into Shuffle; do not commit it to Git."

