# Stakeholder summary — lab exercise

**2026-11-15 · Draft only; not sent or published**

A controlled test made the lab application return errors for about two minutes
and 22 seconds. 282 of 984 test requests failed. No customers, payments, or production systems were affected.
The test checked whether our monitoring could detect a working server that was
returning the wrong response.

Monitoring detected the errors and delivered the critical notification. The test
then restored the original configuration. Requests succeeded again immediately
after restoration. The alert took longer to clear because it deliberately checks
a recent period of traffic, rather than one successful request.

The cause was an intentional configuration change applied to both application
replicas. Having two replicas did not help because both had the same fault.
The separate server health checks stayed green, showing why we also need to
check whether the application itself responds correctly.

Before using this setup for a real service, we propose making the existing
application check a deployment gate and adding a check from outside the cluster.
Proposed owners and dates are listed in the [technical postmortem](02-http503.md).

## Status-page drafts

These illustrate the communication sequence; they were not public updates.

| Stage | Draft |
| --- | --- |
| Investigating | The lab application is returning errors. We are checking the affected request path. Production is not affected. |
| Identified | We traced the lab errors to a configuration change affecting both application replicas. We are restoring the previous configuration. |
| Monitoring | The original configuration is restored and test requests are succeeding. We are watching traffic and waiting for the monitoring windows to clear. |
| Resolved | The lab application has recovered and its burn alerts have cleared. We will add a deployment check to catch this failure before promotion. |
