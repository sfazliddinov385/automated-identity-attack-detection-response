# Lessons learned

## Check the fields in the actual events

The target username appeared in Splunk's multivalue `Account_Name` field,
rather than the field initially expected. The detection only worked after
checking the raw events and selecting the correct username value.

## Check the clocks when recent events look missing

The VM clocks were not fully synchronized, and different time zones made the
timestamps harder to compare. Comparing `_time` with `_indextime` helped
identify the problem. Matching the time zones made troubleshooting easier;
VMware time synchronization corrected the clock differences that affected
the search window.

## An accepted webhook does not mean the workflow ran

The first Shuffle execution stayed in `EXECUTING` after the webhook accepted
the alert. The worker logs showed Docker Swarm DNS failures. Connecting the
worker and HTTP services to the `shuffle_swarm_executions` overlay network
let the services find each other again.

## Check the result of the account change

An HTTP `200` does not prove that an account was disabled. The updated responder
checks `Enabled=False` in AD before reporting success. The separate Event 4725
check in Splunk confirms that Windows recorded the disable action.

## Require approval before disabling accounts

The responder uses separate authentication, source-IP filtering, an exact
account list, an OU check, dry-run mode, and logs. The update adds approval for
each request before live account changes. The lab test showed the difference:
the same request first returned `pending_approval`, then completed after local
approval and resubmission from Shuffle.

## Expect the same alert to appear more than once

The same rolling-window result can appear in several consecutive searches.
Saving a fingerprint after Shuffle accepts the alert prevents the connector
from sending that same result on every poll. It remembers only the last
delivered result, so it is not a complete history of duplicates.

## Test one connection at a time

The original version was tested in this order:

```text
Data ingestion → search validation → manual webhook test
→ workflow condition test → responder authentication test
→ dry-run response → live response → automatic connector
→ full end-to-end validation
```

This kept each troubleshooting step small enough to identify which connection
was failing. For the updated responder, testing also covered a request before
approval, the same request after approval, the AD result, and the Event 4725
records in Splunk.

