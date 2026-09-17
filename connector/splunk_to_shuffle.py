#!/usr/bin/env python3


from __future__ import annotations

from pathlib import Path
from datetime import datetime, timezone
import argparse
import base64
import hashlib
import json
import os
import ssl
import time
import urllib.error
import urllib.parse
import urllib.request


FOLDER = Path(
    os.environ.get("SOAR_CONNECTOR_DIR", Path.home() / ".soar-connector")
).expanduser()
STATE_FILE = FOLDER / "state.json"
LOG_FILE = FOLDER / "connector.log"
SPLUNK_URL = os.environ.get(
    "SOAR_SPLUNK_URL",
    "https://127.0.0.1:8089/services/search/jobs/export",
)
SPLUNK_INDEX = os.environ.get("SOAR_SPLUNK_INDEX", "wineventlog")
DC_HOST = os.environ.get("SOAR_DC_HOST", "WIN-3B0FE43Q9UR")
DOMAIN = os.environ.get("SOAR_DOMAIN", "LAB")
VERIFY_TLS = os.environ.get("SOAR_VERIFY_TLS", "false").lower() == "true"


def read_file(name: str) -> str:
    """Read a required value from the private connector directory."""
    path = FOLDER / name
    value = path.read_text(encoding="utf-8").strip()
    if not value:
        raise RuntimeError(f"Required connector file is empty: {path}")
    return value


def log(message: str) -> None:
    """Write a UTC timestamped message to stdout and the connector log."""
    timestamp = datetime.now(timezone.utc).isoformat()
    line = f"{timestamp} {message}"
    print(line, flush=True)
    FOLDER.mkdir(mode=0o700, parents=True, exist_ok=True)
    with LOG_FILE.open("a", encoding="utf-8") as logfile:
        logfile.write(line + "\n")


def tls_context() -> ssl.SSLContext:
    """Use verified TLS in production; allow self-signed TLS in this lab."""
    if VERIFY_TLS:
        return ssl.create_default_context()
    return ssl._create_unverified_context()  # noqa: SLF001 - lab only


def build_search(lookback: str) -> str:
    """Return the SPL used by the validated lab detection."""
    return rf'''
search index={SPLUNK_INDEX} host="{DC_HOST}"
sourcetype="WinEventLog:Security" EventCode=4625 earliest={lookback} latest=now
| eval target_user=mvindex(
    mvfilter(match(Account_Name,"^spray\.user[0-9]+$")),0)
| where isnotnull(target_user)
| sort 0 _time
| streamstats time_window=5m
    count as failed_attempts
    dc(target_user) as targeted_accounts
    values(target_user) as targeted_users
    values(Workstation_Name) as source_hosts
    min(_time) as first_seen
    max(_time) as last_seen
    by Source_Network_Address
| where targeted_accounts >= 5
| sort 0 - last_seen
| head 1
| eval detection="Password Spraying Detected",
       severity="High",
       mitre_technique="T1110.003",
       status="New"
| rename Source_Network_Address as source_ip
| table detection severity first_seen last_seen source_ip
        source_hosts targeted_accounts failed_attempts
        targeted_users mitre_technique status
'''


def search_splunk(lookback: str) -> dict | None:
    """Execute the detection through Splunk's streaming export endpoint."""
    username = read_file("splunk.user")
    password = read_file("splunk.password")
    credentials = base64.b64encode(f"{username}:{password}".encode()).decode()

    body = urllib.parse.urlencode(
        {"search": build_search(lookback), "output_mode": "json"}
    ).encode()
    request = urllib.request.Request(
        SPLUNK_URL,
        data=body,
        headers={
            "Authorization": f"Basic {credentials}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )

    with urllib.request.urlopen(
        request, context=tls_context(), timeout=60
    ) as response:
        for line in response:
            record = json.loads(line)
            if record.get("result"):
                return record["result"]
    return None


def make_list(value: object) -> list[str]:
    """Normalize Splunk scalar or multivalue results to a string list."""
    if isinstance(value, list):
        return [str(item) for item in value]
    if not value:
        return []
    return [item.strip() for item in str(value).split(",") if item.strip()]


def iso_time(epoch: object) -> str:
    """Convert a Splunk epoch value to an ISO-8601 UTC timestamp."""
    return datetime.fromtimestamp(float(str(epoch)), timezone.utc).isoformat()


def build_payload(result: dict) -> dict:
    """Build the normalized alert contract consumed by the Shuffle workflow."""
    source_hosts = make_list(result.get("source_hosts"))
    targeted_users = make_list(result.get("targeted_users"))
    return {
        "detection": result["detection"],
        "severity": result["severity"],
        "event_time": iso_time(result["last_seen"]),
        "first_seen": iso_time(result["first_seen"]),
        "source_ip": result["source_ip"],
        "source_host": source_hosts[0] if source_hosts else "Unknown",
        "domain": DOMAIN,
        "targeted_accounts": int(result["targeted_accounts"]),
        "failed_attempts": int(result["failed_attempts"]),
        "targeted_users": targeted_users,
        "mitre_technique": result["mitre_technique"],
        "status": result["status"],
    }


def fingerprint(payload: dict) -> str:
    """Create a stable identity for one source/time/account combination."""
    important_fields = {
        "source_ip": payload["source_ip"],
        "event_time": payload["event_time"],
        "targeted_users": payload["targeted_users"],
    }
    encoded = json.dumps(important_fields, sort_keys=True).encode()
    return hashlib.sha256(encoded).hexdigest()


def previously_sent(current_fingerprint: str) -> bool:
    """Return true when the last successful delivery has the same identity."""
    if not STATE_FILE.exists():
        return False
    try:
        state = json.loads(STATE_FILE.read_text(encoding="utf-8"))
        return state.get("last_fingerprint") == current_fingerprint
    except (json.JSONDecodeError, OSError):
        return False


def save_state(current_fingerprint: str, execution_id: str) -> None:
    """Record a successful delivery without storing credentials or payloads."""
    state = {
        "last_fingerprint": current_fingerprint,
        "execution_id": execution_id,
        "delivery_status": "accepted_by_shuffle",
        "sent_at": datetime.now(timezone.utc).isoformat(),
    }
    STATE_FILE.write_text(json.dumps(state, indent=2), encoding="utf-8")
    STATE_FILE.chmod(0o600)


def send_to_shuffle(payload: dict) -> tuple[int, dict]:
    """Send one authenticated JSON alert to the private Shuffle webhook."""
    webhook_url = read_file("webhook.url")
    webhook_key = read_file("webhook.key")
    request = urllib.request.Request(
        webhook_url,
        data=json.dumps(payload).encode(),
        headers={
            "Content-Type": "application/json",
            "X-SOAR-LAB-KEY": webhook_key,
        },
        method="POST",
    )
    with urllib.request.urlopen(
        request, context=tls_context(), timeout=30
    ) as response:
        return response.status, json.loads(response.read().decode())


def run_once(lookback: str, check_only: bool = False) -> None:
    """Perform one detection, deduplication, and optional delivery cycle."""
    result = search_splunk(lookback)
    if not result:
        log(f"No password-spraying detection found for {lookback}.")
        return

    payload = build_payload(result)
    log("Password-spraying detection found.")
    if check_only:
        print(json.dumps(payload, indent=2))
        log("Check-only mode: nothing sent to Shuffle.")
        return

    current_fingerprint = fingerprint(payload)
    if previously_sent(current_fingerprint):
        log("Detection already sent. Duplicate skipped.")
        return

    status, response = send_to_shuffle(payload)
    if status != 200 or not response.get("success"):
        raise RuntimeError(f"Shuffle rejected the alert: HTTP {status}")

    execution_id = str(response.get("execution_id", "unknown"))
    save_state(current_fingerprint, execution_id)
    log(f"Alert accepted by Shuffle. Execution ID: {execution_id}. "
        "Account response requires operator approval and a verified responder result.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--lookback", default="-10m")
    parser.add_argument("--interval", type=int, default=60)
    args = parser.parse_args()

    while True:
        try:
            run_once(args.lookback, args.check)
        except urllib.error.HTTPError as error:
            log(f"HTTP error {error.code}; request was rejected.")
        except Exception as error:  # keep a long-running lab service alive
            log(f"Connector error: {error}")

        if args.once or args.check:
            break
        time.sleep(args.interval)


if __name__ == "__main__":
    main()

