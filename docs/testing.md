# Testing and results

## Test objective

Validate that five failed authentication attempts against five distinct lab
accounts trigger exactly one automated containment workflow.

## Preconditions

- All hosts are on the isolated `192.168.226.0/24` VMware network.
- `spray.user01` through `spray.user05` are enabled.
- Splunk is receiving Event ID `4625` data from DC-01.
- The connector service is active.
- The Shuffle webhook is running.
- The Windows responder is listening on port 8081.
- Dry-run testing has passed before live response is enabled.

## Procedure

1. Run the controlled simulation from VICTIM-B.
2. Confirm Windows error `1326` for each intentionally incorrect password.
3. Wait for the connector's next 60-second polling cycle.
4. Confirm one alert is sent to Shuffle.
5. Confirm later polling cycles log `Duplicate skipped`.
6. Open the Shuffle run and verify the response node returns HTTP `200`.
7. Verify all five AD accounts show `Enabled=False`.
8. Search Splunk for Event ID `4725`.

## Observed result

| Check | Result |
| --- | --- |
| Five distinct target accounts detected | Pass |
| Severity set to High | Pass |
| MITRE mapping set to T1110.003 | Pass |
| Connector delivered alert automatically | Pass |
| Duplicate executions suppressed | Pass |
| Shuffle validation branch passed | Pass |
| Responder authentication passed | Pass |
| Live response returned HTTP 200 | Pass |
| Five lab users disabled | Pass |
| Five Event ID 4725 events indexed | Pass |

## Final execution timeline

```text
13:16 local  Failed-logon sequence completed
13:17 local  Connector sent alert to Shuffle
13:17 local  Shuffle invoked the response service
13:17 local  Responder disabled the five lab accounts
13:18+       Connector suppressed repeated matching results
```

## Expected negative tests

The responder should reject:

- Missing or incorrect authentication header (`401`)
- Request from an unapproved source (`403`)
- Incorrect method or path (`404`)
- Oversized request (`413`)
- Detection name other than `Password Spraying Detected` (`400`)
- Severity other than `High` (`400`)
- Fewer than five targeted accounts (`400`)
- Username outside the exact allowlist
- Allowlisted name moved outside the authorized OU

