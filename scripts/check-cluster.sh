#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export KUBECONFIG="$project_dir/.state/artifacts/admin.conf"
kubectl="$project_dir/.state/artifacts/kubectl"
namespace=dpg-network-check
image=docker.io/library/busybox:1.37.0@sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec

"$kubectl" get --raw=/readyz
printf '\n'
"$kubectl" wait --for=condition=Ready nodes --all --timeout=120s
"$kubectl" -n kube-system rollout status daemonset/calico-node --timeout=120s
"$kubectl" -n kube-system rollout status deployment/coredns --timeout=120s

# Refuse to reuse an existing namespace; cleanup only resources created here.
"$kubectl" create namespace "$namespace"
cleanup() {
  "$kubectl" delete namespace "$namespace" --wait=true --timeout=120s
}
trap cleanup EXIT
for node in worker1 worker2; do
  "$kubectl" -n "$namespace" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: check-$node
  labels:
    app: network-check
    check-node: $node
spec:
  terminationGracePeriodSeconds: 1
  nodeSelector:
    kubernetes.io/hostname: $node
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: check
      image: $image
      command: [sh, -ec, 'echo $node > /tmp/index.html; exec httpd -f -p 8080 -h /tmp']
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: [ALL]
      resources:
        requests: {cpu: 10m, memory: 8Mi}
        limits: {cpu: 100m, memory: 32Mi}
      readinessProbe:
        tcpSocket: {port: 8080}
        periodSeconds: 2
      volumeMounts:
        - {name: web, mountPath: /tmp}
  volumes:
    - name: web
      emptyDir: {sizeLimit: 1Mi}
YAML
done
"$kubectl" -n "$namespace" expose pod check-worker1 --name=check --port=8080 --target-port=8080 --selector=check-node=worker1
"$kubectl" -n "$namespace" wait --for=condition=Ready pod --all --timeout=180s
"$kubectl" -n "$namespace" get pods -o wide
for node in worker1 worker2; do
  "$kubectl" -n "$namespace" exec "check-$node" -- nslookup kubernetes.default.svc.cluster.local
  result=$("$kubectl" -n "$namespace" exec "check-$node" -- wget -qO- -T 5 "http://check.$namespace.svc.cluster.local:8080")
  [[ "$result" == worker1 ]]
  printf 'PASS: DNS and Service HTTP from %s\n' "$node"
done
for pair in 'worker1 worker2' 'worker2 worker1'; do
  read -r source target <<< "$pair"
  target_ip=$("$kubectl" -n "$namespace" get pod "check-$target" -o jsonpath='{.status.podIP}')
  result=$("$kubectl" -n "$namespace" exec "check-$source" -- wget -qO- -T 5 "http://$target_ip:8080")
  [[ "$result" == "$target" ]]
  printf 'PASS: pod HTTP %s -> %s\n' "$source" "$target"
done
