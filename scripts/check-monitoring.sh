#!/usr/bin/env bash
set -euo pipefail
umask 077
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
export KUBECONFIG="$project_dir/.state/artifacts/admin.conf"
kubectl="$project_dir/.state/artifacts/kubectl"
"$kubectl" -n monitoring get pods
"$kubectl" -n monitoring port-forward service/monitoring-kube-prometheus-prometheus 19090:9090 \
  > .state/monitoring/port-forward.log 2>&1 &
forward_pid=$!
trap 'kill "$forward_pid" 2>/dev/null || true; wait "$forward_pid" 2>/dev/null || true' EXIT
python3 - <<'PY'
import json,time,urllib.request,urllib.parse
base='http://127.0.0.1:19090/api/v1/'
def get(path):
    with urllib.request.urlopen(base+path,timeout=5) as response:
        return json.load(response)['data']
checks={
    'NGINX exporter reaches NGINX': 'nginx_up{namespace="dpg-app"}',
    'PHP exporter reaches FPM': 'phpfpm_up{namespace="dpg-app"}',
    'Traefik replicas scraped': 'up{namespace="ingress-system"}',
    'Kubelet TLS scrapes': 'up{job="kubelet"}',
}
for attempt in range(60):
    try:
        results={name:get('query?'+urllib.parse.urlencode({'query':query}))['result']
                 for name,query in checks.items()}
        targets=get('targets?state=active')['activeTargets']
        down=[t for t in targets if t['health']!='up']
        if all(len(rows)>=2 and all(float(r['value'][1])==1 for r in rows)
               for rows in results.values()) and not down:
            break
    except (OSError,KeyError):
        pass
    time.sleep(3)
else:
    for target in locals().get('down',[]):
        print(target['labels'].get('job'),target['scrapeUrl'],target.get('lastError'))
    raise SystemExit('Monitoring targets did not become healthy within 180 seconds')
for name,rows in results.items():
    print(f'OK {name}: {len(rows)} healthy series')
print(f'OK all {len(targets)} Prometheus targets healthy')
PY
# Keep the password out of process arguments and command output.
python3 - <<'PY'
from pathlib import Path
password=Path('.state/monitoring/admin-password').read_text().strip()
Path('.state/monitoring/netrc').write_text('machine grafana.dpg.test login admin password '+password+'\n')
PY
curl_args=(--silent --show-error --noproxy '*' --interface 192.168.56.1
  --connect-timeout 5 --max-time 15 --cacert .state/tls/ca.crt
  --resolve grafana.dpg.test:443:192.168.56.10)
code=$(curl "${curl_args[@]}" --output /dev/null --write-out '%{http_code}' https://grafana.dpg.test/api/user)
[[ "$code" == 401 ]] || { echo "Expected unauthenticated 401, got $code" >&2; exit 1; }
curl "${curl_args[@]}" --fail --netrc-file .state/monitoring/netrc \
  https://grafana.dpg.test/api/user | python3 -c '
import json,sys
v=json.load(sys.stdin)
assert v["login"]=="admin" and v["isGrafanaAdmin"], "Grafana admin login failed"
print("OK Grafana HTTPS, certificate verification, and admin authentication")
'
bash scripts/check-ingress.sh
bash scripts/check-app-network.sh
