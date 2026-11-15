#!/usr/bin/env python3
"""Validate the four custom resource kinds against the pinned upstream CRDs."""
import json,pathlib,sys,tarfile
import jsonschema,yaml
root=pathlib.Path(__file__).resolve().parents[1]
schemas={}
crd_specs={}
def add_crd(d):
    if not d or d.get('kind')!='CustomResourceDefinition':return
    spec=d['spec']
    crd_specs[d['metadata']['name']]=spec
    for v in spec['versions']:
        schemas[(spec['group']+'/'+v['name'],spec['names']['kind'])]=v['schema']['openAPIV3Schema']
for d in yaml.safe_load_all((root/'.state/argocd/core-install-v3.6.1.yaml').read_text()):add_crd(d)
with tarfile.open(root/'.state/charts/kube-prometheus-stack-93.3.0.tgz') as archive:
    for kind in ['prometheusrules','servicemonitors']:
        name=f'kube-prometheus-stack/charts/crds/crds/crd-{kind}.yaml'
        for d in yaml.safe_load_all(archive.extractfile(name)):add_crd(d)
count=0
for filename in sys.argv[1:]:
    for d in yaml.safe_load_all(pathlib.Path(filename).read_text()):
        if d and d.get('kind')=='CustomResourceDefinition':
            assert d['spec']==crd_specs[d['metadata']['name']], 'Rendered CRD differs from checksum-verified upstream definition'
            for v in d['spec']['versions']:jsonschema.Draft7Validator.check_schema(v['schema']['openAPIV3Schema'])
            count+=1
            continue
        if not d or d.get('kind') not in ['Application','AppProject','PrometheusRule','ServiceMonitor']:continue
        schema=schemas[(d['apiVersion'],d['kind'])]
        jsonschema.Draft7Validator(schema).validate(d)
        count+=1
print(f'OK {count} custom resources / unchanged upstream CRDs validated')
