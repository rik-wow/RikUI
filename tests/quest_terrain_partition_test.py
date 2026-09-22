"""Directed partition regression cases; no navigation links inferred from XY."""
import sys,pathlib,unittest,copy,random,json
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'tools'/'terrain'))
from terrain_partition import partition_graph,verify_partition
META={'identity':{'product':'forever','build':'1.60.1.69913','locale':'enUS'},'revision':'fixture','modeledMaxStep':1}
def fixture():
    def rect(i,x,y):return dict(id=i,points=[[x,y,0],[x+1,y,0],[x+1,y,1],[x,y,1]],portals=[],provenance={'id':i})
    rows=[rect(1,0,0),rect(2,1,0),rect(3,2,0),rect(4,3,0),rect(10,0,10),rect(11,1,10)]
    nodes={r['id']:r for r in rows}
    for a,b,x,y in [(1,2,1,0),(2,1,1,0),(2,3,2,0),(3,4,3,0),(4,3,3,0),(10,11,1,10),(11,10,1,10)]:
        nodes[a]['portals'].append(dict(to=b,left=[x,y,1],right=[x,y,0],evidence={'kind':'fixture-boundary'}))
    return rows
class PartitionTests(unittest.TestCase):
    def test_lossless(self):
        rows=fixture();before=copy.deepcopy(rows);result=partition_graph(rows,META,max_polygons=2,max_portals=3)
        self.assertTrue(verify_partition(rows,META,result));self.assertEqual(rows,before)
        self.assertEqual([r['polygonIDs'] for r in result['catalog']['regions']],[[1,2],[3,4],[10,11]])
        self.assertEqual([(s['fromPolygon'],s['toPolygon']) for s in result['catalog']['seams']],[(2,3)])
    def test_deterministic(self):
        rows=fixture();expected=json.dumps(partition_graph(rows,META,max_polygons=2),sort_keys=True)
        for seed in range(20):
            shuffled=copy.deepcopy(rows);rng=random.Random(seed);rng.shuffle(shuffled)
            for p in shuffled:rng.shuffle(p['portals'])
            actual=partition_graph(shuffled,META,max_polygons=2)
            self.assertEqual(json.dumps(actual,sort_keys=True),expected);self.assertTrue(verify_partition(shuffled,META,actual))
    def test_directed_and_floors(self):
        result=partition_graph(fixture(),META,max_polygons=20)
        self.assertTrue(verify_partition(fixture(),META,result))
        self.assertEqual([[c['polygonIDs'] for c in r['components']] for r in result['catalog']['regions']],[[[1,2],[3,4]],[[10,11]]])
        self.assertEqual([(s['fromPolygon'],s['toPolygon']) for s in result['catalog']['componentLinks']],[(2,3)])
        self.assertEqual(result['catalog']['seams'],[])
    def test_spatial_subdivision_preserves_directed_floors(self):
        rows=fixture();meta=dict(META,bounds=[-64,0,256,64])
        for i,row in enumerate(rows):
            for point in row['points']:point[0]+=i*64
        # Packing does not alter or infer portal geometry, even on disconnected floors.
        result=partition_graph(rows,meta,cell_size=64,max_polygons=2)
        self.assertTrue(verify_partition(rows,meta,result))
        self.assertEqual(len(result['catalog']['regions']),6)
        shuffled=list(reversed(rows))
        self.assertEqual(result,partition_graph(shuffled,meta,cell_size=64,max_polygons=2))
    def test_duplicates_preserved(self):
        rows=fixture();rows[1]['portals'].append(copy.deepcopy(rows[1]['portals'][1]))
        result=partition_graph(rows,META,max_polygons=2)
        self.assertTrue(verify_partition(rows,META,result));seams=result['catalog']['seams']
        self.assertEqual(len(seams),2);self.assertEqual(seams[0]['portal'],seams[1]['portal']);self.assertNotEqual(seams[0]['id'],seams[1]['id'])
    def test_outgoing_caps(self):
        rows=fixture();result=partition_graph(rows,META,max_polygons=20,max_portals=2)
        self.assertTrue(verify_partition(rows,META,result))
        self.assertTrue(all(r['outgoingPortalCount']<=2 for r in result['catalog']['regions']))
        rows[0]['portals']*=3
        with self.assertRaises(ValueError):partition_graph(rows,META,max_portals=2)
    def test_seam_tampering(self):
        rows=fixture();valid=partition_graph(rows,META,max_polygons=2)
        for mode in ('missing','height','extra'):
            result=copy.deepcopy(valid);seams=result['catalog']['seams']
            if mode=='missing':seams.clear()
            elif mode=='height':seams[0]['portal']['left'][1]=10
            else:seams.append(copy.deepcopy(seams[0]))
            with self.assertRaises(ValueError):verify_partition(rows,META,result)
    def test_components_metadata(self):
        rows=fixture();valid=partition_graph(rows,META,max_polygons=20)
        result=copy.deepcopy(valid);result['catalog']['regions'][0]['components'][0]['polygonIDs'] += [3,4]
        with self.assertRaises(ValueError):verify_partition(rows,META,result)
        result=copy.deepcopy(valid);result['packs'][0]['metadata']['identity']['build']='different'
        with self.assertRaises(ValueError):verify_partition(rows,META,result)
    def test_isolated_invalid_caps_and_references(self):
        rows=fixture();rows.append(dict(id=50,points=[[20,0,0],[21,0,0],[20,0,1]],portals=[]))
        result=partition_graph(rows,META,max_polygons=1,max_portals=2)
        self.assertTrue(verify_partition(rows,META,result))
        for cap in (0,-1,True,1.5,8193):
            with self.assertRaises(ValueError):partition_graph(rows,META,max_polygons=cap)
        rows[0]['portals'][0]['to']=999
        with self.assertRaises(ValueError):partition_graph(rows,META)
if __name__=='__main__':unittest.main()
