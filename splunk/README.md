# Splunk detections

## Data source

The lab uses Windows Security events forwarded from the domain controller to
Splunk Enterprise. The working source configuration was:

```text
index=wineventlog
host=WIN-3B0FE43Q9UR
sourcetype=WinEventLog:Security
```

## Password-spraying detection

[`password-spraying-detection.spl`](password-spraying-detection.spl) correlates
Event ID `4625` failures by source IP inside a rolling five-minute window. The
lab threshold is five distinct accounts.

The `spray.userNN` expression deliberately scopes the public rule to the five
purpose-built test accounts. For a production rule, normalize the target-user
field for the deployed Windows add-on and replace this expression with the
organization's account exclusions and service-account suppression logic.

## Response audit

[`account-disable-audit.spl`](account-disable-audit.spl) searches for Event ID
`4725`, which records that a user account was disabled. It provides independent
verification that the SOAR response reached Active Directory.

## Suggested alert settings

- Run every minute
- Search the previous ten minutes
- Trigger when the search returns at least one result
- Suppress duplicate alerts by `source_ip` and `targeted_users`
- Map to MITRE ATT&CK `T1110.003`

The project connector performs the scheduling and duplicate suppression outside
Splunk so that it also works with Splunk Free lab licensing.

