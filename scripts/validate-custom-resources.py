#!/usr/bin/env python3
"""Validate custom resources against checksum-verified, pinned upstream CRDs."""

import argparse
from pathlib import Path
import tarfile

import jsonschema
import yaml

ROOT = Path(__file__).resolve().parents[1]
CUSTOM_KINDS = {"Application", "AppProject", "PrometheusRule", "ServiceMonitor"}


def load_schemas():
    """Read Argo and monitoring schemas from the exact artifacts used to install."""
    definitions = list(
        yaml.safe_load_all(
            (ROOT / ".state/argocd/core-install-v3.6.1.yaml").read_text()
        )
    )
    with tarfile.open(
        ROOT / ".state/charts/kube-prometheus-stack-93.3.0.tgz"
    ) as archive:
        for kind in ("prometheusrules", "servicemonitors"):
            name = f"kube-prometheus-stack/charts/crds/crds/crd-{kind}.yaml"
            definitions.extend(yaml.safe_load_all(archive.extractfile(name)))
    schemas, specs = {}, {}
    for definition in definitions:
        if not definition or definition.get("kind") != "CustomResourceDefinition":
            continue
        spec = definition["spec"]
        specs[definition["metadata"]["name"]] = spec
        for version in spec["versions"]:
            schemas[(spec["group"] + "/" + version["name"], spec["names"]["kind"])] = (
                version["schema"]["openAPIV3Schema"]
            )
    return schemas, specs


def validate_file(filename, schemas, specs):
    """Check custom resources and refuse changes to the bundled upstream CRDs."""
    count = 0
    for document in yaml.safe_load_all(filename.read_text()):
        if not document:
            continue
        if document.get("kind") == "CustomResourceDefinition":
            if document["spec"] != specs[document["metadata"]["name"]]:
                raise ValueError(
                    f"{filename}: CRD differs from pinned upstream definition"
                )
            for version in document["spec"]["versions"]:
                jsonschema.Draft7Validator.check_schema(
                    version["schema"]["openAPIV3Schema"]
                )
        elif document.get("kind") in CUSTOM_KINDS:
            schema = schemas[(document["apiVersion"], document["kind"])]
            jsonschema.Draft7Validator(schema).validate(document)
        else:
            continue
        count += 1
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", type=Path, nargs="+")
    args = parser.parse_args()
    schemas, specs = load_schemas()
    count = sum(validate_file(path, schemas, specs) for path in args.files)
    print(f"OK {count} custom resources / unchanged upstream CRDs validated")


if __name__ == "__main__":
    main()
