# Digipay SRE lab

Vagrant creates four local VMs. Kubespray installs Kubernetes and its prerequisites.

| VM | IP | RAM | vCPUs | Intended role |
| --- | --- | --- | --- | --- |
| lb | 192.168.56.10 | 512 MiB | 1 | HAProxy for the API and ingress |
| cp1 | 192.168.56.11 | 2 GiB | 2 | Control plane and etcd |
| worker1 | 192.168.56.21 | 3 GiB | 2 | Application and platform workloads |
| worker2 | 192.168.56.22 | 3 GiB | 2 | Application and platform workloads |

The lab uses libvirt/KVM, Ubuntu 24.04 guests, containerd, and Calico.
Kubespray uses kubeadm internally, so it fits the brief's kubeadm requirement.
See the [upstream explanation](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/getting_started/comparisons.md#kubespray-vs-kubeadm).

## Limits

This is a small lab on one physical host. The load balancer, control plane, and
etcd each have a single instance. Keepalived is deliberately omitted because
there is no second load balancer. This departs from the brief's Keepalived
requirement. We can test application recovery, but cannot claim control-plane
or load-balancer HA.

## Host setup

Run on Ubuntu 24.04 amd64 as your normal user:

```sh
bash scripts/setup-host.sh
```

This installs QEMU/libvirt and build dependencies from Ubuntu, Vagrant 2.4.9
from HashiCorp's package server with a pinned SHA-256 checksum, and the
vagrant-libvirt 0.12.2 plugin. It enables libvirtd and adds your user to the
libvirt and kvm groups. Sudo prompts for your password in the terminal.

Log out and back in, then check the host:

```sh
bash scripts/preflight.sh
```

The preflight script is read-only and exits with status 1 for missing
prerequisites. Setup follows the [Vagrant installation guidance](https://developer.hashicorp.com/vagrant/install)
and [libvirt plugin requirements](https://vagrant-libvirt.github.io/vagrant-libvirt/installation.html).

## Create the VMs

The four VMs reserve 8.5 GiB RAM in total. Free at least 10 GiB of available host
memory before starting all four, allowing some room for virtualization overhead.
This is an initial budget; workload capacity still needs measurement.

```sh
vagrant validate
vagrant up --provider=libvirt --no-parallel
vagrant status
vagrant ssh cp1
```

The box is `bento/ubuntu-24.04`, pinned to `202508.03.0` for libvirt/amd64.
The lab network is isolated on `192.168.56.0/24`; the separate management network
uses NAT on `192.168.121.0/24` for SSH and outbound downloads. Neither overlaps
the host routes checked during setup. Check again if VPN routes change.

Use `vagrant halt` to stop the VMs and release their memory.

## Provision Kubernetes

Once all four VMs are running:

```sh
bash scripts/provision-cluster.sh
```

This checks SSH access, configures HAProxy, runs Kubespray, and checks API,
node, Calico, and CoreDNS readiness. Re-run the same command after an interrupted
provisioning attempt.

Kubespray is pinned to v2.32.0, commit
`9751ea6f63244e433a7a6263d9ecf381e57bb8e9`. The inventory pins Kubernetes 1.36.4,
containerd 2.3.5, etcd 3.6.14, and Calico 3.31.7 from that release's supported
versions. Kubespray handles swap, kernel/network prerequisites, and systemd
cgroup alignment. Calico uses VXLAN on the lab network.

HAProxy forwards API traffic at `192.168.56.10:6443` to `cp1`; TLS terminates at
the API server. Application HTTP/HTTPS forwarding will be added with ingress.

The generated admin kubeconfig and matching kubectl binary stay under the
Git-ignored `.state/artifacts/` directory:

```sh
export KUBECONFIG="$PWD/.state/artifacts/admin.conf"
.state/artifacts/kubectl get nodes -o wide
```

Check API readiness, Calico, CoreDNS, in-pod DNS, Service routing, and pod HTTP
traffic in both directions between the workers:

```sh
bash scripts/check-cluster.sh
```

The check creates two small BusyBox pods in a temporary namespace and removes
the namespace when it finishes. The image is pinned by digest.

SSH uses Vagrant's generated private keys and records first-seen host keys in
`.state/known_hosts`. After intentionally destroying and recreating a VM, remove
its old host key with `ssh-keygen -f .state/known_hosts -R <VM-IP>` before provisioning.

## Application images

```sh
bash scripts/build-images.sh
bash scripts/check-images.sh
```

See [application settings and checks](docs/application.md) for the endpoints,
PHP-FPM pool budget, and test results. Helm packaging is next.

## Current state

Host setup is complete. All four VMs booted and passed Ansible SSH/sudo checks.
The three Kubernetes nodes can reach the load balancer over the lab network.
HAProxy is active, its configuration passes validation, and it listens on
`192.168.56.10:6443`. Re-running its playbook reported zero changes.

Kubernetes 1.36.4 is running with all three nodes Ready, using containerd 2.3.5.
The API readiness check passes through HAProxy. Calico and CoreDNS are healthy.
DNS and Service HTTP checks pass from both workers, and direct pod HTTP works
in both directions across workers. The temporary check resources are removed.

Firewall and SSH hardening are still pending. A clean rebuild and a complete
repeat-provisioning check are also pending.

Remaining work is tracked in [docs/tasks.md](docs/tasks.md).
