#!/usr/bin/env bash
set -euo pipefail
umask 077
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
export KUBECONFIG="$project_dir/.state/artifacts/admin.conf"
kubectl="$project_dir/.state/artifacts/kubectl"
bash scripts/prepare-argocd.sh
"$kubectl" create namespace argocd --dry-run=client -o yaml | "$kubectl" apply -f -
.venv/bin/python - <<'PYCODE'
import pathlib,yaml
objects=list(yaml.safe_load_all(pathlib.Path('.state/argocd/install.yaml').read_text()))
for d in objects:
    if d['kind']=='CustomResourceDefinition':
        pathlib.Path('.state/argocd/'+d['metadata']['name']+'.yaml').write_text(yaml.safe_dump(d))
pathlib.Path('.state/argocd/workloads.yaml').write_text(yaml.safe_dump_all(d for d in objects if d['kind']!='CustomResourceDefinition'))
PYCODE
for name in applications.argoproj.io appprojects.argoproj.io applicationsets.argoproj.io; do
  "$kubectl" apply --server-side -f ".state/argocd/$name.yaml"
  "$kubectl" wait --for=condition=Established "crd/$name" --timeout=120s
done
"$kubectl" -n argocd apply --server-side -f .state/argocd/workloads.yaml
# Optional company CA, kept local. Scope trust to GitHub rather than disabling TLS.
if [[ -n "${GIT_CA_FILE:-}" ]]; then
  "$kubectl" -n argocd create configmap argocd-tls-certs-cm \
    --from-file="github.com=$GIT_CA_FILE" --dry-run=client -o yaml | "$kubectl" apply -f -
fi
"$kubectl" -n argocd rollout status deployment/argocd-redis --timeout=600s
"$kubectl" -n argocd rollout status deployment/argocd-repo-server --timeout=600s
"$kubectl" -n argocd rollout status statefulset/argocd-application-controller --timeout=600s
"$kubectl" apply -f gitops/project.yaml -f gitops/application.yaml
bash scripts/check-gitops.sh
