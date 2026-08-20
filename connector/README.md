# Splunk-to-Shuffle connector

The connector polls the local Splunk REST API every 60 seconds, normalizes a
matching detection into JSON, sends it to an authenticated Shuffle webhook, and
records a fingerprint after successful delivery.

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

## Safe validation

This checks historical data without notifying Shuffle:

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

## Deduplication

After a successful webhook delivery, the connector writes a fingerprint to
`state.json`. The fingerprint combines the source IP, last event time, and
targeted users. Matching results are logged as `Duplicate skipped` and do not
trigger another containment action.

