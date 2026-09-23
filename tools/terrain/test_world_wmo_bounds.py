"""Invalid WMO set and physics bounds cannot shrink to the MODF author box."""
import copy,unittest
from unittest import mock
import world_placements as p
import world_geometry as g

class Source:
 def __init__(self,job):self.task=job;self.used={};self.tiles={(30,32,32):{}}
 def job(self,*_):return self.task
 def asset(self,*_):return b'fixture'
class Index:
 sha256='a'*64
 def __init__(self,placement):self.placement=placement
 def query(self,*_):return [self.placement]

def fixture(invalid=True,physics=None,group_flags=0):
 job=dict(worldMapID=30,batchGrid=[0,0],ownedXZ=[0,0,512,512],inputXZ=[-5,-5,400,100],tiles=[dict(rootADT=1,obj0ADT=2,tile=[32,32])])
 placement=dict(kind='wmo',uniqueID=99,reference=3,scale=1024,flags=12,doodadSet=1 if invalid else 0)
 root=dict(groups=[4],flags=0,unknownChunks=[],sets=[dict(first=0,count=1)],doodads=[dict(reference=5,flags=16,position=[100,0,0],rotation=[0,0,0,1],scale=1)])
 model=dict(positions=[0,0,0,1,0,0,0,0,1],indices=[0,1,2],chunks=[])
 if physics:
  model=dict(positions=[],indices=[],chunks=[physics])
  if physics=='PCOL':model['physicsExtent']=dict(positions=[200,0,0,210,10,10])
 group=dict(positions=[0,0,0,1,0,0,0,0,1],indices=[0,1,2],doodadReferences=[],unsupported=[],flags=group_flags)
 row=dict(position=[0,0,0],subchunks=[],x=0,y=0)
 with mock.patch.object(g.t,'root',return_value=([row],['MVER'])),mock.patch.object(g.t,'objects',return_value=([],['MVER'],[])),mock.patch.object(g.t,'mesh',return_value=([0,0,0,1,0,0,0,0,1],[0,1,2],0)),mock.patch.object(g.liquid,'liquid',return_value=([],[],[],[])),mock.patch.object(g.wmo,'root',return_value=root),mock.patch.object(g.wmo,'group',return_value=group),mock.patch.object(g.wmo,'placement_bounds',return_value=[[0,0,0],[1,1,1]]),mock.patch.object(g.collision,'m2',return_value=model),mock.patch.object(g.collision,'transformed',side_effect=lambda m,_:m['positions']):
  return g.geometry(Source(job),job,Index(placement))

class Tests(unittest.TestCase):
 def test_valid_set_scope_remains_selected(self):
  root=dict(sets=[dict(first=0,count=1),dict(first=2,count=1)],doodads=[{}, {}, {}])
  self.assertEqual(p.doodad_extent_scope(root,1),([0,2],None))
 def test_invalid_set_union_is_explicitly_unknown(self):
  root=dict(sets=[dict(first=0,count=1)],doodads=[{}, {}, {}])
  self.assertEqual(p.doodad_extent_scope(root,3),([0,1,2],'WMO-selected-set-range'))
 def test_other_selection_errors_not_downgraded(self):
  with mock.patch.object(p.w,'selected_doodads',side_effect=ValueError('corrupt-root')):
   with self.assertRaisesRegex(ValueError,'corrupt-root'):p.doodad_extent_scope({},0)
 def test_invalid_set_is_audited_and_keeps_parsed_geometry(self):
  result=fixture();gate=result['coverageGates'][0]
  self.assertIn('WMO-selected-set-range',gate['reasons']);self.assertEqual(gate['bounds'][1][0],101)
  self.assertEqual(gate['reason'],'approximated-WMO');self.assertFalse([r for r in result['exclusions'] if r['reason']!='unsourced-physical-tile'])
  self.assertEqual(result['statistics']['wmoInstances'],1);self.assertEqual(len(result['indices']),9)
 def test_empty_static_child_physics_still_expands_audit_bounds(self):
  result=fixture(False,'PCOL');gate=result['coverageGates'][0]
  self.assertIn('extra-doodad-physics:PCOL',gate['reasons']);self.assertEqual(gate['bounds'][1][0],310)
  self.assertEqual(len(result['indices']),6)
 def test_antiportal_group_adds_no_collision(self):
  result=fixture(False,None,g.ANTIPORTAL_GROUP)
  self.assertEqual(result['statistics']['skippedAntiportalGroups'],1);self.assertEqual(len(result['indices']),6)
 def test_unknown_physics_doodad_is_skipped_not_the_wmo(self):
  result=fixture(False,'PFDC');gate=result['coverageGates'][0]
  self.assertIn('skipped-unknown-physics-doodad',gate['reasons'])
  self.assertEqual(result['statistics']['skippedUnknownPhysicsDoodads'],1)
  self.assertEqual(len(result['indices']),6)  # terrain and the WMO group, no doodad
 def test_known_physics_requires_extent_even_when_empty(self):
  with self.assertRaisesRegex(ValueError,'unbounded-model-physics:5'):p.model_extent_positions(dict(positions=[],chunks=['PCOL']),5)

if __name__=='__main__':unittest.main()
