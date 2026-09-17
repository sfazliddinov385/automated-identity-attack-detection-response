# Architecture

> Historical v1 architecture below. The current responder adds local operator
> approval before account changes and automatic AD state readback afterward.
> See [the current flow](approval-and-verification.md). Existing diagrams describe
> the original direct-response test.

## Network design

The project was implemented on an isolated VMware network using four active
systems:

| Host | Function | Key services |
| --- | --- | --- |
| VICTIM-B | Controlled source of failed logons | Windows, Sysmon, Splunk Universal Forwarder |
| DC-01 | Identity provider and response target | AD DS, DNS, Security log, responder on TCP 8081 |
| SIEM-01 | Detection and orchestration connector | Splunk Enterprise, Python systemd user service |
| SOAR-01 | Workflow automation | Shuffle, Docker, OpenSearch |

```text
VMware isolated network: 192.168.226.0/24

VICTIM-B  .133 ──failed SMB authentication──▶ DC-01 .132
DC-01     .132 ──Windows Security events────▶ SIEM-01 .129:9997
SIEM-01   .129 ──authenticated webhook──────▶ SOAR-01 .134:3443
SOAR-01   .134 ──restricted HTTP response───▶ DC-01 .132:8081
DC-01     .132 ──Event ID 4725 audit────────▶ SIEM-01 .129:9997
```

## Data flow

1. VICTIM-B attempts authentication against five purpose-built AD users with
   an incorrect password.
2. DC-01 records failed-logon Event ID `4625` events.
3. The Splunk Universal Forwarder sends those events to SIEM-01.
4. Splunk correlates five distinct target accounts from one source within five
   minutes.
5. The connector calls Shuffle's authenticated webhook.
6. Shuffle validates severity, account count, and detection name.
7. Shuffle calls the Windows responder with a separate authentication key.
8. The responder applies its source, username, and OU allowlists.
9. Active Directory disables the five users.
10. DC-01 records Event ID `4725`, which is forwarded back to Splunk.

## Trust boundaries

- **Detection boundary:** Only SIEM-01 has Splunk REST credentials.
- **SOAR ingestion boundary:** Shuffle requires a dedicated webhook header.
- **Response boundary:** DC-01 requires a different response header.
- **Network boundary:** Windows Firewall accepts port 8081 only from SOAR-01.
- **Identity boundary:** The responder can act only on exact users inside the
  lab OU.

## Availability

The connector runs as an enabled systemd user service with automatic restart.
The Windows responder runs as a scheduled task under `SYSTEM` at startup.
Shuffle services run through Docker and Docker Swarm.

