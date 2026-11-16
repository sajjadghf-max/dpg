#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
export PATH="$project_dir/.state/bin:$PATH"
python="$project_dir/.state/validation-venv/bin/python"
mkdir -p .state/validation .state/charts .state/validation/schema-cache
export KUBECTL=kubectl
bash scripts/prepare-argocd.sh
chart=.state/charts/kube-prometheus-stack-93.3.0.tgz
if [[ ! -f "$chart" ]]; then
  curl --fail --location --retry 2 --output "$chart" \
    https://github.com/prometheus-community/helm-charts/releases/download/kube-prometheus-stack-93.3.0/kube-prometheus-stack-93.3.0.tgz
fi
printf '%s\n' "2d40be0b19523cb4fed25b4db09e3ca35f471a06872baf7048b916a62c7af0eb  $chart" | sha256sum -c -
"$python" - <<'PY'
import json,pathlib,yaml
v=yaml.safe_load(pathlib.Path('gitops/application.yaml').read_text())
pathlib.Path('.state/validation/app-values.json').write_text(json.dumps(v['spec']['source']['helm']['valuesObject']))
json.loads(pathlib.Path('charts/dpg-observability/files/dashboard.json').read_text())
PY
helm lint charts/dpg-app
helm lint charts/dpg-app -f .state/validation/app-values.json
helm lint charts/dpg-observability --set receiver.image=dpg-php:validation
helm template app charts/dpg-app -n dpg-app --kube-version 1.36.4 > .state/validation/app-default.yaml
helm template app charts/dpg-app -n dpg-app --kube-version 1.36.4 \
  -f .state/validation/app-values.json > .state/validation/app-gitops.yaml
helm template dpg-observability charts/dpg-observability -n monitoring \
  --set receiver.image=dpg-php:validation > .state/validation/observability.yaml
files=(.state/validation/app-default.yaml .state/validation/app-gitops.yaml \
  .state/validation/observability.yaml .state/argocd/install.yaml \
  gitops/project.yaml gitops/application.yaml platform/traefik/networkpolicy.yaml)
# Custom resources are checked below against their exact bundled CRDs.
kubeconform -strict -summary -kubernetes-version 1.36.4 \
  -cache .state/validation/schema-cache \
  -skip Application,AppProject,PrometheusRule,ServiceMonitor,CustomResourceDefinition "${files[@]}"
"$python" scripts/validate-custom-resources.py "${files[@]}"
for script in scripts/*.sh; do bash -n "$script"; done
"$python" - <<'PY'
import ast,pathlib
for p in pathlib.Path('scripts').glob('*.py'):ast.parse(p.read_text(),filename=str(p))
print('OK shell and Python syntax')
PY
# The main playbook imports the real upstream Kubespray plays at parse time.
if [[ ! -d vendor/kubespray ]]; then
  mkdir -p vendor
  git clone --depth 1 --branch v2.32.0 https://github.com/kubernetes-sigs/kubespray.git vendor/kubespray
fi
[[ "$(git -C vendor/kubespray rev-parse HEAD)" == 9751ea6f63244e433a7a6263d9ecf381e57bb8e9 ]]
.state/validation-venv/bin/ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml --syntax-check
