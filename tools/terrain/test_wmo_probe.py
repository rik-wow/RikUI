import copy,json,math,os,pathlib,struct,tempfile,unittest
import wmo_probe as w
import terrain_probe as t
HERE=pathlib.Path(__file__).parent
if not os.environ.get('RIKUI_TERRAIN_ACQUISITION'):
    raise RuntimeError('Set RIKUI_TERRAIN_ACQUISITION to the verified external acquisition directory')
ROOT=pathlib.Path(os.environ['RIKUI_TERRAIN_ACQUISITION'])

def chunk(tag,data):return tag[::-1].encode()+struct.pack('<I',len(data))+data

def replace(data,tag,operation):
    result=b''
    for name,a,b in t.chunks(data):result+=chunk(name,operation(data[a:b]) if name==tag else data[a:b])
    return result

class WMOTests(unittest.TestCase):
    def setUp(self):
        self.root=(ROOT/'collision/113875.bin').read_bytes()
        self.group=(ROOT/'wmo-groups/113876.bin').read_bytes()
    def test_actual_root_records_bound_sets(self):
        root=w.root(self.root);self.assertEqual(root['framedDoodadCount'],527)
        self.assertEqual(root['advertisedDoodadCount'],538)
        sets,rows=w.selected_doodads(root,1);self.assertEqual(sets,[0,1]);self.assertEqual(len(rows),72)
        self.assertEqual(w.selected_doodads(root,0)[1],list(range(4)))
    def test_reject_selected_set_outside_table(self):
        with self.assertRaises(ValueError):w.selected_doodads(w.root(self.root),5)
    def test_reject_truncated_root(self):
        with self.assertRaises(ValueError):w.root(self.root[:-1])
    def test_reject_unknown_version(self):
        with self.assertRaises(ValueError):w.root(replace(self.root,'MVER',lambda _:struct.pack('<I',18)))
    def test_reject_duplicate_chunks(self):
        with self.assertRaises(ValueError):w.root(self.root+chunk('MVER',struct.pack('<I',17)))
    def test_reject_set_exceeding_framed_records(self):
        def bad(data):
            b=bytearray(data);struct.pack_into('<I',b,24,528);return b
        with self.assertRaises(ValueError):w.root(replace(self.root,'MODS',bad))
    def test_preserve_collision_only_material(self):
        result=w.group(self.group);self.assertGreater(result['collisionOnlyMaterialTriangles'],0)
        self.assertTrue(w.collision_face(8));self.assertTrue(w.collision_face(32))
        self.assertFalse(w.collision_face(36));self.assertTrue(w.collision_face(12))
        self.assertFalse(w.collision_face(4));self.assertFalse(w.collision_face(0))
    def test_reject_invalid_group_vertex_index(self):
        def modify_mogp(raw):
            return raw[:68]+replace(raw[68:],'MOVI',lambda a:struct.pack('<H',65535)+a[2:])
        with self.assertRaises(ValueError):w.group(replace(self.group,'MOGP',modify_mogp))
    def test_reject_nonfinite_group(self):
        def modify_mogp(raw):return raw[:68]+replace(raw[68:],'MOVT',lambda a:struct.pack('<f',math.nan)+a[4:])
        with self.assertRaises(ValueError):w.group(replace(self.group,'MOGP',modify_mogp))
    def test_liquid_gates_instead_of_certification(self):
        def modify_mogp(raw):
            b=bytearray(raw);struct.pack_into('<I',b,52,1);return b
        self.assertIn('WMO-liquid-not-modeled',w.group(replace(self.group,'MOGP',modify_mogp))['unsupported'])
    def test_unknown_group_chunk_gates(self):
        result=w.group(replace(self.group,'MOGP',lambda a:a+chunk('TEST',b'')))
        self.assertIn('unknown-group-chunk:TEST',result['unsupported'])
    def test_version274_profile_exact_empty_sample(self):
        data=(ROOT/'wmo-doodads/314951.bin').read_bytes();m=w.demonstrated_empty_274(data)
        self.assertEqual(m['version'],274);self.assertEqual(m['indices'],[]);self.assertEqual(m['positions'],[])
        with self.assertRaises(ValueError):w.demonstrated_empty_274(data[:-1]+bytes([data[-1]^1]))
    def test_reject_wrong_receipt_product_or_build(self):
        data=json.loads((ROOT/'extraction-manifest.json').read_text())
        for key,value in (('product','wow_classic'),('version','1.15.0'),('buildConfig','0'*32),('cdnConfig','0'*32)):
            bad=dict(data);bad[key]=value
            with self.assertRaises(ValueError):w.receipt_identity(bad)
    def test_transforms_against_pinned_primary_source(self):
        result=json.loads((HERE/'wmo-transform-validation.json').read_text())
        self.assertEqual(result['cases'],384);self.assertLess(result['maxErrorYards'],0.002)
    def test_complete_artifact_keeps_count_uncertainty_gate(self):
        result=w.build(HERE/'geometry-full.json',ROOT,ROOT/'recursive-dependencies-manifest.json')
        self.assertEqual(result['audit']['counts']['selectedDoodadInstances'],707)
        self.assertEqual(result['audit']['counts']['demonstratedEmpty274Instances'],9)
        self.assertEqual({r['placementID'] for r in result['audit']['placements']},{100929,100930,101588,125539})
        self.assertTrue(result['coverage']['allGroupDoodadRefsInRange'])
        self.assertTrue(result['coverage']['framedSelectedStaticDecoded'])
        self.assertFalse(result['coverage']['staticWMO']);self.assertFalse(result['publishable']);self.assertFalse(result['nativeVerified'])
        self.assertEqual(len(result['audit']['unsupported']),3)
        self.assertTrue(all(r['reason']=='MOHD-doodad-count-disagrees-with-framed-MODD' for r in result['audit']['unsupported']))
        self.assertTrue(all(i<len(result['positions'])//3 for i in result['indices']))
    def test_forged_geometry_placements_are_rejected(self):
        data=json.loads((HERE/'geometry-full.json').read_text());data['placements'][0]['position'][0]+=1
        with tempfile.TemporaryDirectory(prefix='rikui-wmo-test-') as directory:
            p=pathlib.Path(directory)/'bad.json';p.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError,'WMO-placement-provenance'):w.build(p,ROOT,ROOT/'recursive-dependencies-manifest.json')

if __name__=='__main__':unittest.main()
