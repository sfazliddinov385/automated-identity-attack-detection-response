# Original implementation

> These notes describe v1, which responded without a separate approval step.
> For the current version, use the [approval and verification guide](approval-and-verification.md).

## 1. Test accounts

Five enabled users were created inside a dedicated OU:

```text
OU=SOAR-Lab-Users,DC=lab,DC=local

spray.user01
spray.user02
spray.user03
spray.user04
spray.user05
```

The responder checks this OU before changing an account. That check is in the
code; it does not limit the permissions of the SYSTEM task running the responder.

## 2. Windows event collection

The domain controller was configured to audit successful and failed Logon and
Account Logon activity. Its Splunk Universal Forwarder sent the Security,
System, and Application logs to SIEM-01 on TCP 9997.

VICTIM-B also forwarded Windows Security, System, PowerShell, and Sysmon data.

## 3. Splunk detection

The query selects the lab username from Splunk's multivalue `Account_Name`
field. It then uses `streamstats time_window=5m` to count failed logins and
different users for each `Source_Network_Address`.

The query adds these fields to each matching result:

```text
detection       Password Spraying Detected
severity        High
MITRE technique T1110.003
status          New
```

## 4. Splunk REST connector

The lab's Splunk Free setup could not run scheduled alert actions. A Python
connector handled the search and delivery instead:

- Execute the detection through `/services/search/jobs/export`
- Convert Splunk epoch timestamps to ISO-8601 UTC
- Normalize multivalue fields into JSON arrays
- Send authenticated JSON to Shuffle
- Persist only a non-secret fingerprint after successful delivery
- Poll every 60 seconds as a systemd user service

## 5. Shuffle workflow

Shuffle checks the alert's detection name, severity, and account count. All
three conditions must pass before the HTTP response action runs. The webhook
and responder use different keys.

## 6. Windows responder

The original lab ran the responder on DC-01 for convenience. AD commands can
also run from a separate management host if it has the required connectivity
and delegated permissions. The original responder checked the alert, checked
every account against the allowed usernames and lab OU, then called
`Disable-ADAccount`.

The installer generated a local response key, restricted directory permissions,
added a firewall rule for SOAR-01's source IP, and created the startup task.

## 7. Response verification

Two separate checks confirmed the account changes:

1. `Get-ADUser` reports `Enabled=False` for all five users.
2. Splunk receives five Event ID `4725` events from DC-01.

These checks showed both the resulting account state and the Windows record
of each disable action.
