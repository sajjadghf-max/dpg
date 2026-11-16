# VM hardening

Apply and verify from the checkout:

```sh
.venv/bin/ansible-playbook -i inventory/lab/hosts.yml ansible/hardening.yml
.venv/bin/ansible-playbook -i inventory/lab/hosts.yml ansible/check-hardening.yml
bash scripts/check-cluster.sh
bash scripts/check-monitoring.sh
```

The provisioning script runs hardening after Kubespray. The playbook processes one
VM at a time and verifies a fresh SSH connection after applying changes.

## Rules

SSH requires the existing Vagrant key, permits only `vagrant`, and rejects root,
password, and keyboard-interactive login. SSH is reachable only from the host's
lab and management addresses (`192.168.56.1`, `192.168.121.1`). Vagrant's sudo
access remains necessary for provisioning. SSH TCP forwarding remains available
for Vagrant tooling; agent and X11 forwarding are disabled.

The `inet dpg_host` nftables table defaults host input to drop. It allows loopback,
established replies, ICMP, management DHCP, and these lab paths:

| Destination | Allowed source and traffic |
| --- | --- |
| LB | Lab subnet: TCP 80, 443, 6443; pod subnet: TCP 6443 |
| Nodes | Three node IPs: VXLAN UDP 4789 |
| Nodes | Nodes/pods: API 6443, kubelet 10250, node exporter 9100, DNS metrics 9253/9254/9353 |
| Nodes | Nodes/pods to Service CIDR `10.233.0.0/18`: IPVS Service traffic |
| Nodes | LB only: ingress NodePorts 30080/30443 |
| Nodes | Pods to NodeLocal DNS `169.254.25.10`: TCP/UDP 53 |

Port allowances do not start services or replace endpoint authentication. The LB
is deliberately local-lab only; accessing it from another subnet needs an explicit
rule change. IPv6 has no service allowances, apart from loopback, established
traffic and ICMPv6.

There are no custom output or forwarding chains. Kubernetes/Calico still enforce
forwarding and NetworkPolicies. IPVS Service VIPs traverse INPUT, so their explicit
allowance is necessary. The playbook replaces only its own table atomically and
never runs `flush ruleset`. A dedicated enabled systemd unit loads it at boot;
the distribution's global nftables configuration is not used. See
[Ubuntu's nftables documentation](https://documentation.ubuntu.com/security/security-features/network/firewall/nftables/)
for how independent base chains interact.

Unused ModemManager, VMware guest services, and apport crash-report services/units
are stopped, disabled and masked. Kubernetes services, time synchronization,
networking, AppArmor, logging, and package maintenance are retained.

## Recovery

For a rule mistake, use the Vagrant/libvirt console if SSH is unavailable. Remove
only this table, then correct the template and rerun Ansible:

```sh
sudo systemctl disable dpg-host-firewall.service
sudo nft delete table inet dpg_host
```

To undo the SSH policy, remove `/etc/ssh/sshd_config.d/00-dpg-hardening.conf` from
the console, run `sudo sshd -t`, then `sudo systemctl reload ssh`. Do not flush the
whole firewall or remove Kubernetes rules. Console recovery and boot persistence
are documented but have not been tested by rebooting the lab in this phase.

## Verification

Verified on 2026-11-16: fresh key-based SSH to all four VMs; effective SSH settings;
host access to node ports 9100/10250 blocked; worker-to-control-plane SSH blocked;
node-to-LB API access; DNS, Service routing and cross-worker pod traffic; HTTPS,
client IP preservation, Grafana authentication, application NetworkPolicies and
all 28 Prometheus targets. A second hardening run reports zero changes.

HAProxy logs show HTTPS requests alternating between worker1 and worker2. API
traffic uses its separate backend to cp1. There is still only one LB and one
control plane, so this configuration does not provide infrastructure failover.
