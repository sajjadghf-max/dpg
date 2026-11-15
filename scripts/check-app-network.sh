#!/usr/bin/env bash
set -euo pipefail
umask 077
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
export KUBECONFIG="$project_dir/.state/artifacts/admin.conf"
kubectl="$project_dir/.state/artifacts/kubectl"
if ! "$kubectl" -n argocd get application app -o json > .state/app-gitops.json 2>/dev/null; then
  helm test app --namespace dpg-app --logs --timeout 120s
  exit
fi
python3 - <<'PY'
import json,pathlib
v=json.load(open('.state/app-gitops.json'))['spec']['source']['helm']['valuesObject']
pathlib.Path('.state/app-network-values.json').write_text(json.dumps(v))
PY
helm template app charts/dpg-app --namespace dpg-app --kube-version 1.36.4 \
  --values .state/app-network-values.json --show-only templates/tests/network.yaml > .state/app-network-tests.yaml
"$kubectl" -n dpg-app delete pod app-test-allowed app-test-denied --ignore-not-found --wait=true --timeout=30s
"$kubectl" -n dpg-app create -f .state/app-network-tests.yaml
result=0
"$kubectl" -n dpg-app wait --for=jsonpath='{.status.phase}'=Succeeded \
  pod/app-test-allowed pod/app-test-denied --timeout=120s || result=$?
for pod in app-test-allowed app-test-denied; do "$kubectl" -n dpg-app logs "$pod"; done
exit "$result"
