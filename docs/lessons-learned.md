# Lessons learned

## Check the fields in the actual events

The username was in Splunk's multivalue `Account_Name` field, not the field I originally expected. I had to look at the raw events and select the right value before the detection worked. Checking a few real events first would have saved time.

## Check the clocks when recent events look missing

Some events appeared outside the search window because the VM clocks were out of sync. Different time zones also made the timestamps confusing.

Comparing `_time` with `_indextime` helped me find the problem. Using the same time zone made the logs easier to compare, while VMware time synchronization fixed the clock differences.

## An accepted webhook does not mean the workflow ran

Shuffle accepted the alert, but the first execution stayed in `EXECUTING`. The worker logs showed Docker Swarm DNS errors.

Connecting the worker and HTTP services to the `shuffle_swarm_executions` overlay network fixed communication between them. This taught me to check the workflow execution and worker logs instead of stopping at the webhook response.

## Check the result of the account change

An HTTP `200` response does not prove that an account was disabled. The responder now reads the account back from AD and checks for `Enabled=False` before reporting success.

I also checked Event ID 4725 in Splunk to confirm that Windows recorded the account changes. The AD check confirms the account state; the audit event records the disable action.

## Require approval before disabling accounts

Failed logins alone do not prove that an account was compromised. The responder already had a separate response key, source-IP filtering, an exact account list, an OU check, dry-run mode, and logging. I added approval so an administrator can review the request before accounts are disabled.

The lab test confirmed this worked: the request first returned `pending_approval` without changing any accounts. After I approved it on DC-01 and resent the same alert from Shuffle, the responder disabled and verified all five test accounts.

## Expect the same alert to appear more than once

Because the searches use a rolling time window, the same activity can appear in several polls. The connector saves a fingerprint after Shuffle accepts an alert and skips it if the next result matches.

It only remembers the last delivered result. That stops repeated sends of the same consecutive result, but it does not catch every duplicate across the full alert history.

## Test one connection at a time

I tested the original version in this order:

```text
Data ingestion → search validation → manual webhook test
→ workflow condition test → responder authentication test
→ dry-run response → live response → automatic connector
→ full end-to-end validation
```

Testing each part separately made it easier to find where something was failing.

For the updated responder, I also checked that an unapproved request made no changes, then approved and resent that same request. Finally, I checked the AD results and the five Event ID 4725 records in Splunk.
