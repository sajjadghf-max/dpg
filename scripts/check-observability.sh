#!/usr/bin/env bash
set -euo pipefail
umask 077
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
export KUBECONFIG="$project_dir/.state/artifacts/admin.conf"
kubectl="$project_dir/.state/artifacts/kubectl"
mkdir -p .state/monitoring
"$kubectl" -n monitoring port-forward service/monitoring-kube-prometheus-prometheus 19092:9090 > .state/monitoring/observability-forward.log 2>&1 &
prom_forward=$!
"$kubectl" -n monitoring port-forward service/monitoring-grafana 19093:80 > .state/monitoring/grafana-forward.log 2>&1 &
grafana_forward=$!
cleanup() {
  "$kubectl" -n monitoring delete prometheusrule dpg-notification-test --ignore-not-found >/dev/null
  kill "$prom_forward" "$grafana_forward" 2>/dev/null || true
  wait "$prom_forward" "$grafana_forward" 2>/dev/null || true
}
trap cleanup EXIT
test_alertname="DpgNotificationTest$(date +%s)"
export test_alertname
# Exercise the complete Prometheus -> Alertmanager -> receiver path, without an outage.
"$kubectl" apply -f - <<YAML
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: dpg-notification-test
  namespace: monitoring
  labels: {release: monitoring}
spec:
  groups:
    - name: dpg.notification-test
      rules:
        - alert: $test_alertname
          expr: vector(1)
          labels: {scope: dpg, severity: info}
          annotations:
            summary: Synthetic notification delivery test; no application failure
YAML
python3 - <<'PY'
import base64,json,os,pathlib,time,urllib.request,urllib.parse
root='http://127.0.0.1:19092'
def get(path):
    return json.load(urllib.request.urlopen(root+path,timeout=10))
for attempt in range(60):
    try:
        groups=get('/api/v1/rules')['data']['groups']
        group=next(g for g in groups if g['name']=='dpg.slo')
        errors=[r.get('lastError','unhealthy') for r in group['rules'] if r.get('health')!='ok']
        if errors: raise RuntimeError(str(errors))
        test=next(g for g in groups if g['name']=='dpg.notification-test')
        if test['rules'][0]['name']==os.environ['test_alertname'] and test['rules'][0]['state']=='firing': break
    except (OSError,StopIteration,RuntimeError): pass
    time.sleep(3)
else: raise SystemExit('Rules failed to become healthy and test alert did not fire')
print('OK SLO recording/alert rules are healthy; synthetic alert is firing')
password=pathlib.Path('.state/monitoring/admin-password').read_text().strip()
request=urllib.request.Request('http://127.0.0.1:19093/api/dashboards/uid/dpg-application')
request.add_header('Authorization','Basic '+base64.b64encode(('admin:'+password).encode()).decode())
for attempt in range(30):
    try:
        dashboard=json.load(urllib.request.urlopen(request,timeout=10))['dashboard']
        assert len(dashboard['panels'])==14
        break
    except (OSError,AssertionError): time.sleep(2)
else: raise SystemExit('Provisioned dashboard is missing')
print('OK provisioned Grafana dashboard has all 14 panels')
for panel in dashboard['panels']:
    for target in panel['targets']:
        result=get('/api/v1/query?'+urllib.parse.urlencode({'query':target['expr']}))
        if result['status']!='success': raise SystemExit('Invalid dashboard query: '+panel['title'])
print('OK all dashboard queries are accepted by Prometheus')
PY
for attempt in $(seq 1 60); do
  if "$kubectl" -n monitoring logs deployment/dpg-alert-receiver --since=5m | \
    grep -Fq "\"status\":\"firing\",\"alertname\":\"$test_alertname\""; then
    echo 'OK Prometheus -> Alertmanager -> webhook notification delivered'
    break
  fi
  if [[ "$attempt" == 60 ]]; then
    echo 'Notification was not received within 180 seconds' >&2
    exit 1
  fi
  sleep 3
done
"$kubectl" -n monitoring patch prometheusrule dpg-notification-test --type=json \
  -p='[{"op":"replace","path":"/spec/groups/0/rules/0/expr","value":"vector(0) > 0"}]'
for attempt in $(seq 1 60); do
  if "$kubectl" -n monitoring logs deployment/dpg-alert-receiver --since=5m | \
    grep -Fq "\"status\":\"resolved\",\"alertname\":\"$test_alertname\""; then
    echo 'OK resolved notification delivered'
    break
  fi
  if [[ "$attempt" == 60 ]]; then
    echo 'Resolved notification was not received within 180 seconds' >&2
    exit 1
  fi
  sleep 3
done
