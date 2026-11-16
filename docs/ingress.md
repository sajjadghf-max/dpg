# Ingress and TLS

`app.dpg.test` is served at `192.168.56.10` through:

```text
HAProxy :80/:443 -> Traefik NodePort :30080/:30443 -> NGINX Service :80 -> PHP-FPM :9000
```

TLS terminates at Traefik. Two controller replicas run across the workers.
The controller uses chart 42.4.0 and Traefik 3.7.18, with the chart checksum and
image digest pinned. We use standard Kubernetes Ingress resources. The brief
allows controller choice; community ingress-nginx was
[retired in March 2026](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/).

After the app is deployed:

```sh
.venv/bin/ansible-playbook -i inventory/lab/hosts.yml ansible/platform.yml --tags ingress
.venv/bin/ansible-playbook -i inventory/lab/hosts.yml ansible/verify.yml --tags ingress
curl --noproxy '*' --resolve app.dpg.test:443:192.168.56.10 \
  --cacert .state/tls/ca.crt https://app.dpg.test/
```

No DNS or system-trust changes are needed for these commands. The local CA is
valid for one year and the server certificate for 90 days. Re-running installation
renews the server certificate when fewer than seven days remain. Keys and
certificates stay in Git-ignored `.state/tls/`; Kubernetes holds the server key
in the `dpg-app/app-tls` Secret.

## Client IP and access

HAProxy sends PROXY protocol v2. Traefik trusts it only from `192.168.56.10`;
`externalTrafficPolicy: Local` preserves that peer address. Incoming client
forwarding headers are not trusted. Traefik sets the forwarded address from
the verified connection, and NGINX passes it to PHP as `REMOTE_ADDR`.

NGINX trusts the lab pod CIDR for forwarding headers, paired with NetworkPolicy:
only Traefik and the administrative Helm test client can reach its HTTP port.
The ingress controller accepts public-entrypoint traffic only from the LB VM.
The dashboard is disabled; no extra Gateway API or Traefik CRDs are installed.

## Verified

HTTPS certificate validation, HTTP-to-HTTPS redirect, health/readiness, and
client IP preservation passed through the full chain. Six requests with forged
`X-Forwarded-For`, `X-Real-IP`, and `Forwarded` headers still returned the actual
host lab address, `192.168.56.1`. Public status paths returned 404.
Direct NodePort access from the host was blocked, and the existing Helm
allowed/denied traffic tests still passed.
