# Restricted Active Directory responder

The responder is a small Windows HTTP service that accepts an authenticated
JSON alert from Shuffle and disables only the five purpose-built lab accounts.

## Safety model

The public script starts in **dry-run mode** unless the `-LiveResponse` switch
is explicitly supplied. It also enforces:

- Source address allowlist for SOAR-01
- `X-SOAR-RESPONSE-KEY` authentication header
- Maximum 64 KiB request body
- Exact `POST /disable-users` endpoint
- Detection type, severity, and account-count checks
- Exact username allowlist
- Required Active Directory OU boundary
- Local JSON-line audit logging

## Install in dry-run mode

Run in Administrator PowerShell on the domain controller:

```powershell
.\install-responder.ps1 -SoarHostIP "192.168.226.134"
```

## Enable live response

Only after validating dry-run output in an isolated lab:

```powershell
.\install-responder.ps1 `
    -SoarHostIP "192.168.226.134" `
    -EnableLiveResponse
```

The scheduled task runs as `SYSTEM` at startup. The secret is generated at:

```text
C:\SOAR\Response\response.key
```

Copy its value securely into the Shuffle HTTP action as:

```text
X-SOAR-RESPONSE-KEY: <value>
```

Never upload the value to GitHub.

## Expected request

```json
{
  "detection": "Password Spraying Detected",
  "severity": "High",
  "source_ip": "192.168.226.133",
  "targeted_accounts": 5,
  "targeted_users": [
    "spray.user01",
    "spray.user02",
    "spray.user03",
    "spray.user04",
    "spray.user05"
  ]
}
```

## Verification

```powershell
Get-ScheduledTask -TaskName "SOAR AD Responder"
Get-NetTCPConnection -LocalPort 8081 -State Listen
Get-Content "C:\SOAR\Response\response.log" -Tail 10
```

