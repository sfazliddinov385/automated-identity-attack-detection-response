# Splunk detections

## Data source

The domain controller forwards Windows Security events to Splunk Enterprise.
The lab searches use these values:

```text
index=wineventlog
host=WIN-3B0FE43Q9UR
sourcetype=WinEventLog:Security
```

## Password-spraying detection

[`password-spraying-detection.spl`](password-spraying-detection.spl) groups
Event ID `4625` failed logins by source IP. It looks for failures against at
least five different accounts within a rolling five-minute window.

The username filter matches `spray.user` followed by digits. In this lab, the
test uses `spray.user01` through `spray.user05`; the responder has a separate
allowlist for those exact five accounts. The search returns only the latest
matching result.

To adapt the search to a larger environment, check how its Windows add-on
extracts usernames and replace the test-account filter with suitable account
exclusions. Slow attempts or attempts spread across several source IPs may not
meet this rule's threshold.

## Response audit

[`account-disable-audit.spl`](account-disable-audit.spl) searches for Event ID
`4725`, which records that a user account was disabled. Check the target accounts
and timestamps against the response. This is a manual audit check in Splunk;
the responder checks account state directly in AD automatically.

## Suggested alert settings

- Run every minute
- Search the previous ten minutes
- Trigger when the search returns at least one result
- Suppress duplicate alerts by `source_ip` and `targeted_users`
- Map to MITRE ATT&CK `T1110.003`

In this project, the connector runs the search on a schedule and skips duplicate
results. This avoids relying on Splunk's alert scheduler, so the same approach
also works with Splunk Free.
