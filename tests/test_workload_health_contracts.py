# Copyright (c) 2026 Cisco and/or its affiliates.
# Licensed under the Cisco Sample Code License, Version 1.1. See LICENSE.
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

def step(name):
    doc = yaml.safe_load((ROOT / '.github/workflows/workload-test.yaml').read_text())
    return next((s['run'] for j in doc['jobs'].values() for s in j['steps'] if s.get('name') == name))

class WorkloadHealthContracts(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        interpreter = self.bin / 'python3'
        interpreter.write_text('#!/bin/sh\nexec ' + shlex.quote(sys.executable) + ' "$@"\n')
        interpreter.chmod(493)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'], GITHUB_STEP_SUMMARY=str(self.base / 'summary'))

    def stub(self, name, body):
        path = self.bin / name
        path.write_text('#!' + sys.executable + '\n' + body)
        path.chmod(493)

    def run_step(self, name, body):
        self.stub('oc', body)
        return subprocess.run(['bash', '-eo', 'pipefail', '-c', step(name)], env=self.env, text=True, capture_output=True)

    def test_pod_query_error_and_empty_cannot_pass(self):
        for body in ('raise SystemExit(1)', 'print("")'):
            with self.subTest(body=body):
                result = self.run_step('Validate Pod Health', body)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('No pods in error state', (self.base / 'summary').read_text())

    def test_populated_healthy_pod_query_passes(self):
        self.assertEqual(self.run_step('Validate Pod Health', 'print("demo responder 1/1 Running 0 1h")').returncode, 0)

    def operator_stub(self, mode):
        return "import sys,json\nargs=sys.argv[1:]\nmode=%r\nif args[:2]==['get','namespaces']:\n    print('openshift-nfd')\nelif args[:2]==['get','subscriptions']:\n    if mode=='query-error': raise SystemExit(1)\n    if mode=='empty': print(json.dumps({'items':[]}))\n    elif mode=='pending': print(json.dumps({'items':[{'status':{}}]}))\n    else: print(json.dumps({'items':[{'status':{'installedCSV':'chosen.v1'}}]}))\nelif args[:2]==['get','csv']:\n    if mode=='csv-error': raise SystemExit(1)\n    print('Succeeded' if mode=='healthy' else '')\nelse: raise SystemExit(98)\n" % mode

    def test_required_operator_error_empty_pending_and_empty_phase_fail(self):
        for mode in ('query-error', 'empty', 'pending', 'csv-error', 'empty-phase'):
            with self.subTest(mode=mode):
                self.assertNotEqual(self.run_step('Validate OLM Operators', self.operator_stub(mode)).returncode, 0)

    def test_operator_selected_csv_succeeded_passes(self):
        self.assertEqual(self.run_step('Validate OLM Operators', self.operator_stub('healthy')).returncode, 0)

    def test_namespace_query_error_or_empty_fails(self):
        for body in ('raise SystemExit(1)', 'print("")'):
            self.assertNotEqual(self.run_step('Validate OLM Operators', body).returncode, 0)

    def test_optional_absent_operator_not_claimed_healthy(self):
        self.assertEqual(self.run_step('Validate OLM Operators', 'print("default")').returncode, 0)
        self.assertIn('not qualified', (self.base / 'summary').read_text())
if __name__ == '__main__':
    unittest.main()
