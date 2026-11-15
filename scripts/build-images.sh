#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for component in php nginx; do
  docker build --tag "dpg-$component:lab" "$project_dir/app/$component"
done
