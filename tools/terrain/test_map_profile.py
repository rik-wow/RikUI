"""Actual pinned map acquisition/coverage and malformed-proof regression checks."""
import argparse,copy,json,pathlib,struct,unittest
import map_profile,m2_physics_extent,height_contract,map_coverage_contract
from terrain_contract import CompileError
SOURCE=MANIFEST=None
class MapTests(unittest.TestCase):
    def test_exact_all_source_bytes(self):
        profile,receipt,recursive=map_profile.validate_sources(SOURCE)
        self.assertEqual(len(profile['files']),1590)
        self.assertEqual(sum(r['bytes'] for r in profile['files']),77298678)
    def test_inline_physics_extent_exclusion_only(self):
        profile=json.loads((SOURCE/'acquisition-profile-map.json').read_text())
        row=next(r for r in profile['files'] if r['fileDataID']==200767)
        raw=(SOURCE/row['path']).read_bytes();result=m2_physics_extent.extent(raw)
        self.assertEqual(len(result['positions']),102);self.assertFalse(result['nativeVerified'])
        self.assertEqual(result['method'],'pinned-PCOL-static-union-exclusion-only')
        mutated=bytearray(raw);mutated[-1]^=1
        self.assertIsNone(m2_physics_extent.extent(mutated))
    def test_actual_tile_bounds(self):
        height_contract.validate(MANIFEST['generator'])
        a=MANIFEST['generator']['heightAudit']
        self.assertLessEqual(a['maxSpanVoxels'],8190);self.assertLessEqual(a['maxOverlappingChunks'],512)
        self.assertGreater(MANIFEST['generator']['config']['bounds'][1][1]-MANIFEST['generator']['config']['bounds'][0][1],819.1)
    def test_global_height_saturation_rejected(self):
        g=copy.deepcopy(MANIFEST['generator']);g.pop('heightStrategy')
        with self.assertRaisesRegex(CompileError,'Recast-height-span-overflow'):height_contract.validate(g)
    def test_local_height_corruption_rejected(self):
        for field,value in [('spanVoxels',9000),('minY',-99999),('overlappingChunks',513)]:
            g=copy.deepcopy(MANIFEST['generator'])
            row=next(r for r in g['heightAudit']['tiles'] if r.get('built'));row[field]=value
            with self.assertRaises(CompileError):height_contract.validate(g)
        g=copy.deepcopy(MANIFEST['generator']);g['heightAudit']['tiles'].pop()
        with self.assertRaises(CompileError):height_contract.validate(g)
    def test_full_coverage_contract(self):
        boxes,gates,step=map_coverage_contract.validate(MANIFEST,map_profile.BOUNDS)
        self.assertEqual(step,1);self.assertEqual(len(boxes),3291)
        self.assertEqual(len(MANIFEST['exclusions']),24)
        self.assertEqual(len(MANIFEST['terrainExclusions']),3265)
        self.assertEqual(len(MANIFEST['m2Exclusions']),2)
    def test_changed_exclusions_rejected(self):
        for field in ('exclusions','terrainExclusions','m2Exclusions'):
            m=copy.deepcopy(MANIFEST);m[field][0]['bounds'][0][0]+=.1
            with self.assertRaises((CompileError,ValueError)):map_coverage_contract.validate(m,map_profile.BOUNDS)
    def test_unsafe_step_links_recorded(self):
        audit=MANIFEST['stepPortalAudit'];self.assertEqual(audit['removedDirectedLinks'],16)
        self.assertTrue(all(r['maxDifference']>1 for r in audit['rejected']))
        pairs={(r['from'],r['to']) for r in audit['rejected']}
        self.assertTrue(all((b,a) in pairs for a,b in pairs))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',required=True);p.add_argument('--manifest',required=True)
    a=p.parse_args();SOURCE=pathlib.Path(a.source);MANIFEST=json.loads(pathlib.Path(a.manifest).read_text())
    unittest.main(argv=['test_map_profile'])
