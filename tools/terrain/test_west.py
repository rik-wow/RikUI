"""Boundary and exact-source checks for the west/central Dun Morogh delivery."""
import argparse,copy,json,pathlib,struct,sys,unittest
import terrain_probe as t
import terrain_region as region
import west_profile as west
import wmo_probe as w
import collision_probe as c
import coverage_contract as coverage
from terrain_contract import CompileError

def replace(data,tag,fn):
    return b''.join(name[::-1].encode()+struct.pack('<I',len(value))+value
        for name,a,b in t.chunks(data) for value in [fn(data[a:b]) if name==tag else data[a:b]])

class WestTests(unittest.TestCase):
    def test_exact_profile_and_source_pins(self):
        import acquire
        profile=json.loads((SOURCE/'acquisition-profile-west.json').read_text())
        self.assertEqual(acquire.digest(acquire.canonical(profile)),west.PROFILE_SHA256)
        for fid,(size,digest) in west.FILES.items():
            row=next(r for r in profile['files'] if r['fileDataID']==fid)
            raw=(SOURCE/row['path']).read_bytes()
            self.assertEqual((len(raw),t.digest(raw)),(size,digest))

    def test_source_mapping_and_geometry_reproduce(self):
        actual=region.create(SOURCE,SOURCE/'extraction-manifest.json','west')
        for key in ('positions','indices','placements','terrainExclusions','tiles','regionBounds'):
            self.assertEqual(actual[key],GEOMETRY[key])
        self.assertEqual(len(actual['tiles']),8)
        receipt=json.loads((SOURCE/'extraction-manifest.json').read_text())
        bad=copy.deepcopy(actual['source']['inputs']);bad['tiles'][0]['root']['sha256']='0'*64
        with self.assertRaisesRegex(ValueError,'west-source-pin'):region.source_inputs(bad,receipt)

    def test_water_cells_cannot_be_omitted_or_shrunk(self):
        expected=coverage.terrain_rectangles(MANIFEST);self.assertEqual(len(expected),6)
        for kind in ('missing','duplicate','shrunk','relabel'):
            bad=copy.deepcopy(MANIFEST)
            entries=bad['terrainExclusions']
            if kind=='missing':entries.pop()
            if kind=='duplicate':entries[1]=copy.deepcopy(entries[0])
            if kind=='shrunk':entries[0]['bounds'][0][0]+=1
            if kind=='relabel':entries[0]['tile']=[32,41]
            with self.subTest(kind=kind),self.assertRaises(CompileError):coverage.terrain_rectangles(bad)

    def test_water_header_is_bounded(self):
        raw=(SOURCE/'Azeroth_31_41.69913.adt').read_bytes();records,_=t.root(raw)
        self.assertEqual(len(west.liquid_exclusions(raw,records,[31,41])),6)
        def broken(payload):
            data=bytearray(payload);struct.pack_into('<II',data,190*12,len(data)-1,1);return data
        with self.assertRaisesRegex(ValueError,'MH2O-instance-range'):
            west.liquid_exclusions(replace(raw,'MH2O',broken),records,[31,41])

    def test_legacy_no_liquid_requires_root_semantics(self):
        raw=(SOURCE/'wmo-groups/113873.bin').read_bytes()
        self.assertNotIn('WMO-liquid-not-modeled',w.group(raw,0)['unsupported'])
        self.assertIn('WMO-liquid-not-modeled',w.group(raw,4)['unsupported'])
        self.assertIn('WMO-liquid-not-modeled',w.group(raw)['unsupported'])
        def liquid_flag(payload):
            data=bytearray(payload);flags=struct.unpack_from('<I',data,8)[0]
            struct.pack_into('<I',data,8,flags|0x1000);return data
        self.assertIn('WMO-liquid-not-modeled',w.group(replace(raw,'MOGP',liquid_flag),0)['unsupported'])
        self.assertIn('WMO-liquid-not-modeled',w.group(replace(raw,'MOGP',
            lambda p:p+b'QILM'+struct.pack('<I',0)),0)['unsupported'])

    def test_empty_doodads_can_omit_reference_table(self):
        raw=(SOURCE/'collision/108125.bin').read_bytes()
        self.assertEqual(w.root(raw)['doodads'],[])
        bad=replace(raw,'MODD',lambda _:b'\0'*40)
        with self.assertRaisesRegex(ValueError,'WMO-missing:MODI'):w.root(bad)

    def test_unknown_root_layout_has_whole_placement_exclusion(self):
        self.assertIn(coverage.ROOT_GATE,[g['reason'] for g in MANIFEST['coverageGates']])
        raw=(SOURCE/'collision/7801267.bin').read_bytes()
        with self.assertRaisesRegex(ValueError,'LOD-or-group-count'):w.root(raw)
        coverage.validate(MANIFEST,west.BOUNDS)
        for kind in ('missing','layout','claimed'):
            bad=copy.deepcopy(MANIFEST)
            gate=next(g for g in bad['coverageGates'] if g['reason']==coverage.ROOT_GATE)
            if kind=='missing':bad['exclusions']=[r for r in bad['exclusions'] if r['placementID']!=gate['placementID']]
            if kind=='layout':gate['layout']='guessed'
            if kind=='claimed':bad['coverage']['framedSelectedStaticDecoded']=True
            with self.subTest(kind=kind),self.assertRaises(CompileError):coverage.validate(bad,west.BOUNDS)

    def test_resolution_preserves_physical_limits(self):
        _,config=coverage.profile(MANIFEST)
        self.assertEqual(config['cs']*config['walkableRadius'],.5)
        self.assertAlmostEqual(config['ch']*config['walkableHeight'],1.8)
        self.assertAlmostEqual(config['ch']*config['walkableClimb'],.3)
        self.assertEqual(config['cs']*config['tileSize'],64)
        for key,value in (('walkableRadius',1),('walkableClimb',4),('walkableHeight',17),('walkableSlopeAngle',45)):
            bad=copy.deepcopy(MANIFEST);bad['generator']['config'][key]=value
            with self.subTest(key=key),self.assertRaises(CompileError):coverage.profile(bad)

    def test_new_m2_collision_matches_independent_pinned_parser(self):
        proof=json.loads(REFERENCE.read_text())
        self.assertEqual(proof['referenceCommit'],t.PIN)
        ref=proof['records'][0];raw=(SOURCE/'collision/203171.bin').read_bytes()
        self.assertEqual(ref['sha256'],t.digest(raw));self.assertEqual(ref['remainingBytes'],0)
        parsed=c.m2(raw);mapped=[]
        for at in range(0,len(parsed['positions']),3):
            x,y,z=parsed['positions'][at:at+3];mapped.extend((x,z,-y))
        self.assertEqual(mapped,ref['collisionPositions'])
        self.assertEqual(parsed['indices'],ref['collisionIndices'])
        self.assertEqual((len(mapped)//3,len(parsed['indices'])//3),(8,12))

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    for name in ('source','geometry','manifest','reference'):parser.add_argument('--'+name,required=True)
    args,remaining=parser.parse_known_args()
    SOURCE=pathlib.Path(args.source);REFERENCE=pathlib.Path(args.reference)
    GEOMETRY=json.loads(pathlib.Path(args.geometry).read_text())
    MANIFEST=json.loads(pathlib.Path(args.manifest).read_text())
    unittest.main(argv=[sys.argv[0]]+remaining)
