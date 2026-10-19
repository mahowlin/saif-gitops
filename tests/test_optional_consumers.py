# Copyright (c) 2026 Cisco and/or its affiliates.
# Licensed under the Cisco Sample Code License, Version 1.1. See LICENSE.
"""Retained optional consumers: local process fixtures only, no network/credentials."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
import yaml
ROOT = Path(__file__).resolve().parents[1]
NIM = yaml.safe_load((ROOT / 'apps/nim-llm/model-download-config.yaml').read_text())
REPORTER = yaml.safe_load((ROOT / 'apps/splunk-reporter/configmap.yaml').read_text())
SETTINGS = yaml.safe_load((ROOT / 'apps/splunk-reporter/settings.yaml').read_text())

class OptionalConsumers(unittest.TestCase):

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'], CALLS=str(self.root / 'calls.jsonl'))

    def stub(self, name, code):
        path = self.bin / name
        path.write_text('#!' + sys.executable + '\n' + code)
        path.chmod(493)

    def calls(self):
        path = self.root / 'calls.jsonl'
        return [json.loads(r) for r in path.read_text().splitlines()] if path.exists() else []

    def run_script(self, source):
        return subprocess.run(['bash', '-c', source], env=self.env, text=True, capture_output=True, timeout=15)

    def model(self):
        source = self.root / 'source'
        source.mkdir()
        contents = {'metadata.json': b'{"model":"synthetic"}', 'shard-1': b'first-full-shard', 'shard-2': b'second-full-shard'}
        for name, data in contents.items():
            (source / name).write_bytes(data)
        files = self.root / 'files'
        files.write_text('\n'.join(contents) + '\n')
        sums = self.root / 'sums'
        sums.write_text(''.join((hashlib.sha256(data).hexdigest() + '  ' + name + '\n' for name, data in contents.items())))
        self.env.update(MODEL_DIR=str(self.root / 'store/changed-model'), MODEL_STORE_ROOT=str(self.root / 'store'), MODEL_BASE_URL='https://models.example.test/changed-model', MODEL_FILES_FILE=str(files), MODEL_CHECKSUM_FILE=str(sums), WEB_USERNAME='synthetic-user', WEB_PASSWORD='synthetic-password', FIXTURE_SOURCE=str(source))
        self.stub('curl', "import os,sys,json,pathlib\nargs=sys.argv[1:]\nassert not any(os.environ['WEB_PASSWORD'] in a for a in args)\nconfig=sys.stdin.read()\nassert 'Authorization: Basic ' in config\nname=args[-1].rsplit('/',1)[-1]\nwith open(os.environ['CALLS'],'a') as f: f.write(json.dumps({'file':name})+'\\n')\nout=pathlib.Path(args[args.index('--output')+1])\nif name==os.environ.get('FAIL_FILE'):\n    out.write_bytes(b'partial'); raise SystemExit(22)\ndata=(pathlib.Path(os.environ['FIXTURE_SOURCE'])/name).read_bytes()\nif name==os.environ.get('TRUNCATE_FILE'): data=data[:2]\nout.write_bytes(data)\nprint('200',end='')\n")
        return (Path(self.env['MODEL_DIR']), contents)

    def assert_clean_staging(self):
        self.assertEqual(list((self.root / 'store').glob('*.download.*')), [])
        self.assertFalse(Path(self.env['MODEL_DIR'] + '.download-lock').exists())

    def test_failed_fresh_download_never_publishes_or_leaves_stage(self):
        final, _ = self.model()
        self.env['FAIL_FILE'] = 'shard-2'
        self.assertNotEqual(self.run_script(NIM['data']['download.sh']).returncode, 0)
        self.assertFalse(final.exists())
        self.assert_clean_staging()

    def test_partial_first_shard_does_not_skip_and_retry_completes_atomically(self):
        final, contents = self.model()
        final.mkdir(parents=True)
        (final / 'shard-1').write_bytes(b'old partial')
        self.env['FAIL_FILE'] = 'shard-2'
        self.assertNotEqual(self.run_script(NIM['data']['download.sh']).returncode, 0)
        self.assertEqual((final / 'shard-1').read_bytes(), b'old partial')
        self.assertFalse((final / 'metadata.json').exists())
        self.assert_clean_staging()
        self.env.pop('FAIL_FILE')
        self.assertEqual(self.run_script(NIM['data']['download.sh']).returncode, 0)
        for name, data in contents.items():
            self.assertEqual((final / name).read_bytes(), data)
        self.assertEqual(final.stat().st_mode & 511, 493)
        self.assertTrue(all(((final / name).stat().st_mode & 511 == 420 for name in contents)))
        self.assertEqual(len(self.calls()), 6)
        self.assert_clean_staging()

    def test_failed_publish_restores_prior_directory_and_cleans_owned_stage(self):
        final, _ = self.model()
        final.mkdir(parents=True)
        (final / 'shard-1').write_bytes(b'prior partial')
        self.stub('mv', '\n'.join(['import os,sys,pathlib', 'source,target=map(pathlib.Path,sys.argv[1:])', "if target==pathlib.Path(os.environ['MODEL_DIR']) and not str(source).endswith('.previous'): raise SystemExit(1)", 'os.rename(source,target)']))
        self.assertNotEqual(self.run_script(NIM['data']['download.sh']).returncode, 0)
        self.assertEqual((final / 'shard-1').read_bytes(), b'prior partial')
        self.assert_clean_staging()

    def test_truncated_success_response_cannot_publish(self):
        final, _ = self.model()
        self.env['TRUNCATE_FILE'] = 'shard-1'
        result = self.run_script(NIM['data']['download.sh'])
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(final.exists())
        self.assert_clean_staging()

    def test_only_complete_verified_existing_model_skips_download(self):
        final, contents = self.model()
        final.mkdir(parents=True)
        for name, data in contents.items():
            (final / name).write_bytes(data)
        self.assertEqual(self.run_script(NIM['data']['download.sh']).returncode, 0)
        self.assertEqual(self.calls(), [])
        (final / 'shard-2').write_bytes(b'nonempty but incorrect')
        self.assertEqual(self.run_script(NIM['data']['download.sh']).returncode, 0)
        self.assertEqual(len(self.calls()), len(contents))
        self.assert_clean_staging()

    def test_incomplete_checksum_manifest_and_non_https_fail_before_curl(self):
        self.model()
        sums = Path(self.env['MODEL_CHECKSUM_FILE'])
        original = sums.read_text()
        for content in ('', original.splitlines()[0] + '\n'):
            sums.write_text(content)
            self.assertNotEqual(self.run_script(NIM['data']['download.sh']).returncode, 0)
            self.assertEqual(self.calls(), [])
        sums.write_text(original)
        self.env['MODEL_BASE_URL'] = 'http://models.example.test'
        self.assertNotEqual(self.run_script(NIM['data']['download.sh']).returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_job_uses_declared_config_and_runtime_secret_refs(self):
        job = yaml.safe_load((ROOT / 'apps/nim-llm/model-download-job.yaml').read_text())
        pod = job['spec']['template']['spec']
        c = pod['containers'][0]
        env = {r['name']: r for r in c['env']}
        for name, key in [('WEB_USERNAME', 'username'), ('WEB_PASSWORD', 'password')]:
            self.assertEqual(env[name]['valueFrom']['secretKeyRef'], {'name': 'webserver-credentials', 'key': key})
        self.assertEqual(env['MODEL_BASE_URL']['valueFrom']['configMapKeyRef']['key'], 'base-url')
        self.assertEqual(c['command'], ['/bin/bash', '/download-config/download.sh'])
        self.assertFalse(NIM['data']['base-url'])
        self.assertFalse(NIM['data']['sha256sums'])
        self.assertEqual(len(NIM['data']['files'].splitlines()), 15)

    def reporter(self):
        self.env.update(SPLUNK_REALM='synthetic-one', SPLUNK_API_TOKEN='synthetic-token')
        for key in SETTINGS['data']:
            if key.startswith('CHART_'):
                self.env[key] = 'mapped-' + key.lower()
        self.stub('kubectl', 'raise SystemExit(0)')
        self.stub('oc', 'raise SystemExit(0)')
        self.stub('curl', "import os,sys,json\nargs=sys.argv[1:]\nassert not any(os.environ['SPLUNK_API_TOKEN'] in a for a in args)\nassert 'X-SF-Token: ' in sys.stdin.read()\nwith open(os.environ['CALLS'],'a') as f: f.write(json.dumps({'url':args[-1], 'payload':json.loads(args[args.index('--data')+1])})+'\\n')\nif os.environ.get('CURL_FAIL'): raise SystemExit(22)\nprint(os.environ.get('CURL_STATUS','200'),end='')\n")
        return REPORTER['data']['update-dashboard-charts.sh']

    def test_missing_mapping_fails_before_external_updates(self):
        script = self.reporter()
        self.env.pop('CHART_LLM')
        self.assertNotEqual(self.run_script(script).returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_failed_or_redirected_update_cannot_report_completion(self):
        script = self.reporter()
        for name, value in [('CURL_FAIL', 'true'), ('CURL_STATUS', '302')]:
            self.env[name] = value
            previous = len(self.calls())
            result = self.run_script(script)
            self.assertEqual(len(self.calls()), previous + 1)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('Dashboard update complete', result.stdout)
            self.env.pop(name)

    def test_changed_realm_and_mapping_drive_actual_update_requests(self):
        script = self.reporter()
        self.env['SPLUNK_REALM'] = 'synthetic-two'
        self.env['CHART_LLM'] = 'other-llm'
        result = self.run_script(script)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.calls()), 15)
        self.assertTrue(all((c['url'].startswith('https://api.synthetic-two.signalfx.com/v2/chart/') for c in self.calls())))
        self.assertTrue(any((c['url'].endswith('/other-llm') for c in self.calls())))

    def test_update_payload_is_json_serialized_for_quotes_and_newlines(self):
        script = self.reporter().split('echo "=== Collecting cluster data')[0]
        result = self.run_script(script + '\nupdate_chart synthetic-id $\'name"\\nline\' $\'html\\\\"\\nline\'\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[0]['payload']['name'], 'name"\nline')
        self.assertIn('\n', self.calls()[0]['payload']['options']['markdown'])

    def test_cronjob_binds_nonsecret_settings_and_existing_token_secret(self):
        job = yaml.safe_load((ROOT / 'apps/splunk-reporter/cronjob.yaml').read_text())
        c = job['spec']['jobTemplate']['spec']['template']['spec']['containers'][0]
        self.assertEqual(c['envFrom'], [{'configMapRef': {'name': SETTINGS['metadata']['name']}}])
        self.assertEqual(c['env'][0]['valueFrom']['secretKeyRef'], {'name': 'splunk-credentials', 'key': 'api-token'})
        self.assertTrue(all((v == '' for v in SETTINGS['data'].values())))

    def helm(self, values):
        path = self.root / 'values.yaml'
        path.write_text(yaml.safe_dump(values))
        return subprocess.run(['helm', 'template', 'synthetic', str(ROOT / 'charts/intersight-otel'), '--namespace', 'synthetic-metrics', '-f', str(path)], text=True, capture_output=True)

    def intersight(self, suffix):
        return {'clusterName': 'cluster-' + suffix, 'bladeSerial': 'SERIAL-' + suffix, 'image': {'intersightOtel': {'repository': 'registry.' + suffix + '.example/collector'}}, 'splunk': {'realm': 'realm-' + suffix, 'apiUrl': 'https://api.' + suffix + '.example', 'ingestUrl': 'https://ingest.' + suffix + '.example'}}

    def test_intersight_missing_required_inputs_rejected(self):
        self.assertNotEqual(self.helm({}).returncode, 0)
        for field in ('clusterName', 'bladeSerial'):
            values = self.intersight('one')
            values[field] = ''
            self.assertNotEqual(self.helm(values).returncode, 0)
        values = self.intersight('one')
        values['splunk']['apiUrl'] = 'http://api.one.example'
        self.assertNotEqual(self.helm(values).returncode, 0)

    def test_intersight_changed_inputs_drive_render_without_invented_domain(self):
        first = self.helm(self.intersight('one'))
        second = self.helm(self.intersight('two'))
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn('cluster-two', second.stdout)
        self.assertIn('SERIAL-two', second.stdout)
        self.assertIn('https://api.two.example', second.stdout)
        self.assertIn('registry.two.example/collector', second.stdout)
        self.assertNotIn('cluster-one', second.stdout)
        self.assertNotIn('cluster-two.example.com', second.stdout)
if __name__ == '__main__':
    unittest.main()
