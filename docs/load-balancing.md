# Load-balancer failover

Two dedicated 512 MiB VMs run HAProxy and Keepalived:

| Node | Address | VRRP priority |
| --- | --- | --- |
| lb | 192.168.56.13 | 150 |
| lb2 | 192.168.56.14 | 100 |

Clients use the floating IP `192.168.56.10`, not either node address. API TLS
certificates and app/Grafana URLs keep their existing addresses. Both HAProxy
instances bind the VIP with `ip_nonlocal_bind=1`; only the current VIP owner
receives client traffic. Backends remain cp1:6443 and both worker ingress ports.
PROXY v2 carries the original client IP. Traefik and firewall rules trust both
physical LB addresses, since backend traffic uses the active node's source IP.

Keepalived uses unicast VRRP on eth1, peer-restricted firewall rules and process
tracking. Both start in BACKUP state; priority elects lb. If HAProxy disappears,
that instance enters FAULT and releases the VIP. Recovery preempts the standby.
Configuration is validated before service changes.
See the [Keepalived configuration reference](https://www.keepalived.org/documentation/keepalived-conf/).

```sh
source .venv/bin/activate
ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml -e lab_phase=loadbalancer
# Briefly disrupts one LB; services are restored even when assertions fail.
ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml -e lab_phase=failover
```

This is LB redundancy within one host. The API server and etcd still each have
one member. All VMs share power, storage and the virtual bridge. VRRP partitions
can cause two owners; there is no quorum/fencing. Process tracking detects a
missing HAProxy process, not every possible stuck process or failed backend.
Failover does not preserve TCP sessions and is not a zero-downtime guarantee.
A production design needs independent failure domains and multiple control-plane
and etcd members.

## Verification on 2026-11-16

Stopping Keepalived and stopping HAProxy were tested separately on lb. In each
case lb2 acquired the VIP, lb released it, and authenticated API readiness plus
verified application HTTPS/client IP checks passed through lb2. Restoring each
service returned the VIP to lb, with no duplicate owner after convergence.
These were service-failure tests, not a physical-host outage or a TCP-session
continuity measurement. A repeated configuration run reported zero changes on
all five VMs.
