# Security controls

## Request authentication and policy

The connector-to-Shuffle key and Shuffle-to-responder key remain separate.
The HTTP responder checks the source IP, authentication header, method/path,
actual request byte count (64 KiB maximum), and normalized alert contract.

The live response accepts only the exact five purpose-built lab users in the
LAB domain. All users are read and checked against the authorized OU before
any change. Every HTTP outcome is logged without keys or raw request bodies.

## Approval authority

A valid alert is only a request. Live changes require a protected local approval
created by an operator using `Approve-SOARRequest.ps1`. Approval includes the
operator identity, review reason, issue time, and a short expiry.

The request ID binds the source, event time, domain, detection, severity, and
exact user set. Caller-supplied approval fields are ignored. There is no HTTP
approval route. The installer sets SYSTEM/Administrators-only ACLs on the root
and resets child ACLs so older explicit grants cannot leave state writable.

These ACLs are part of the trust boundary. A local administrator or SYSTEM can
change approvals or code; this mechanism does not defend against either being
compromised. Production separation of duties requires a different deployment.

## Execution and outcome

Dry run changes nothing and never reports verified success. Live requests create
a durable exclusive processing claim before any AD changes. Interrupted actions
require manual inspection; replay cannot silently restart them. Final results,
including partial failure, are preserved.

Each action is followed by AD state readback on the same DC. Overall success
requires all five accounts verified disabled. A cached result is explicitly
historical and is not a fresh check of current state.

Splunk Event ID 4725 remains a separate audit source. The connector records only
Shuffle delivery acceptance, not completed account containment.

## Remaining production work

The lab still uses a SYSTEM task on a domain controller, internal HTTP to the
responder, and optional disabled TLS verification for self-signed lab services.
The OU allowlist is a code restriction, not delegated least-privilege AD rights.

Production work includes trusted TLS, narrow delegated service permissions,
managed secrets, central protected auditing, monitoring, capacity controls,
production-specific detection tuning, and an approved recovery process.

See [approval and recovery details](approval-and-verification.md).

