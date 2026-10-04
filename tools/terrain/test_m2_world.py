"""Verify pinned world M2 arrays and reject unsafe collision/physics assumptions."""
import argparse,collections,json,pathlib,struct,sys,unittest
import collision_probe as c
import terrain_probe as t
PROFILE_SHA='de8b30b38337373f951a4a1570dd720554cfd14aa2fb52b94f0aed966ab1abf8'
REFERENCE_SHA='f671b8a8f0d4778c6332160a6c9cff244a97112e1d5439b7e68163f862ffbe4e'
def chunk(tag,body):return tag.encode()+struct.pack('<I',len(body))+body
def fixture(version=272,empty=False,extras=b''):
    p=bytearray(240);p[:4]=b'MD20';struct.pack_into('<I',p,4,version)
    if not empty:
        struct.pack_into('<6I',p,216,3,240,3,246,1,282)
        p.extend(struct.pack('<3H12f',0,1,2,0,0,0,1,0,0,0,1,0,0,0,1))
    return chunk('MD21',p)+extras
class M2Tests(unittest.TestCase):
    def test_geometry_and_normals(self):
        model=c.m2(fixture())
        self.assertEqual(model['indices'],[0,1,2]);self.assertEqual(model['normals'],[0,0,1])
        self.assertEqual(len(model['positions']),9)
    def test_empty_static_is_not_extra_physics_absence(self):
        for tag in c.EXTRA_PHYSICS:
            model=c.m2(fixture(empty=True,extras=chunk(tag,b'')))
            gap=c.physics_gap(model,dict(reference=1,uniqueID=2))
            self.assertEqual(gap['chunks'],[tag]);self.assertNotIn('bounds',gap)
    def test_distant_static_does_not_bound_unknown_extra_physics(self):
        model=c.m2(fixture(extras=chunk('PFDC',b'')))
        self.assertNotIn('bounds',c.physics_gap(model,dict(reference=1,uniqueID=2)))
    def test_ordinary_empty_has_no_physics_gap(self):
        self.assertIsNone(c.physics_gap(c.m2(fixture(empty=True)),{}))
    def test_unknown_new_format_rejected(self):
        for version in (274,273,275):
            with self.assertRaisesRegex(ValueError,'unsupported-M2-version'):c.m2(fixture(version))
    def test_bad_normal_offset_and_finite_rejected(self):
        data=bytearray(fixture());struct.pack_into('<I',data,8+236,len(data))
        with self.assertRaisesRegex(ValueError,'M2-collision-overrun'):c.m2(data)
        data=bytearray(fixture());struct.pack_into('<f',data,8+282,float('nan'))
        with self.assertRaisesRegex(ValueError,'M2-collision-finite'):c.m2(data)
    def test_index_header_alias_and_truncation_rejected(self):
        data=bytearray(fixture());struct.pack_into('<I',data,8+220,4)
        with self.assertRaisesRegex(ValueError,'M2-collision-overrun'):c.m2(data)
        with self.assertRaisesRegex(ValueError,'m2-chunk-overrun'):c.m2(fixture()[:-1])
    def empty274(self,extras=b''):
        data=bytearray(fixture(274,empty=True,extras=extras))
        struct.pack_into('<7f',data,8+188,1e7,1e7,1e7,-1e7,-1e7,-1e7,0)
        return bytes(data)
    def test_structurally_empty_current_decoration(self):
        model=c.m2(self.empty274(chunk('LDV1',bytes(16))))
        self.assertEqual(model['positions'],[])
        self.assertEqual(model['indices'],[])
        self.assertEqual(model['profile'],'bounded-v274-empty-static-collision')
    def test_empty_current_contract_rejects_unknown_physics_and_chunks(self):
        for tag in (*c.EXTRA_PHYSICS,'NEW1','SKID'):
            with self.subTest(tag=tag),self.assertRaisesRegex(ValueError,'unsupported-M2-version'):
                c.m2(self.empty274(chunk(tag,bytes(4))))
    def test_empty_contract_rejects_changed_sentinel_and_duplicate_chunks(self):
        data=bytearray(self.empty274());struct.pack_into('<f',data,8+188,0)
        with self.assertRaisesRegex(ValueError,'unsupported-M2-version'):c.m2(bytes(data))
        with self.assertRaises(ValueError):c.m2(self.empty274(chunk('LDV1',bytes(4))+chunk('LDV1',bytes(4))))
    def test_known_profile_inventory(self):
        rows=c.profiles274();self.assertEqual(len(rows),132)
        self.assertEqual(sum(row['triangles']>0 for row in rows.values()),58)
def checked_json(path,sha):
    data=pathlib.Path(path).read_bytes()
    if t.digest(data)!=sha:raise ValueError('source-pin:'+str(path))
    return json.loads(data)
def audit(profile_path,reference_path):
    profile=checked_json(profile_path,PROFILE_SHA);reference=checked_json(reference_path,REFERENCE_SHA)
    if reference['failed'] or reference['total']!=132 or reference['referenceCommit']!=t.PIN:
        raise ValueError('incomplete-independent-reference')
    refs={row['fileDataID']:row for row in reference['records']}
    counts=collections.Counter();physics=[];seen=set()
    for row in profile['files']:
        if row['kind']!='M2':continue
        data=pathlib.Path(row['path']).read_bytes()
        if len(data)!=row['bytes'] or t.digest(data)!=row['sha256']:raise ValueError('M2-source-pin')
        model=c.m2(data);counts[str(model['version'])]+=1
        counts['withCollision' if model['indices'] else 'emptyStaticCollision']+=1
        extra=[tag for tag in model['chunks'] if tag in c.EXTRA_PHYSICS]
        if extra:physics.append(dict(fileDataID=row['fileDataID'],chunks=extra,knownExtent=model['physicsExtent'] is not None))
        if model['version']==274:
            seen.add(row['fileDataID']);ref=refs[row['fileDataID']]
            if ref['sha256']!=row['sha256'] or ref['bytes']!=len(data) or ref['remainingBytes']!=0:
                raise ValueError('reference-identity')
            def converted(values):
                return [v for at in range(0,len(values),3) for v in (values[at],values[at+2],-values[at+1])]
            if (converted(model['positions'])!=ref['collisionPositions'] or
                converted(model['normals'])!=ref['collisionNormals'] or model['indices']!=ref['collisionIndices']):
                raise ValueError('independent-collision-array-mismatch:'+str(row['fileDataID']))
    if seen!=set(refs) or counts['272']!=5598 or counts['274']!=132:raise ValueError('source-coverage')
    return dict(format='rikui-world-m2-production-audit-v1',sourceProfileSHA256=PROFILE_SHA,
        referenceResultSHA256=REFERENCE_SHA,parserSHA256=t.digest(pathlib.Path(c.__file__).read_bytes()),
        exactModels=5730,independentReferenceMatches=len(seen),counts=dict(counts),
        extraPhysics=physics,nativeVerified=False)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--profile');p.add_argument('--reference');p.add_argument('--output')
    args=p.parse_args()
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(M2Tests))
    if not result.wasSuccessful():sys.exit(1)
    if args.profile or args.reference:
        if not args.profile or not args.reference:p.error('--profile and --reference required together')
        report=audit(args.profile,args.reference)
        if args.output:pathlib.Path(args.output).write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
        print(json.dumps(report))
