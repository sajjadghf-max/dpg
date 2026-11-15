#!/usr/bin/env bash
set -euo pipefail
umask 077
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
export KUBECONFIG="$project_dir/.state/artifacts/admin.conf"
export ANSIBLE_CONFIG="$project_dir/ansible.cfg"
kubectl="$project_dir/.state/artifacts/kubectl"
mkdir -p .state/charts .state/tls
chart=.state/charts/traefik-42.4.0.tgz
if [[ ! -f "$chart" ]]; then
  curl --fail --location --output "$chart" \
    https://traefik.github.io/charts/traefik/traefik-42.4.0.tgz
fi
printf '%s\n' "eebfaff03c0f210b6424898ccf7583c9d40291cb9b14644ef3e369be6caeb0f0  $chart" | sha256sum -c -
if [[ ! -f .state/tls/ca.crt ]]; then
  openssl req -x509 -newkey rsa:2048 -noenc -sha256 -days 365 \
    -keyout .state/tls/ca.key -out .state/tls/ca.crt -subj '/CN=dpg lab CA' \
    -addext 'basicConstraints=critical,CA:TRUE' \
    -addext 'keyUsage=critical,keyCertSign,cRLSign'
fi
if [[ ! -f .state/tls/app.crt ]] || ! openssl x509 -checkend 604800 -noout -in .state/tls/app.crt; then
  openssl req -newkey rsa:2048 -noenc -keyout .state/tls/app.key \
    -out .state/tls/app.csr -subj '/CN=app.dpg.test'
  cat > .state/tls/server.ext <<'CERT'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:app.dpg.test
CERT
  openssl x509 -req -in .state/tls/app.csr -CA .state/tls/ca.crt \
    -CAkey .state/tls/ca.key -CAcreateserial -out .state/tls/app.crt \
    -days 90 -sha256 -extfile .state/tls/server.ext
fi
"$kubectl" -n dpg-app create secret tls app-tls --cert=.state/tls/app.crt \
  --key=.state/tls/app.key --dry-run=client -o yaml | "$kubectl" apply -f -
helm upgrade --install traefik "$chart" --namespace ingress-system --create-namespace \
  --values platform/traefik/values.yaml --skip-crds --wait --timeout 180s
"$kubectl" apply -f platform/traefik/networkpolicy.yaml
# Keep the content-based image tags while loading the chart's new defaults.
helm get values app --namespace dpg-app -o json | python3 -c '
import json,sys
v=json.load(sys.stdin)
print(json.dumps({k:{"image":v[k]["image"]} for k in ("php","nginx")}))
' > .state/app-images.json
helm upgrade app charts/dpg-app --namespace dpg-app --reset-values \
  --values .state/app-images.json --wait --timeout 180s
.venv/bin/ansible-playbook -i inventory/lab/hosts.yml ansible/load-balancer.yml
bash scripts/check-ingress.sh
