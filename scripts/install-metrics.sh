#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
export KUBECONFIG="$project_dir/.state/artifacts/admin.conf"
export ANSIBLE_CONFIG="$project_dir/ansible.cfg"
kubectl="$project_dir/.state/artifacts/kubectl"

.venv/bin/ansible-playbook -i inventory/lab/hosts.yml ansible/kubelet-serving.yml
sleep 2
.venv/bin/python scripts/approve-kubelet-csrs.py
mkdir -p .state/charts
chart=.state/charts/metrics-server-3.14.0.tgz
if [[ ! -f "$chart" ]]; then
  curl --fail --location --output "$chart" \
    https://github.com/kubernetes-sigs/metrics-server/releases/download/metrics-server-helm-chart-3.14.0/metrics-server-3.14.0.tgz
fi
printf '%s\n' "c2ca1185c01e6e7f53dd1b7d131f0c9b3fa50e003ed068b784563a1b5a3422a1  $chart" | sha256sum -c -
helm upgrade --install metrics-server "$chart" --namespace kube-system \
  --values platform/metrics-server/values.yaml --wait --timeout 180s
"$kubectl" wait --for=condition=Available apiservice/v1beta1.metrics.k8s.io --timeout=120s
"$kubectl" top nodes
