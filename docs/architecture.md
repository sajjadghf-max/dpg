# Architecture

```mermaid
flowchart TB
  User["Client: app.dpg.test / grafana.dpg.test"]
  Admin["Operator: kubectl / Ansible"]
  Git["GitHub: reviewed chart on main"]
  subgraph Host["One physical host — four VMs, 9.5 GiB total"]
    LB["lb · 512 MiB<br/>HAProxy TCP :80 / :443 / :6443"]
    CP["cp1 · 3 GiB<br/>Kubernetes API + single etcd member"]
    subgraph Workers["worker1 + worker2 · 3 GiB each · Calico VXLAN"]
      Ingress["Traefik ×2<br/>TLS termination · NodePorts 30080 / 30443"]
      NG["NGINX Service → pods ×2–3"]
      PHP["PHP Service → FPM pods ×2–3<br/>4 application workers per pod"]
      Obs["Prometheus / Grafana / Alertmanager<br/>exporters · internal webhook mock"]
      Argo["Argo CD Core"]
    end
  end
  User -->|"HTTP / HTTPS"| LB
  Admin -->|"API :6443"| LB
  LB -->|"API TLS passthrough"| CP
  LB -->|"PROXY v2 · worker NodePorts"| Ingress
  Ingress -->|"HTTP · trusted forwarding headers"| NG
  NG -->|"FastCGI :9000"| PHP
  Ingress -->|"Grafana host"| Obs
  NG -.->|"private exporter metrics"| Obs
  PHP -.->|"private exporter metrics"| Obs
  Ingress -.->|"request / latency metrics"| Obs
  Git -->|"HTTPS fetch"| Argo
  Argo -->|"reconcile via API"| CP
```

A request reaches the dedicated load balancer first. HAProxy keeps the original
source in PROXY v2, Traefik terminates TLS, and NGINX accepts forwarding headers
only from the trusted ingress network. PHP returns the resulting client IP.
NGINX and PHP are separate Deployments and Services; each normally has one pod
per worker. HPAs can raise each tier from two to three replicas. PDBs preserve
one healthy replica during permitted voluntary eviction, not arbitrary outages.

Monitoring observes ingress requests, connections, PHP workers, and Kubernetes
resources. Grafana has TLS and a generated admin login. Prometheus, Alertmanager,
and the notification mock have no public ingress. Their local data is ephemeral.
Argo CD reconciles the application chart from Git; infrastructure and platform
installation stay with the existing scripts. See [GitOps ownership](gitops.md).

This is application redundancy on one host, not infrastructure HA. There is one
LB, one control plane, one etcd member, and one physical failure domain. Keepalived
was omitted by agreement. The application can continue during some API outages,
but scheduling, reconciliation, and autoscaling cannot be relied on then.
