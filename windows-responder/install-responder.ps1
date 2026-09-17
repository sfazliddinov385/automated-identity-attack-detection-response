#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [ValidatePattern('^[0-9.]+$')][string]$SoarHostIP = "192.168.226.134",
    [ValidateRange(1, 65535)][int]$ListenPort = 8081,
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
$ErrorActionPreference = 'Stop'
$SoarHostIP = [Net.IPAddress]::Parse($SoarHostIP).ToString()

if (-not (Test-Path $ResponderSource)) {
    throw "SOAR-AD-Responder.ps1 must be in the same directory as this installer."
}

New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
$ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($ExistingTask) { Stop-ScheduledTask -TaskName $TaskName }
Copy-Item -Path $ResponderSource -Destination $ResponderPath -Force
foreach ($Name in @('SOAR-ResponseCore.ps1', 'Approve-SOARRequest.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $Name) -Destination (Join-Path $InstallDirectory $Name) -Force
}

if (-not (Test-Path $KeyPath)) {
    $Bytes = New-Object byte[] 32
    $Generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    $Generator.GetBytes($Bytes)
    $Generator.Dispose()
    $ResponseKey = -join ($Bytes | ForEach-Object { $_.ToString("x2") })
    [IO.File]::WriteAllText($KeyPath, $ResponseKey)
    Remove-Variable ResponseKey, Bytes
}

$Acl = [Security.AccessControl.DirectorySecurity]::new()
$Acl.SetAccessRuleProtection($true, $false)
$AdminSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
$Acl.SetOwner($AdminSid)
foreach ($SidText in @('S-1-5-18', 'S-1-5-32-544')) {
    $Sid = [Security.Principal.SecurityIdentifier]::new($SidText)
    $Rule = [Security.AccessControl.FileSystemAccessRule]::new(
        $Sid, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')
    $Acl.AddAccessRule($Rule)
}
Set-Acl -LiteralPath $InstallDirectory -AclObject $Acl
# Reset existing child ACLs too, including state left by an older installation.
& icacls (Join-Path $InstallDirectory '*') /reset /T /Q | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not protect all responder files and state.' }
. (Join-Path $InstallDirectory 'SOAR-ResponseCore.ps1')
Initialize-SOARState (Join-Path $InstallDirectory 'state')

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
    "-File", ('"{0}"' -f $ResponderPath),
    "-ListenPrefix", ('"http://+:{0}/"' -f $ListenPort),
    "-AllowedSourceIPs", ('"{0}"' -f $SoarHostIP)
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
Write-Host 'Live response still requires per-request local approval. HTTP callers cannot grant approval.'
Write-Host "Copy the key securely into Shuffle; do not commit it to Git."
