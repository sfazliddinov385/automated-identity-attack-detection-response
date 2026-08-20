# Lessons learned

## 1. Field normalization matters

The Windows target username appeared through Splunk's multivalue
`Account_Name` extraction rather than the initially expected field. Inspecting
raw events and normalizing the value was necessary before correlation worked.

## 2. Event time and index time are different

The VMs initially used different time zones and were not fully synchronized.
Comparing `_time` with `_indextime`, aligning time zones, and enabling VMware
time synchronization prevented recent events from appearing outside the
expected search window.

## 3. Infrastructure problems can resemble workflow problems

The first Shuffle execution remained in `EXECUTING` even though the webhook had
accepted the alert. Worker logs revealed Docker Swarm DNS failures. Attaching
the worker and HTTP services to the `shuffle_swarm_executions` overlay network
restored service discovery.

## 4. Automation needs independent verification

An HTTP `200` from Shuffle proves that the request completed, but not by itself
that Active Directory changed. Checking `Enabled=False` and Event ID `4725`
provided independent confirmation.

## 5. High-impact actions need multiple guardrails

The response service became safer and easier to explain after adding separate
authentication, source-IP filtering, an exact user allowlist, an OU boundary,
dry-run mode, and audit logging.

## 6. Duplicate suppression is part of response engineering

The same rolling-window detection remains visible for multiple polling cycles.
Without state, a connector can repeatedly launch the same workflow. Persisting
a post-success fingerprint solved this while allowing new events to trigger.

## 7. Build and test in phases

The most reliable sequence was:

```text
Data ingestion → search validation → manual webhook test
→ workflow condition test → responder authentication test
→ dry-run response → live response → automatic connector
→ full end-to-end validation
```

This reduced the number of systems involved in each troubleshooting step and
made failures easier to isolate.

