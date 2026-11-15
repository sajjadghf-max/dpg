# Exercise 1: voluntary NGINX pod eviction

**2026-11-15 · local lab · no real users affected**

One of two NGINX pods was evicted through the Kubernetes eviction API. The other
replica served traffic while the Deployment created a replacement. The exercise
passed without a sampled application failure; this was a resilience test, not
a user-visible outage.

## Timeline

Times are Asia/Tehran (UTC+03:30), measured by the test runner.

| Time | Observation |
| --- | --- |
| 16:58:04 | Started healthy baseline at roughly two requests/second. |
| 16:58:34.093 | Started the disruption. |
| 16:58:34.175 | API accepted eviction of the worker1 NGINX pod. |
| 16:58:34.262 | Dry-run eviction of the peer returned TooManyRequests: PDB would be violated. |
| 16:58:37.579 | Replacement pod was Ready; two Ready NGINX pods again. |
| 16:59:07 | Finished observation after another 30 seconds of traffic. |

## Detection, recovery, and impact

The runner observed the eviction immediately through its API response and found
the Ready replacement 3.4 seconds later. No application alert fired at the final
rule check; no notification was expected for a disruption with no observed SLO
violation. Alert MTTD is therefore not applicable. The API's PDB rejection is
the evidence that a second voluntary disruption was blocked, not an alert.

All **128/128** requests returned HTTP 200, including seven during replacement.
There were no transport failures and no requests above 300 ms; maximum observed
client latency was 75.8 ms. For this test cohort, availability allowed 0.128 bad
requests and latency allowed 1.28; zero were consumed for either objective.
This does not prove zero loss between samples or under a larger workload.

## Cause and lessons

The trigger was an intentional eviction. Two replicas, Service routing, and
Deployment reconciliation preserved sampled availability. The PDB limited
voluntary disruption to one healthy pod at a time. It does not protect against
node failures, direct pod deletion, or a bad configuration affecting both pods.
No human error is attributed; the exercise tested the configured safeguards.

## Follow-up

Proposed role owners and dates, for review rather than assigned commitments:

| Action | Owner | Due |
| --- | --- | --- |
| Repeat with a single-worker drain after confirming host capacity. | SRE owner | 2026-11-20 |
| Include this eviction check in the pre-release lab checklist. | Application owner | 2026-11-18 |

Evidence run: `20261115T132803Z-eviction`; exact summary is in
[the checked-in exercise results](results.json). Full requests and API output
remain in `.state/chaos/`.
