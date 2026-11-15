# Task checklist

Checked items are complete. Runtime results will be recorded only after testing.

## Infrastructure

- [x] Choose the host and topology: local machine, one LB, one control plane, two workers.
- [x] Choose Vagrant/libvirt, Ubuntu 24.04, Kubespray, and Calico.
- [x] Add read-only host checks.
- [x] Allocate 8.5 GiB RAM; choose 192.168.56.0/24 for the lab and 192.168.121.0/24 for management (no current route overlap).
- [x] Add host setup and four VM definitions; pin Vagrant, its libvirt plugin, and the Ubuntu box.
- [x] Run host setup and verify all four VMs boot and accept SSH.
- [x] Pin Kubespray, Kubernetes, containerd, etcd, and Calico versions.
- [x] Add Kubespray inventory, API HAProxy playbook, and provisioning commands.
- [x] Automate VM creation and Kubernetes provisioning, including swap, kernel, sysctl, and cgroups.
- [ ] Configure HAProxy, firewall rules, SSH restrictions, and unused-service hardening.
- [x] Omit Keepalived as agreed; document the departure and single-LB limitation.
- [x] Verify API readiness, DNS, Service routing, and cross-node networking.
- [ ] Verify a clean rebuild and complete repeated provisioning.

## Application and delivery

- [x] Build PHP-FPM and NGINX images; justify PHP-FPM pool settings.
- [ ] Package separate NGINX and PHP-FPM workloads in a Helm chart.
- [x] Add separate health/readiness endpoints and internal NGINX/PHP-FPM status endpoints.
- [ ] Add startup/liveness/readiness probes, resource settings, HPA, and PDBs.
- [ ] Restrict traffic with NetworkPolicies and test allowed/denied paths.
- [ ] Add ingress and TLS; verify real client IPs through the full proxy chain.
- [ ] Configure GitOps and CI chart/manifest validation.

## Observability and exercises

- [ ] Install Prometheus, Grafana, Alertmanager, NGINX and PHP-FPM exporters, and HPA metrics support.
- [ ] Provide request/error rates, latency percentiles, upstream timings, connections, pool saturation, restarts, resource usage, and scaling events.
- [ ] Protect Grafana with TLS and authentication; export dashboard JSON and screenshots.
- [ ] Define two SLOs, error budgets, burn-rate/saturation/crash-loop alerts, and a notification receiver.
- [ ] Run two failure scenarios and record detection, recovery, and SLO impact.
- [ ] Write a postmortem for each, with timeline, cause, impact, owners, and follow-up dates.

## Operational handover

- [ ] Write the alerting strategy, runbook, architecture diagram, and walkthrough.
- [ ] Draft the one-page stakeholder summary and four-stage status updates.
- [ ] Document on-call rotation, escalation, and handover.
- [ ] Measure capacity for 3x traffic; document scaling and cost trade-offs.
- [ ] Document security, secrets, payments data handling, and etcd/application backup and recovery.
- [ ] Describe change review, rollback, and one first-month reliability practice.
- [ ] Verify a clean rebuild and finish README access instructions and caveats.
