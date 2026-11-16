# Automation

Run from the repository root after `source .venv/bin/activate`.
`ansible/main.yml` is the single entry point. Vagrant creates the VMs;
Kubespray installs Kubernetes; the project roles configure and verify the lab.
Argo CD owns the application after bootstrap.

## Layout

```text
ansible/main.yml                 plays, host groups and execution order
ansible/group_vars/all.yml      shared paths, chart pins and phase default
ansible/group_vars/localhost.yml controller Python interpreter
ansible/roles/                  tasks, templates, handlers and role defaults
ansible/requirements.yml        collection version pins
inventory/lab/                  VM inventory and Kubernetes settings
ansible.cfg                     role lookup and SSH settings
```

Shared settings live in group variables. Role-specific defaults and handlers stay
with the role that uses them; unrelated services do not share restart handlers.
The pinned Ansible package already includes the collections in requirements.yml.

## Commands

Prepare the controller with `bash scripts/prepare-kubespray.sh` first. Its pinned
Kubespray checkout is needed even for syntax checks because main imports the
upstream plays. Host setup requires sudo; create the Vagrant VMs before cluster
installation (see the README).

```sh
ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml -e lab_phase=host --ask-become-pass
ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml -e lab_phase=cluster
ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml -e lab_phase=images
ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml -e lab_phase=platform
ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml -e lab_phase=verify
```

`lab_phase=all` runs cluster, images and platform in order; host setup and
verification remain separate. With no phase specified, main runs verification.
`lab_phase=hardening` reapplies VM hardening alone.
`lab_phase=loadbalancer` configures CA trust, both HAProxy/Keepalived instances
and host firewall rules without rerunning Kubernetes installation.
`lab_phase=failover` briefly stops Keepalived, then HAProxy, on the preferred LB,
checks standby API/HTTPS access and restores each service in an `always` block.
Run it only when a short LB interruption is acceptable.

`lab_phase=preflight` checks host tools and access without changing configuration.
`lab_phase=imagecheck` runs isolated Docker endpoint/security/recovery checks and
removes the containers/network. Build the images first; do not run concurrently.

For CI validation, use its pinned Python environment; no cluster access is needed:

```sh
bash scripts/setup-validation.sh
source .state/validation-venv/bin/activate
ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml -e lab_phase=validate
```

Within platform or verification, `--tags` selects `metrics` (platform only),
`app`, `ingress`, `monitoring`, `observability` or `gitops`.
Verification also supports `cluster` and `hardening` tags. For example:

```sh
ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml -e lab_phase=platform --tags ingress
ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml -e lab_phase=verify --tags ingress
```

Before first GitOps bootstrap, commit/push the generated image names from
`.state/app-images.json` into `gitops/application.yaml`, as explained in
[GitOps](gitops.md). Ansible preserves live Argo-managed app settings and skips
its Helm release. It does not commit or push.

Optional `LAB_CA_FILE` supplies VM CA trust during the cluster phase;
`GIT_CA_FILE` supplies Argo CD's Git trust during the platform phase. CA files and
credentials stay outside Git. TLS verification remains enabled.

## Repeat runs and checks

Charts, manifests and the Helm diff plugin have pinned checksums. Helm uses
atomic rollback and bounded readiness waits. Keys and the Grafana password are
preserved. Leaf certificates renew within seven days of expiry; an invalid CA
stops execution instead of silently replacing client trust.

Image archives use content-derived names and workers import missing images only.
CSR approval validates node identity and waits for bootstrap certificates when
absent on disk. Verification creates temporary resources and cleans them in
`always` blocks. Run one verification at a time.

The remaining scripts handle only the Python/Ansible bootstrap, custom CRD
schema validation and timed capacity/incident exercises. The CSR identity helper
belongs to the platform role. See [scripts](../scripts/README.md).
