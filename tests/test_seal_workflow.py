"""Offline trigger/access/write checks; never dispatches the workflow."""
from pathlib import Path
import subprocess
import unittest
import yaml
ROOT=Path(__file__).resolve().parents[1]
class SealWorkflowTests(unittest.TestCase):
 def test_manual_only_explicit_access_and_write_gates(self):
  workflow=yaml.load((ROOT/'.github/workflows/sealed-secrets-sync.yaml').read_text(),Loader=yaml.BaseLoader)
  self.assertEqual(set(workflow['on']),{'workflow_dispatch'})
  inputs=workflow['on']['workflow_dispatch']['inputs']
  self.assertEqual(inputs['allow_secret_access']['default'],'false')
  self.assertEqual(inputs['dry_run']['default'],'true')
  self.assertNotIn('env',workflow)
  job=workflow['jobs']['seal']
  self.assertEqual(job['if'],"github.event_name == 'workflow_dispatch' && inputs.allow_secret_access == true")
  self.assertEqual(job['runs-on'],"${{ fromJSON(vars.RUNNER_LABELS) }}")
  self.assertEqual(job['container']['image'],"${{ vars.RUNNER_CONTAINER_IMAGE }}")
  writers=[step for step in job['steps'] if 'git push' in step.get('run','')]
  self.assertEqual(len(writers),1);self.assertEqual(writers[0]['if'],'inputs.dry_run != true')
  for step in job['steps']:
   if 'run' in step:
    script=step['run']
    # Expressions are substituted by Actions before Bash runs; only parse here.
    import re
    script=re.sub(r'\$\{\{.*?\}\}','synthetic',script)
    checked=subprocess.run(['bash','-n'],input=script,text=True,capture_output=True)
    self.assertEqual(checked.returncode,0,checked.stderr)
if __name__=='__main__':unittest.main()
