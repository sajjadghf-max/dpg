#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
export KUBECONFIG="$project_dir/.state/artifacts/admin.conf"
export ANSIBLE_CONFIG="$project_dir/ansible.cfg"

helm lint charts/dpg-app
bash scripts/build-images.sh
mkdir -p .state/images
images=()
image_settings=()
for component in php nginx; do
  image_id=$(docker image inspect "dpg-$component:lab" --format '{{.Id}}')
  image="dpg-$component:sha-${image_id#sha256:}"
  docker tag "dpg-$component:lab" "$image"
  images+=("$image")
  image_settings+=(--set-string "$component.image=$image")
done
docker image save --platform linux/amd64 --output .state/images/app.tar "${images[@]}"
.venv/bin/ansible-playbook -i inventory/lab/hosts.yml ansible/import-images.yml
if .state/artifacts/kubectl get prometheus monitoring-kube-prometheus-prometheus -n monitoring >/dev/null 2>&1; then
  image_settings+=(--set monitoring.enabled=true)
fi
helm upgrade --install app charts/dpg-app --namespace dpg-app --create-namespace \
  "${image_settings[@]}" --wait --timeout 180s
helm test app --namespace dpg-app --logs --timeout 120s
.state/artifacts/kubectl -n dpg-app wait --for=condition=ScalingActive hpa --all --timeout=90s
.state/artifacts/kubectl -n dpg-app get pods -o wide
.state/artifacts/kubectl -n dpg-app get hpa,pdb
