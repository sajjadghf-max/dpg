#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
mkdir -p .state/bin .state/downloads
if [[ ! -x .state/bin/helm ]]; then
  if command -v helm >/dev/null && [[ "$(helm version --template '{{.Version}}')" == v3.21.3 ]]; then
    ln -s "$(command -v helm)" .state/bin/helm
  else
    curl --fail --location --retry 2 --output .state/downloads/helm.tar.gz https://get.helm.sh/helm-v3.21.3-linux-amd64.tar.gz
    printf '%s\n' '15e041a93a590dce8100f39385cd98c84a765c9e36aeeb9e2dc6ff9e4769e2e0  .state/downloads/helm.tar.gz' | sha256sum -c -
    tar -xzf .state/downloads/helm.tar.gz -C .state/downloads linux-amd64/helm
    cp .state/downloads/linux-amd64/helm .state/bin/helm
  fi
fi
if [[ ! -x .state/bin/kubectl ]]; then
  if [[ -x .state/artifacts/kubectl ]]; then
    cp .state/artifacts/kubectl .state/bin/kubectl
  else
    curl --fail --location --retry 2 --output .state/bin/kubectl https://dl.k8s.io/release/v1.36.4/bin/linux/amd64/kubectl
  fi
  printf '%s\n' '8b8f088da2dab964f853b38464033b1be15ede2839eca751482357c45abdd05a  .state/bin/kubectl' | sha256sum -c -
  chmod +x .state/bin/kubectl
fi
if [[ ! -x .state/bin/kubeconform ]]; then
  archive=.state/downloads/kubeconform-linux-amd64.tar.gz
  if [[ ! -f "$archive" ]]; then
    curl --fail --location --retry 2 --output "$archive" https://github.com/yannh/kubeconform/releases/download/v0.8.0/kubeconform-linux-amd64.tar.gz
  fi
  printf '%s\n' "9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883  $archive" | sha256sum -c -
  tar -xzf "$archive" -C .state/bin kubeconform
fi
if [[ ! -x .state/validation-venv/bin/python ]]; then
  python3 -m venv .state/validation-venv
fi
.state/validation-venv/bin/pip install --disable-pip-version-check -r requirements-validation.txt
