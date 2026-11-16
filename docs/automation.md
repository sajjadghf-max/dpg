# Automation

Ansible configures the VMs and Kubernetes platform. Argo CD owns application
reconciliation after bootstrap. Run commands from the repository root.

## Entry points

| Playbook | Purpose |
| --- | --- |
| `ansible/setup-host.yml` | Host packages, Vagrant, libvirt and user groups; requires sudo |
| `ansible/cluster.yml` | SSH check, optional VM CA, HAProxy, pinned Kubespray and hardening |
| `ansible/images.yml` | Build content-tagged images, export once and import missing worker images |
| `ansible/platform.yml` | Metrics Server, app bootstrap, TLS/Traefik, monitoring, SLOs and Argo CD |
| `ansible/verify.yml` | Hardening, DNS/networking, HTTPS/IP, NetworkPolicies, metrics, GitOps and SLO/notification checks |

Bootstrap the controller and host as shown in the README. After creating the VMs:

```sh
bash scripts/prepare-kubespray.sh
.venv/bin/ansible-playbook -i inventory/lab/hosts.yml ansible/cluster.yml
.venv/bin/ansible-playbook -i inventory/lab/hosts.yml ansible/images.yml
.venv/bin/ansible-playbook -i inventory/lab/hosts.yml ansible/platform.yml
.venv/bin/ansible-playbook -i inventory/lab/hosts.yml ansible/verify.yml
```

Before first GitOps bootstrap, copy the generated image names from
`.state/app-images.json` into `gitops/application.yaml` and commit/push them, as
explained in [GitOps](gitops.md). Later image updates follow the same Git review
process. Ansible preserves live Argo-managed app settings and skips its Helm
release. It does not commit or push on your behalf.

Platform tags: `metrics`, `app`, `ingress`, `monitoring`, `observability`, `gitops`.
Verification tags: `hardening`, `cluster`, `ingress`, `app`, `monitoring`, `gitops`,
`observability`. Run the complete playbooks in order for first setup; tags are for
maintenance after dependencies exist.

For a local network that requires an additional trusted CA, set `LAB_CA_FILE` to
the controller-side PEM path when running `cluster.yml`. Set `GIT_CA_FILE` for
Argo CD's GitHub trust when running `platform.yml`. These inputs are optional,
remain outside Git, and never disable TLS verification.

## Repeat runs and failures

Charts and upstream manifests have pinned versions and SHA-256 checksums.
[Helm modules](https://docs.ansible.com/projects/ansible/latest/collections/kubernetes/core/helm_module.html)
use a project-local, checksum-pinned Helm diff 3.12.5 plugin. Server-side dry-run allows
charts to look up existing certificates rather than report new random TLS data on
every run. Failed Helm upgrades use atomic rollback; readiness waits are bounded.
Certificate keys and the Grafana password are preserved. Leaf certificates renew
within seven days of expiry. An expired/mismatched CA stops the playbook rather
than silently replacing client trust.

Argo CD CRDs apply sequentially to limit API memory pressure. Serving CSR approval
keeps the inventory identity/SAN/signature validation in a small Python helper.
It waits for bootstrap certificates only when absent on disk, because issued
CSR history is garbage-collected by Kubernetes.
Image archives use content-derived names; present worker images are not imported
again. Verification uses temporary pods/Jobs/rules with `always` cleanup. The
GitOps drift check restores its harmless comment even if reconciliation fails.

Installation tasks should be unchanged on a second run. Verification deliberately
creates and removes test resources, so its changed count is expected. Run one
verification at a time; reserved test names are checked before the larger tests.

## Remaining scripts

The ten remaining scripts support controller bootstrap/preflight, CI tooling and
schema validation, Docker integration checks, CSR identity validation, and timed
capacity/incident exercises. There are no shell installation or routine cluster
check wrappers. CI's Argo manifest preparation script is used only for rendering
and validation, not deployment.

## Validation of this migration

On 2026-11-16, the full platform playbook completed against the existing lab; a
repeat run reported zero changes on the controller and all three Kubernetes
nodes. Image build/export/import also reported zero changes on repeat. The full
verification playbook passed, including promtool fixtures and firing/resolved
webhook delivery. Local chart/manifest validation and Ansible syntax checks pass.

Host setup and the full Kubespray entry point were syntax-checked, not rerun with
host package changes or a clean cluster rebuild. The archive was explicitly imported on both existing workers with
`-e force_image_import=true`, then a normal run verified the zero-change skip path.
A fresh-worker rebuild remains unverified. The existing single-LB/control-plane limitations remain.
