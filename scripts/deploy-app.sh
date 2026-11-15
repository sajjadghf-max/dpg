#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
export KUBECONFIG="$project_dir/.state/artifacts/admin.conf"
export ANSIBLE_CONFIG="$project_dir/ansible.cfg"

helm lint charts/dpg-app
if .state/artifacts/kubectl -n argocd get application app >/dev/null 2>&1; then
  echo 'Argo CD owns app. Use scripts/import-app-images.sh and the GitOps update steps in docs/gitops.md.' >&2
  exit 1
fi
bash scripts/import-app-images.sh
image_settings=(--values .state/app-images.json)
if .state/artifacts/kubectl get prometheus monitoring-kube-prometheus-prometheus -n monitoring >/dev/null 2>&1; then
  image_settings+=(--set monitoring.enabled=true)
fi
helm upgrade --install app charts/dpg-app --namespace dpg-app --create-namespace \
  "${image_settings[@]}" --wait --timeout 180s
helm test app --namespace dpg-app --logs --timeout 120s
.state/artifacts/kubectl -n dpg-app wait --for=condition=ScalingActive hpa --all --timeout=90s
.state/artifacts/kubectl -n dpg-app get pods -o wide
.state/artifacts/kubectl -n dpg-app get hpa,pdb
