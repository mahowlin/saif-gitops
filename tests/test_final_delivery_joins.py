"""Encrypted Git staging and selected resource health; synthetic data only."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import yaml
ROOT=Path(__file__).resolve().parents[1]
def load(name):
 spec=importlib.util.spec_from_file_location(name,ROOT/'.github/scripts'/f'{name}.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
sealer=load('seal_manifest');health=load('selected_workload_health')

class FinalDelivery(unittest.TestCase):
 def test_all_scopes_stage_encrypted_ignored_output_and_reject_plaintext(self):
  manifest=ROOT/'apps/sealed-secrets/secrets-manifest.yaml';groups=yaml.safe_load(manifest.read_text())['secrets']
  env={k['github_secret']:'synthetic' for g in groups for s in g['secrets'] for k in s['keys']}
  def seal(cmd,**kw):
   value=yaml.safe_load(kw['input']);return subprocess.CompletedProcess(cmd,0,yaml.safe_dump({'kind':'SealedSecret','metadata':value['metadata'],'spec':{'encryptedData':{k:'cipher' for k in value['stringData']}}}),'')
  for scope in ['all','_common','_gpu','_splunk']:
   with self.subTest(scope=scope),tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp);shutil.copyfile(ROOT/'.gitignore',root/'.gitignore');subprocess.run(['git','init','-q',str(root)],check=True)
    sealer.generate(manifest,root,scope,False,'synthetic',env,seal)
    paths=[str(p.relative_to(root/'apps/sealed-secrets')) for p in (root/'apps/sealed-secrets').rglob('*.yaml')]
    sealer.stage_generated(manifest,root,paths)
    staged=subprocess.check_output(['git','-C',str(root),'diff','--cached','--name-only'],text=True).splitlines()
    self.assertEqual(set(staged),{'apps/sealed-secrets/'+p for p in paths})
    p=root/'apps/sealed-secrets'/paths[0];p.write_text('kind: Secret\nstringData:\n  password: synthetic\n')
    with self.assertRaises(ValueError):sealer.stage_generated(manifest,root,paths)
    self.assertIn('*-secret.yaml',(root/'.gitignore').read_text())

 def test_selected_inventory_does_not_require_absent_optional_demo_integrations(self):
  apps=[{'kind':'Application','metadata':{'name':'selected'},'spec':{'destination':{'server':'https://kubernetes.default.svc','namespace':'chosen'}}}]
  calls=[]
  def observe(kind,ns,name):
   calls.append((kind,ns,name))
   if kind=='Application':return {'status':{'resources':[{'kind':'Deployment','namespace':'chosen','name':'actual'}]}}
   return {'kind':'Deployment','metadata':{'generation':2},'spec':{'replicas':2},'status':{'observedGeneration':2,'readyReplicas':2,'updatedReplicas':2}}
  self.assertEqual(health.validate(apps,observe),[('Deployment','chosen','actual')]);self.assertFalse(any('splunk' in str(x) or 'nim' in str(x) for x in calls))
  for value in [None,[],[{'kind':'Job','name':'model-download','namespace':'nim-llm'}]]:
   def incomplete(kind,ns,name):return {'status':{'resources':value}} if kind=='Application' else {'kind':'Job','status':{}}
   with self.assertRaises(ValueError):health.validate(apps,incomplete)
  with self.assertRaises(ValueError):health.check_workload({'kind':'Deployment','metadata':{'generation':2},'spec':{'replicas':2},'status':{'observedGeneration':2,'readyReplicas':1,'updatedReplicas':2}})

 def test_legacy_injection_supplies_ingester_push_key_without_secret_argv(self):
  doc=yaml.safe_load((ROOT/'.github/workflows/gitops-sync.yaml').read_text());step=next(s for j in doc['jobs'].values() for s in j['steps'] if s.get('name')=='Inject Hubble Timescape Secrets')
  self.assertIn('PUSH_API_PASSWORD=$INJECT_DIR/push',step['run']);self.assertIn('--from-file=',step['run']);self.assertNotIn('--from-literal=',step['run'])

 def test_selected_connection_log_pattern_matches_actual_hubble_filename(self):
  import re
  source=yaml.safe_load((ROOT/'clusters/_base/tier2-isovalent/hubble-timescape.yaml').read_text())['spec']['source']
  result=subprocess.run(['helm','template','hubble-timescape',str(ROOT/source['path']),'-f','-'],input=source['helm']['values'],text=True,capture_output=True,check=True)
  ingester=next(d for d in yaml.safe_load_all(result.stdout) if d and d.get('kind')=='ConfigMap' and d['metadata']['name']=='hubble-timescape-ingester-config')
  text=next(v for v in ingester['data'].values() if 'connection-logs-pattern:' in v)
  pattern=yaml.safe_load(text)['connection-logs-pattern']
  self.assertIsNotNone(re.fullmatch(pattern,'connectionlog.log'))
  self.assertIsNone(re.fullmatch(pattern,'tetragon-connections.log'))

if __name__=='__main__':unittest.main()
