# Service runbook

Use this from the repository root. Start with the failing user request, then
check the narrowest affected tier. Keep timestamps, recent changes, and commands
in the incident note. Do not dump Secrets or request bodies into tickets.

```sh
export KUBECONFIG="$PWD/.state/artifacts/admin.conf"
K=.state/artifacts/kubectl
curl --noproxy '*' --cacert .state/tls/ca.crt \
  --resolve app.dpg.test:443:192.168.56.10 https://app.dpg.test/
"$K" -n dpg-app get pods,hpa,pdb
"$K" -n argocd get application app
```

The response should be HTTP 200 JSON with the service name and the client's
actual IP. From this host, bind curl with `--interface 192.168.56.1` to compare
against that exact client IP. `/healthz` tests NGINX; `/readyz` tests PHP ping.
Both can pass while `/` fails: the 503 exercise demonstrated that case.

| Symptom | Inspect | Action |
| --- | --- | --- |
| Connection/TLS failure | HAProxy, Traefik pods, local CA/leaf expiry, hostname resolution | Restore the affected proxy/config or renew through the Ansible platform phase with `--tags ingress`; verify with the CA, not `curl -k`. |
| Root 5xx, probes green | Recent Git/chart change, NGINX logs, request/error panels | Revert the bad reviewed change; confirm `/` and client IP, not only probes. |
| PHP 502/504 or readiness failure | PHP pods, Service endpoints, PHP logs, queue and upstream latency | Fix/roll back backend config; inspect slow requests before raising replicas or timeouts. |
| CrashLoop/OOM | Pod events, previous logs, limits, node memory | Restore known-good image/config or correct measured resource needs; do not restart repeatedly without the reason. |
| High queue/latency | PHP active/idle workers, queue, CPU/throttling, HPA current/desired and conditions | Scale only with worker capacity; pool size four is tied to a 256 MiB limit. |
| Pending pods | Events, hard topology spread, worker allocatable/requested resources, imported images | Restore node capacity or import the exact image on both workers; do not weaken policy to hide the cause. |
| Metrics missing | Targets, exporter status, Metrics Server, kubelet serving CSR | Restore scrape/certificate access; distinguish no data from a healthy SLO. |

Useful bounded diagnostics:

```sh
"$K" -n dpg-app get endpointslices
"$K" -n dpg-app describe pod <pod-name>
"$K" -n dpg-app logs <pod-name> -c php --previous --tail=100
"$K" -n dpg-app logs -l app.kubernetes.io/component=nginx -c nginx --prefix --tail=100
"$K" -n dpg-app describe hpa app-php
"$K" top nodes
"$K" -n dpg-app top pods --containers
"$K" get csr
```

For certificate renewal, `ansible/roles/platform/files/approve-kubelet-csrs.py` validates the three
inventory identities; the platform phase's `metrics` tag invokes it. Never approve every CSR
blindly. In Grafana, use **Digipay application**. To inspect Prometheus locally:

```sh
"$K" -n monitoring port-forward service/monitoring-kube-prometheus-prometheus 9090:9090
```

## API or node outage

Check `vagrant status` and host memory first. If the LB API endpoint fails but
cp1 is reachable, compare the direct endpoint with the same trusted kubeconfig:

```sh
"$K" --server=https://192.168.56.11:6443 get --raw=/readyz
ansible load_balancer -i inventory/lab/hosts.yml -b -m command \
  -a 'haproxy -c -f /etc/haproxy/haproxy.cfg'
ansible load_balancer -i inventory/lab/hosts.yml -b -m command \
  -a 'systemctl status haproxy keepalived'
ansible load_balancer -i inventory/lab/hosts.yml -b -m command \
  -a 'ip -4 address show dev eth1'
ansible cp1 -i inventory/lab/hosts.yml -b -m command -a 'systemctl status etcd kubelet'
ansible cp1 -i inventory/lab/hosts.yml -b -m command -a 'free -m'
```

If cp1 is stopped, restore that VM; there is no standby API or etcd member.
Inspect guest kernel OOM logs and disk space before restarting services. The
control plane has 3 GiB; Argo CRDs are applied sequentially to limit memory pressure.
Loss of etcd data requires the separate recovery procedure, not a blind service
restart or fresh empty data directory.

## Restore and close

For chart regressions, revert the reviewed Git commit and push; Argo reconciles
`main`. Image/bootstrap settings require reapplying the reverted Application
manifest after the corresponding images are available. Do not use the stale
Helm `app` release for upgrade/rollback/uninstall. See [change and on-call policy](operations.md).

After recovery:

```sh
ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml -e lab_phase=verify --tags ingress
ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml -e lab_phase=verify --tags app
ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml -e lab_phase=verify --tags monitoring
"$K" -n argocd get application app
```

Confirm healthy user responses, replica placement, HPAs, and notification
resolution. Burn alerts clear after their short windows recover; the spent
rolling error budget remains spent. Send a concise impact/update draft for
review, record the timeline, and create owned follow-ups. Existing examples:
[postmortems](failure-exercises.md) and [stakeholder drafts](incidents/stakeholder-update.md).
