import copy,json,pathlib,tempfile,unittest
from unittest import mock
import compile_quest_terrain as c

class CompilerTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='rikui-terrain-compiler-test-');self.addCleanup(self.tmp.cleanup)
        self.root=pathlib.Path(self.tmp.name);self.input=self.root/'input';self.input.mkdir();self.out=self.root/'addon'
        a=[-900,400,-5500];b=[-899,400,-5500];d=[-900,400,-5499];v=[-899,400,-5499]
        self.shard={'format':'rikui-nav-shard-v1','identity':dict(c.IDENTITY),'mapID':0,'status':'derived-pending-validation','publishable':False,'id':0,'grid':[0,0,0],
            'polygons':[{'id':1,'center':[-899.33,400,-5499.67],'points':[a,b,v],'portals':[{'to':2,'left':a,'right':v,'meters':1}]},
            {'id':2,'center':[-899.67,400,-5499.33],'points':[a,v,d],'portals':[{'to':1,'left':v,'right':a,'meters':1}]}]}
        bounds=[[-950,390,-5700],[-945,410,-5695]]
        gate={'placementID':10,'fileDataID':20,'reason':c.GATE,'advertised':2,'framed':1}
        self.m={'format':'rikui-nav-tile-proof-v1','identity':dict(c.IDENTITY),'mapID':0,'tile':[33,42],'status':'derived-pending-validation','publishable':False,
            'coordinateSystem':'Y-up; X=game world Y; Z=game world X','coverageScope':'outside-exclusions',
            'bounds':{'min':[-1066.6673177083333,385.2856750488281,-5866.667317708333],'max':[-533.333984375,516.3817138671875,-5333.333984375]},
            'coverage':{'terrain':True,'holes':True,'staticM2':True,'staticWMO':False,'liquids':'no-MH2O-or-MCLQ-in-root-and-no-MLIQ-or-liquid-type-in-selected-WMO-groups','dynamicDoors':False,'agentProfileCalibrated':False,'placementReferencesAreNames':False,'framedSelectedStaticDecoded':True,'modelExcludesUnresolvedStaticFootprints':True,'nativeTraversalVerified':False},
            'collisionAudit':{'unresolved':[]},'wmoAudit':{'placements':[{'placementID':10,'fileDataID':20,'MODFworldBounds':bounds}],'unsupported':[gate]},
            'coverageGates':[dict(gate,modelMitigation=c.MITIGATION)],'exclusions':[{'placementID':10,'bounds':bounds,'padding':.5,'reasons':[c.GATE]}],
            'source':{'buildConfig':c.BUILD_CONFIG,'cdnConfig':c.CDN_CONFIG,'acquisitionReceipt':{'path':'do-not-open-untrusted-path','sha256':'a'*64}},
            'limitations':['Native verification pending.'],
            'generator':{'agentProfileNativeVerified':False,'config':{'cs':.5,'ch':.1,'walkableRadius':1,'walkableHeight':18,'walkableClimb':3,'walkableSlopeAngle':40,'maxVertsPerPoly':6}},
            'statistics':{},'regions':[],'probes':[{'success':True,'from':1,'to':2,'meters':1,'path':[a,v],'polygonPath':[1,2]}]}
    def write(self):
        raw=json.dumps(self.shard,separators=(',',':')).encode();(self.input/'region-0-0-0.json').write_bytes(raw)
        edges=sum(len(p['portals']) for p in self.shard['polygons'])
        self.m['regions']=[{'filename':'region-0-0-0.json','sha256':c.sha(raw),'bytes':len(raw),'id':0,'grid':[0,0,0],'polygons':len(self.shard['polygons']),'directedEdges':edges}]
        self.m['statistics']={'regions':1,'polygons':len(self.shard['polygons']),'directedEdges':edges,'jsonShardBytes':len(raw)}
        return self.write_manifest()
    def write_manifest(self):
        data=json.dumps(self.m,separators=(',',':')).encode();p=self.input/'manifest.json';p.write_bytes(data);return p,c.sha(data)
    def reject(self,token,pair=None):
        p,h=pair or self.write()
        with self.assertRaisesRegex(c.CompileError,token):c.compile_addon(p,h,self.out)
        self.assertFalse(self.out.exists())
    def test_valid_output_contract_and_receipt(self):
        p,h=self.write();result=c.compile_addon(p,h,self.out);self.assertEqual(result['counts'],{'shards':1,'polygons':2,'directedPortals':2})
        meta,shards,_=c.validate(p,h);self.assertEqual(meta['identity'],c.RUNTIME_IDENTITY);self.assertEqual(meta['counts'],{'polygons':2,'portals':2})
        self.assertEqual(meta['exclusions'],[[-950.5,-5700.5,-944.5,-5694.5]]);self.assertEqual(meta['blockers'],[]);self.assertFalse(meta['nativeVerified'])
        self.assertEqual(meta['modeledMaxStep'],.3)
        self.assertEqual(set(shards[0]),{'identity','polygons'});self.assertEqual(set(shards[0]['polygons'][0]),{'id','points','portals'})
        self.assertEqual(set(shards[0]['polygons'][0]['portals'][0]),{'to','left','right'})
        toc=(self.out/'RikUIQuestTerrain.toc').read_text();self.assertIn('## Interface: 16001',toc);self.assertIn('## Dependencies: RikUI',toc);self.assertNotIn('validation-probes',toc);self.assertEqual((self.out/'validation-probes.lua').read_text(),'return {{["from"]=1,["to"]=2}}\n')
        register=(self.out/'register.lua').read_text();self.assertIn('Terrain.Install(data.meta, data.shards)',register);self.assertIn('data.meta = nil',register);self.assertIn('data.shards = nil',register)
        receipt=json.loads((self.out/'compile-receipt.json').read_text());self.assertEqual(receipt['inputManifest']['sha256'],h);self.assertEqual(len(receipt['coverageGates']),1)
        self.assertEqual(set(e['filename'] for e in receipt['outputs']),{x.name for x in self.out.iterdir()}-{'compile-receipt.json'})
        for e in receipt['outputs']:self.assertEqual(c.sha((self.out/e['filename']).read_bytes()),e['sha256'])
    def test_wrong_expected_hash(self):
        p,_=self.write();self.reject('manifest-hash-mismatch',(p,'0'*64))
    def test_tampered_shard_hash(self):
        pair=self.write();p=self.input/'region-0-0-0.json';b=p.read_bytes().replace(b'-900',b'-901');p.write_bytes(b);self.reject('region-hash-mismatch',pair)
    def test_path_traversal_and_windows_paths(self):
        self.write()
        for path in ('../outside.json','region-0-0-0.json/../secret','C:\\secret.json','/tmp/secret','region-0-0-0.json:stream'):
            with self.subTest(path=path):self.m['regions'][0]['filename']=path;self.reject('unsafe-region-path',self.write_manifest())
    def test_nonfinite_geometry_and_audit(self):
        for value in (float('nan'),float('inf'),-float('inf')):
            with self.subTest(value=value):self.shard['polygons'][0]['points'][0][0]=value;self.reject('nonfinite-json-number')
        self.shard['polygons'][0]['points'][0][0]=-900;self.m['source']['unknownNumericAudit']=float('inf');self.reject('nonfinite-json-number')
    def test_duplicate_json_keys(self):
        with self.assertRaisesRegex(c.CompileError,'duplicate-json-key'):c.parse_json(b'{"x":1,"x":2}')
    def test_json_resource_depth(self):
        with self.assertRaisesRegex(c.CompileError,'json-resource-bound'):c.parse_json(('['*34+'0'+']'*34).encode())
    def test_unsupported_identity(self):
        for field,value in [('product','wow_classic'),('edition','Classic'),('build','1.60.1.70000'),('locale','deDE')]:
            with self.subTest(field=field):self.m['identity']=dict(c.IDENTITY,**{field:value});self.reject('unsupported-product-build-locale')
    def test_unsupported_formats(self):
        self.m['format']='future-v2';self.reject('unsupported-manifest-format');self.m['format']='rikui-nav-tile-proof-v1';self.shard['format']='future-v2';self.reject('unsupported-shard-format')
    def test_manifest_and_shard_size_caps(self):
        p=self.input/'manifest.json';p.write_bytes(b' '*(c.MAX_MANIFEST+1));self.reject('input-size-bound',(p,c.sha(p.read_bytes())))
        pair=self.write()
        with mock.patch.object(c,'MAX_SHARD',1):self.reject('input-size-bound',pair)
    def test_total_resource_cap(self):
        pair=self.write()
        with mock.patch.object(c,'MAX_TOTAL',1):self.reject('total-input-size-bound',pair)
    def test_count_mismatch(self):
        self.write();self.m['statistics']['polygons']=3;self.reject('manifest-count-mismatch',self.write_manifest())
    def test_region_declared_count_mismatch(self):
        self.write();self.m['regions'][0]['polygons']=3;self.reject('region-polygon-count-mismatch',self.write_manifest())
    def test_portal_count_mismatch(self):
        self.write();self.m['regions'][0]['directedEdges']=3;self.reject('region-edge-count-mismatch',self.write_manifest())
    def test_duplicate_polygon_ids_and_bool_ids(self):
        self.shard['polygons'][1]['id']=1;self.shard['polygons'][1]['portals']=[];self.reject('duplicate-polygon-ID')
        self.shard['polygons'][1]['id']=True;self.reject('invalid-polygon-ID')
    def test_dangling_portal(self):
        self.shard['polygons'][0]['portals'][0]['to']=999;self.reject('dangling-portal')
    def test_off_boundary_portal(self):
        self.shard['polygons'][0]['portals'][0]['left']=[-850,400,-5450];self.reject('portal-not-on-both-boundaries')
    def test_source_portal_height_cannot_be_spoofed(self):
        self.shard['polygons'][0]['portals'][0]['left']=list(self.shard['polygons'][0]['portals'][0]['left'])
        self.shard['polygons'][0]['portals'][0]['left'][1]+=100
        self.reject('portal-height-disagrees-with-source-edge')
    def test_adjacent_horizontal_polygons_do_not_establish_vertical_transport(self):
        row=self.shard['polygons'][1]
        row['points']=[[p[0],p[1]+100,p[2]] for p in row['points']]
        row['portals']=[dict(edge,left=[edge['left'][0],500,edge['left'][2]],right=[edge['right'][0],500,edge['right'][2]]) for edge in row['portals']]
        self.reject('portal-exceeds-modeled-step')
    def test_source_height_rounding_and_declared_small_step_allowed(self):
        row=self.shard['polygons'][1]
        row['points']=[[p[0],p[1]+.1125,p[2]] for p in row['points']]
        row['portals']=[dict(edge,left=[edge['left'][0],400.1125,edge['left'][2]],right=[edge['right'][0],400.1125,edge['right'][2]]) for edge in row['portals']]
        p,h=self.write();meta,_,receipt=c.validate(p,h)
        self.assertEqual(meta['modeledMaxStep'],.3);self.assertFalse(receipt['nativeVerified'])
    def test_self_intersecting_star_with_same_turns_is_rejected(self):
        row=self.shard['polygons'][0]
        row['points']=[[-900+x,400,-5500+z] for x,z in ((0,3),(2,-3),(-3,1),(3,1),(-2,-3))]
        row['portals']=[]
        self.reject('nonconvex-or-self-intersecting-polygon')
    def test_runtime_resource_limits_are_enforced(self):
        pair=self.write()
        with mock.patch.object(c,'MAX_SHARD_POLYGONS',1):self.reject('invalid-shard-polygons',pair)
        with mock.patch.object(c,'MAX_SHARD_PORTALS',1):self.reject('shard-portal-resource-bound',pair)
        self.m['statistics']['directedEdges']=32769
        self.reject('invalid-portal-count',self.write_manifest())
    def test_polygon_beyond_source_bounds(self):
        self.shard['polygons'][0]['points'][1][2]=-5319;self.reject('polygon-outside-supported-tile')
    def test_source_bounds_inflation(self):
        self.m['bounds']['max'][2]=-5000;self.reject('unsupported-source-region-bounds')
    def test_unmitigated_or_unknown_coverage_gate(self):
        self.m['coverageGates'][0]['modelMitigation']='ignore';self.reject('unknown-or-unmitigated-gate')
        self.m['coverageGates'][0]['modelMitigation']=c.MITIGATION;self.m['coverageGates'][0]['reason']='unknown-future-gate';self.reject('unknown-or-unmitigated-gate')
    def test_missing_exclusion(self):
        self.m['exclusions']=[];self.reject('gate-missing-exclusion')
    def test_extra_audit_gate_not_hidden(self):
        self.m['wmoAudit']['unsupported'].append({'placementID':99,'reason':'unknown'});self.reject('unrecorded-WMO-coverage-gate')
    def test_footprint_shrink_not_accepted(self):
        self.m['exclusions'][0]['bounds']=copy.deepcopy(self.m['exclusions'][0]['bounds']);self.m['exclusions'][0]['bounds'][1][0]-=1;self.reject('exclusion-does-not-cover')
    def test_padding_and_agent_profile(self):
        self.m['exclusions'][0]['padding']=.49;self.reject('unsafe-exclusion-padding')
        self.m['exclusions'][0]['padding']=.5;self.m['generator']['config']['walkableRadius']=2;self.reject('unsupported-agent-profile')
    def test_polygon_touching_exclusion_rejected(self):
        box=[[-900.5,390,-5500.5],[-898.5,410,-5498.5]];self.m['exclusions'][0]['bounds']=box;self.m['wmoAudit']['placements'][0]['MODFworldBounds']=box;self.reject('polygon-touches-exclusion')
    def test_unknown_coverage_field_and_liquid(self):
        self.m['coverage']['future']=True;self.reject('unknown-coverage-field');del self.m['coverage']['future'];self.m['coverage']['liquids']='unknown';self.reject('unsupported-liquid-coverage')
    def test_nonempty_output_preserved(self):
        p,h=self.write();self.out.mkdir();sentinel=self.out/'user.txt';sentinel.write_text('preserve')
        with self.assertRaisesRegex(c.CompileError,'output-must-be-new-or-empty'):c.compile_addon(p,h,self.out)
        self.assertEqual(sentinel.read_text(),'preserve')
    def test_existing_empty_output_allowed(self):
        p,h=self.write();self.out.mkdir();c.compile_addon(p,h,self.out);self.assertTrue((self.out/'register.lua').is_file())
    def test_failure_writes_no_output_or_stage(self):
        self.m['identity']['build']='wrong';p,h=self.write()
        with self.assertRaises(c.CompileError):c.compile_addon(p,h,self.out)
        self.assertFalse(self.out.exists());self.assertEqual(sorted(p.name for p in self.root.iterdir()),['input'])
    def test_reproducible_bytes(self):
        p,h=self.write();second=self.root/'second';c.compile_addon(p,h,self.out);c.compile_addon(p,h,second)
        self.assertEqual({f.name:f.read_bytes() for f in self.out.iterdir()},{f.name:f.read_bytes() for f in second.iterdir()})
    def test_safe_lua_strings(self):
        self.assertEqual(c.lua('a"\\\n'), '"a\\034\\092\\010"');self.assertEqual(c.lua('é'),'"\\195\\169"')
    def test_shard_symlink_rejected(self):
        p,h=self.write();shard=self.input/'region-0-0-0.json';target=self.root/'source';target.write_bytes(shard.read_bytes());shard.unlink()
        try:shard.symlink_to(target)
        except OSError:self.skipTest('symlink permission unavailable')
        self.reject('escaped-region-path|input-not-regular-file',(p,h))

if __name__=='__main__':unittest.main()
