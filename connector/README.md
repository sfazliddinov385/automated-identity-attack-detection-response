# Splunk-to-Shuffle connector

The connector checks Splunk every 60 seconds. When the search finds a match, it
formats the result as JSON and sends it to Shuffle through an authenticated
webhook. It then saves a fingerprint of the alert to avoid sending the same
result again.

`delivery_status: accepted_by_shuffle` means Shuffle accepted the alert. The
connector does not check whether the workflow finished or any accounts changed.
Account changes require approval on DC-01, followed by a manual resend of the
same alert from Shuffle. The responder then checks each account in AD. See the
[approval and verification guide](../docs/approval-and-verification.md).

## Private files

Create the following files under `~/.soar-connector`. Never add them to Git:

```text
splunk.user       Splunk REST username
splunk.password   Splunk REST password
webhook.url       Full Shuffle webhook URL
webhook.key       Value expected by X-SOAR-LAB-KEY
```

Protect the directory and files:

```bash
chmod 700 ~/.soar-connector
chmod 600 ~/.soar-connector/{splunk.user,splunk.password,webhook.url,webhook.key}
```

## Installation

```bash
install -m 700 splunk_to_shuffle.py ~/.soar-connector/splunk_to_shuffle.py
mkdir -p ~/.config/systemd/user
install -m 600 soar-connector.service \
  ~/.config/systemd/user/soar-connector.service
systemctl --user daemon-reload
systemctl --user enable --now soar-connector.service
```

To start the user service at boot without an interactive login:

```bash
sudo loginctl enable-linger "$USER"
```

## Check the search without sending an alert

This searches the previous 24 hours without sending anything to Shuffle:

```bash
~/.soar-connector/splunk_to_shuffle.py \
  --once --check --lookback=-24h
```

## Configuration

The following environment variables are optional:

| Variable | Default |
| --- | --- |
| `SOAR_CONNECTOR_DIR` | `~/.soar-connector` |
| `SOAR_SPLUNK_URL` | Local Splunk export endpoint on port 8089 |
| `SOAR_SPLUNK_INDEX` | `wineventlog` |
| `SOAR_DC_HOST` | `WIN-3B0FE43Q9UR` |
| `SOAR_DOMAIN` | `LAB` |
| `SOAR_VERIFY_TLS` | `false` for the self-signed lab |

Set `SOAR_VERIFY_TLS=true` when a trusted certificate chain is available.

## Duplicate alerts

After Shuffle accepts an alert, the connector writes its fingerprint to
`state.json`. The fingerprint uses the source IP, last event time, and targeted
users. If the next result matches, it logs `Duplicate skipped` and does not send
another webhook.

Only the last fingerprint is stored. This is a basic duplicate check, not a
history of every alert or response. It also will not resend an alert after you
approve a pending request; that step is manual.
