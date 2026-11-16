# Monitoring

```sh
ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml -e lab_phase=platform --tags monitoring
ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml -e lab_phase=verify --tags monitoring
```

The installer pins kube-prometheus-stack 93.3.0 and verifies its archive checksum.
It installs Prometheus, Grafana, Alertmanager, kube-state-metrics, and node-exporter.
NGINX and PHP-FPM each get an exporter sidecar. Traefik supplies request counts,
status codes, and latency histograms, including service/upstream latency.
NGINX supplies connection counters; PHP-FPM supplies pool, queue, and process metrics.
Kubelet/cAdvisor and kube-state-metrics supply container resources, restarts, and HPA state.

Prometheus scrapes every 30 seconds and retains up to 24 hours or 1 GB, whichever
limit is reached first. Prometheus, Grafana, and Alertmanager have one replica
and ephemeral storage. Replacing their pods loses metrics, Grafana UI changes,
and Alertmanager silences. Provisioned dashboards and rules remain in Git.
This is a resource-saving lab choice, not a durable monitoring installation.

Kubelet scrapes verify the cluster CA and signed serving certificates.
Etcd, controller-manager, scheduler, and kube-proxy scrapes are disabled because
this lab has not exposed their metrics endpoints. Their metrics are not covered.

## Grafana access

Grafana uses `https://grafana.dpg.test`, the ingress local CA, and an admin login.
Resolve that name to `192.168.56.10` on your client. The CA certificate is
`.state/tls/ca.crt`; installing it into browser trust is a separate local choice.
The username is `admin`; retrieve the generated password locally:

```sh
cat .state/monitoring/admin-password
```

The password, TLS keys, and certificates stay in ignored `.state/` files.
The generated password initializes Grafana's ephemeral database; keep the file
for reinstalls. Anonymous access and self-registration are disabled.
Prometheus and Alertmanager have ClusterIP services and no public ingress.
For temporary local Prometheus access:

```sh
export KUBECONFIG="$PWD/.state/artifacts/admin.conf"
.state/artifacts/kubectl -n monitoring port-forward \
  service/monitoring-kube-prometheus-prometheus 9090:9090
```

Application exporter ports and Traefik metrics accept only Prometheus pods in
`monitoring`. The PHP status listener and NGINX status page remain private.
The platform phase preserves the application's imported image tags and keeps
monitoring enabled when the stack exists.

## Checks

The verification playbook waits for healthy Prometheus targets, confirms both application
exporters can reach their local processes, and checks kubelet and Traefik scrapes.
It verifies Grafana's certificate, rejects anonymous API access, and tests the
admin login without placing the password in process arguments. The full verification phase also runs
the application HTTPS/client-IP checks and allowed/denied network tests.
After Argo CD adoption, the network test pods are rendered from the chart instead
of using the old Helm release history.

The provisioned **Digipay application** dashboard is at `/d/dpg-application`.
Its [JSON export](../charts/dpg-observability/files/dashboard.json) stays in Git.
It covers requests, 4xx/5xx rates, p50/p95/p99 and mean upstream latency,
NGINX connections, PHP busy/idle workers and queue, restarts, CPU/memory, HPA
replicas and observed replica changes, SLIs, and remaining budgets. Replica
changes are sampled metrics, not a durable Kubernetes Events archive.

Screenshots from the running lab:
[requests](screenshots/dashboard-requests.png),
[pool](screenshots/dashboard-pool.png),
[resources](screenshots/dashboard-resources.png), and
[SLOs](screenshots/dashboard-slo.png).

See [SLOs and alert delivery](alerting.md) for targets, limitations, rules,
and verification commands. The stack also keeps its upstream Kubernetes
dashboards and default rules. Failure exercises remain a separate step.

Verified on 2026-11-15: all 28 scrape targets were healthy, including both NGINX
exporters, both PHP-FPM exporters, both Traefik replicas, and nine kubelet
endpoints. Grafana rejected anonymous API access and accepted the generated
admin credentials over verified HTTPS. Application and network checks passed.

Grafana exceeded the initial 256 MiB limit during startup. Its final limit is
512 MiB, with a 256 MiB request; each configuration sidecar requests 64 MiB and
has a 192 MiB limit. Recheck usage when adding dashboards or load.
