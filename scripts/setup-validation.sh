#!/usr/bin/env bash
# Bootstrap Python/Ansible only. The validation role installs other pinned tools.
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"

python3 -m venv .state/validation-venv
.state/validation-venv/bin/python -m pip install --disable-pip-version-check -r requirements-validation.txt

# main.yml statically imports this pinned checkout, including for validation.
if [[ ! -d vendor/kubespray ]]; then
  mkdir -p vendor
  git clone --depth 1 --branch v2.32.0 https://github.com/kubernetes-sigs/kubespray.git vendor/kubespray
fi
[[ "$(git -C vendor/kubespray rev-parse HEAD)" == 9751ea6f63244e433a7a6263d9ecf381e57bb8e9 ]]
