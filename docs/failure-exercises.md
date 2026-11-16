# Failure exercises

Run only against this disposable local lab. Both tests generate roughly two HTTPS
requests per second through the load balancer, using the local CA. They require
two healthy NGINX pods, one permitted PDB disruption, and the monitoring stack.
Do not run them concurrently or during an application deployment.

```sh
python3 scripts/run-failure-exercise.py eviction
python3 scripts/run-failure-exercise.py http503
ansible-playbook -i inventory/lab/hosts.yml ansible/verify.yml --tags ingress
```

The first test evicts one NGINX pod through the eviction API, immediately tries
a **dry-run** eviction of its peer, and requires the PDB to reject that second
request. It waits for a replacement Ready pod while sending traffic. No node
is drained, and the peer is never actually evicted. This checks voluntary
pod disruption, not node or control-plane failover. The API's PDB behavior is
explained in the [Kubernetes eviction documentation](https://kubernetes.io/docs/concepts/scheduling-eviction/api-eviction/).

The second test backs up each pod's generated `/tmp/default.conf`, injects
`return 503` only into the root location, validates the config, and reloads NGINX.
Health/readiness and status routes stay intact. The files in Git, images, Helm
values, and Deployment templates are unchanged. This deliberately shows that
healthy probes do not prove the main application works.

Each pod starts a 240-second restore watchdog before injection. The host also
restores on normal completion, errors, Ctrl-C, or SIGTERM. Once the critical
availability-burn notification arrives, it restores the original config and
continues successful traffic until the critical notification resolves and the
slow burn clears. If no notification arrives, it restores without extending
the fault beyond four minutes. Keep this terminal running through recovery.

A host process killed with SIGKILL cannot run its cleanup, but the pod watchdog
still restores the file. Recreating an affected pod also regenerates its normal
config from the image; use the eviction API one pod at a time and respect the PDB.
A pod/container restart loses both the temporary fault and its backup.

Evidence is written under ignored `.state/chaos/<UTC timestamp>-<scenario>/`:
request timestamps/status/duration, timeline, pre/post Prometheus snapshots,
webhook logs, and a per-phase summary. Files use private permissions. The tests
query the existing rules and receiver; they do not inject a synthetic alert,
reduce alert thresholds, or silence alerts.

Client results count every test request, including transport failures. The SLI
in Prometheus measures only traffic reaching the application ingress service;
its counter estimates and rolling-window ratios can differ from exact client
counts. Report those separately. Raw evidence expires with this checkout;
reviewed measurements and postmortems are kept in Git below.

- [Voluntary NGINX eviction](incidents/01-nginx-eviction.md)
- [Application HTTP 503](incidents/02-http503.md)

## Recorded result (2026-11-15)

Eviction: 128/128 requests succeeded; replacement Ready in 3.4 seconds; the PDB
rejected the peer's dry-run eviction. HTTP 503: 282/984 requests failed; the
critical burn alert fired in 131.2 seconds and both configs were restored in
141.6 seconds. Both burn notifications later resolved. See the postmortems for
scope, measurement limits, and budget calculations.

A [stakeholder summary and four status drafts](incidents/stakeholder-update.md)
are included. They have not been sent or published.
