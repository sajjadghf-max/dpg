#!/usr/bin/env bash
set -euo pipefail

network="dpg-app-check-$$"
php="dpg-php-check-$$"
nginx="dpg-nginx-check-$$"
# shellcheck disable=SC2317 # Invoked by the EXIT trap.
cleanup() {
  docker rm -f "$nginx" "$php" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create "$network" >/dev/null
docker run -d --name "$php" --network "$network" --network-alias php-fpm \
  --memory=256m --memory-swap=256m --cpus=0.5 --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=16m --cap-drop=ALL \
  --security-opt=no-new-privileges dpg-php:lab >/dev/null
docker run -d --name "$nginx" --network "$network" \
  --memory=64m --memory-swap=64m --cpus=0.25 \
  --read-only --tmpfs /tmp:rw,noexec,nosuid,size=16m --cap-drop=ALL \
  --security-opt=no-new-privileges dpg-nginx:lab >/dev/null
url=http://127.0.0.1:8080
fetch() { docker exec "$nginx" wget -qO- -T 3 "$url/$1"; }
http_status() {
  docker exec "$nginx" sh -c 'wget -S -O /dev/null -T 3 "$1" 2>&1 || true' sh "$url/$1" \
    | awk '/HTTP\/1.1/ {print $2; exit}'
}
for _ in {1..20}; do
  if fetch readyz >/dev/null 2>&1; then break; fi
  sleep 1
done
[[ "$(fetch healthz)" == ok ]]
[[ "$(fetch readyz)" == ready ]]
response=$(docker exec "$nginx" wget -qO- -T 3 --header='X-Forwarded-For: 203.0.113.99' \
  --header='X-Real-IP: 203.0.113.99' "$url/")
python3 - "$response" <<'PY'
import ipaddress, json, sys
response = json.loads(sys.argv[1])
assert response['service'] == 'digipay-sre-lab'
ipaddress.ip_address(response['client_ip'])
assert response['client_ip'] != '203.0.113.99', 'Untrusted forwarded header accepted'
print('PASS: JSON response; untrusted client-IP headers ignored')
PY
for path in nginx-status fpm-status missing; do
  [[ "$(http_status "$path")" == 404 ]]
done
docker exec "$nginx" wget -qO- http://127.0.0.1:8081/nginx-status | grep 'Active connections:'
docker exec "$nginx" wget -qO- http://127.0.0.1:8081/fpm-status | grep 'pool:'
printf 'PASS: health/readiness and internal status endpoints\n'
docker exec "$php" php -l /var/www/html/index.php
docker exec "$php" php -l /usr/local/bin/ready.php
docker exec "$php" php /usr/local/bin/ready.php
docker exec "$php" php-fpm -t
docker exec "$nginx" nginx -t
docker exec "$php" ps -o pid,rss,args
docker stats --no-stream --format '{{.Name}}: {{.MemUsage}}' "$php" "$nginx"

docker stop --time 3 "$php" >/dev/null
[[ "$(fetch healthz)" == ok ]]
status=$(http_status readyz)
[[ "$status" == 502 || "$status" == 504 ]]
printf 'PASS: PHP failure breaks readiness while NGINX health stays up\n'
docker start "$php" >/dev/null
for _ in {1..20}; do
  if [[ "$(fetch readyz 2>/dev/null)" == ready ]]; then
    printf 'PASS: readiness recovers after PHP restart\n'
    exit 0
  fi
  sleep 1
done
docker logs "$php"
docker logs "$nginx"
exit 1
