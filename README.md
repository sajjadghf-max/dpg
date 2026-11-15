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
etcd each have a single instance. Keepalived alone cannot provide failover without
a second load balancer. We can test application recovery, but cannot claim
control-plane or load-balancer HA.

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

## Current state

VM definitions and host setup are prepared. Host installation and VM boot have
not been verified yet. Kubernetes and HAProxy provisioning come next.

Remaining work is tracked in [docs/tasks.md](docs/tasks.md).
