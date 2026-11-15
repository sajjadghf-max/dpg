# Application images

The app returns JSON with its service name and client IP. It has no database or
external dependencies. PHP reads `REMOTE_ADDR` supplied by NGINX; it does not
parse client-supplied forwarding headers. Trusted ingress proxies will be
configured with the Helm deployment, then tested through the full LB path.

Build and check locally with Docker:

```sh
bash scripts/build-images.sh
bash scripts/check-images.sh
```

The images are `dpg-php:lab` and `dpg-nginx:lab`. Base images are PHP
8.4.27 FPM and NGINX 1.30.6 on Alpine, pinned by digest and downloaded through
Arvan's mirror. The checks run both containers as non-root, with read-only root
filesystems, a writable `/tmp`, dropped capabilities, and memory/CPU limits.
Temporary containers and their network are removed afterward.

| Port | Path | Purpose |
| --- | --- | --- |
| NGINX 8080 | `/` | PHP JSON response |
| NGINX 8080 | `/healthz` | NGINX health, independent of PHP |
| NGINX 8080 | `/readyz` | PHP-FPM ping, independent of application code |
| NGINX 8081 | `/nginx-status` | NGINX stub_status for the exporter |
| NGINX 8081 | `/fpm-status` | PHP-FPM pool status for the exporter |

The future public Service must expose only port 8080. Port 8081 and PHP's
FastCGI ports 9000/9001 are for internal traffic. NetworkPolicies and probes
will be added with the Helm chart. NGINX logs JSON with status and request/upstream
timing, without query strings or request bodies.

## PHP-FPM pool

The initial PHP container budget is 256 MiB and 0.5 CPU. Reserve 64 MiB for the
master, status worker, and overhead. Allow 48 MiB per application worker: a
32 MiB PHP heap limit plus an assumed 16 MiB of native overhead. This gives
`floor((256 - 64) / 48) = 4` children. It is a planning estimate to check under
load, not a proven memory bound or throughput claim.

`dynamic` starts two workers and keeps one to two spare, avoiding a cold start
without keeping all four idle. `pm.max_requests=500` periodically recycles
workers. The listen backlog is 128, so queueing remains bounded. Requests get
a slow-log threshold of 5 seconds and terminate after 10 seconds; NGINX waits
12 seconds for FastCGI. The separate status listener keeps pool metrics
accessible when application workers are occupied. These directives follow the
[PHP-FPM configuration reference](https://www.php.net/manual/en/install.fpm.configuration.php).

## Verified

Configuration syntax, JSON responses, ignored spoofed forwarding headers,
internal status endpoints, and public status-path blocking passed. Stopping
PHP makes readiness fail while NGINX health stays up; restarting PHP restores
readiness. The small check used roughly 10–26 MiB for PHP and 2.5 MiB for NGINX.
These are Docker-network checks; Kubernetes ingress, full client-IP forwarding,
and load capacity still need testing.
