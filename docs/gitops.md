# GitOps and CI

## Argo CD

Run this after the application, ingress, and monitoring setup. On a fresh build,
set the image tags in `gitops/application.yaml` from `.state/app-images.json`
before installing Argo; do not assume another build has the same image IDs.

```sh
ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml -e lab_phase=platform --tags gitops
ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml -e lab_phase=verify --tags gitops
```

Argo CD Core 3.6.1 runs the application controller, repo server, and Redis, each
with one replica and explicit resource limits. ApplicationSet is not running;
the upstream CRDs remain installed. There is no public Argo CD UI or API server.
Access uses Kubernetes RBAC and the existing local kubeconfig, as described in
[Argo CD Core](https://argo-cd.readthedocs.io/en/stable/operator-manual/core/).
This is a small, single-cluster lab installation, not an HA GitOps control plane.

The installer verifies the pinned upstream manifest checksum, applies CRDs one
at a time, waits for establishment, and applies the resource overlay. Container
images are pinned by digest and use the configured registry mirrors. Redis is
an ephemeral cache; desired configuration remains in Git.

For a network that signs GitHub HTTPS with a private CA, provide its trusted root
at install time. The certificate is copied into Argo's GitHub trust ConfigMap,
not committed or used to disable certificate verification:

```sh
GIT_CA_FILE=/path/to/trusted-root.pem ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml -e lab_phase=platform --tags gitops
```

`gitops/project.yaml` permits only this repository and namespaced application
resource kinds in `dpg-app`. `gitops/application.yaml` bootstraps the `app`
Application, using the chart at `charts/dpg-app` on `main`. It preserves the
imported immutable image tags, enables exporters, and skips Helm test hooks.
Argo polls Git, applies chart changes, repairs drift, and prunes its tracked
resources after applying replacements. It ignores Deployment replica counts
because the HPAs own them. TLS Secrets and platform components remain managed
by Ansible; they are not owned or pruned by this Application.

Traefik reports the actual LB address, `192.168.56.10`, in Ingress status so Argo
can assess Ingress health without bypassing its normal health check.

Argo uses Helm to render templates, not to operate a Helm release. The old `app`
release history remains as a bootstrap record and becomes stale after Argo
changes the workloads. Do not run `helm upgrade`, `rollback`, or `uninstall app`.
The platform phase skips the application Helm release once Argo owns it and
preserves its live application settings. Network checks render the current chart's
test pods instead of relying on stale Helm hook history.

## Changes and rollback

For chart changes, open a PR, pass validation, merge, and push to `main`. Argo
then reconciles the chart automatically. Revert the commit and push to roll back.
Inspect status with:

```sh
export KUBECONFIG="$PWD/.state/artifacts/admin.conf"
.state/artifacts/kubectl -n argocd get application app
.state/artifacts/kubectl -n argocd get application app -o yaml
```

Images still use the agreed local import workflow; CI does not publish images.
Build and import on both workers before changing an image reference:

```sh
ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml -e lab_phase=images
cat .state/app-images.json
```

Copy those content-based tags into `spec.source.helm.valuesObject` in
`gitops/application.yaml`, review, commit, and push. Reapply this bootstrap
definition with `kubectl apply -f gitops/application.yaml` after committing its
settings; Argo then deploys the images. The Application definition itself is
bootstrapped locally, not managed by an additional parent Application. Reverting
image settings likewise requires reapplying the reverted definition. New workers
need the same imported images before they can run the app.

To stop reconciliation during deliberate manual recovery, set
`spec.syncPolicy.automated.enabled` to `false` on the Application. Record the
change, restore the reviewed Git/bootstrap settings, and re-enable automation
after recovery. This is not needed for the provided bounded failure exercises.

## CI validation

```sh
bash scripts/setup-validation.sh
source .state/validation-venv/bin/activate
ansible-playbook -i inventory/lab/hosts.yml ansible/main.yml -e lab_phase=validate
```

GitHub Actions runs the same checks for pull requests and pushes to `main`, with
read-only repository permission and no kubeconfig, registry credential, or
deployment access. Actions are pinned by commit; Helm 3.21.3, kubectl 1.36.4, and
kubeconform 0.8.0 downloads are checksum-verified. Python dependencies are pinned.
To enforce a merge gate, make the `manifests` job in `Validate` a required check
in repository branch protection; that setting has not been changed here.

The job lints both application modes and the observability chart, renders them
and Argo's overlay, checks standard resources strictly against Kubernetes 1.36.4
schemas, validates custom instances against the pinned Argo/Prometheus CRDs,
and checks shell/Python syntax and dashboard JSON. The schema registry lacks a
CRD-definition schema for this Kubernetes version: those upstream definitions
are checksum-verified, compared unchanged after rendering, and their embedded
schemas checked separately. Missing schemas for other standard resources fail
validation. Schema validation does not replace API admission or runtime tests.
