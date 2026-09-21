"""Structural checks of the actual local model and correction boundaries."""
import copy, hashlib, json, math, pathlib, unittest
import merge_geometry as merge

def read(path):return json.loads(pathlib.Path(path).read_text())
def distance(a,b):return math.dist(a,b)
def inside(point,polygon,tolerance=0.003):
    signs=[]
    for i,a in enumerate(polygon):
        b=polygon[(i+1)%len(polygon)]
        cross=(b[0]-a[0])*(point[2]-a[2])-(b[2]-a[2])*(point[0]-a[0])
        if abs(cross)>tolerance:signs.append(cross>0)
    return not signs or all(s==signs[0] for s in signs)

class ArtifactChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest=read('full-tile/manifest.json');cls.rows={};cls.shards=[]
        for entry in cls.manifest['regions']:
            raw=(pathlib.Path('full-tile')/entry['filename']).read_bytes()
            if hashlib.sha256(raw).hexdigest()!=entry['sha256']:raise ValueError('shard-hash')
            shard=json.loads(raw);cls.shards.append(shard)
            for row in shard['polygons']:
                if row['id'] in cls.rows:raise ValueError('duplicate-poly')
                cls.rows[row['id']]=row
    def test_exact_identity_resource_caps_and_source_hashes(self):
        m=self.manifest
        self.assertEqual(m['identity']['build'],'1.60.1.69913');self.assertFalse(m['publishable'])
        self.assertFalse(m['generator']['agentProfileNativeVerified']);self.assertEqual(m['coverageScope'],'outside-exclusions')
        self.assertLessEqual(len(self.rows),8192)
        self.assertEqual(sum(len(p['portals']) for p in self.rows.values()),m['statistics']['directedEdges'])
        for shard in self.shards:
            self.assertLessEqual(len(shard['polygons']),512)
            self.assertLessEqual(sum(len(p['portals']) for p in shard['polygons']),2048)
        for item in m['source']['inputs'].values():
            self.assertEqual(hashlib.sha256(pathlib.Path(item['path']).read_bytes()).hexdigest(),item['sha256'])
    def test_convex_polygons_centers_and_portals(self):
        for poly in self.rows.values():
            points=poly['points'];self.assertTrue(3<=len(points)<=6)
            self.assertTrue(inside(poly['center'],points))
            for point in points:self.assertTrue(inside(point,points))
            for portal in poly['portals']:
                target=self.rows[portal['to']]
                self.assertTrue(any(p['to']==poly['id'] for p in target['portals']))
                self.assertTrue(inside(portal['left'],points));self.assertTrue(inside(portal['right'],points))
                mid=[(a+b)/2 for a,b in zip(portal['left'],portal['right'])]
                self.assertTrue(inside(mid,target['points'],0.03))
                expected=distance(poly['center'],mid)+distance(mid,target['center'])
                self.assertAlmostEqual(expected,portal['meters'],delta=.00006)
    def test_uncertain_footprints_cannot_receive_graph_nodes(self):
        m=self.manifest;self.assertEqual(len(m['coverageGates']),3);self.assertEqual(len(m['exclusions']),3)
        self.assertGreater(m['statistics']['excludedPolygons'],0)
        for poly in self.rows.values():
            for box in m['exclusions']:
                overlaps=all(max(p[a] for p in poly['points'])>=box['bounds'][0][a]-box['padding'] and min(p[a] for p in poly['points'])<=box['bounds'][1][a]+box['padding'] for a in (0,2))
                self.assertFalse(overlaps)
    def test_model_does_not_expand_past_sourced_tile(self):
        bounds=self.manifest['bounds']
        for poly in self.rows.values():
            for point in poly['points']:
                for axis in (0,2):
                    self.assertGreaterEqual(point[axis],bounds['min'][axis]-.0001)
                    self.assertLessEqual(point[axis],bounds['max'][axis]+.0001)
    def test_filtered_paths_follow_only_declared_portals(self):
        for probe in self.manifest['probes']:
            self.assertTrue(probe['success']);self.assertEqual(probe['endpointError'],0)
            total=0
            for a,b in zip(probe['polygonPath'],probe['polygonPath'][1:]):
                edge=next(p for p in self.rows[a]['portals'] if p['to']==b)
                total+=edge['meters']
            self.assertAlmostEqual(total,probe['meters'])
    def test_merge_rejects_foreign_source_missing_placement_and_unlocated_gate(self):
        g=read('geometry-full-m2.json');w=read('collision-wmo.json')
        for kind in ('build','receipt','base','placement','gate','nan','index'):
            bad=copy.deepcopy(w)
            if kind=='build':bad['build']='1.15.0'
            if kind=='receipt':bad['source']['acquisitionReceipt']['sha256']='0'*64
            if kind=='base':bad['source']['geometry']['sha256']='0'*64
            if kind=='placement':bad['audit']['placements'].pop()
            if kind=='gate':bad['audit']['unsupported'][0]['placementID']=999
            if kind=='nan':bad['positions'][0]=math.nan
            if kind=='index':bad['indices'][0]=99999999
            with self.assertRaises(ValueError,msg=kind):merge.merge(g,bad)
if __name__=='__main__':unittest.main()
