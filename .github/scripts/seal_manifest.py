#!/usr/bin/env python3
"""Seal the declared runtime references; never log or stage plaintext values."""
import argparse
import os
from pathlib import Path
import subprocess
import sys

import yaml


def generate(manifest_path, root, scope, dry_run, cert, environ=os.environ, run=subprocess.run):
    manifest = yaml.safe_load(Path(manifest_path).read_text())
    selected = 0
    outputs = set()
    for group in manifest['secrets']:
        namespace, group_scope = group['namespace'], group['scope']
        if scope != 'all' and group_scope != scope:
            continue
        for secret in group['secrets']:
            name = secret['name']
            # Preserve the existing watched filename interface.
            filename = name.removeprefix('hubble-timescape-') + '.yaml'
            parts = (group_scope, namespace, filename)
            if any(not p or p in ('.', '..') or '/' in p or '\\' in p for p in parts):
                raise ValueError('Invalid manifest output component')
            output = Path(root) / 'apps/sealed-secrets' / group_scope / namespace / filename
            if output in outputs:
                raise ValueError('Duplicate manifest output')
            outputs.add(output)
            selected += 1
            print(f'{group_scope}/{namespace}/{filename}')
            if dry_run:
                continue
            data = {}
            for key in secret['keys']:
                key_name, reference = key['name'], key['github_secret']
                if key_name in data or not environ.get(reference):
                    raise ValueError('Required secret reference missing or duplicate key')
                data[key_name] = environ[reference]
            if not data:
                raise ValueError('Selected secret has no keys')
            payload = {'apiVersion': 'v1', 'kind': 'Secret', 'type': 'Opaque',
                       'metadata': {'name': name, 'namespace': namespace}, 'stringData': data}
            result = run(['kubeseal', '--cert', str(cert), '--format', 'yaml', '--scope', 'strict'],
                         input=yaml.safe_dump(payload), text=True, capture_output=True)
            if result.returncode:
                # Tool stderr can contain plaintext input. Report status only.
                raise ValueError(f'kubeseal failed (exit {result.returncode})')
            sealed = yaml.safe_load(result.stdout)
            if (not isinstance(sealed, dict) or sealed.get('kind') != 'SealedSecret'
                    or sealed.get('metadata', {}).get('name') != name
                    or sealed.get('metadata', {}).get('namespace') != namespace
                    or set(sealed.get('spec', {}).get('encryptedData', {})) != set(data)):
                raise ValueError('Sealed output does not match selected identity and key set')
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(yaml.safe_dump(sealed, sort_keys=False))
    if not selected:
        raise ValueError('Manifest selection is empty')
    return selected


def stage_generated(manifest_path, root, paths, run=subprocess.run):
    """Force-stage only declared strict encrypted outputs, including ignored names."""
    root = Path(root).resolve()
    manifest = yaml.safe_load(Path(manifest_path).read_text())
    allowed = {}
    for group in manifest['secrets']:
        for secret in group['secrets']:
            relative = f"{group['scope']}/{group['namespace']}/{secret['name'].removeprefix('hubble-timescape-')}.yaml"
            allowed[relative] = (group['namespace'], secret['name'], {k['name'] for k in secret['keys']})
    staged = []
    # Validate the entire requested set before any Git mutation.
    for relative in paths:
        if relative not in allowed or relative in staged:
            raise ValueError('undeclared or duplicate encrypted output')
        path = root / 'apps/sealed-secrets' / relative
        if path.is_symlink() or not path.resolve().is_relative_to(root / 'apps/sealed-secrets'):
            raise ValueError('unsafe encrypted output path')
        value = yaml.safe_load(path.read_text())
        ns, name, keys = allowed[relative]
        if (value.get('kind') != 'SealedSecret'
                or value.get('metadata', {}).get('namespace') != ns
                or value.get('metadata', {}).get('name') != name
                or set(value.get('spec', {}).get('encryptedData', {})) != keys
                or any(not isinstance(v, str) or not v for v in value['spec']['encryptedData'].values())
                or any(k in value for k in ('data', 'stringData'))
                or any(k in value.get('spec', {}) for k in ('data', 'stringData'))
                or any(k in value.get('spec', {}).get('template', {}) for k in ('data', 'stringData'))):
            raise ValueError('only declared encrypted SealedSecrets may be force-staged')
        staged.append(relative)
    if not staged:
        raise ValueError('empty encrypted output selection')
    run(['git', 'add', '-f', '--', *['apps/sealed-secrets/' + p for p in staged]], cwd=root, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage-paths', type=Path, help='Validate and stage only generated encrypted paths')
    parser.add_argument('--manifest', default='apps/sealed-secrets/secrets-manifest.yaml')
    parser.add_argument('--root', type=Path, default=Path('.'))
    parser.add_argument('--scope', default=os.environ.get('SCOPE', 'all'))
    parser.add_argument('--dry-run', action='store_true', default=os.environ.get('DRY_RUN') == 'true')
    parser.add_argument('--cert', default=os.environ.get('SEAL_CERT_PATH'))
    args = parser.parse_args()
    try:
        if args.stage_paths:
            stage_generated(args.manifest, args.root, args.stage_paths.read_text().splitlines())
            return 0
        if not args.dry_run and not args.cert:
            raise ValueError('Certificate path required')
        generate(args.manifest, args.root, args.scope, args.dry_run, args.cert)
    except (ValueError, KeyError, TypeError, OSError, yaml.YAMLError):
        # Malformed YAML exceptions may quote input. Do not expose it in logs.
        print('Secret generation failed: check selected metadata, required references and kubeseal status', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
