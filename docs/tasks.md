# Task checklist

Checked items are complete. Runtime results will be recorded only after testing.

## Infrastructure

- [x] Choose the host and topology: local machine, two LBs, one control plane, two workers.
- [x] Choose Vagrant/libvirt, Ubuntu 24.04, Kubespray, and Calico.
- [x] Add read-only host checks.
- [x] Allocate 10 GiB RAM (control plane increased to 3 GiB during GitOps setup); choose 192.168.56.0/24 for the lab and 192.168.121.0/24 for management (no current route overlap).
- [x] Add host setup and five VM definitions; pin Vagrant, its libvirt plugin, and the Ubuntu box.
- [x] Run host setup and verify all five VMs boot and accept SSH.
- [x] Pin Kubespray, Kubernetes, containerd, etcd, and Calico versions.
- [x] Add Kubespray inventory, API HAProxy playbook, and provisioning commands.
- [x] Automate VM creation and Kubernetes provisioning, including swap, kernel, sysctl, and cgroups.
- [x] Configure HAProxy for API and application traffic.
- [x] Configure and verify VM firewall rules, SSH restrictions, and unused-service hardening through Ansible.
- [x] Configure two Keepalived/HAProxy servers and document the remaining single-control-plane/physical-host limits.
- [x] Verify API readiness, DNS, Service routing, and cross-node networking.
- [ ] Verify a clean rebuild and complete repeated provisioning.

## Application and delivery

- [x] Build PHP-FPM and NGINX images; justify PHP-FPM pool settings.
- [x] Package separate NGINX and PHP-FPM workloads in a Helm chart.
- [x] Add separate health/readiness endpoints and internal NGINX/PHP-FPM status endpoints.
- [x] Add startup/liveness/readiness probes, resource settings, HPA, and PDBs.
- [x] Restrict traffic with NetworkPolicies and test allowed/denied paths.
- [x] Add ingress and TLS; verify real client IPs through the full proxy chain.
- [x] Configure GitOps and CI chart/manifest validation (local checks and hosted Validate run passed).

## Observability and exercises

- [x] Install Metrics Server with verified TLS and confirm HPA resource metrics.
- [x] Install Prometheus, Grafana, Alertmanager, and NGINX/PHP-FPM exporters.
- [x] Provide request/error rates, latency percentiles, upstream timings, connections, pool saturation, restarts, resource usage, and scaling events.
- [x] Protect Grafana with TLS and authentication.
- [x] Export dashboard JSON and screenshots.
- [x] Define two SLOs, error budgets, burn-rate/saturation/crash-loop alerts, and a notification receiver.
- [x] Run two failure scenarios and record detection, recovery, and SLO impact.
- [x] Write a postmortem for each, with timeline, cause, impact, owners, and follow-up dates.

## Operational handover

- [x] Write the alerting strategy, runbook, architecture diagram, and walkthrough.
- [x] Draft the one-page stakeholder summary and four-stage status updates.
- [x] Document on-call rotation, escalation, and handover.
- [x] Measure capacity for 3x traffic; document scaling and cost trade-offs.
- [x] Document security, secrets, payments data handling, and etcd/application backup and recovery.
- [x] Describe change review, rollback, and one first-month reliability practice.
- [x] Finish README access instructions and caveats.
- [ ] Verify a clean rebuild and a backup restore drill.
