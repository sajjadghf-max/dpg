# GitOps and CI

## Argo CD

Run this after the application, ingress, and monitoring setup. On a fresh build,
set the image tags in `gitops/application.yaml` from `.state/app-images.json`
before installing Argo; do not assume another build has the same image IDs.

```sh
bash scripts/install-gitops.sh
bash scripts/check-gitops.sh
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
GIT_CA_FILE=/path/to/trusted-root.pem bash scripts/install-gitops.sh
```

`gitops/project.yaml` permits only this repository and namespaced application
resource kinds in `dpg-app`. `gitops/application.yaml` bootstraps the `app`
Application, using the chart at `charts/dpg-app` on `main`. It preserves the
imported immutable image tags, enables exporters, and skips Helm test hooks.
Argo polls Git, applies chart changes, repairs drift, and prunes its tracked
resources after applying replacements. It ignores Deployment replica counts
because the HPAs own them. TLS Secrets and platform components remain managed
by their existing setup scripts; they are not owned or pruned by this Application.

Traefik reports the actual LB address, `192.168.56.10`, in Ingress status so Argo
can assess Ingress health without bypassing its normal health check.

Argo uses Helm to render templates, not to operate a Helm release. The old `app`
release history remains as a bootstrap record and becomes stale after Argo
changes the workloads. Do not run `helm upgrade`, `rollback`, or `uninstall app`.
`deploy-app.sh` now refuses to compete with Argo; ingress and monitoring scripts
preserve Argo's application settings. Network checks render the current chart's
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
bash scripts/import-app-images.sh
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
bash scripts/validate.sh
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

## Verified on 2026-11-15

The installer was rerun successfully. Argo used approximately 314 MiB across
its three pods at the final resource check. `app` was Synced and Healthy at remote Git
revision `5c7eebc882e8fdc5d149649bf16fb6dd41aea5e4`. Argo repaired an injected
comment in its ConfigMap automatically; HTTPS/client-IP and both network tests
passed. Local CI checks accepted 75 standard resources and eight custom resources
or unchanged upstream CRDs. Deliberately invalid Deployment replica and AppProject
namespace types were rejected. The hosted workflow has not run yet: these new
files must be committed and pushed first.

During CRD installation on the original 2 GiB control plane, the API server was
OOM-killed three times as its pod memory cgroup ran out of room. It recovered;
two CRDs needed an update to resume establishment. With approval, cp1 was raised
to 3 GiB, taking the VM total to 9.5 GiB. Vagrant's reload hit a provider error
after shutdown, so the stopped domain's persistent memory was updated through
libvirt and the VM started again. The Vagrantfile now specifies 3 GiB for new
builds; the installer applies CRDs sequentially and waits for establishment.

After the resize, the API and node recovered and Argo remained Healthy. The
installer rerun, self-healing test, all 28 scrapes, Grafana TLS/login, and network
checks passed; the API-server restart count did not increase during verification.
A clean rebuild is still unverified; successful reconciliation is not proof of
reproducible provisioning or HA. The single control-plane API is unavailable
while cp1 is stopped, even when the application continues serving on workers.
