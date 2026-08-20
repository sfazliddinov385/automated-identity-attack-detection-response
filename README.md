# Automated Identity Attack Detection and Response

A blue-team security automation lab that detects Active Directory password
spraying in Splunk, sends a validated alert to Shuffle SOAR, and automatically
disables the targeted lab accounts through a restricted Windows response
service.

> **Status:** End-to-end lab validation completed successfully on August 20,
> 2026.

![Final Shuffle workflow](evidence/07-final-workflow-architecture.png)

## What this project demonstrates

- Windows Security log collection from an Active Directory domain controller
- Detection of one source attempting authentication against five distinct
  accounts inside a rolling five-minute window
- MITRE ATT&CK mapping to **T1110.003 — Password Spraying**
- Automatic Splunk-to-Shuffle alert delivery using a Python connector
- Three validation gates before containment is permitted
- Authenticated and allowlisted Active Directory account containment
- Duplicate-alert suppression to prevent repeated response actions
- Verification through Windows Event ID **4725** audit events

## Architecture

![Architecture diagram](diagrams/architecture-diagram.png)

| System | Lab role | Address |
| --- | --- | --- |
| VICTIM-B | Controlled authentication-test source | `192.168.226.133` |
| DC-01 (`WIN-3B0FE43Q9UR`) | Active Directory and Windows Security logs | `192.168.226.132` |
| SIEM-01 | Splunk Enterprise and automatic connector | `192.168.226.129` |
| SOAR-01 | Shuffle SOAR on Docker | `192.168.226.134` |

All systems were placed on an isolated VMware network. The private addresses
above are included only to make the lab reproducible.

## Detection logic

The Splunk search identifies failed logons where:

1. Event ID `4625` is recorded on the domain controller.
2. The attempts originate from the same source IP.
3. Five or more distinct lab accounts are targeted.
4. The attempts occur within a rolling five-minute window.

The complete SPL is available at
[`splunk/password-spraying-detection.spl`](splunk/password-spraying-detection.spl).

![Splunk password-spraying detection](evidence/01-splunk-password-spraying-detection.png)

## Automated workflow

```text
Failed logons on VICTIM-B
        ↓
Windows Security Event ID 4625 on DC-01
        ↓
Splunk correlation search on SIEM-01
        ↓
Python connector (60-second polling + deduplication)
        ↓
Authenticated Shuffle webhook on SOAR-01
        ↓
Validate severity + account count + detection type
        ↓
Authenticated POST to the DC-01 responder
        ↓
Allowlisted lab accounts disabled
        ↓
Windows Security Event ID 4725 returned to Splunk
```

Shuffle only permits the response branch when all three conditions are true:

- `severity == "High"`
- `targeted_accounts > 4`
- `detection == "Password Spraying Detected"`

## Results

The final controlled test produced the following results:

- Five distinct failed logons were correlated by Splunk.
- The connector sent one alert to Shuffle.
- Repeated detections were suppressed as duplicates.
- Shuffle returned HTTP `200` with `success: true` and `dry_run: false`.
- All five allowlisted lab accounts were disabled.
- Splunk received five Event ID `4725` account-disable events.

| Stage | Evidence |
| --- | --- |
| Detection | [Splunk detection](evidence/01-splunk-password-spraying-detection.png) |
| Alert ingestion | [Shuffle received the alert](evidence/02-shuffle-alert-received.png) |
| Automatic delivery | [Connector and deduplication](evidence/03-automatic-connector-deduplication.png) |
| Automated response | [Shuffle response](evidence/04-shuffle-automatic-response.png) |
| AD containment | [Accounts disabled](evidence/05-active-directory-accounts-disabled.png) |
| Response audit | [Event ID 4725](evidence/06-splunk-response-audit-4725.png) |
| Workflow design | [Final workflow](evidence/07-final-workflow-architecture.png) |

## Security controls

This project intentionally avoids unrestricted account-management automation.
The response service uses:

- Separate secrets stored outside the repository
- A custom authentication header for each integration
- A Windows Firewall rule restricted to the SOAR host
- An exact username allowlist
- An Active Directory OU boundary
- Detection-type, severity, and account-count validation
- Dry-run mode enabled by default in the public scripts
- JSON-line response auditing
- Duplicate-event suppression in the connector

See [`docs/security-controls.md`](docs/security-controls.md) for details.

## Repository guide

| Directory | Purpose |
| --- | --- |
| `splunk/` | Detection and response-audit SPL |
| `connector/` | Splunk-to-Shuffle Python connector and systemd unit |
| `shuffle/` | Sanitized workflow design template |
| `windows-responder/` | Restricted Active Directory response service |
| `testing/` | Controlled lab simulation and verification scripts |
| `docs/` | Architecture, implementation, testing, and lessons learned |
| `evidence/` | Final screenshots from the validated test |

## Quick start

This repository documents a completed lab rather than providing a one-command
production deployment. Review the component READMEs in this order:

1. [`splunk/README.md`](splunk/README.md)
2. [`connector/README.md`](connector/README.md)
3. [`shuffle/README.md`](shuffle/README.md)
4. [`windows-responder/README.md`](windows-responder/README.md)
5. [`testing/README.md`](testing/README.md)

## Production considerations

The lab used self-signed certificates and internal HTTP communication on a
fully isolated network. A production implementation should use trusted TLS,
managed secrets, service identities, approval gates for high-impact actions,
centralized audit storage, high availability, and broader detection tuning.

## Ethical-use statement

The included test script is intended only for systems you own or are explicitly
authorized to test. This project was performed in an isolated lab against
purpose-built accounts. Do not run the simulation against production systems
or third-party infrastructure.

## Author

**Sarvarbek “Bek” Fazliddinov**  
Information Security Graduate Student at Georgia Tech

