#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$project_dir"
# Binding the source makes the expected client IP explicit for this local lab.
client_ip=192.168.56.1
curl_args=(--noproxy '*' --interface "$client_ip" --connect-timeout 5 --max-time 15
  --cacert .state/tls/ca.crt --resolve app.dpg.test:443:192.168.56.10)
for _ in {1..10}; do
  if curl "${curl_args[@]}" --fail --silent https://app.dpg.test/readyz >/dev/null; then break; fi
  sleep 2
done
for _ in {1..6}; do
  response=$(curl "${curl_args[@]}" --fail --silent --show-error \
    -H 'X-Forwarded-For: 203.0.113.99, 198.51.100.99' \
    -H 'X-Real-IP: 203.0.113.99' -H 'Forwarded: for=203.0.113.99' https://app.dpg.test/)
  python3 - "$response" "$client_ip" <<'PY'
import json,sys
response=json.loads(sys.argv[1])
assert response['service']=='digipay-sre-lab'
assert response['client_ip']==sys.argv[2],response
print('PASS: verified HTTPS and real client IP:',response['client_ip'])
PY
done
[[ "$(curl "${curl_args[@]}" --fail --silent https://app.dpg.test/healthz)" == ok ]]
[[ "$(curl "${curl_args[@]}" --fail --silent https://app.dpg.test/readyz)" == ready ]]
redirect=$(curl --noproxy '*' --interface "$client_ip" --connect-timeout 5 --max-time 15 \
  --resolve app.dpg.test:80:192.168.56.10 --silent --show-error --dump-header - \
  --output /dev/null http://app.dpg.test/)
redirect=${redirect//$'\r'/}
grep -Eq '^HTTP/[0-9.]+ (301|308) ' <<< "$redirect"
grep -Eiq '^location: https://app\.dpg\.test/$' <<< "$redirect"
for path in nginx-status fpm-status; do
  [[ "$(curl "${curl_args[@]}" --silent --output /dev/null --write-out '%{http_code}' \
    "https://app.dpg.test/$path")" == 404 ]]
done
printf 'PASS: HTTP redirect, health/readiness, and public status-path blocking\n'
for node in 192.168.56.21 192.168.56.22; do
  if curl --noproxy '*' --interface "$client_ip" --connect-timeout 2 --max-time 3 \
    --silent --output /dev/null "http://$node:30080/"; then
    printf 'FAIL: direct NodePort bypass on %s\n' "$node" >&2
    exit 1
  fi
done
printf 'PASS: direct NodePort access from the host is blocked\n'
