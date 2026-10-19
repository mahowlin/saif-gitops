#!/usr/bin/env python3
"""Read selected management Applications' resource inventory, never fixed demo objects.

No mutation, endpoint curl, Secret data read or first-node hardware assumption.
Hosted API destinations require their own selected-cluster run and credentials.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import yaml


def command_json(args, run=subprocess.run):
    result = run(args, text=True, capture_output=True)
    if result.returncode:
        raise ValueError('required resource observation failed')
    return json.loads(result.stdout)


def check_workload(value):
    kind = value['kind']
    spec, status = value.get('spec', {}), value.get('status', {})
    if kind in ('Deployment', 'StatefulSet', 'DaemonSet'):
        if status.get('observedGeneration', -1) < value['metadata'].get('generation', 1):
            raise ValueError('controller has not observed selected generation')
    if kind in ('Deployment', 'StatefulSet'):
        desired = spec.get('replicas', 1)
        if status.get('readyReplicas', 0) != desired or status.get('updatedReplicas', 0) != desired:
            raise ValueError('selected workload replicas not ready/updated')
    elif kind == 'DaemonSet':
        desired = status.get('desiredNumberScheduled', 0)
        if desired < 1 or status.get('numberReady', 0) != desired or status.get('updatedNumberScheduled', 0) != desired:
            raise ValueError('selected DaemonSet incomplete')
    elif kind == 'Job':
        if not any(c.get('type') == 'Complete' and c.get('status') == 'True' for c in status.get('conditions', [])):
            raise ValueError('selected Job incomplete')
    elif kind == 'PersistentVolumeClaim' and status.get('phase') != 'Bound':
        raise ValueError('selected PVC not Bound')


def validate(apps, observe):
    checked = []
    kinds = {'Deployment', 'StatefulSet', 'DaemonSet', 'Job', 'PersistentVolumeClaim', 'SealedSecret'}
    selected = [a for a in apps if a.get('kind') == 'Application'
                and a['spec'].get('destination', {}).get('server') == 'https://kubernetes.default.svc']
    if not selected:
        raise ValueError('selected root contains no management Applications')
    seen = set()
    for app in selected:
        live = observe('Application', app['metadata'].get('namespace', 'openshift-gitops'), app['metadata']['name'])
        resources = live.get('status', {}).get('resources')
        if not isinstance(resources, list) or not resources:
            raise ValueError('selected Application has no observed resource inventory')
        for resource in resources:
            kind = resource['kind']
            if kind not in kinds or resource.get('hook'):
                continue
            namespace = resource.get('namespace') or app['spec']['destination'].get('namespace')
            name = resource['name']
            key = kind, namespace, name
            if key in seen:
                continue
            seen.add(key)
            value = observe(kind, namespace, name)
            if kind == 'SealedSecret':
                target = value.get('spec', {}).get('template', {}).get('metadata', {})
                # Metadata-only Secret query. Never request Secret JSON/data.
                observe('SecretMetadata', target.get('namespace', namespace), target.get('name', name))
            else:
                check_workload(value)
            checked.append(key)
    if not checked:
        raise ValueError('no selected workload resources observed; no health qualification')
    return checked


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cluster', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]*', args.cluster):
        parser.error('invalid selected cluster name')
    root = Path('clusters') / args.cluster
    rendered = subprocess.run(['kubectl', 'kustomize', str(root)], text=True, capture_output=True, check=True)
    apps = [a for a in yaml.safe_load_all(rendered.stdout) if a]
    def observe(kind, namespace, name):
        if not namespace:
            raise ValueError('selected namespaced resource lacks namespace')
        if kind == 'SecretMetadata':
            subprocess.run(['oc', 'get', 'secret', name, '-n', namespace, '-o', 'name'], check=True, capture_output=True)
            return {}
        value = command_json(['oc', 'get', kind, name, '-n', namespace, '-o', 'json'])
        if value.get('kind') != kind or value.get('metadata', {}).get('name') != name:
            raise ValueError('observed identity differs from selection')
        return value
    checked = validate(apps, observe)
    for kind, namespace, name in checked:
        print(f'{kind} {namespace}/{name}: selected observation passed')
    print('Coverage: observed selected management workloads only; no hosted API, endpoint, model-quality or external integration qualification.')


if __name__ == '__main__':
    main()
