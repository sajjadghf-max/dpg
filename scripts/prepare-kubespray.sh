#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"

kubespray_tag=v2.32.0
kubespray_commit=9751ea6f63244e433a7a6263d9ecf381e57bb8e9
mkdir -p vendor
if [[ ! -d vendor/kubespray ]]; then
  git clone --depth 1 --branch "$kubespray_tag" \
    https://github.com/kubernetes-sigs/kubespray.git vendor/kubespray
fi
if [[ "$(git -C vendor/kubespray rev-parse HEAD)" != "$kubespray_commit" ]]; then
  printf 'vendor/kubespray must be at %s (%s).\n' "$kubespray_tag" "$kubespray_commit" >&2
  exit 1
fi
if [[ -n "$(git -C vendor/kubespray status --porcelain)" ]]; then
  printf 'vendor/kubespray has local changes; use a clean pinned checkout.\n' >&2
  exit 1
fi

if [[ ! -x .venv/bin/python ]]; then
  python3 -m venv .venv
fi
.venv/bin/python -m pip install -r vendor/kubespray/requirements.txt -r ansible/requirements.txt
.venv/bin/ansible --version
