#!/usr/bin/env bash
set -euo pipefail
umask 077
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
export ANSIBLE_CONFIG="$project_dir/ansible.cfg"
bash scripts/build-images.sh
mkdir -p .state/images
images=()
for component in php nginx; do
  image_id=$(docker image inspect "dpg-$component:lab" --format '{{.Id}}')
  image="dpg-$component:sha-${image_id#sha256:}"
  docker tag "dpg-$component:lab" "$image"
  images+=("$image")
done
docker image save --platform linux/amd64 --output .state/images/app.tar "${images[@]}"
.venv/bin/ansible-playbook -i inventory/lab/hosts.yml ansible/import-images.yml
python3 - "${images[@]}" <<'PYCODE'
import json,pathlib,sys
pathlib.Path('.state/app-images.json').write_text(json.dumps({k:{"image":v} for k,v in zip(('php','nginx'),sys.argv[1:])})+'\n')
PYCODE
printf 'Imported images; settings saved in .state/app-images.json\n'
