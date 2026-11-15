# Application SLOs and alerts

```sh
bash scripts/install-observability.sh
bash scripts/check-observability.sh
bash scripts/test-slo-rules.sh
```

The Helm release `dpg-observability` owns the dashboard, recording/alert rules,
and webhook mock. Its receiver reuses the imported PHP image; no registry or
external notification account is needed.

## Targets and budgets

These are agreed lab targets over a rolling 24-hour window:

| SLO | Good event | Target | Allowed bad requests per 10,000 |
| --- | --- | --- | --- |
| Availability | HTTP status below 500 | 99.9% | 10 |
| Latency | Traefik service response within 300 ms | 99% | 100 |

The denominator is requests for the application's Traefik service, aggregated
across ingress replicas. Availability includes 4xx as successful service responses;
the dashboard shows 4xx separately. Latency includes all status codes. Traefik's
300 ms histogram bucket measures the latency objective directly; percentiles
are histogram estimates. Upstream timing covers NGINX and PHP together, not
isolated PHP execution or the client's full network round trip.

Bad ratio = bad requests / total requests. Allowed budget = total × (1 − target).
Remaining budget fraction = 1 − bad ratio / (1 − target); negative means overspent.
The recording rules use counter rates over the window, accounting for resets;
counts inferred from counters are estimates between scrapes. With a full window,
a constant bad rate consumes its proportional request budget.

No requests means no SLI, not 100% success. Windows are partial after startup,
pod replacement, or retention eviction. The 1 GB retention cap may shorten the
24-hour history, so this lab cannot certify a full-day production SLO. The latency
window starts with the new 300 ms bucket; old series lacking that bucket are
excluded. Health/readiness and deliberate test requests reaching this service
are included because these metrics have no URL-path label. DNS, TLS, and LB
failures before Traefik are outside this SLI; production needs an external probe.

## Notification policy

| Condition | Windows / duration | Action in a real on-call setup |
| --- | --- | --- |
| Fast burn | >6× budget rate in both 10m and 1m, for 1m | Page primary |
| Slow burn | >3× in both 1h and 5m, for 1m | Ticket / team notification |
| PHP saturation | ≥90% of four workers per pod, or queue >0, for 2m | Investigate capacity / slow requests |
| Crash loop | CrashLoopBackOff observed within 5m, persisting 2m | Page primary |

Each burn alert needs at least 20 requests in its long window. This reduces noise
in this quiet lab but can suppress real low-traffic incidents; it is not a
substitute for an external availability probe. For a 24-hour budget, 6× over
10 minutes spends about 4.17% of the budget; 3× over one hour spends 12.5%,
assuming steady traffic. These thresholds are scaled for this lab's one-day
window, not copied from a 30-day policy.

Availability/latency alerts describe user symptoms. Pool and crash alerts add
likely causes and can fire before broad user impact. Group by alert name, SLO,
and namespace; wait 10 seconds, batch updates each minute, and repeat after four
hours. Critical alerts suppress warnings with the same SLO. Default Kubernetes
alerts still evaluate but remain on the null receiver; only `scope=dpg` alerts
go to this mock. Do not treat this as a staffed paging service.

The webhook has no ingress. NetworkPolicy admits only Alertmanager pods in its
namespace and denies receiver egress. It logs alert name, severity, status, and
time; it does not store annotations or forward messages. Logs are ephemeral.
Read delivery evidence with:

```sh
export KUBECONFIG="$PWD/.state/artifacts/admin.conf"
.state/artifacts/kubectl -n monitoring logs deployment/dpg-alert-receiver \
  --since=10m | grep alert_received
```

For burn alerts, inspect request/error and latency panels, deployment changes,
and upstream logs; restore the last working release if a change caused impact.
For saturation, inspect per-pod queues, CPU throttling, and slow requests before
raising replicas or the pool ceiling. For crash loops, inspect `kubectl describe
pod` and `kubectl logs --previous`, especially OOM termination and config errors.
Do not raise PHP `max_children` without checking the memory budget; dashboard
and alert queries currently use the configured ceiling of four.

The burn logic follows the [multiwindow approach in the SRE Workbook](https://sre.google/workbook/alerting-on-slos/).
Webhook routing uses [Alertmanager's supported configuration](https://prometheus.io/docs/alerting/latest/configuration/).
See [failure exercises](failure-exercises.md) for measured incident impact and postmortems.

## Verified in the lab

On 2026-11-15, all 14 dashboard panels were provisioned and their PromQL queries
were accepted. Screenshots show the live dashboard. Promtool passed four cases:
healthy traffic (including no 5xx counter), sustained burn, low traffic below the
notification floor, and no traffic. The no-traffic case produced no SLI sample.
A temporary synthetic rule delivered both firing and resolved webhook messages
through Prometheus and Alertmanager; the rule was then removed. All 28 scrape
targets remained healthy and HTTPS/client-IP checks passed. This verifies rule
logic and delivery, not an actual outage; failure exercises remain to be run.
