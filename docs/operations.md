# On-call and changes

This is a proposed policy for a four-person, cross-trained SRE/service team.
No people have been assigned and the lab webhook is not a staffed paging channel.

## Rotation and escalation

Rotate weekly primary and secondary roles; hand over Monday at 10:00 Asia/Tehran.
The other two engineers are off rotation. Agree coverage, rest after overnight
incidents, and compensation before promising 24/7 service; a smaller team needs
shared coverage rather than an unstaffed pager.

| Signal | Initial route | Escalation |
| --- | --- | --- |
| Fast availability/latency burn or app crash loop | Page primary | Unacknowledged after 5m: secondary; unresolved/high impact after 10m: service owner; after 15m: incident manager/engineering lead. |
| Slow burn or sustained PHP saturation without user impact | Ticket and team channel | Primary reviews next business day; upgrade to a page if user impact or rapid budget burn appears. |
| Missing telemetry | Team channel/ticket; investigate coverage | Page if it prevents detection during an active incident or accompanies a failed external check. |

Start an incident note and assign an incident lead for material user impact.
Use one communication owner; update stakeholders about every 15 minutes during
an outage, even if the update is that investigation continues. Route related
alerts together and suppress lower-severity duplicates, as in [alerting](alerting.md).
Escalation timing is a proposal, not a claim about measured response times.

## Handover

Spend 15 minutes reviewing active incidents, consumed error budget, silences and
expiry, pending changes, capacity, certificate expiry, and backup/restore status.
The incoming primary acknowledges the handover. A useful note is:

```text
Period / outgoing / incoming:
Service health and error-budget trend:
Active incidents / owner / next update:
Silences / reason / expiry:
Recent or pending change / rollback:
Capacity, certificate, backup concerns:
Actions / owner / due / evidence links:
```

## Review and rollback

Use a small PR with the problem, expected behavior, validation, and rollback.
Require one peer review; require the `Validate` check through branch protection
before merge. The workflow exists, but required-check protection has not been
configured here. Runtime checks still need the lab; CI has no deployment access.
Import any new image on both workers before promoting its content-based tag.
Follow the bootstrap-image steps in [GitOps](gitops.md).

Merge/push reviewed chart changes to `main`, observe Argo sync and the functional
HTTPS check, then watch request errors, latency, queue, and restarts. Revert and
push a faulty chart commit; reapply reverted Application settings when those
settings changed. During an emergency, record the incident and rollback first,
then obtain the normal peer review afterward. Log any temporary reconciliation
pause and re-enable it after recovery; never leave Git and the cluster divergent
without an owner and expiry.

For the first month, hold one 20-minute weekly error-budget review. Look at the
two SLIs, data gaps, top incident causes, and overdue postmortem actions. Choose
one reliability improvement with an owner and due date. If the budget is spent,
prioritize recovery/prevention and defer discretionary risky releases until the
service owner reviews the trade-off. This lab's short history and synthetic
traffic must not be presented as production SLO compliance.
