# Security and recovery

## Current controls and gaps

Application containers run as non-root with read-only roots, dropped capabilities,
no service-account token, resource limits, and a small writable `/tmp`. The app
namespace denies traffic by default and admits the documented ingress, FastCGI,
DNS, test, and metrics paths. TLS and forwarded client IPs are tested end to end.
Images, tools, and charts are version/digest/checksum pinned.

This is not a production security assessment. VM firewall rules, SSH restrictions,
and unused-service hardening were explicitly deferred. Platform namespaces are
not all under default-deny policy. The Argo controller retains upstream cluster
permissions even though its AppProject limits this application's destinations and
kinds. CI does not currently scan images for vulnerabilities. Review these gaps
before exposing the lab or adding workloads with sensitive data.

The admin kubeconfig, Vagrant keys, TLS CA/private keys, and Grafana password stay
in ignored `.state/` or `.vagrant/`, with private file permissions. Git ignore is
not a secrets manager or encryption. Do not commit credentials, put them in image
layers, pass them in shell history, or include them in incident logs. For a real
service, use workload identity and a dedicated secret manager, scoped short-lived
credentials, rotation, access auditing, and a documented break-glass path.

No API-server encryption-provider argument was found in the live manifest on
2026-11-16. Treat Kubernetes Secrets and etcd snapshots as unencrypted sensitive
content: base64 is not encryption. Kubernetes documents the
[default storage behavior and encryption configuration](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/).
A production deployment should configure and verify encryption at rest, preferably
with managed key custody, while retaining RBAC and encrypted backups. Keep key
recovery material separately from the data backup.

## Payments data

Use synthetic data only here. A real integration should avoid sending raw card
data to this app where provider tokens can serve the use case. Do not log PANs,
authorization headers, card verification codes, or request bodies. Current NGINX
logs omit bodies/query strings but include client IP and path: restrict access
and define retention for those too. A new route can leak identifiers in a path.

PCI SSC identifies card verification values as sensitive authentication data and
[prohibits retaining them after authorization](https://www.pcisecuritystandards.org/faqs/1280/).
Treat that as a design constraint, not a claim that this lab is PCI compliant;
production scope and applicable requirements need a formal security review.

## Backup policy — proposed, not running

| Item | Proposed protection |
| --- | --- |
| etcd | Daily authenticated snapshot and before risky cluster changes; retain seven daily and four weekly encrypted off-host copies. |
| Cluster identity/config | Protect `/etc/kubernetes`, `/etc/ssl/etcd`, `/etc/etcd.env`, and `etcd.service`; preserve certificates and any encryption keys needed to read snapshots. |
| Host-local secrets | Back up the lab TLS CA/key and Grafana password securely, separately from Git; retain the cluster admin credential only where operationally required. |
| App | Source/chart/config in Git; retain reproducible images or a protected registry. This app has no database or persistent user data. |
| Monitoring | Dashboards/rules in Git. Metrics, Grafana UI changes, silences, and webhook logs are deliberately ephemeral; no recovery promise for that data. |

Proposed RPO is 24 hours and RTO one hour for this lab, pending a restore drill.
Neither is measured or guaranteed. A copy on cp1 alone is not protection against
host/disk loss. Choose an approved encrypted off-host destination and restricted
backup identity before scheduling uploads; none has been configured or used.

## etcd snapshot procedure

Run as root on cp1 during an approved backup operation. These exact tool and
certificate paths exist, and authenticated endpoint health passed on 2026-11-16.
The snapshot command itself has **not** been executed in this phase.

```sh
umask 077
install -d -m 0700 /var/backups/dpg-etcd
snapshot="/var/backups/dpg-etcd/$(date -u +%Y%m%dT%H%M%SZ).db"
/usr/local/bin/etcdctl \
  --endpoints=https://192.168.56.11:2379 \
  --cacert=/etc/ssl/etcd/ssl/ca.pem \
  --cert=/etc/ssl/etcd/ssl/admin-cp1.pem \
  --key=/etc/ssl/etcd/ssl/admin-cp1-key.pem snapshot save "$snapshot"
/usr/local/bin/etcdutl snapshot status "$snapshot" --write-out=table
sha256sum "$snapshot" > "$snapshot.sha256"
```

Use the live snapshot API, not a casual copy of a running database. Check the
snapshot status/hash, encrypt it for the approved destination, verify the remote
copy, and record timestamp, revision, size, and retention expiry. Do not print
snapshot contents. See the [etcd 3.6 recovery guidance](https://etcd.io/docs/v3.6/op-guide/recovery/).

## Offline restore plan — not tested or executed

This applies only to this lab's single member, `etcd1`, with its current addresses.
Restoring rolls cluster state back; coordinate maintenance and preserve the
failed data/config for investigation before changing it.

1. Verify the snapshot hash/status and the required certificates/keys. Stop API
   writes by moving the API/controller/scheduler static manifests outside the
   kubelet's watched directory and wait for those containers to stop. Stop the
   `etcd` systemd unit. Do not assume stopping kubelet stops existing containers.
2. Restore into a **new** data directory, leaving `/var/lib/etcd` untouched:

   ```sh
   /usr/local/bin/etcdutl snapshot restore /secure/path/snapshot.db \
     --name=etcd1 --data-dir=/var/lib/etcd-restored \
     --initial-cluster=etcd1=https://192.168.56.11:2380 \
     --initial-advertise-peer-urls=https://192.168.56.11:2380 \
     --initial-cluster-token="dpg-recovery-$(date -u +%Y%m%dT%H%M%SZ)" \
     --bump-revision=1000000000 --mark-compacted
   ```

3. Check directory ownership/permissions for the root-run etcd service, point
   `ETCD_DATA_DIR` in `/etc/etcd.env` at the restored directory, and record the
   restored member/bootstrap settings. Start etcd and check authenticated health.
   Restore the static manifests, then check API readiness, nodes, DNS, Argo,
   certificates, and the application with the [runbook](runbook.md).
4. Reconcile reviewed Git state carefully: it may intentionally be newer than the
   snapshot. Verify Secrets, image availability, endpoints, and a functional HTTPS
   request before ending maintenance. Record actual data loss and recovery time.

The revision bump and compaction invalidate stale Kubernetes watch history. The
example bump is generous for this small lab, not a universal production value;
choose it against write volume and snapshot age. Never restore over a live data
directory or test this plan against the only working cluster. A separate restore
drill and clean rebuild remain outstanding.
