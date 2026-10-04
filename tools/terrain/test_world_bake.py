"""Source/job/portal regression fixtures; actual source checks are optional."""
import argparse,copy,json,pathlib,tempfile,unittest
from unittest.mock import patch
import terrain_probe,world_projection,world_source as s,world_stitch as stitch
import world_geometry as geometry
def pair():
 source={'profileSHA256':'p','tileWorklistSHA256':'t','projectionSources':{}}
 gen={k:'h' for k in ('wrapperSHA256','boundedWrapperSHA256','filterSHA256')}
 akey='w30:r7:0:0:p0';bkey='w30:r8:0:0:p0'
 pa=dict(key=akey,grid=[7,0,0],points=[[448,0,0],[512,0,0],[512,0,64],[448,0,64]],center=[480,0,32],portals=[dict(to=bkey,left=[512,0,0],right=[512,0,64],meters=64)])
 pb=dict(key=bkey,grid=[8,0,0],points=[[512,0,0],[576,0,0],[576,0,64],[512,0,64]],center=[544,0,32],portals=[dict(to=akey,left=[512,0,64],right=[512,0,0],meters=64)])
 manifest=dict(job=dict(lattice={},source=source),generator=gen)
 a=dict(namespace=(30,0,0),manifest=copy.deepcopy(manifest),polygons={akey:pa},witnesses={bkey:copy.deepcopy(pb)},sha256='a')
 b=dict(namespace=(30,1,0),manifest=copy.deepcopy(manifest),polygons={bkey:pb},witnesses={akey:copy.deepcopy(pa)},sha256='b')
 return a,b

class Tests(unittest.TestCase):
 def test_scheduler_uses_eight_slots_without_exceeding_the_bound(self):
  import threading
  from types import SimpleNamespace
  import world_bake_parallel as scheduler
  jobs=[dict(id="fixture-%d"%i,worldMapID=0,batchGrid=[i,0]) for i in range(24)]
  barrier=threading.Barrier(8,timeout=10);lock=threading.Lock();running=[0,0]
  class Process:
   returncode=0
   def __init__(self,*args,**kwargs):
    with lock:
     running[0]+=1;running[1]=max(running)
    barrier.wait()
   def poll(self):
    with lock:running[0]-=1
    return 0
  with tempfile.TemporaryDirectory() as folder:
   root=pathlib.Path(folder)/"eight-workers"
   args=["world_bake_parallel.py","--root",str(root),"--workers","8"]
   for name in ("profile","expected-sha256","source-directory","tile-csv","topology-inventory","placement-index","index-sha256"):
    args+=["--"+name,"fixture"]
   with patch.object(scheduler.sys,"argv",args),patch.object(scheduler,"Source") as source,\
        patch.object(scheduler.shutil,"disk_usage",return_value=SimpleNamespace(free=16*1024**3)),\
        patch.object(scheduler.subprocess,"Popen",Process),\
        patch.object(scheduler,"verified_run",return_value={job["id"] for job in jobs}) as verified,patch("builtins.print"):
    source.return_value.jobs.return_value=jobs
    scheduler.main()
   progress=json.loads((root/"generation-progress.json").read_bytes())
   self.assertEqual(running,[0,8]);self.assertEqual(progress["completed"],24)
   self.assertEqual(progress["counts"],{"ok":24});self.assertEqual(verified.call_count,24)
   self.assertEqual({row["jobID"] for row in progress["results"]},{job["id"] for job in jobs})
   with patch.object(scheduler.sys,"argv",[arg if arg!="8" else "9" for arg in args]),\
        patch.object(scheduler,"Source") as source:
    with self.assertRaisesRegex(ValueError,"workers must be between 1 and 8"):scheduler.main()
    source.assert_not_called()

 def test_scheduler_progress_windows_sharing_retry_and_retention(self):
  import world_bake_parallel as scheduler
  with tempfile.TemporaryDirectory() as root:
   path=pathlib.Path(root)/'generation-progress.json'
   original=pathlib.Path.replace
   attempts=[]
   def busy_reader(source,destination):
    attempts.append(1)
    if len(attempts)<3:raise PermissionError('Windows reader sharing')
    return original(source,destination)
   with patch.object(pathlib.Path,'replace',busy_reader),patch.object(scheduler.time,'sleep'):
    scheduler.atomic(path,dict(completed=1))
   self.assertEqual(json.loads(path.read_bytes()),dict(completed=1))
   self.assertEqual(len(attempts),3)
   with patch.object(pathlib.Path,'replace',side_effect=PermissionError('reader')) as replace,patch.object(scheduler.time,'sleep'):
    with self.assertRaises(PermissionError):scheduler.atomic(path,dict(completed=2))
    self.assertEqual(replace.call_count,40)
   self.assertEqual(json.loads(path.read_bytes()),dict(completed=1))
   self.assertEqual(json.loads(path.with_name(path.name+'.next').read_bytes()),dict(completed=2))

 def test_full_index_footprint_survives_smaller_modf_bounds(self):
  placement=dict(kind='wmo',reference=7,uniqueID=8,scale=1024,flags=12,doodadSet=0)
  job=dict(worldMapID=30,batchGrid=[0,0],inputXZ=[0,0,10,10],ownedXZ=[0,0,10,10],tiles=[])
  class Source:
   used={};tiles={}
   def job(self,*args):return job
   def asset(self,*args):return b''
  class Index:
   sha256='index'
   def query(self,*args):return [placement]
  model=dict(positions=[1,0,1,2,0,1,1,0,2],indices=[0,1,2],doodadReferences=[],unsupported=[])
  root=dict(groups=[9],flags=4,unknownChunks=[],doodads=[])
  with patch.object(geometry.wmo,'placement_bounds',return_value=[[20,0,20],[21,1,21]]),patch.object(geometry.wmo,'root',return_value=root),patch.object(geometry.wmo,'group',return_value=model),patch.object(geometry.wmo,'selected_doodads',return_value=([],[])),patch.object(geometry.collision,'transformed',side_effect=lambda m,p:m['positions']):
   # A contradicted MODF box cannot drop the full indexed geometry before exclusion.
   calls=[]
   real=geometry.collision.bounds
   def captured(points):calls.append(points);return real(points)
   with patch.object(geometry.collision,'bounds',side_effect=captured):
    result=geometry.geometry(Source(),job,Index())
   self.assertTrue(any(points==model['positions'] for points in calls))
   self.assertEqual(result['indices'],[0,1,2]);self.assertFalse([r for r in result['exclusions'] if r['reason']!='unsourced-physical-tile'])
   self.assertEqual(result['coverageGates'][0]['bounds'],[[1,0,1],[21,1,21]])
   self.assertIn('WMO-transform-outside-MODF-bounds',result['coverageGates'][0]['reasons'])
 def test_unknown_physics_is_excluded_not_fatal(self):
  job=dict(worldMapID=0,batchGrid=[0,0],inputXZ=[0,0,100,100],ownedXZ=[0,0,100,100],tiles=[])
  box=[[40,-5,40],[60,20,60]]
  class Source:
   used={};tiles={}
   def job(self,*args):return job
  class Index:
   sha256='index'
   def query(self,*args):return []
   def unknown_exclusions(self,*args):return [dict(kind='m2',uniqueID=5,reference=304027,reason='unbounded-model-physics:304027',bounds=box)]
  result=geometry.geometry(Source(),job,Index())
  rows=[r for r in result['exclusions'] if r['reason']=='unknown-physics-extent']
  self.assertEqual(len(rows),1);self.assertEqual(rows[0]['bounds'],box);self.assertEqual(rows[0]['fileDataID'],304027)
  self.assertEqual(result['statistics']['excludedUnknownExtentPlacements'],1)
 def _index(self,rows):
  import sqlite3,world_placements as wp
  db=sqlite3.connect(':memory:')
  db.executescript('CREATE TABLE placements(id INTEGER PRIMARY KEY,world INTEGER NOT NULL,kind TEXT NOT NULL,uid INTEGER NOT NULL,body TEXT NOT NULL,bounds TEXT,reason TEXT); CREATE VIRTUAL TABLE extents USING rtree(id,minX,maxX,minZ,maxZ);')
  for uid,box,reason in rows:
   body=json.dumps(dict(kind='m2',uniqueID=uid,reference=uid*10))
   c=db.execute('INSERT INTO placements(world,kind,uid,body,bounds,reason) VALUES(0,?,?,?,?,?)',('m2',uid,body,json.dumps(box) if box else None,reason))
   if box:db.execute('INSERT INTO extents VALUES(?,?,?,?,?)',(c.lastrowid,box[0][0],box[1][0],box[0][2],box[1][2]))
  self.addCleanup(db.close)
  index=object.__new__(wp.Index);index.db=db;return index
 def test_index_separates_unknown_footprints(self):
  import world_placements as wp
  known=[[0,0,0],[10,1,10]];unknown=wp.padded([[20,0,20],[22,2,22]])
  self.assertEqual(unknown,[[12,-8,12],[30,10,30]])
  index=self._index([(1,known,None),(2,unknown,'unbounded-model-physics:9')])
  self.assertEqual([p['uniqueID'] for p in index.query(0,[0,0,100,100])],[1])
  rows=index.unknown_exclusions(0,[0,0,100,100]);self.assertEqual([(r['uniqueID'],r['bounds']) for r in rows],[(2,unknown)])
  self.assertEqual(index.unknown_exclusions(0,[50,50,60,60]),[])
 def test_undecodable_footprint_still_blocks_world(self):
  index=self._index([(1,[[0,0,0],[1,1,1]],None),(3,None,'unbounded-model-physics:9')])
  with self.assertRaisesRegex(ValueError,'unbounded world placement extents'):index.query(0,[0,0,100,100])
 def test_tile_axes(self):self.assertEqual(s.tile_rect(32,32),[-s.terrain.TILE,-s.terrain.TILE,0,0])
 def test_world_namespace(self):self.assertNotEqual(s.polygon_key(0,1,2,0,0),s.polygon_key(1,1,2,0,0))
 def test_fixed_batch_bounds(self):self.assertEqual(s.batch_rect(-1,0),[-512,0,0,512]);self.assertEqual(s.BORDER,1.25)
 def test_reciprocal_seam(self):
  a,b=pair();r=stitch.admit(a,b);self.assertEqual(len(r['directedLinks']),2);self.assertEqual(r['exactWitnessMatches'],2)
 def test_never_cross_world(self):
  a,b=pair();b['namespace']=(1,1,0)
  with self.assertRaisesRegex(ValueError,'share a world'):stitch.admit(a,b)
 def test_not_nearest_join(self):
  a,b=pair();next(iter(b['polygons'].values()))['points'][0][0]+=.001
  with self.assertRaisesRegex(ValueError,'geometry mismatch'):stitch.admit(a,b)
 def test_missing_reciprocal(self):
  a,b=pair();next(iter(b['polygons'].values()))['portals']=[]
  with self.assertRaisesRegex(ValueError,'reciprocal'):stitch.admit(a,b)
 def test_source_pin_mismatch(self):
  a,b=pair();b['manifest']['job']['source']['profileSHA256']='changed'
  with self.assertRaisesRegex(ValueError,'source mismatch'):stitch.admit(a,b)
 def test_interval_intersection(self):
  a,b=pair();next(iter(b['polygons'].values()))['portals'][0]['left'][2]=63
  result=stitch.admit(a,b);self.assertEqual(result['normalization']['narrowedDirectedLinks'],1)
  self.assertEqual(result['normalization']['minimumRetainedWidth'],63)
  self.assertEqual(result['normalization']['maxEndpointDiscrepancy'],1)
  self.assertTrue(all(0<=p[2]<=63 for row in result['directedLinks'] for p in (row['left'],row['right'])))
 def test_disjoint_intervals(self):
  f=dict(left=[0,0,0],right=[0,0,2]);r=dict(left=[0,0,3],right=[0,0,4])
  with self.assertRaisesRegex(ValueError,'disjoint'):stitch.shared_interval(f,r)
 def test_touch_only_intervals(self):
  f=dict(left=[0,0,0],right=[0,0,2]);r=dict(left=[0,0,2],right=[0,0,4])
  with self.assertRaisesRegex(ValueError,'touch-only'):stitch.shared_interval(f,r)
 def test_off_line_interval(self):
  f=dict(left=[0,0,0],right=[0,0,2]);r=dict(left=[1,0,0],right=[1,0,2])
  with self.assertRaisesRegex(ValueError,'off source boundary'):stitch.shared_interval(f,r)
 def test_intersection_does_not_waive_step(self):
  a,b=pair();other=next(iter(b['polygons'].values()))
  for point in other['points']:point[1]=2
  other['center'][1]=2
  for edge in other['portals']:edge['left'][1]=2;edge['right'][1]=2
  a['witnesses'][other['key']]=copy.deepcopy(other)
  with self.assertRaisesRegex(ValueError,'step mismatch'):stitch.admit(a,b)
 def test_convex_and_center(self):
  a,_=pair();row=next(iter(a['polygons'].values()));stitch.validate_poly(row);row['center'][1]=1
  with self.assertRaisesRegex(ValueError,'center mismatch'):stitch.validate_poly(row)
 def test_source_expected_hash(self):
  with tempfile.TemporaryDirectory() as root:
   path=pathlib.Path(root)/'profile.json';path.write_text('{}')
   with self.assertRaisesRegex(ValueError,'source hash mismatch'):s.Source(path,'0'*64,root,path,path)

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--actual-source-directory');p.add_argument('--profile');p.add_argument('--expected-sha256');p.add_argument('--first-bake');p.add_argument('--second-bake');p.add_argument('--receipt');a,unknown=p.parse_known_args()
 result=unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(Tests));need=result.wasSuccessful()
 if not need:raise SystemExit(1)
 receipt={'unitTests':result.testsRun,'nativeVerified':False}
 if a.actual_source_directory:
  r=pathlib.Path(a.actual_source_directory);path=pathlib.Path(a.profile);source=s.Source(path,a.expected_sha256,r,r/'all-projected-world-tile-worklist.csv',r/'inventory.json');jobs=source.jobs()
  assert source.tiles and jobs and len({j['id'] for j in jobs})==len(jobs)
  assert set(j['worldMapID'] for j in jobs)==set(source.wdts)
  assert all(len(j['tiles'])<=9 and j['bakeXZ']==s.expand(j['ownedXZ'],64) and j['inputXZ']==s.expand(j['bakeXZ'],1.25) for j in jobs)
  receipt['actualSource']={'tiles':len(source.tiles),'jobs':len(jobs),'maxInputADTs':max(len(j['tiles']) for j in jobs),'profileSHA256':source.profile_sha}
 if a.first_bake and a.second_bake:
  batches=[]
  for path in (a.first_bake,a.second_bake):
   path=pathlib.Path(path);batches.append(stitch.load(path,s.sha((path/'manifest.json').read_bytes())))
  proof=stitch.admit(*batches);assert len(proof['directedLinks'])>0
  receipt['actualSeam']={'directedLinks':len(proof['directedLinks']),'exactWitnessMatches':proof['exactWitnessMatches'],'proofSHA256':s.sha(s.canonical(proof))}
 if a.receipt:
  with pathlib.Path(a.receipt).open('xb') as f:f.write(s.canonical(receipt))
 print(json.dumps(receipt))
