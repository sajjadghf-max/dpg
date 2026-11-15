#!/usr/bin/env bash
set -euo pipefail
umask 077
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
export KUBECONFIG="$project_dir/.state/artifacts/admin.conf"
kubectl="$project_dir/.state/artifacts/kubectl"
mkdir -p .state/charts .state/monitoring .state/tls
chart=.state/charts/kube-prometheus-stack-93.3.0.tgz
if [[ ! -f "$chart" ]]; then
  curl --fail --location --output "$chart" \
    https://github.com/prometheus-community/helm-charts/releases/download/kube-prometheus-stack-93.3.0/kube-prometheus-stack-93.3.0.tgz
fi
printf '%s\n' "2d40be0b19523cb4fed25b4db09e3ca35f471a06872baf7048b916a62c7af0eb  $chart" | sha256sum -c -
[[ -f .state/tls/ca.key ]] || { echo 'Run scripts/install-ingress.sh first.' >&2; exit 1; }
"$kubectl" create namespace monitoring --dry-run=client -o yaml | "$kubectl" apply -f -
if [[ ! -f .state/monitoring/admin-password ]]; then
  openssl rand -hex 24 | tr -d '\n' > .state/monitoring/admin-password
fi
printf admin > .state/monitoring/admin-user
"$kubectl" -n monitoring create secret generic grafana-admin \
  --from-file=admin-user=.state/monitoring/admin-user \
  --from-file=admin-password=.state/monitoring/admin-password \
  --dry-run=client -o yaml | "$kubectl" apply -f -
if [[ ! -f .state/tls/grafana.crt ]] || ! openssl x509 -checkend 604800 -noout -in .state/tls/grafana.crt; then
  openssl req -newkey rsa:2048 -noenc -keyout .state/tls/grafana.key \
    -out .state/tls/grafana.csr -subj '/CN=grafana.dpg.test'
  cat > .state/tls/grafana.ext <<'CERT'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:grafana.dpg.test
CERT
  openssl x509 -req -in .state/tls/grafana.csr -CA .state/tls/ca.crt \
    -CAkey .state/tls/ca.key -CAcreateserial -out .state/tls/grafana.crt \
    -days 90 -sha256 -extfile .state/tls/grafana.ext
fi
"$kubectl" -n monitoring create secret tls grafana-tls --cert=.state/tls/grafana.crt \
  --key=.state/tls/grafana.key --dry-run=client -o yaml | "$kubectl" apply -f -
alerting_values=()
if helm status dpg-observability --namespace monitoring >/dev/null 2>&1; then
  alerting_values=(--values platform/monitoring/alerting-values.yaml)
fi
helm upgrade --install monitoring "$chart" --namespace monitoring \
  --values platform/monitoring/values.yaml "${alerting_values[@]}" --wait --timeout 1200s
"$kubectl" -n monitoring rollout status statefulset/prometheus-monitoring-kube-prometheus-prometheus --timeout=180s
"$kubectl" -n monitoring rollout status statefulset/alertmanager-monitoring-kube-prometheus-alertmanager --timeout=180s
helm upgrade traefik .state/charts/traefik-42.4.0.tgz --namespace ingress-system \
  --values platform/traefik/values.yaml --values platform/monitoring/traefik-values.yaml \
  --skip-crds --wait --timeout 180s
"$kubectl" apply -f platform/traefik/networkpolicy.yaml
helm get values app --namespace dpg-app -o json | python3 -c '
import json,sys
v=json.load(sys.stdin)
print(json.dumps({k:{"image":v[k]["image"]} for k in ("php","nginx")}))
' > .state/app-images.json
helm upgrade app charts/dpg-app --namespace dpg-app --reset-values \
  --values .state/app-images.json --set monitoring.enabled=true --wait --timeout 300s
bash scripts/check-monitoring.sh
