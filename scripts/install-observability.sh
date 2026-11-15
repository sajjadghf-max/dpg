#!/usr/bin/env bash
set -euo pipefail
umask 077
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
export KUBECONFIG="$project_dir/.state/artifacts/admin.conf"
php_image=$(helm get values app -n dpg-app -o json | python3 -c 'import json,sys; print(json.load(sys.stdin)["php"]["image"])')
helm upgrade --install dpg-observability charts/dpg-observability -n monitoring \
  --set-string "receiver.image=$php_image" --wait --timeout 180s
helm upgrade traefik .state/charts/traefik-42.4.0.tgz -n ingress-system \
  -f platform/traefik/values.yaml -f platform/monitoring/traefik-values.yaml \
  --skip-crds --wait --timeout 180s
helm upgrade monitoring .state/charts/kube-prometheus-stack-93.3.0.tgz -n monitoring \
  -f platform/monitoring/values.yaml -f platform/monitoring/alerting-values.yaml \
  --wait --timeout 300s
bash scripts/check-observability.sh
