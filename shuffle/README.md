# Shuffle SOAR workflow

The workflow contains four nodes:

1. **Webhook** — receives authenticated JSON from SIEM-01.
2. **Receive Splunk Alert** — makes the normalized alert available to later
   actions.
3. **Validate High-Risk Alert** — permits the response path only when all three
   policy conditions pass.
4. **Disable Compromised Lab Accounts** — posts the validated payload to the
   restricted responder on DC-01.

## Validation conditions

```text
$receive_splunk_alert.severity equals High
$receive_splunk_alert.targeted_accounts larger than 4
$receive_splunk_alert.detection equals Password Spraying Detected
```

## HTTP response action

```text
Method: POST
URL: http://<DC-01>:8081/disable-users
Headers:
  Content-Type: application/json
  X-SOAR-RESPONSE-KEY: <secret stored outside Git>
Body:
  $validate_high-risk_alert
```

The public [`workflow-template.json`](workflow-template.json) is a sanitized
reference rather than a one-click import. Shuffle assigns installation-specific
IDs to webhooks, apps, actions, and authentication objects. Recreate the four
nodes in the UI or sanitize an export from your own installation before use.

Never commit a live webhook URI, webhook authentication header, or response
service key.

