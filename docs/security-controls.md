# Security controls

## Request checks

The connector uses one key to send alerts to Shuffle, and Shuffle uses a separate key to contact the Windows responder.

Before accepting a request, the responder checks:

- The source IP and response key.
- The HTTP method and URL path.
- The request size, with a maximum of 64 KiB.
- The required alert fields.
- The exact five test usernames and the LAB domain.

It also checks that all five accounts are in the lab OU before changing any of them. Each HTTP outcome is logged, but keys and raw request bodies are left out of the logs.

## Approval

An accepted alert cannot disable accounts by itself. An administrator must approve the request on DC-01 using `Approve-SOARRequest.ps1`. The approval records the administrator's identity, their reason, and when the approval starts and expires.

Each approval is tied to a request ID based on the source IP, event time, domain, detection name, severity, and exact account list. Adding an approval field to the alert does not bypass this step. There is no HTTP endpoint for granting approval.

The installer limits access to the response directory to SYSTEM and Administrators. It also resets permissions on the files and folders inside it to remove older access permissions.

Someone with Administrator or SYSTEM access could still change the scripts or approval files. For use outside the lab, approval should be controlled separately from the account that runs the responder.

## Account changes and results

Dry-run mode previews the response without changing accounts or reporting verified success.

Before a live response changes any accounts, it saves a record that processing has started. This prevents another copy of the same request from starting the actions again. If the service stops partway through, an administrator needs to check what happened before attempting recovery.

The responder saves the final result, including partial failures. After each account action, it checks the account on the same DC. It only reports success when all five accounts are confirmed disabled.

If a completed request is sent again, the responder returns its saved result and marks it as cached. That result describes the earlier attempt; it does not include a new check of the accounts.

Event ID 4725 is checked separately in Splunk to confirm that Windows recorded the disable actions. The connector's delivery record only confirms that Shuffle accepted the alert.

## What still needs work

The responder runs as SYSTEM on the lab domain controller and receives requests over HTTP. Some lab connections also allow TLS certificate checks to be skipped for self-signed services.

The OU check limits which accounts the script will change, but the scheduled task still has broad AD permissions.

Before using this outside the lab, I would need to:

- Use HTTPS with trusted certificates and enable certificate verification.
- Run the responder under a service account with only the AD permissions it needs.
- Set up secure key storage and rotation.
- Send logs to a protected central location.
- Monitor the services and limit how many requests they can handle at once.
- Test the detection against normal login activity.
- Document how to recover from failed responses or accounts disabled by mistake.

See [approval and recovery details](approval-and-verification.md).
