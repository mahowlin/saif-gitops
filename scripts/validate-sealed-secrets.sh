#!/usr/bin/env bash
# Copyright (c) 2026 Cisco and/or its affiliates.
# Licensed under the Cisco Sample Code License, Version 1.1
# See LICENSE in the project root.
# Validate scoped SealedSecret metadata against the declared runtime references.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 - "${SCRIPT_DIR}/../apps/sealed-secrets" <<'PY'
from pathlib import Path
import json
import sys
import yaml

root = Path(sys.argv[1])
manifest = yaml.safe_load((root / 'secrets-manifest.yaml').read_text())
expected = {}
for group in manifest['secrets']:
    for secret in group['secrets']:
        identity = (group['scope'], group['namespace'], secret['name'])
        keys = {key['name']: (key['github_secret'], key.get('multiline', False))
                for key in secret['keys']}
        if len(keys) != len(secret['keys']) or (identity in expected and expected[identity] != keys):
            raise SystemExit('Validation failed: conflicting declared secret identity')
        expected[identity] = keys
# Hosted writer enrollment has its own existing metadata owner. Preserve that
# boundary instead of widening _common to arbitrary cluster scopes.
retained = set()
hosted_paths = {}
intent_path = root / 'hosted-writer-intent.json'
if intent_path.is_file():
    intent = json.loads(intent_path.read_text())
    retained = set(intent.get('retainedExternal', [])) | {
        row['cluster'] for row in intent.get('enrollments', []) if row['enrollment'] == 'retained'}
    for target in intent['targets']:
        relative = Path(target['sealedPath']).relative_to('apps/sealed-secrets')
        if (len(relative.parts) != 3 or relative.parts[:2] != (target['cluster'], target['namespace'])
                or target['cluster'] in retained):
            raise SystemExit('Validation failed: conflicting hosted writer scope/path')
        identity = (target['cluster'], target['namespace'], target['secretName'])
        keys = {key: ('hosted-writer-intent', False) for key in target['keys']}
        if (len(keys) != len(target['keys'])
                or (identity in expected and set(expected[identity]) != set(keys))
                or (identity in hosted_paths and hosted_paths[identity] != relative)):
            raise SystemExit('Validation failed: conflicting declared secret identity')
        expected[identity] = keys
        hosted_paths[identity] = relative
files = sorted(root.glob('*/*/*.yaml'))
if not expected or not files:
    raise SystemExit('Validation failed: empty secret metadata or scoped observation')
errors = []
validated = 0
for file in files:
    if file.parent.parent.name in retained:
        print('Retained external scope not qualified: ' + file.parent.parent.name)
        continue
    validated += 1
    # Only metadata and encrypted key names are validated; no values are logged.
    doc = yaml.safe_load(file.read_text())
    metadata = doc.get('metadata', {}) if isinstance(doc, dict) else {}
    identity = (file.parent.parent.name, metadata.get('namespace'), metadata.get('name'))
    keys = doc.get('spec', {}).get('encryptedData', {}) if isinstance(doc, dict) else {}
    template = doc.get('spec', {}).get('template', {}).get('metadata', {}) if isinstance(doc, dict) else {}
    if (not isinstance(doc, dict) or doc.get('kind') != 'SealedSecret'
            or identity not in expected or identity[1] != file.parent.name
            or (identity in hosted_paths and file.relative_to(root) != hosted_paths[identity])
            or set(keys) != set(expected.get(identity, {}))
            or template.get('name', identity[2]) != identity[2]
            or template.get('namespace', identity[1]) != identity[1]):
        errors.append(file.relative_to(root).as_posix())
if not validated:
    raise SystemExit('Validation failed: no owned scoped observations')
if errors:
    raise SystemExit('Validation failed for scoped metadata: ' + ', '.join(errors))
print(f'Validated {validated} owned scoped SealedSecret identities and key sets')
PY
