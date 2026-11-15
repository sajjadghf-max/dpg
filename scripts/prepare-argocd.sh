#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
mkdir -p .state/argocd
base=.state/argocd/core-install-v3.6.1.yaml
if [[ ! -f "$base" ]]; then
  curl --fail --location --retry 2 --output "$base" \
    https://raw.githubusercontent.com/argoproj/argo-cd/v3.6.1/manifests/core-install.yaml
fi
printf '%s\n' "0b38189d6e1fd76ef5c3db10355026c48a02020d82bf21a1a1b5ab16dffe4f3c  $base" | sha256sum -c -
cp platform/argocd/kustomization.yaml .state/argocd/kustomization.yaml
"${KUBECTL:-.state/artifacts/kubectl}" kustomize .state/argocd > .state/argocd/install.yaml
