[CmdletBinding()]
param(
    [switch]$LiveResponse,
    [string]$ListenPrefix = "http://+:8081/",
    [string]$KeyPath = "C:\SOAR\Response\response.key",
    [string]$LogPath = "C:\SOAR\Response\response.log",
    [string[]]$AllowedSourceIPs = @("192.168.226.134")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module ActiveDirectory

$DryRun = -not $LiveResponse
$AllowedOu = "OU=SOAR-Lab-Users,DC=lab,DC=local"
$AllowedUsers = @(
    "spray.user01",
    "spray.user02",
    "spray.user03",
    "spray.user04",
    "spray.user05"
)

function Write-JsonResponse {
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerResponse]$Response,

        [Parameter(Mandatory)]
        [int]$StatusCode,

        [Parameter(Mandatory)]
        [hashtable]$Body
    )

    $Json = $Body | ConvertTo-Json -Depth 8 -Compress
    $Bytes = [Text.Encoding]::UTF8.GetBytes($Json)

    $Response.StatusCode = $StatusCode
    $Response.ContentType = "application/json"
    $Response.ContentEncoding = [Text.Encoding]::UTF8
    $Response.ContentLength64 = $Bytes.Length
    $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
    $Response.OutputStream.Close()
}

function Write-AuditRecord {
    param([Parameter(Mandatory)]$Record)

    $Directory = Split-Path -Parent $LogPath
    if (-not (Test-Path $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    $Record |
        ConvertTo-Json -Depth 8 -Compress |
        Add-Content -Path $LogPath -Encoding UTF8
}

if (-not (Test-Path $KeyPath)) {
    throw "Response key was not found at $KeyPath"
}

$ExpectedKey = (Get-Content -Raw $KeyPath).Trim()
if ($ExpectedKey.Length -lt 32) {
    throw "Response key is missing or too short."
}

$Listener = [System.Net.HttpListener]::new()
$Listener.Prefixes.Add($ListenPrefix)
$Listener.Start()

Write-Host "SOAR AD responder listening on $ListenPrefix"
Write-Host "Dry-run mode: $DryRun"

try {
    while ($Listener.IsListening) {
        $Context = $Listener.GetContext()
        $Request = $Context.Request
        $Response = $Context.Response
        $RemoteAddress = $Request.RemoteEndPoint.Address

        if ($RemoteAddress.IsIPv4MappedToIPv6) {
            $RemoteAddress = $RemoteAddress.MapToIPv4()
        }

        $RemoteIP = $RemoteAddress.ToString()

        try {
            if ($AllowedSourceIPs -notcontains $RemoteIP) {
                Write-JsonResponse -Response $Response -StatusCode 403 -Body @{
                    success = $false
                    reason  = "Source address is not authorized."
                }
                continue
            }

            if ($Request.HttpMethod -ne "POST" -or
                $Request.Url.AbsolutePath -ne "/disable-users") {
                Write-JsonResponse -Response $Response -StatusCode 404 -Body @{
                    success = $false
                    reason  = "Endpoint not found."
                }
                continue
            }

            if ($Request.ContentLength64 -gt 65536) {
                Write-JsonResponse -Response $Response -StatusCode 413 -Body @{
                    success = $false
                    reason  = "Request body is too large."
                }
                continue
            }

            $ProvidedKey = $Request.Headers["X-SOAR-RESPONSE-KEY"]
            if ([string]::IsNullOrWhiteSpace($ProvidedKey) -or
                $ProvidedKey -cne $ExpectedKey) {
                Write-JsonResponse -Response $Response -StatusCode 401 -Body @{
                    success = $false
                    reason  = "Authentication failed."
                }
                continue
            }

            $Reader = [IO.StreamReader]::new(
                $Request.InputStream,
                $Request.ContentEncoding
            )
            $Payload = $Reader.ReadToEnd() | ConvertFrom-Json
            $Reader.Close()

            if ($Payload.detection -ne "Password Spraying Detected" -or
                $Payload.severity -ne "High" -or
                [int]$Payload.targeted_accounts -lt 5) {
                Write-JsonResponse -Response $Response -StatusCode 400 -Body @{
                    success = $false
                    reason  = "Alert did not satisfy response policy."
                }
                continue
            }

            $RequestedUsers = @($Payload.targeted_users | Select-Object -Unique)

            if ($RequestedUsers.Count -lt 5 -or
                $RequestedUsers.Count -ne [int]$Payload.targeted_accounts) {
                Write-JsonResponse -Response $Response -StatusCode 400 -Body @{
                    success = $false
                    reason  = "Unique user count did not match the alert count."
                }
                continue
            }

            $Results = foreach ($Username in $RequestedUsers) {
                if ($AllowedUsers -notcontains [string]$Username) {
                    [PSCustomObject]@{
                        user    = [string]$Username
                        success = $false
                        action  = "RejectedNotAllowlisted"
                    }
                    continue
                }

                try {
                    $AdUser = Get-ADUser -Identity $Username -Properties Enabled
                    $RequiredSuffix = ",$AllowedOu"

                    if (-not $AdUser.DistinguishedName.EndsWith(
                            $RequiredSuffix,
                            [StringComparison]::OrdinalIgnoreCase
                        )) {
                        throw "Account is outside the authorized lab OU."
                    }

                    if (-not $AdUser.Enabled) {
                        $Action = "AlreadyDisabled"
                    }
                    elseif ($DryRun) {
                        $Action = "WouldDisable"
                    }
                    else {
                        Disable-ADAccount -Identity $AdUser -Confirm:$false
                        $Action = "Disabled"
                    }

                    [PSCustomObject]@{
                        user    = $AdUser.SamAccountName
                        success = $true
                        action  = $Action
                    }
                }
                catch {
                    [PSCustomObject]@{
                        user    = [string]$Username
                        success = $false
                        action  = "Error"
                        reason  = $_.Exception.Message
                    }
                }
            }

            $ResponseBody = @{
                success            = $true
                dry_run            = $DryRun
                detection          = [string]$Payload.detection
                source_ip          = [string]$Payload.source_ip
                requested_accounts = $RequestedUsers.Count
                results            = @($Results)
                timestamp_utc      = (Get-Date).ToUniversalTime().ToString("o")
            }

            Write-AuditRecord -Record ([PSCustomObject]@{
                timestamp_utc = $ResponseBody.timestamp_utc
                remote_ip     = $RemoteIP
                dry_run       = $DryRun
                detection     = $ResponseBody.detection
                source_ip     = $ResponseBody.source_ip
                results       = @($Results)
            })

            Write-JsonResponse -Response $Response -StatusCode 200 -Body $ResponseBody
        }
        catch {
            Write-AuditRecord -Record ([PSCustomObject]@{
                timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
                remote_ip     = $RemoteIP
                success       = $false
                error         = $_.Exception.Message
            })

            if ($Response.OutputStream.CanWrite) {
                Write-JsonResponse -Response $Response -StatusCode 500 -Body @{
                    success = $false
                    reason  = "Response processing failed."
                }
            }
        }
    }
}
finally {
    $Listener.Stop()
    $Listener.Close()
}
