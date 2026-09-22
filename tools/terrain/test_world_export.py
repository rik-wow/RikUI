"""Exact export/gateway fixtures; optional replay and installed source audit."""
import argparse,copy,json,math,pathlib,tempfile,unittest
import world_export as export
import world_export_graph as graph
from world_source import canonical,sha

class Assignment:
 id=1;ui_map_id=1459;world_map_id=30;supported=True
 game_x_min=-1000;game_x_max=1000;game_y_min=-1000;game_y_max=1000
 def record(self):
  return dict(projection=dict(originX=1000,originY=1000,width=2000,height=2000),validUIRectangle=dict(minX=0,minY=0,maxX=1,maxY=1),validWorldRectangle=dict(minX=-1000,minZ=-1000,maxX=1000,maxZ=1000,minY=-10000,maxY=10000))
class Catalog:assignments=[Assignment()]

def fixture():
 points=[[0,0,0],[64,0,0],[64,.1,64],[0,.1,64]];key='w30:r0:0:0:p0'
 batch=dict(namespace=(30,0,0),sha256='a'*64,receiptSHA256='b'*64,manifest=dict(job=dict(ownedXZ=[0,0,512,512])),polygons={key:dict(key=key,points=points,portals=[])})
 return dict(batches={(30,0,0):batch},sourceProfileSHA256='c'*64,indexSHA256='d'*64,seams=[])

def row(i,first='W30_Xp0_Zp0',last='W30_Xp1_Zp0'):
 return dict(id=sha(str(i).encode()),worldMapID=30,fromNamespace=first,toNamespace=last,fromID=i+1,toID=i+2,fromKey='w30:r7:0:0:p0',toKey='w30:r8:0:0:p0',left=[512,0,0],right=[512,0,64],midpoint=[512,0,32],meters=64,authoredCenterCost=64,proofSHA256='a'*64)

class Tests(unittest.TestCase):
 def test_required_gateway_without_region_crossing(self):
  adjacency={1:[(2,2,1)],2:[(3,3,2)],3:[],4:[]};owners={n:1 for n in adjacency}
  network,trees,used,boundary=graph.contract_gateways(adjacency,owners,{1,3,4})
  self.assertEqual(boundary,{1,3,4});self.assertEqual(network[1],[(3,5,None)]);self.assertEqual(network[3],[]);self.assertEqual(network[4],[])
  self.assertEqual(trees[1],[[2,1,1],[3,2,2]]);self.assertEqual(used,{1,2})
 def test_required_gateway_exact_directed_distances(self):
  adjacency={1:[(2,2,1),(3,9,2)],2:[(3,3,3),(4,8,4)],3:[(4,1,5)],4:[(2,7,6)]};owners={1:1,2:1,3:2,4:2}
  network,_,_,boundary=graph.contract_gateways(adjacency,owners,{1,4})
  for start in boundary:
   original=graph.backbone.dijkstra(adjacency,{start:0})[0];coarse=graph.backbone.dijkstra(network,{start:0})[0]
   for target in boundary:self.assertEqual(original.get(target),coarse.get(target))
 def test_existing_boundary_regression(self):
  adjacency={1:[(2,1,1)],2:[(3,2,2)],3:[]};owners={1:1,2:1,3:2}
  expected=graph.backbone.contract(adjacency,owners)
  self.assertEqual(graph.contract_gateways(adjacency,owners),expected[:4])
 def test_absent_required_gateway_rejected(self):
  with self.assertRaisesRegex(ValueError,'missing'):graph.contract_gateways({1:[]},{1:1},{2})
 def test_float_geometry_normalized_before_hash(self):
  group=graph.group_graph(fixture(),[(30,0,0)],Catalog());self.assertTrue(all(type(v) is float for p in group['nodes'][1]['points'] for v in p))
  self.assertEqual(group['sourceKeys'],['w30:r0:0:0:p0']);self.assertEqual(group['metadata']['worldMapID'],30)
 def test_never_group_distinct_worlds(self):
  admitted=fixture();other=copy.deepcopy(admitted['batches'][(30,0,0)]);other['namespace']=(1,0,0);admitted['batches'][(1,0,0)]=other
  with self.assertRaisesRegex(ValueError,'crosses worlds'):graph.group_graph(admitted,[(30,0,0),(1,0,0)],Catalog())
 def test_expected_hash_rejects_modified_input(self):
  with tempfile.TemporaryDirectory() as root:
   path=pathlib.Path(root)/'input.json';path.write_bytes(b'{}')
   with self.assertRaisesRegex(ValueError,'hash mismatch'):graph.read(path,'0'*64,1024)
 def test_seam_payload_bounded_directed_deterministic(self):
  rows=[row(i) for i in range(257)];files,parts=export.seam_files(rows)
  self.assertEqual(sum(p['rows'] for p in parts),257);self.assertTrue(all(p['rows']<=128 and p['bytes']<=32768 and p['fromNamespace']!=p['toNamespace'] for p in parts))
  self.assertTrue(all(p['fromNamespace']=='W30_Xp0_Zp0' for p in parts));self.assertEqual((files,parts),export.seam_files(rows))
  self.assertEqual(sum(path.endswith('/seams.lua') for path in files),len(parts))
 def test_replay_rejects_mutated_payload(self):
  with tempfile.TemporaryDirectory() as root:
   target=pathlib.Path(root)/'new';files={'a.lua':b'return 1\n'};export.compact.write_or_verify(files,target);export.compact.write_or_verify(files,target,True)
   (target/'a.lua').write_bytes(b'return 2\n')
   with self.assertRaises(ValueError):export.compact.write_or_verify(files,target,True)

def verify_artifact(root):
 root=pathlib.Path(root);receipt=json.loads((root/'world-export-receipt.json').read_bytes());assert receipt['nativeVerified'] is False
 expected=set()
 for record in receipt['files']:
  path=(root/record['path']).resolve();assert path.is_relative_to(root.resolve());raw=path.read_bytes();assert len(raw)==record['bytes'] and sha(raw)==record['sha256'];expected.add(record['path'])
 actual={p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()};assert actual==expected|{'world-export-receipt.json'}
 audits={};total=0
 for pack in receipt['packs']:
  audit=json.loads((root/'audit'/str(pack['namespace']+'.json')).read_bytes());assert audit['nativeVerified'] is False
  assert len(audit['sourceKeys'])==pack['polygons'];assert len(set(audit['sourceKeys']))==pack['polygons']
  assert all(graph.stitch.key(k)[0]==pack['worldMapID'] for k in audit['sourceKeys']);assert audit['graphSHA256']==pack['graphSHA256']
  audits[pack['namespace']]=audit;total+=pack['polygons']
 ledger=json.loads((root/'world-pack-seams.json').read_bytes());assert ledger['nativeVerified'] is False and len(ledger['seams'])==receipt['seams']
 for seam in ledger['seams']:
  for prefix in ('from','to'):
   audit=audits[seam[prefix+'Namespace']];ident=seam[prefix+'ID'];assert audit['sourceKeys'][ident-1]==seam[prefix+'Key'];assert ident in audit['gatewayOriginalIDs'];assert audit['metadata']['worldMapID']==seam['worldMapID']
  assert seam['midpoint']==[(x+y)/2 for x,y in zip(seam['left'],seam['right'])]
  assert seam['meters']==seam['authoredCenterCost'] and seam['meters']>0 and math.dist(seam['left'],seam['right'])>0
  assert seam['id']==sha(canonical(dict(worldMapID=seam['worldMapID'],fromKey=seam['fromKey'],toKey=seam['toKey'],left=seam['left'],right=seam['right'])))
 return dict(packs=len(audits),polygons=total,seams=len(ledger['seams']),files=len(actual),nativeVerified=False)

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--artifact');p.add_argument('--source-directory');p.add_argument('--receipt');a=p.parse_args()
 result=unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(Tests));assert result.wasSuccessful()
 report=dict(unitTests=result.testsRun,nativeVerified=False)
 if a.source_directory:
  catalog=graph.projection.Catalog(a.source_directory);views=[graph.view_record(v) for v in catalog.assignments if v.ui_map_id==947]
  assert len(views)==2 and len({v['worldMapID'] for v in views})==2 and all(v['validUIRectangle']!=[0,0,1,1] for v in views)
  assert len({v['projectionSHA256'] for v in views})==2;report['partialAssignmentBindings']=len(views)
 if a.artifact:report['artifact']=verify_artifact(a.artifact)
 if a.receipt:pathlib.Path(a.receipt).write_bytes(canonical(report))
 print(json.dumps(report))
