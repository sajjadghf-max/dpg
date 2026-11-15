#!/usr/bin/env bash
set -euo pipefail
umask 077
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
export KUBECONFIG="$project_dir/.state/artifacts/admin.conf"
kubectl="$project_dir/.state/artifacts/kubectl"
mkdir -p .state/gitops
wait_synced() {
  for _ in {1..90}; do
    "$kubectl" -n argocd get application app -o json > .state/gitops/application-status.json
    if python3 - <<'PY'
import json,sys
v=json.load(open('.state/gitops/application-status.json'))['status']
sys.exit(not (v.get('sync',{}).get('status')=='Synced' and v.get('health',{}).get('status')=='Healthy'))
PY
    then return; fi
    sleep 2
  done
  "$kubectl" -n argocd get application app -o yaml
  return 1
}
wait_synced
python3 - <<'PY'
import json
v=json.load(open('.state/gitops/application-status.json'))
print('OK application Synced and Healthy at Git revision '+v['status']['sync']['revision'])
PY
# A comment is valid NGINX config and has no behavior change; test self-healing.
"$kubectl" -n dpg-app get configmap app-trusted-proxies -o json > .state/gitops/configmap-before.json
python3 - <<'PY'
import json,pathlib
v=json.load(open('.state/gitops/configmap-before.json'))['data']
key='trusted-proxies.conf'
v[key]+='\n# temporary GitOps drift check\n'
pathlib.Path('.state/gitops/drift-patch.json').write_text(json.dumps({'data':v}))
PY
restore_config() {
  python3 - <<'PY'
import json,pathlib
v=json.load(open('.state/gitops/configmap-before.json'))
pathlib.Path('.state/gitops/restore-patch.json').write_text(json.dumps({'data':v['data']}))
PY
  "$kubectl" -n dpg-app patch configmap app-trusted-proxies --type=merge \
    --patch-file=.state/gitops/restore-patch.json >/dev/null
}
trap restore_config EXIT
"$kubectl" -n dpg-app patch configmap app-trusted-proxies --type=merge --patch-file=.state/gitops/drift-patch.json
"$kubectl" -n argocd annotate application app argocd.argoproj.io/refresh=hard --overwrite
for attempt in {1..90}; do
  "$kubectl" -n dpg-app get configmap app-trusted-proxies -o json > .state/gitops/configmap-after.json
  if python3 - <<'PY'
import json,sys
before=json.load(open('.state/gitops/configmap-before.json'))['data']
after=json.load(open('.state/gitops/configmap-after.json'))['data']
sys.exit(before!=after)
PY
  then
    echo 'OK Argo CD automatically corrected harmless ConfigMap drift'
    trap - EXIT
    break
  fi
  if [[ "$attempt" == 90 ]]; then echo 'Argo CD did not repair drift in 180 seconds' >&2; exit 1; fi
  sleep 2
done
wait_synced
bash scripts/check-ingress.sh
