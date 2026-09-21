"""Actual two-ADT provenance, resource bounds, conservative carve and seam replay checks."""
import copy,hashlib,json,math,os,pathlib,struct,unittest
import terrain_region as region
import terrain_probe as terrain
import collision_probe as collision
HERE=pathlib.Path(__file__).parent
ROOT=pathlib.Path(os.environ['RIKUI_TERRAIN_ACQUISITION'])

def read(path):return json.loads(pathlib.Path(path).read_text())
def area(points):
    a=points[0]
    return sum((b[0]-a[0])*(c[2]-a[2])-(b[2]-a[2])*(c[0]-a[0]) for b,c in zip(points[1:],points[2:]))

class RegionChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.geometry=read(HERE/'geometry-region.json');cls.manifest=read(HERE/'region/manifest.json')
        cls.receipt=read(ROOT/'extraction-manifest.json');cls.polys={};cls.shards=[]
        for entry in cls.manifest['regions']:
            data=(HERE/'region'/entry['filename']).read_bytes()
            if hashlib.sha256(data).hexdigest()!=entry['sha256']:raise ValueError('changed-region-shard')
            shard=json.loads(data);cls.shards.append(shard)
            for p in shard['polygons']:
                if p['id'] in cls.polys:raise ValueError('duplicate-polygon-ID')
                cls.polys[p['id']]=p
    def test_exact_two_source_tiles_and_equal_dedup(self):
        self.assertEqual(self.geometry['tiles'],[[32,42],[33,42]])
        self.assertNotIn('tile',self.geometry)
        rows=region.source_inputs(self.geometry['source']['inputs'],self.receipt)
        placements,names,duplicates=region.merge_placements(rows)
        self.assertFalse(names);self.assertEqual(duplicates,27);self.assertEqual(placements,self.geometry['placements'])
        self.assertEqual(len(placements),1512)
    def test_changed_WDT_tile_link_rejected(self):
        bad=copy.deepcopy(self.geometry['source']['inputs']);bad['tiles'][0]['root']=copy.deepcopy(bad['tiles'][1]['root'])
        with self.assertRaisesRegex(ValueError,'WDT-source-mapping'):region.source_inputs(bad,self.receipt)
    def test_changed_source_hash_rejected(self):
        bad=copy.deepcopy(self.geometry['source']['inputs']);bad['tiles'][0]['obj']['sha256']='0'*64
        with self.assertRaisesRegex(ValueError,'unregistered-input'):region.source_inputs(bad,self.receipt)
    def test_conflicting_duplicate_placement_rejected(self):
        data=(ROOT/'Azeroth_33_42_obj0.69913.adt').read_bytes();bad=bytearray(data)
        for tag,a,b in terrain.chunks(data):
            if tag=='MDDF':struct.pack_into('<f',bad,a+8,struct.unpack_from('<f',data,a+8)[0]+1);break
        with self.assertRaisesRegex(ValueError,'conflicting-placement'):
            region.merge_placements([(None,None,data),(None,None,bytes(bad))])
    def test_runtime_resource_caps(self):
        self.assertLessEqual(len(self.shards),128);self.assertLessEqual(len(self.polys),8192)
        self.assertLessEqual(sum(len(p['portals']) for p in self.polys.values()),32768)
        for shard in self.shards:
            self.assertLessEqual(len(shard['polygons']),512);self.assertLessEqual(sum(len(p['portals']) for p in shard['polygons']),2048)
    def test_degenerate_face_and_incident_links_removed(self):
        m=self.manifest;removed={p['id'] for p in m['degeneratePolygons']}
        self.assertEqual(len(removed),m['statistics']['degeneratePolygonsRemoved']);self.assertGreater(len(removed),0)
        for entry in m['degeneratePolygons']:
            self.assertEqual(entry['reason'],'degenerate-horizontal-projection');self.assertLessEqual(abs(area(entry['points'])),.00001)
        self.assertFalse(removed&set(self.polys))
        for p in self.polys.values():
            self.assertGreater(abs(area(p['points'])),.00001)
            self.assertFalse(removed&{e['to'] for e in p['portals']})
    def test_known_unsupported_footprints_remain_excluded(self):
        m=self.manifest;self.assertEqual(m['coverage']['liquids'],'no-MH2O-or-MCLQ-in-root-and-no-MLIQ-or-liquid-type-in-selected-WMO-groups')
        self.assertFalse(m['coverage']['staticWMO']);self.assertFalse(m['coverage']['framedSelectedStaticDecoded'])
        self.assertEqual({g['reason'] for g in m['coverageGates']},{'WMO-doodad-flags'})
        self.assertEqual(len(m['coverageGates']),1);self.assertEqual(len(m['exclusions']),1)
        self.assertNotIn(230090,{g['placementID'] for g in m['coverageGates']})
        for p in self.polys.values():
            for box in m['exclusions']:
                intersects=all(max(v[a] for v in p['points'])>=box['bounds'][0][a]-box['padding'] and min(v[a] for v in p['points'])<=box['bounds'][1][a]+box['padding'] for a in [0,2])
                self.assertFalse(intersects)
    def test_output_respects_explicit_sourced_rectangle(self):
        bounds=self.manifest['bounds']
        for p in self.polys.values():
            for v in p['points']:
                for a in [0,2]:self.assertTrue(bounds['min'][a]-.0001<=v[a]<=bounds['max'][a]+.0001)
    def test_cross_source_seam_uses_real_connected_portals(self):
        seam=next(p for p in self.manifest['probes'] if p.get('kind')=='cross-source-tile-seam')
        self.assertEqual(seam['sourceTiles'],[[33,42],[32,42]])
        self.assertLess(self.polys[seam['from']]['center'][0],-533.334)
        self.assertGreater(self.polys[seam['to']]['center'][0],-533.333)
        self.assertGreater(len(seam['polygonPath']),1)
        for a,b in zip(seam['polygonPath'],seam['polygonPath'][1:]):
            self.assertTrue(any(e['to']==b for e in self.polys[a]['portals']))
        self.assertEqual(seam['endpointError'],0)
    def test_all_declared_probes_follow_portals_and_reach_endpoints(self):
        for probe in self.manifest['probes']:
            total=0
            for a,b in zip(probe['polygonPath'],probe['polygonPath'][1:]):total+=next(e['meters'] for e in self.polys[a]['portals'] if e['to']==b)
            self.assertAlmostEqual(total,probe['meters']);self.assertEqual(probe['endpointError'],0)
            self.assertEqual(probe['path'][-1],self.polys[probe['to']]['center'])
    def test_new_v274_profiles_are_hash_specific(self):
        for ident in [197388,197389]:
            raw=(ROOT/'collision'/f'{ident}.bin').read_bytes();result=collision.m2(raw)
            self.assertEqual(result['version'],274);self.assertGreater(len(result['indices']),0)
            bad=bytearray(raw);bad[-1]^=1
            with self.assertRaisesRegex(ValueError,'unsupported-M2-version'):collision.m2(bytes(bad))
    def test_no_native_claims(self):
        self.assertFalse(self.manifest['publishable']);self.assertFalse(self.manifest['generator']['agentProfileNativeVerified'])
        self.assertFalse(self.manifest['coverage']['nativeTraversalVerified']);self.assertFalse(self.manifest['coverage']['agentProfileCalibrated'])

if __name__=='__main__':unittest.main()
