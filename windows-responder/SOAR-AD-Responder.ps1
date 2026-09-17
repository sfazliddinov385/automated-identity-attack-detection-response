[CmdletBinding()]
param(
    [switch]$LiveResponse,
    [string]$ListenPrefix = 'http://+:8081/',
    [string]$KeyPath = 'C:\SOAR\Response\response.key',
    [string]$LogPath = 'C:\SOAR\Response\response.log',
    [string]$StateRoot = 'C:\SOAR\Response\state',
    [string]$DirectoryServer = 'localhost',
    [string[]]$AllowedSourceIPs = @('192.168.226.134')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
. (Join-Path $PSScriptRoot 'SOAR-ResponseCore.ps1')

function Write-JsonResponse {
    param([Net.HttpListenerResponse]$Response, [int]$StatusCode, [hashtable]$Body)
    $Bytes = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 12 -Compress))
    $Response.StatusCode = $StatusCode
    $Response.ContentType = 'application/json'
    $Response.ContentEncoding = [Text.Encoding]::UTF8
    $Response.ContentLength64 = $Bytes.Length
    $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
    $Response.OutputStream.Close()
}

function Read-AlertBody {
    param([Net.HttpListenerRequest]$Request)
    # Enforce the actual byte count, including requests without Content-Length.
    $Buffer = New-Object byte[] 4096
    $Stream = [IO.MemoryStream]::new()
    try {
        while (($Read = $Request.InputStream.Read($Buffer, 0, $Buffer.Length)) -gt 0) {
            if (($Stream.Length + $Read) -gt 65536) { throw [IO.InvalidDataException]::new('Request body exceeds 64 KiB.') }
            $Stream.Write($Buffer, 0, $Read)
        }
        [Text.Encoding]::UTF8.GetString($Stream.ToArray()) | ConvertFrom-Json -ErrorAction Stop
    }
    finally { $Stream.Dispose() }
}

$ExpectedKey = (Get-Content -LiteralPath $KeyPath -Raw).Trim()
if ($ExpectedKey.Length -lt 32) { throw 'Response key is missing or too short.' }
Initialize-SOARState $StateRoot
$Listener = [Net.HttpListener]::new()
$Listener.Prefixes.Add($ListenPrefix)
$Listener.Start()
Write-Host "SOAR responder listening on $ListenPrefix; dry run: $(-not $LiveResponse)"
Write-Host 'Live requests require local approval and automatic AD state verification.'

try {
    while ($Listener.IsListening) {
        $Context = $Listener.GetContext()
        $Request = $Context.Request
        $RemoteAddress = $Request.RemoteEndPoint.Address
        if ($RemoteAddress.IsIPv4MappedToIPv6) { $RemoteAddress = $RemoteAddress.MapToIPv4() }
        $RemoteIP = $RemoteAddress.ToString()
        $Reply = $null
        try {
            if ($AllowedSourceIPs -notcontains $RemoteIP) {
                $Reply = New-SOARReply 403 @{ success = $false; status = 'rejected'; reason = 'Unauthorized source address.' }
            }
            elseif ($Request.HttpMethod -ne 'POST' -or $Request.Url.AbsolutePath -cne '/disable-users') {
                $Reply = New-SOARReply 404 @{ success = $false; status = 'rejected'; reason = 'Endpoint not found.' }
            }
            elseif ($Request.ContentLength64 -gt 65536) {
                $Reply = New-SOARReply 413 @{ success = $false; status = 'rejected'; reason = 'Request body exceeds 64 KiB.' }
            }
            elseif ([string]::IsNullOrWhiteSpace($Request.Headers['X-SOAR-RESPONSE-KEY']) -or
                $Request.Headers['X-SOAR-RESPONSE-KEY'] -cne $ExpectedKey) {
                $Reply = New-SOARReply 401 @{ success = $false; status = 'rejected'; reason = 'Authentication failed.' }
            }
            else {
                $Payload = Read-AlertBody $Request
                $Reply = Invoke-SOARResponse -Payload $Payload -StateRoot $StateRoot -DryRun (-not $LiveResponse) -DirectoryServer $DirectoryServer
            }
        }
        catch [IO.InvalidDataException] {
            $Reply = New-SOARReply 413 @{ success = $false; status = 'rejected'; reason = 'Request body exceeds 64 KiB.' }
        }
        catch [ArgumentException] {
            $Reply = New-SOARReply 400 @{ success = $false; status = 'rejected'; reason = 'Invalid request body.' }
        }
        catch {
            $Reply = New-SOARReply 500 @{ success = $false; status = 'requires_review'; reason = 'Response processing failed. Inspect protected state and audit logs.' }
        }
        try {
            # Log every HTTP outcome, including rejected requests. Never log keys or raw payloads.
            $Audit = @{
                timestamp_utc = [DateTimeOffset]::UtcNow.ToString('o'); remote_ip = $RemoteIP
                http_status = $Reply.StatusCode; response = $Reply.Body
            }
            $Audit | ConvertTo-Json -Depth 12 -Compress | Add-Content -LiteralPath $LogPath -Encoding UTF8
            Write-JsonResponse -Response $Context.Response -StatusCode $Reply.StatusCode -Body $Reply.Body
        }
        catch {
            # State is durable before verified success is returned. Do not repeat side effects.
            try { $Context.Response.Abort() } catch { }
            Write-Warning 'Could not write response or audit log. Inspect state and file permissions.'
        }
    }
}
finally { $Listener.Stop(); $Listener.Close() }
