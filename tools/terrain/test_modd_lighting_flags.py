"""Actual-source MODD appearance-flag audit with unsupported-bit retention."""
import argparse,collections,hashlib,importlib,json,pathlib,sys,unittest
import wmo_probe as w
unsupported_doodad_flags=w.unsupported_doodad_flags
PIN='de8b30b38337373f951a4a1570dd720554cfd14aa2fb52b94f0aed966ab1abf8'
REFERENCES={'wmoObject.cpp':'93f0b10b488b9fc6e85f44fd12678ac051b981100ed6d2c347c1111f762a058d','m2Object.cpp':'2a2b592073db40b1c83e943d08008b481bd0e22eb553635cde5dea1b5527107a','wmoFileHeader.h':'ef98732e0109ff090d339928be1902857e1839f38a057aeac8ac27ee04d79ab2'}

def sha(raw):return hashlib.sha256(raw).hexdigest()
class Tests(unittest.TestCase):
 def test_actual_lighting_combinations(self):
  for flags in (0,2,16,17,18,20,22,26,30,146):self.assertEqual(unsupported_doodad_flags(flags),0)
 def test_bit32_and_future_bits_remain_unsupported(self):
  for flags in (32,48,50,255):self.assertEqual(unsupported_doodad_flags(flags),32)
  self.assertEqual(unsupported_doodad_flags(256),256)
 def test_lighting_does_not_change_model_transform(self):
  model={'positions':[1,2,3,-2,0,4]};base=dict(position=[10,20,30],rotation=[0,0,0,1],scale=2,flags=0)
  expected=[12,24,36,6,20,38]
  for flags in (0,2,16,18,20,22,30,146):
   row=dict(base,flags=flags);self.assertEqual(w.doodad_positions(model,row),expected)
 def test_unknown_flag_is_not_a_geometry_waiver(self):
  row=dict(position=[0,0,0],rotation=[0,0,0,1],scale=1,flags=48)
  self.assertNotEqual(unsupported_doodad_flags(row['flags']),0)

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--policy-module',default='wmo_probe');p.add_argument('--profile');p.add_argument('--references');p.add_argument('--output');a=p.parse_args();unsupported_doodad_flags=importlib.import_module(a.policy_module).unsupported_doodad_flags;r=unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(Tests));assert r.wasSuccessful();report=dict(unitTests=r.testsRun,nativeVerified=False)
 if a.references:
  for name,expected in REFERENCES.items():assert sha((pathlib.Path(a.references)/name).read_bytes())==expected
  report['primaryImplementationSHA256']=REFERENCES
 if a.profile:
  raw=pathlib.Path(a.profile).read_bytes();assert sha(raw)==PIN;profile=json.loads(raw);flags=collections.Counter();remaining=[];roots=0;doodads=0
  for record in profile['files']:
   if record['kind']!='WMO':continue
   data=pathlib.Path(record['path']).read_bytes();assert len(data)==record['bytes'] and sha(data)==record['sha256'];root=w.root(data);roots+=1;doodads+=len(root['doodads']);flagged=[]
   for index,row in enumerate(root['doodads']):
    flags[row['flags']]+=1
    if unsupported_doodad_flags(row['flags']):flagged.append(dict(index=index,flags=row['flags'],reference=row['reference']))
   if flagged:remaining.append(dict(fileDataID=record['fileDataID'],sha256=record['sha256'],doodads=flagged))
  assert roots==866 and all(row['flags']&~0xdf==32 for root in remaining for row in root['doodads'])
  report.update(profileSHA256=PIN,roots=roots,doodads=doodads,flagCounts=dict(flags),unsupported=remaining)
 if a.output:pathlib.Path(a.output).write_text(json.dumps(report,sort_keys=True,separators=(',',':')),encoding='utf8')
 print(json.dumps({k:v for k,v in report.items() if k not in ('unsupported','primaryImplementationSHA256')},sort_keys=True));print('remainingRoots',len(report.get('unsupported',[])))
