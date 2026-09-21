import copy, json, pathlib, struct, tempfile, unittest, subprocess, sys
import terrain_probe as terrain
import collision_probe as collision

def chunk(tag,payload):return tag[::-1].encode()+struct.pack('<I',len(payload))+payload

def record(x=0,y=0):
    return dict(x=x,y=y,flags=0,areaID=1,holesLow=0,holesHigh=[0]*8,
        position=(100,200,10),heights=[0]*145,subchunks=['MCVT'])

class GeometryChecks(unittest.TestCase):
    def test_flat_geometry_uses_upward_winding_and_height(self):
        v,idx,removed=terrain.mesh([record()])
        self.assertEqual((len(v)//3,len(idx)//3,removed),(145,256,0))
        self.assertTrue(all(v[i]==10 for i in range(1,len(v),3)))
        for i in range(0,len(idx),3):
            a,b,c=(v[k*3:k*3+3] for k in idx[i:i+3])
            up=(b[2]-a[2])*(c[0]-a[0])-(b[0]-a[0])*(c[2]-a[2])
            self.assertGreater(up,0)
    def test_low_and_high_resolution_holes_are_not_bridged(self):
        low=record();low['holesLow']=1
        high=record();high['flags']=0x10000;high['holesHigh'][0]=1
        self.assertEqual(terrain.mesh([low])[2],16)
        self.assertEqual(terrain.mesh([high])[2],4)
        high['holesHigh']=[255]*8
        self.assertEqual(terrain.mesh([high])[1],[])
    def test_chunk_framing_rejects_truncation_and_trailing_byte(self):
        for data in (b'REVM',chunk('MVER',struct.pack('<I',18))+b'!',b'REVM'+struct.pack('<I',999)):
            with self.assertRaises(ValueError):list(terrain.chunks(data))
    def test_full_root_requires_unique_256_chunks_and_version(self):
        sections=[chunk('MVER',struct.pack('<I',18))]
        for y in range(16):
            for x in range(16):
                header=bytearray(128)
                struct.pack_into('<III',header,0,0,x,y)
                struct.pack_into('<I',header,52,1)
                struct.pack_into('<fff',header,104,100-x*terrain.CHUNK,200-y*terrain.CHUNK,10)
                sections.append(chunk('MCNK',header+chunk('MCVT',struct.pack('<145f',*([0]*145)))))
        data=b''.join(sections)
        self.assertEqual(len(terrain.root(data)[0]),256)
        with self.assertRaises(ValueError):terrain.root(data[:-1])
        bad=bytearray(data);struct.pack_into('<I',bad,8,19)
        with self.assertRaises(ValueError):terrain.root(bad)
        with self.assertRaises(ValueError):terrain.root(b''.join(sections[:-1]))
    def test_m2_arrays_reject_overruns_indices_and_versions(self):
        payload=bytearray(240+6+36);payload[:4]=b'MD20';struct.pack_into('<I',payload,4,272)
        struct.pack_into('<II',payload,216,3,240);struct.pack_into('<II',payload,224,3,246)
        struct.pack_into('<3H',payload,240,0,1,2)
        struct.pack_into('<9f',payload,246,0,0,0,1,0,0,0,1,0)
        wrap=lambda p:b'MD21'+struct.pack('<I',len(p))+p
        self.assertEqual(collision.m2(wrap(payload))['indices'],[0,1,2])
        bad=bytearray(payload);struct.pack_into('<H',bad,240,3)
        with self.assertRaises(ValueError):collision.m2(wrap(bad))
        bad=bytearray(payload);struct.pack_into('<I',bad,228,999999)
        with self.assertRaises(ValueError):collision.m2(wrap(bad))
        bad=bytearray(payload);struct.pack_into('<I',bad,4,999)
        with self.assertRaises(ValueError):collision.m2(wrap(bad))
    def test_model_transform_keeps_z_up_and_honors_scale(self):
        model={'positions':[0,0,0,0,0,10]}
        placement={'position':[17066.666666666668,100,17066.666666666668],
            'rotation':[0,0,0],'scale':2048}
        result=collision.transformed(model,placement)
        self.assertAlmostEqual(result[1],100)
        self.assertAlmostEqual(result[4],120)
        self.assertAlmostEqual(result[0],result[3])
        self.assertAlmostEqual(result[2],result[5])
    def test_actual_region_is_fail_closed_and_dependency_accounting_complete(self):
        data=json.loads(pathlib.Path('geometry-collision.json').read_text())
        self.assertFalse(data['publishable'])
        self.assertEqual(len(data['source']['collisionAssets']),81)
        counts=data['collisionAudit']['counts']
        self.assertEqual(counts['includedM2Placements']+counts['excludedM2ByBounds']+counts['noStaticM2Collision'],810)
        self.assertEqual(counts['excludedWMOByBounds'],4)
        self.assertTrue(all(s['areaID']==1 for s in data['statistics']['selectedChunks']))
        nav=json.loads(pathlib.Path('nav-region-collision.json').read_text())
        self.assertFalse(nav['publishable']);self.assertTrue(nav['probe']['success'])
        self.assertLessEqual(nav['statistics']['polygons'],512)
        self.assertLessEqual(nav['statistics']['directedEdges'],2048)

    def test_mixed_build_or_changed_input_receipt_cannot_stamp_forever(self):
        geometry=json.loads(pathlib.Path('geometry.json').read_text())
        receipt=json.loads(pathlib.Path(geometry['source']['acquisitionReceipt']['path']).read_text())
        with tempfile.TemporaryDirectory() as folder:
            target=pathlib.Path(folder)/'rejected.json'
            receiptPath=pathlib.Path(folder)/'receipt.json'
            command=[sys.executable,'terrain_probe.py']
            for role in ('root','obj','wdt'):
                command.extend(['--'+role,geometry['source']['inputs'][role]['path']])
            command.extend(['--out',str(target),'--receipt',str(receiptPath)])
            for alteration in ('version','product','hash'):
                bad=copy.deepcopy(receipt)
                if alteration=='version':bad['version']='1.15.0.00000'
                elif alteration=='product':bad['product']='wow_classic_era'
                else:bad['files'][0]['sha256']='0'*64
                receiptPath.write_text(json.dumps(bad))
                result=subprocess.run(command,capture_output=True,text=True)
                self.assertNotEqual(result.returncode,0)
                self.assertFalse(target.exists())
if __name__=='__main__':unittest.main()
