# Capacity and cost

## Measured comparison

On 2026-11-16, the agreed synthetic baseline was 10 RPS and the 3× case was
30 RPS, each scheduled for two minutes. This is a chosen lab baseline, not a
measurement of existing customer demand.

```sh
python3 scripts/check-capacity.py
```

| Target | Requests | HTTP 200 + valid JSON/IP | Client p50 | p95 | p99 | Maximum |
| --- | --- | --- | --- | --- | --- | --- |
| 10 RPS | 1,200 | 1,200 | 5.16 ms | 8.98 ms | 10.05 ms | 64.13 ms |
| 30 RPS | 3,600 | 3,600 | 5.73 ms | 8.82 ms | 10.81 ms | 112.76 ms |

There were no missed scheduled requests, transport/functional failures, or
requests above 300 ms. Both HPAs stayed at two current/desired replicas in the
before/after samples. Argo remained Synced and Healthy after the test.

The driver runs on the same host as the VMs, uses up to 16 in-flight HTTP/1.1
requests with connection reuse, binds the lab source IP, verifies the local CA,
and tests the complete LB → TLS ingress → NGINX → PHP path. It checks response
content and client IP, not just status. Achieved rates were 10.01 and 30.01 RPS
when divided by first-dispatch-to-last-completion time. Keep other tests and
application changes out of this window. Raw requests stay in `.state/capacity/`;
[the reviewed summary and metrics](capacity-results.json) are committed.

End-of-stage Prometheus samples, summed across both pods of each tier:

| Tier | CPU at 10 / 30 RPS (trailing 1m) | Working-set memory at 30 RPS |
| --- | --- | --- |
| NGINX | 3.0m / 7.5m | 4.8 MiB |
| PHP | 10.4m / 16.1m | 26.3 MiB |
| All four exporter sidecars | 2.6m / 2.9m | 30.1 MiB |

The PHP queue sample was zero at each stage end. These are before/after snapshots,
not peak measurements; short queues, memory spikes, or replica changes can be
missed. Two minutes does not validate leak behavior, long bursts, cold starts,
node-loss capacity, or maximum throughput. No database or payment-provider call
exists in this minimal app. Do not extrapolate these results to payment traffic.
The test did not trigger autoscaling, so it does not demonstrate HPA scale-up.

## Planning a real 3× event

Measure representative request mixes, payloads, downstream latency, per-worker
memory, throttling, and burst duration first. Confirm the starting traffic rate
and multiply that rate by three; do not multiply this synthetic baseline blindly.
Ramp to it on a representative environment and include a sustained soak and a
single-worker-loss test. Keep the SLOs and telemetry intact; stop if errors,
queues, throttling, or node pressure rise.

Use arrival rate × service time to estimate required concurrent PHP work, then
validate it against CPU and measured per-worker memory. Keep `max_children=4`
until its 256 MiB budget has been checked with the real code. Raising the pool
ceiling can move a queue into CPU contention or OOM rather than add throughput.

For a known event, pre-scale ahead of the burst and verify scheduling. Argo owns
the chart while HPAs own actual replicas; change reviewed chart/bootstrap values,
not a manual scale that an HPA immediately reverses. The current maximum of
three replicas gives only 50% more pods than two, not a guarantee of 3× capacity.
A 70% target balances reaction headroom against pod count, and the five-minute
downscale delay reduces flapping; neither predicts the whole downstream limit.

## Resource and cost trade-offs

At two replicas per tier, app pods including exporters request **340m CPU and
224 MiB**. At three each, they request **510m and 336 MiB**: +170m/+112 MiB.
Combined container limits rise from 1.9 to 2.85 CPU and 896 to 1,344 MiB. Limits
are ceilings, not measured consumption or guaranteed reserved capacity. Leave
room for monitoring, Argo, system workloads, and a failed node before expanding.

Extra pods on existing VMs do not change the VM allocation, but consume its
headroom. A third worker of the current size would add 3 GiB and two vCPUs,
raising configured guest RAM from 9.5 to 12.5 GiB; this 16 GiB host would need
more room or a different host. Keep production cost estimates tied to actual
provider/region prices rather than inventing a currency figure for local VMs.

The small ephemeral monitoring setup saves resources at the cost of history and
recovery. Production durability and separate failure domains cost more but are
needed for meaningful HA. A single LB/control plane/etcd and one physical host
remain the larger reliability limits; low app CPU does not remove them.
