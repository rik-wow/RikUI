import argparse,csv,dataclasses,hashlib,math,pathlib,tempfile,unittest,json,sys
sys.path.insert(0,str(pathlib.Path(__file__).parent))
import world_projection as p
SOURCE=None
class ProjectionTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):cls.cat=p.Catalog(SOURCE)
 def test_exact_build_inventory(self):
  self.assertTrue(0<len(self.cat.map_rows)<=256);self.assertEqual(len(self.cat.ui_rows),60)
  self.assertEqual(len(self.cat.assignments),61)
  self.assertEqual({a.world_map_id for a in self.cat.assignments},{0,1,30,489,529,2991,2997})
  self.assertTrue(all(a.supported for a in self.cat.assignments))
 def test_all_assignment_corner_midpoint_roundtrips(self):
  for a in self.cat.assignments:
   for u in [a.u_min,(a.u_min+a.u_max)/2,a.u_max]:
    for v in [a.v_min,(a.v_min+a.v_max)/2,a.v_max]:
     with self.subTest(assignment=a.id,u=u,v=v):
      w=a.to_world(u,v);uv=a.to_ui(w['x'],w['z'])
      self.assertAlmostEqual(u,uv['x'],places=12);self.assertAlmostEqual(v,uv['y'],places=12)
      expectedX=a.game_y_max-(u-a.u_min)/(a.u_max-a.u_min)*(a.game_y_max-a.game_y_min)
      expectedZ=a.game_x_max-(v-a.v_min)/(a.v_max-a.v_min)*(a.game_x_max-a.game_x_min)
      self.assertAlmostEqual(w['x'],expectedX,places=8);self.assertAlmostEqual(w['z'],expectedZ,places=8)
 def test_dun_morogh_exact_existing_contract(self):
  a=self.cat.by_id[46736];value=a.projection()
  for key,expected in {'originX':-3877.0832519531,'originY':1802.0832519531,'width':4924.9997558593,'height':3283.3332519531}.items():
   self.assertAlmostEqual(value[key],expected,places=8)
  self.assertAlmostEqual(a.to_world(0,0)['x'],1802.0832519531,places=8)
  self.assertAlmostEqual(a.to_world(0,0)['z'],-3877.0832519531,places=8)
  self.assertAlmostEqual(a.to_world(1,1)['x'],-3122.9165039062,places=9)
  self.assertAlmostEqual(a.to_world(1,1)['z'],-7160.4165039062,places=9)
 def test_partial_world_ui_is_not_full_rectangle(self):
  a=self.cat.by_id[46784];b=self.cat.by_id[46785]
  self.assertEqual(a.ui_map_id,947);self.assertEqual(b.ui_map_id,947)
  self.assertNotEqual(a.projection()['originY'],a.game_y_max)
  for row in [a,b]:
   with self.assertRaises(ValueError):row.to_world(0,0)
   nw=row.to_world(row.u_min,row.v_min)
   self.assertAlmostEqual(nw['x'],row.game_y_max,places=8)
   self.assertAlmostEqual(nw['z'],row.game_x_max,places=8)
  self.assertEqual(self.cat.candidates_ui(947,.5,.5),())
  self.assertEqual([r.world_map_id for r in self.cat.candidates_ui(947,.7,.5)],[0])
  self.assertEqual([r.world_map_id for r in self.cat.candidates_ui(947,.2,.5)],[1])
  self.assertEqual(self.cat.candidates_ui(947,.2,.5,0),())
 def test_axis_binding_and_elevation_are_explicit(self):
  a=self.cat.by_id[46736];nw=a.to_world(0,0);east=a.to_world(1,0);south=a.to_world(0,1)
  self.assertLess(east['x'],nw['x']);self.assertEqual(east['z'],nw['z'])
  self.assertLess(south['z'],nw['z']);self.assertEqual(south['x'],nw['x'])
  self.assertFalse(a.contains_world(nw['x'],nw['z'],1000001))
 def test_nonfinite_and_bad_projection(self):
  a=self.cat.by_id[46736]
  for number in [math.nan,math.inf,-math.inf]:
   with self.assertRaises(ValueError):a.to_world(number,.5)
   with self.assertRaises(ValueError):a.to_ui(0,number)
  wmo=dataclasses.replace(a,wmo_group_id=1)
  self.assertFalse(wmo.supported)
  with self.assertRaises(ValueError):wmo.to_world(.5,.5)
 def test_boundary_tolerance_does_not_admit_real_outside_points(self):
  a=self.cat.by_id[46736]
  self.assertFalse(a.contains_world(a.game_y_min-1e-7,a.game_x_min))
  self.assertFalse(a.contains_ui(-1e-10,.5))
  self.assertTrue(a.contains_world(math.nextafter(a.game_y_min,-math.inf),a.game_x_min))
 def test_duplicate_views_remain_independent(self):
  a=self.cat.by_id[46736];copy=dataclasses.replace(a,id=999999,ui_map_id=999999)
  self.assertEqual(a.projection(),copy.projection())
  self.assertNotEqual(a.record()['assignmentID'],copy.record()['assignmentID'])
  self.assertEqual(a.intersects_tile(30,40),copy.intersects_tile(30,40))
 def test_tile_dedupe_and_seam_are_world_scoped(self):
  a=p.tile_key(0,30,40);b=p.tile_key(1,30,40)
  self.assertNotEqual(a,b)
  self.assertEqual(p.seam_key(0,(30,40),(31,40)),p.seam_key(0,(31,40),(30,40)))
  self.assertNotEqual(p.seam_key(0,(30,40),(31,40)),p.seam_key(1,(30,40),(31,40)))
  with self.assertRaises(ValueError):p.seam_key(0,(30,40),(31,41))
  with self.assertRaises(ValueError):p.tile_key(0,64,0)
  west=p.tile_bounds(30,40);east=p.tile_bounds(31,40)
  self.assertEqual(west['minX'],east['maxX'])
 def test_actual_world_inventory_preserves_unknown_maps(self):
  result=p.inventory(SOURCE,SOURCE/'all-projected-world-tile-worklist.csv')
  self.assertEqual(result['counts']['worldTiles'],1888)
  self.assertEqual(result['counts']['zoneViews'],51)  # current local DB2 evidence; older Wago snapshot differed
  self.assertEqual(sum(m['projectionStatus']=='no-UiMapAssignment-source' for m in result['maps']),len(self.cat.map_rows)-len({a.world_map_id for a in self.cat.assignments}))
  self.assertEqual(len({(r['worldMapID'],r['x'],r['y']) for r in result['tiles']}),1888)
  self.assertEqual(len({r['rootADT'] for r in result['tiles']}),1888)
  self.assertTrue(any(len(r['uiMapIDs'])>1 for r in result['tiles']))
  self.assertTrue(any(m['topologyStatus']=='not-inspected' for m in result['maps']))
 def test_exact_source_hash_rejection(self):
  with tempfile.TemporaryDirectory(prefix='projection-test-') as folder:
   name='Map-'+p.BUILD+'.csv';path=pathlib.Path(folder)/name
   path.write_bytes((SOURCE/name).read_bytes()+b'\n')
   with self.assertRaisesRegex(ValueError,'source hash mismatch'):p.read_source(folder,'Map')
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--source-directory',required=True)
 args=parser.parse_args();SOURCE=pathlib.Path(args.source_directory)
 unittest.main(argv=['verify_world_projection'],verbosity=2)
