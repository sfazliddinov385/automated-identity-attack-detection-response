# Security controls

## Authentication

Two independent shared secrets are used:

| Integration | Header | Storage |
| --- | --- | --- |
| SIEM-01 to Shuffle | `X-SOAR-LAB-KEY` | Private file on SIEM-01 and Shuffle authentication configuration |
| Shuffle to DC-01 | `X-SOAR-RESPONSE-KEY` | Protected file on DC-01 and Shuffle HTTP action |

No secret values are stored in this repository.

## Authorization

The response action is limited through multiple controls:

1. Windows Firewall accepts TCP 8081 only from SOAR-01.
2. The service independently checks the remote source address.
3. The request must describe the expected high-severity detection.
4. The account count must be at least five.
5. Every account must appear in an exact username allowlist.
6. Every account must remain inside `OU=SOAR-Lab-Users`.

This is defense in depth: bypassing one check is not enough to gain unrestricted
account-management capability.

## Safe response lifecycle

The responder defaults to dry-run mode. Live account changes require an
explicit installer switch. The project used this sequence:

```text
Authentication failure test → dry-run test → result inspection
→ explicit live-response enablement → controlled final test
```

## Auditing and deduplication

- The responder writes one JSON-line record per processed request.
- Active Directory independently creates Event ID `4725`.
- Splunk preserves the response events for investigation.
- The connector stores a SHA-256 fingerprint only after successful delivery.
- Duplicate detections do not trigger repeated containment.

## Secret handling

The `.gitignore` excludes credential, key, webhook, state, log, certificate,
and local environment files. Before every public release, scan the repository
for private key material, authentication-header values, passwords, and live
webhook identifiers.

## Lab limitations

The isolated lab used internal HTTP and self-signed TLS. These choices are not
appropriate for production. A production design should use:

- Trusted TLS certificates and certificate validation
- A secrets manager with rotation and access logging
- Managed service accounts with minimal rights
- Human approval for high-impact or ambiguous cases
- Centralized immutable response logs
- Rate limiting and request replay protection
- High availability and health monitoring
- Production-specific account exclusions and detection tuning

