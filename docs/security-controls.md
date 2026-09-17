# Security controls

## Request checks

The connector uses one key to send alerts to Shuffle. Shuffle uses a different
key to call the Windows responder. The responder checks the source IP, key,
HTTP method, URL path, request size (64 KiB maximum), and required alert fields.

The responder accepts only the five test users in the LAB domain. It checks
that every account belongs to the lab OU before changing any account. It logs
each HTTP outcome without recording keys or raw request bodies.

## Approval

A valid alert does not authorize an account change on its own. An administrator
must approve it locally with `Approve-SOARRequest.ps1`. The approval records who
approved it, their reason, and its start and expiry times.

Approval applies to a request ID calculated from the source, event time, domain,
detection, severity, and exact account list. Adding an approval field to the
HTTP request does not grant approval, and there is no HTTP approval endpoint.
The installer restricts the response directory to SYSTEM and Administrators.
It also resets permissions on the files and folders inside it to remove any
older grants of access.

An administrator or SYSTEM can still change the approval files or code. These
checks do not protect against someone who already controls either identity.
A production design would need to separate approval permissions from the
permissions used to run the response.

## Account changes and results

Dry-run mode changes nothing and never reports verified success. Before making
AD changes, a live request saves a record that processing has started. This
prevents another copy of the same request from starting the changes again.
If processing stops unexpectedly, an administrator must inspect the result.
The responder saves completed results, including partial failures.

After acting on an account, the responder reads its state from the same DC.
It reports success only when all five accounts are confirmed disabled. Sending
a completed request again returns the saved result, clearly marked as cached;
it does not check the current account state again.

Windows Event 4725 is checked separately in Splunk. The connector's delivery
record means Shuffle accepted the alert; it does not confirm that accounts
were disabled.

## What still needs work

The lab still runs the responder as SYSTEM on a domain controller and sends
requests to it over HTTP. Some lab connections can also skip TLS certificate
verification for self-signed services. The OU check restricts what the code
will change, but it does not reduce the task's AD permissions.

Before using this outside the lab, it would need trusted TLS certificates, a
service account with limited AD permissions, and a way to store and rotate
keys. It would also need protected central logs, service monitoring, limits on
request load, detections tested against normal activity, and a documented way
to recover from failed or mistaken responses.

See [approval and recovery details](approval-and-verification.md).
