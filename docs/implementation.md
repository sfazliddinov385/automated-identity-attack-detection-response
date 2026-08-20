# Implementation

## 1. Active Directory test identities

Five enabled users were created inside a dedicated OU:

```text
OU=SOAR-Lab-Users,DC=lab,DC=local

spray.user01
spray.user02
spray.user03
spray.user04
spray.user05
```

The dedicated OU provides a hard boundary for automated response actions.

## 2. Windows event collection

The domain controller was configured to audit successful and failed Logon and
Account Logon activity. Its Splunk Universal Forwarder sent the Security,
System, and Application logs to SIEM-01 on TCP 9997.

VICTIM-B also forwarded Windows Security, System, PowerShell, and Sysmon data.

## 3. Detection engineering

The detection query normalizes the lab username from Splunk's multivalue
`Account_Name` extraction. It then uses `streamstats time_window=5m` to count
events and distinct users by `Source_Network_Address`.

The result is enriched with:

```text
detection       Password Spraying Detected
severity        High
MITRE technique T1110.003
status          New
```

## 4. Splunk REST connector

Splunk Free does not provide the same scheduled-alert action workflow as the
licensed edition. A Python connector was therefore implemented to:

- Execute the detection through `/services/search/jobs/export`
- Convert Splunk epoch timestamps to ISO-8601 UTC
- Normalize multivalue fields into JSON arrays
- Send authenticated JSON to Shuffle
- Persist only a non-secret fingerprint after successful delivery
- Poll every 60 seconds as a systemd user service

## 5. Shuffle workflow

Shuffle receives the alert and validates three independent policy conditions.
Only the valid branch reaches the HTTP response action. The inbound webhook and
outbound responder use different secrets.

## 6. Windows responder

The responder runs on DC-01 because Active Directory PowerShell commands must
execute within the domain's administrative boundary. It validates the alert,
checks every requested identity against both an exact allowlist and the lab OU,
then invokes `Disable-ADAccount`.

The public installer generates the response key locally, locks directory ACLs,
adds a source-restricted firewall rule, and creates the startup task.

## 7. Response verification

Two independent checks confirm containment:

1. `Get-ADUser` reports `Enabled=False` for all five users.
2. Splunk receives five Event ID `4725` events from DC-01.

This closes the loop from detection to response and audit evidence.

