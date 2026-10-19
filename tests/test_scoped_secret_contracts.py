"""Offline selected-chart and secret/workflow failure regressions; no live clients."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import yaml

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('seal_manifest', ROOT / '.github/scripts/seal_manifest.py')
sealer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sealer)



class ScopedSecretContracts(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        interpreter = self.bin / 'python3'
        interpreter.write_text('#!/bin/sh\nexec ' + shlex.quote(sys.executable) + ' "$@"\n')
        interpreter.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        GITHUB_STEP_SUMMARY=str(self.base / 'summary'))

    def stub(self, name, body):
        path = self.bin / name
        path.write_text('#!' + sys.executable + '\n' + body)
        path.chmod(0o755)

    def manifest(self):
        return {'secrets': [{'scope': '_common', 'namespace': 'changed-namespace', 'secrets': [
            {'name': 'hubble-timescape-ingester-creds', 'keys': [
                {'name': 'PUSH_API_PASSWORD', 'github_secret': 'DUMMY_REFERENCE'}]}]}]}

    def write_manifest(self):
        root = self.base / 'apps/sealed-secrets'
        root.mkdir(parents=True)
        path = root / 'secrets-manifest.yaml'
        path.write_text(yaml.safe_dump(self.manifest()))
        return path

    def test_seal_generation_preserves_strings_and_watched_namespace(self):
        manifest = self.write_manifest()
        value = 'quote" slash\\ newline\nnext: yes\tunicode ä'
        def run(argv, **kwargs):
            self.assertNotIn(value, str(argv))
            payload = yaml.safe_load(kwargs['input'])
            self.assertEqual(payload['stringData']['PUSH_API_PASSWORD'], value)
            return subprocess.CompletedProcess(argv, 0, yaml.safe_dump({
                'kind': 'SealedSecret', 'metadata': payload['metadata'],
                'spec': {'encryptedData': {'PUSH_API_PASSWORD': 'synthetic-cipher'}}}), '')
        sealer.generate(manifest, self.base, 'all', False, 'dummy-cert', {'DUMMY_REFERENCE': value}, run)
        output = self.base / 'apps/sealed-secrets/_common/changed-namespace/ingester-creds.yaml'
        self.assertTrue(output.is_file())
        self.assertNotIn(value, output.read_text())
        self.assertEqual(yaml.safe_load(output.read_text())['metadata']['namespace'], 'changed-namespace')

    def test_generation_error_missing_and_wrong_identity_never_write(self):
        manifest = self.write_manifest()
        for environ, result in (({}, None), ({'DUMMY_REFERENCE': 'dummy'}, subprocess.CompletedProcess([], 1, '', 'dummy')),
                                ({'DUMMY_REFERENCE': 'dummy'}, subprocess.CompletedProcess([], 0, 'kind: SealedSecret\nmetadata: {}', ''))):
            with self.assertRaises(ValueError):
                sealer.generate(manifest, self.base, 'all', False, 'cert', environ, lambda *a, **k: result)
        self.assertEqual(list(self.base.glob('apps/sealed-secrets/*/*/*.yaml')), [])

    def test_dry_run_requires_no_values_and_empty_scope_fails(self):
        manifest = self.write_manifest()
        self.assertEqual(sealer.generate(manifest, self.base, 'all', True, None, {}, mock.Mock()), 1)
        with self.assertRaises(ValueError):
            sealer.generate(manifest, self.base, 'unknown', True, None, {}, mock.Mock())

    def validator(self):
        scripts = self.base / 'scripts'
        scripts.mkdir(exist_ok=True)
        shutil.copyfile(ROOT / 'scripts/validate-sealed-secrets.sh', scripts / 'validate-sealed-secrets.sh')
        return subprocess.run(['bash', str(scripts / 'validate-sealed-secrets.sh')], env=self.env,
                              text=True, capture_output=True)

    def test_scoped_validator_checks_name_namespace_keys_and_empty(self):
        self.write_manifest()
        self.assertNotEqual(self.validator().returncode, 0)
        target = self.base / 'apps/sealed-secrets/_common/changed-namespace/ingester-creds.yaml'
        target.parent.mkdir(parents=True)
        valid = {'kind': 'SealedSecret', 'metadata': {'name': 'hubble-timescape-ingester-creds',
                'namespace': 'changed-namespace'}, 'spec': {'encryptedData': {'PUSH_API_PASSWORD': 'synthetic'}}}
        target.write_text(yaml.safe_dump(valid))
        self.assertEqual(self.validator().returncode, 0)
        for field, value in (('name', 'wrong-name'), ('namespace', 'wrong-namespace')):
            bad = json.loads(json.dumps(valid))
            bad['metadata'][field] = value
            target.write_text(yaml.safe_dump(bad))
            self.assertNotEqual(self.validator().returncode, 0)
        valid['spec']['encryptedData'] = {}
        target.write_text(yaml.safe_dump(valid))
        self.assertNotEqual(self.validator().returncode, 0)

    def test_validator_rejects_valid_secret_in_wrong_scope(self):
        self.write_manifest()
        target = self.base / 'apps/sealed-secrets/_gpu/changed-namespace/ingester-creds.yaml'
        target.parent.mkdir(parents=True)
        target.write_text(yaml.safe_dump({'kind': 'SealedSecret', 'metadata': {
            'name': 'hubble-timescape-ingester-creds', 'namespace': 'changed-namespace'},
            'spec': {'encryptedData': {'PUSH_API_PASSWORD': 'synthetic'}}}))
        self.assertNotEqual(self.validator().returncode, 0)

    def test_validator_two_scopes_same_name_keep_independent_key_contracts(self):
        manifest_path = self.write_manifest()
        manifest = self.manifest()
        other = json.loads(json.dumps(manifest['secrets'][0]))
        other['scope'] = '_gpu'
        other['secrets'][0]['keys'] = [{'name': 'OTHER_PASSWORD', 'github_secret': 'OTHER_REFERENCE'}]
        manifest['secrets'].append(other)
        manifest_path.write_text(yaml.safe_dump(manifest))
        doc = {'kind': 'SealedSecret', 'metadata': {'name': 'hubble-timescape-ingester-creds',
               'namespace': 'changed-namespace'}, 'spec': {'encryptedData': {'PUSH_API_PASSWORD': 'synthetic'}}}
        common = self.base / 'apps/sealed-secrets/_common/changed-namespace/ingester-creds.yaml'
        common.parent.mkdir(parents=True)
        common.write_text(yaml.safe_dump(doc))
        self.assertEqual(self.validator().returncode, 0)  # Other optional scope need not exist.
        gpu = self.base / 'apps/sealed-secrets/_gpu/changed-namespace/ingester-creds.yaml'
        gpu.parent.mkdir(parents=True)
        gpu.write_text(yaml.safe_dump(doc))
        self.assertNotEqual(self.validator().returncode, 0)
        doc['spec']['encryptedData'] = {'OTHER_PASSWORD': 'synthetic'}
        gpu.write_text(yaml.safe_dump(doc))
        self.assertEqual(self.validator().returncode, 0)

    def test_validator_rejects_conflicting_duplicate_manifest_identity(self):
        manifest_path = self.write_manifest()
        manifest = self.manifest()
        duplicate = json.loads(json.dumps(manifest['secrets'][0]))
        duplicate['secrets'][0]['keys'][0]['github_secret'] = 'CONFLICTING_REFERENCE'
        manifest['secrets'].append(duplicate)
        manifest_path.write_text(yaml.safe_dump(manifest))
        result = self.validator()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('conflicting declared secret identity', result.stderr)

    def test_validator_uses_declared_hosted_intent_without_widening_common_scope(self):
        manifest = self.write_manifest()
        target = self.base / 'apps/sealed-secrets/selected-cluster/changed-namespace/writer.yaml'
        target.parent.mkdir(parents=True)
        target.write_text(yaml.safe_dump({'kind': 'SealedSecret', 'metadata': {
            'namespace': 'changed-namespace', 'name': 'writer'},
            'spec': {'encryptedData': {'AWS_ACCESS_KEY_ID': 'synthetic'}}}))
        intent = {'targets': [{'cluster': 'selected-cluster', 'namespace': 'changed-namespace',
            'secretName': 'writer', 'sealedPath': 'apps/sealed-secrets/selected-cluster/changed-namespace/writer.yaml',
            'keys': ['AWS_ACCESS_KEY_ID']}], 'retainedExternal': ['retained-cluster']}
        (manifest.parent / 'hosted-writer-intent.json').write_text(json.dumps(intent))
        retained = manifest.parent / 'retained-cluster/changed-namespace/external.yaml'
        retained.parent.mkdir(parents=True)
        retained.write_text('not owned, must not be parsed')
        result = self.validator()
        self.assertEqual(result.returncode, 0)
        self.assertIn('not qualified: retained-cluster', result.stdout)
        renamed = target.with_name('wrong-path.yaml')
        target.rename(renamed)
        self.assertNotEqual(self.validator().returncode, 0)
        renamed.unlink()
        self.assertNotEqual(self.validator().returncode, 0)  # Retained-only is not a pass.
        intent['targets'][0]['sealedPath'] = 'apps/sealed-secrets/other-cluster/changed-namespace/writer.yaml'
        (manifest.parent / 'hosted-writer-intent.json').write_text(json.dumps(intent))
        self.assertNotEqual(self.validator().returncode, 0)

    def test_cli_helper_no_plaintext_residue_on_kubeseal_failure(self):
        cert = self.base / 'dummy.crt'
        cert.touch()
        captured = self.base / 'captured.json'
        self.stub('kubeseal', 'import sys,pathlib\npathlib.Path(%r).write_text(sys.stdin.read())\nraise SystemExit(3)' % str(captured))
        self.env.update(SEALED_SECRETS_CERT=str(cert), TMPDIR=str(self.base))
        value = 'quote" slash\\ newline\nx: y'
        result = subprocess.run(['bash', str(ROOT / 'scripts/seal-secret.sh'), 'ns', 'name', 'key=' + value],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 3)
        self.assertEqual(json.loads(captured.read_text())['stringData']['key'], value)
        self.assertEqual(list(self.base.glob('tmp.*')), [])


    def test_current_restart_hooks_propagate_restart_and_rollout_failures(self):
        for resolved in (False, True):
            values = {"clusterName": "synthetic", "ciliumConfig": {"enabled": not resolved,
                      "apiHost": "api.synthetic.test", "restartJobImage": "fixture.invalid/tools:v1",
                      "ipam": {"cidr": "10.0.0.0/16"}},
                      "identity": {"apiGroup": "fixture.invalid"}}
            template = 'postsync-restart-hook.yaml'
            if resolved:
                template = 'postsync-resolved-restart-hook.yaml'
                values['renderedCiliumConfig'] = dict(enabled=True, sourceContractSha256='synthetic',
                    sourceRepository='synthetic/repo', sourceRevision='synthetic', receiptState='unqualified',
                    profileRef='synthetic', profileSha256='synthetic', restartJobImage='synthetic/image', spec={})
            path = self.base / 'hook-values.yaml'
            path.write_text(yaml.safe_dump(values))
            result = subprocess.run(['helm', 'template', 'regression', str(ROOT / 'charts/cilium-config'),
                '-f', str(path), '--show-only', 'templates/' + template], text=True, capture_output=True, check=True)
            job = next(d for d in yaml.safe_load_all(result.stdout) if d and d.get('kind') == 'Job')
            script = job['spec']['template']['spec']['containers'][0]['command'][-1]
            for failure in ('restart', 'status'):
                self.stub('oc', 'import sys\nraise SystemExit(7 if sys.argv[2]==%r else 0)' % failure)
                command = subprocess.run(['sh', '-c', script], env=self.env, text=True, capture_output=True)
                self.assertEqual(command.returncode, 7)
                self.assertNotIn('restarts complete', command.stdout)

if __name__ == "__main__":
    unittest.main()
