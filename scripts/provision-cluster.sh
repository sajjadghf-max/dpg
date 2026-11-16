#!/usr/bin/env bash
# Run after all four Vagrant VMs are booted.
set -euo pipefail
umask 077

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
export ANSIBLE_CONFIG="$project_dir/ansible.cfg"

bash scripts/preflight.sh
bash scripts/prepare-kubespray.sh
mkdir -p .state
inventory=inventory/lab/hosts.yml

# Check guest access before changing any VM. Vagrant supplies the SSH keys.
.venv/bin/ansible -i "$inventory" all --become -m ansible.builtin.ping
.venv/bin/ansible-playbook -vvv -i "$inventory" ansible/load-balancer.yml
.venv/bin/ansible-playbook -vvv -i "$inventory" --become --limit k8s_cluster \
  vendor/kubespray/cluster.yml

.venv/bin/ansible-playbook -i "$inventory" ansible/hardening.yml

export KUBECONFIG="$project_dir/.state/artifacts/admin.conf"
kubectl="$project_dir/.state/artifacts/kubectl"
"$kubectl" get --raw=/readyz
"$kubectl" wait --for=condition=Ready nodes --all --timeout=300s
"$kubectl" -n kube-system rollout status daemonset/calico-node --timeout=300s
"$kubectl" -n kube-system rollout status deployment/coredns --timeout=300s
"$kubectl" get nodes -o wide
"$kubectl" get pods --all-namespaces
