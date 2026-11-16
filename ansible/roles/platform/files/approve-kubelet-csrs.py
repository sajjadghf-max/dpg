#!/usr/bin/env python3
"""Approve only serving requests matching this lab's inventory identities."""

import base64
import json
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import yaml
from cryptography import x509
from cryptography.x509.oid import NameOID

root = Path(__file__).resolve().parents[4]
kubectl = [
    str(root / ".state/artifacts/kubectl"),
    "--kubeconfig=" + str(root / ".state/artifacts/admin.conf"),
]
inventory = yaml.safe_load((root / "inventory/lab/hosts.yml").read_text())
groups = inventory["all"]["children"]["k8s_cluster"]["children"]
nodes = {
    name: host["ip"]
    for group in groups.values()
    for name, host in group.get("hosts", {}).items()
}


def approve_pending():
    signed = set()
    requests = json.loads(
        subprocess.check_output(kubectl + ["get", "csr", "-o", "json"])
    )
    for request in requests["items"]:
        spec = request["spec"]
        node = spec["username"].removeprefix("system:node:")
        if spec["signerName"] != "kubernetes.io/kubelet-serving" or node not in nodes:
            continue
        issued = request.get("status", {}).get("certificate")
        if issued:
            certificate = x509.load_pem_x509_certificate(base64.b64decode(issued))
            if certificate.not_valid_after_utc > datetime.now(timezone.utc):
                signed.add(node)
            continue
        if request.get("status", {}).get("conditions"):
            continue
        csr = x509.load_pem_x509_csr(base64.b64decode(spec["request"]))
        names = csr.extensions.get_extension_for_class(
            x509.SubjectAlternativeName
        ).value
        subject = {attr.oid: attr.value for attr in csr.subject}
        valid = (
            spec["username"] == f"system:node:{node}"
            and "system:nodes" in spec["groups"]
            and set(spec["usages"])
            in (
                {"digital signature", "server auth"},
                {"digital signature", "key encipherment", "server auth"},
            )
            and csr.is_signature_valid
            and len(csr.subject) == 2
            and subject
            == {
                NameOID.COMMON_NAME: f"system:node:{node}",
                NameOID.ORGANIZATION_NAME: "system:nodes",
            }
            and len(names) == 2
            and names.get_values_for_type(x509.DNSName) == [node]
            and [str(ip) for ip in names.get_values_for_type(x509.IPAddress)]
            == [nodes[node]]
        )
        if not valid:
            raise SystemExit(
                f'Refusing unexpected serving CSR: {request["metadata"]["name"]}'
            )
        subprocess.run(
            kubectl + ["certificate", "approve", request["metadata"]["name"]],
            check=True,
        )
    return signed


def main():
    """Wait for bootstrap nodes only; issued CSR history is garbage-collected."""
    waiting_nodes = set(sys.argv[1:])
    if not waiting_nodes.issubset(nodes):
        raise SystemExit("Unknown bootstrap node requested")
    for attempt in range(45):
        signed_nodes = approve_pending()
        if waiting_nodes.issubset(signed_nodes):
            break
        time.sleep(2)
    else:
        raise SystemExit(
            "No valid serving certificate for: "
            + ", ".join(sorted(waiting_nodes - signed_nodes))
        )


if __name__ == "__main__":
    main()
