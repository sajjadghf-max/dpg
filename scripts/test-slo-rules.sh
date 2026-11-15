#!/usr/bin/env bash
set -euo pipefail
umask 077
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
export KUBECONFIG="$project_dir/.state/artifacts/admin.conf"
kubectl="$project_dir/.state/artifacts/kubectl"
mkdir -p .state/monitoring
.venv/bin/python - <<'PY'
import pathlib,yaml
rules=yaml.safe_load(pathlib.Path('charts/dpg-observability/files/rules.yaml').read_text())['spec']
pathlib.Path('.state/monitoring/slo-rules.yaml').write_text(yaml.safe_dump(rules))
PY
pod=prometheus-monitoring-kube-prometheus-prometheus-0
image=$("$kubectl" -n monitoring get pod "$pod" -o jsonpath='{.spec.containers[?(@.name=="prometheus")].image}')
node=$("$kubectl" -n monitoring get pod "$pod" -o jsonpath='{.spec.nodeName}')
cleanup() {
  "$kubectl" -n monitoring delete job dpg-slo-test --ignore-not-found >/dev/null
  "$kubectl" -n monitoring delete configmap dpg-slo-test --ignore-not-found >/dev/null
}
trap cleanup EXIT
cleanup
"$kubectl" -n monitoring create configmap dpg-slo-test \
  --from-file=rules.yaml=.state/monitoring/slo-rules.yaml --from-file=tests/slo.test.yaml
"$kubectl" apply -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: dpg-slo-test
  namespace: monitoring
spec:
  backoffLimit: 0
  activeDeadlineSeconds: 120
  template:
    spec:
      nodeName: $node
      automountServiceAccountToken: false
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        fsGroup: 65534
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: test
          image: $image
          imagePullPolicy: IfNotPresent
          command: [/bin/promtool, test, rules, /test/slo.test.yaml]
          resources:
            requests: {cpu: 10m, memory: 32Mi}
            limits: {cpu: 200m, memory: 128Mi}
          securityContext:
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
            capabilities: {drop: [ALL]}
          volumeMounts:
            - {name: rules, mountPath: /test, readOnly: true}
            - {name: scratch, mountPath: /tmp}
      volumes:
        - name: rules
          configMap: {name: dpg-slo-test}
        - name: scratch
          emptyDir: {sizeLimit: 128Mi}
YAML
if ! "$kubectl" -n monitoring wait --for=condition=complete job/dpg-slo-test --timeout=120s; then
  "$kubectl" -n monitoring logs job/dpg-slo-test
  exit 1
fi
"$kubectl" -n monitoring logs job/dpg-slo-test
