"""Add exact-build M2 collision arrays to the bounded terrain research region.
M2 v272 layout and transforms referenced from wow.export c2fd7bd (MIT).
No unverified data is published as runtime traversability.
"""
import argparse, collections, itertools, json, math, pathlib, struct
import terrain_probe as t
import map_profile as fullmap

def m2(data):
    at=0;payload=None;tags=[]
    while at<len(data):
        if len(data)-at<8:t.fail('m2-truncated-header')
        tag=data[at:at+4].decode('ascii');size,=struct.unpack_from('<I',data,at+4)
        end=at+8+size
        if end>len(data):t.fail('m2-chunk-overrun')
        tags.append(tag)
        if tag=='MD21':
            if payload is not None:t.fail('duplicate-MD21')
            payload=data[at+8:end]
        at=end
    if payload is None or len(payload)<240 or payload[:4]!=b'MD20':t.fail('M2-format')
    version,=struct.unpack_from('<I',payload,4)
    # Exact v274 assets independently consumed by the unmodified pinned M2Loader.
    demonstrated274={'0e0f350af340436194c1013d037f81e681876c227dafda816a3c5e3a0c98dfb6',
        '8a2118873adccadd97330ee4326f2e2420e6711cfe8fd3d3a7c83f36e7005116',
        'a67e4ef05abeae92860a77d8d269a65de0b289bcf3a0a57d795e9db339c7f2ff',
        '6ecb28f00e284ef0ad1dfb79b8106cba38c320eaa5f85033e228e77c6829611e',
        'c7abc3992b9b9687de3f351bc79c96302b68535644235f20b600635e4f69900a',
        '13207cd82ff6b30bfab434149e00e30e805af5454261356cbf37811d46c8b105',
        '063da118be429e9b900d39019eb993387dedcf00b1837e78beaade0ea4d66646',
        'b8f0719325b3bd6da886ad6374f219e8e7cfe8cfc86faf728d077ef71af88af5',
        'dc3134e549632a6500cee2f314399087c0eeff13294d1c6fce3fc914846d5100'}
    if version!=272 and not(version==274 and t.digest(data) in demonstrated274):t.fail('unsupported-M2-version')
    count,offset=struct.unpack_from('<II',payload,216)
    nverts,vertOffset=struct.unpack_from('<II',payload,224)
    if count%3 or count>300000 or nverts>65536:t.fail('M2-collision-count')
    if offset+count*2>len(payload) or vertOffset+nverts*12>len(payload):t.fail('M2-collision-overrun')
    indices=list(struct.unpack_from('<'+'H'*count,payload,offset))
    coords=list(struct.unpack_from('<'+'f'*(nverts*3),payload,vertOffset))
    if any(i>=nverts for i in indices):t.fail('M2-collision-index')
    if not all(math.isfinite(v) and abs(v)<100000 for v in coords):t.fail('M2-collision-finite')
    import m2_physics_extent
    return dict(version=version,positions=coords,indices=indices,chunks=tags,physicsExtent=m2_physics_extent.extent(data))

def transformed(model,placement):
    ax,ay,az=map(math.radians,(placement['rotation'][0],placement['rotation'][1]-90,placement['rotation'][2]))
    ca,sa,cb,sb,cc,sc=math.cos(ax),math.sin(ax),math.cos(ay),math.sin(ay),math.cos(az),math.sin(az)
    r=((cb*cc+sa*sb*sc,-cb*sc+sa*sb*cc,ca*sb),
       (ca*sc,ca*cc,-sa),(-sb*cc+sa*cb*sc,sb*sc+sa*cb*cc,ca*cb))
    s=placement['scale']/1024
    p=placement['position'];base=(t.TILE*32-p[0],p[1],t.TILE*32-p[2])
    output=[]
    for i in range(0,len(model['positions']),3):
        raw=model['positions'][i:i+3];local=(raw[0],raw[2],-raw[1])
        for axis,sign in ((0,-1),(1,1),(2,-1)):
            output.append(base[axis]+sign*s*sum(r[axis][j]*local[j] for j in range(3)))
    return output

def bounds(vertices):
    return [[f(vertices[axis::3]) for axis in range(3)] for f in (min,max)]

def intersects(a,b,padding=1.0):
    return all(a[1][i]>=b[0][i]-padding and a[0][i]<=b[1][i]+padding for i in (0,2))

def main():
    p=argparse.ArgumentParser();p.add_argument('--input',default='geometry.json')
    p.add_argument('--directory',required=True);p.add_argument('--output',default='geometry-collision.json');p.add_argument('--allow-full-tile',action='store_true')
    a=p.parse_args();g=json.loads(pathlib.Path(a.input).read_text());region=g.get('regionBounds',bounds(g['positions']))
    evidence=g['source']['acquisitionReceipt'];receiptBytes=t.load(evidence['path'])
    if t.digest(receiptBytes)!=evidence['sha256']:t.fail('changed-extraction-receipt')
    receipt=json.loads(receiptBytes);registered={x['fileDataID']:x for x in receipt['collisionDependencies']}
    models={};assets=[];counts=collections.Counter();unresolved=[];selected=[];physics_exclusions=[]
    empty_flags={7545269:(100,'5f17708b49141082b437adb8ec8a275dacc693880edc43750ff06f0d461d5d1d'),
        7545270:(100,'a65061a209cef275ed64cfab59efcb49e7182fa5ab07948bf551b16cd17d144a'),
        7545272:(100,'445029738fa2553e0077f84e02d234a46f7863301fb63fdddce550533659fd43'),
        7545275:(96,'2ab1262cbcede2c319fdf034ec10aac396944bd67e2cd9e1f6a67be8c20766a4'),
        7568169:(96,'f9640312ce2f918c5ecb5814756e16047b48e11fe63e208a90a334fe7ce8d3b9')}
    for dep in g['dependencies']:
        if dep['kind']!='m2':continue
        ident=dep['reference'];path=pathlib.Path(a.directory)/f'{ident}.bin';data=t.load(path)
        if registered.get(ident,{}).get('sha256')!=t.digest(data):t.fail('collision-source-hash')
        model=m2(data);models[ident]=model
        assets.append(dict(fileDataID=ident,path=str(path.resolve()),sha256=t.digest(data),bytes=len(data),
            version=model['version'],collisionVertices=len(model['positions'])//3,collisionTriangles=len(model['indices'])//3,chunks=model['chunks']))
    for row in g['placements']:
        if row['kind']=='wmo':
            if len(row['bounds'])!=6 or not all(math.isfinite(v) for v in row['bounds']):t.fail('MODF-bounds')
            lo=row['bounds'][:3];hi=row['bounds'][3:]
            box=[[t.TILE*32-hi[0],lo[1],t.TILE*32-hi[2]], [t.TILE*32-lo[0],hi[1],t.TILE*32-lo[2]]]
            if intersects(box,region):unresolved.append(dict(kind='wmo',fileDataID=row['reference'],uniqueID=row['uniqueID'],reason='overlapping-WMO-unprocessed'))
            else:counts['excludedWMOByBounds']+=1
            continue
        model=models[row['reference']]
        if row['flags'] not in (64,576):
            pin=empty_flags.get(row['reference'])
            if (not pin or pin!=(row['flags'],registered[row['reference']]['sha256']) or model['indices'] or model['positions']
                or any(tag in model['chunks'] for tag in ('PFID','PHY2','PCOL'))):t.fail('unsupported-MDDF-flags')
            counts['pinnedEmptyUninterpretedPlacementFlags']+=1
        if not model['indices']:
            counts['noStaticM2Collision']+=1;continue
        vertices=transformed(model,row)
        if not intersects(bounds(vertices),region):counts['excludedM2ByBounds']+=1;continue
        extra=[tag for tag in model['chunks'] if tag in ('PFID','PHY2','PCOL')]
        if extra:
            proof=model.get('physicsExtent')
            if proof and extra==['PCOL']:
                physics=transformed(proof,row)
                physics_exclusions.append(dict(placementID=row['uniqueID'],fileDataID=row['reference'],
                    reason='extra-physics-chunks',chunks=extra,bounds=bounds(vertices+physics),padding=.5,
                    boundsProof={k:v for k,v in proof.items() if k!='positions'}))
            else:unresolved.append(dict(kind='m2',fileDataID=row['reference'],uniqueID=row['uniqueID'],reason='extra-physics-chunks',chunks=extra))
        base=len(g['positions'])//3
        g['positions'].extend(vertices);g['indices'].extend(i+base for i in model['indices'])
        counts['includedM2Placements']+=1
        counts['addedCollisionTriangles']+=len(model['indices'])//3
        selected.append(dict(fileDataID=row['reference'],uniqueID=row['uniqueID'],triangles=len(model['indices'])//3))
    large=g.get('regionID')==fullmap.REGION_ID
    if large:fullmap.validate_sources(pathlib.Path(evidence['path']).parent)
    if len(g['positions'])>(fullmap.MAX_POSITIONS if large else 1500000 if a.allow_full_tile else 30000) or len(g['indices'])>(fullmap.MAX_INDICES if large else 2000000 if a.allow_full_tile else 100000):t.fail('bounded-region-geometry-cap')
    g['regionBounds']=region
    g['m2Exclusions']=physics_exclusions
    g['source']['collisionAssets']=assets
    g['source']['collisionParserSHA256']=t.digest(pathlib.Path(__file__).read_bytes())
    g['source']['geometryBeforeCollisionSha256']=t.digest(pathlib.Path(a.input).read_bytes())
    g['collisionAudit']=dict(counts=dict(counts),included=selected,unresolved=unresolved,
        transformReference='wow.export pinned M2Renderer.compute_model_matrix with loader x,z,-y conversion',
        transformNativeVerified=False,physicsProfileNativeVerified=False)
    g['coverage']['staticM2']=not any(e['kind']=='m2' for e in unresolved)
    g['coverage']['staticWMO']=not unresolved and counts['excludedWMOByBounds']==sum(r['kind']=='wmo' for r in g['placements'])
    g['coverage']['liquids']='no-MH2O-or-MCLQ-in-root-ADT; WMO bounds excluded for this region'
    g['status']='static-collision-included-unvalidated' if not unresolved else 'incomplete-collision'
    g['publishable']=False
    g['limitations']=['Research navmesh: exact local terrain plus decoded static M2 collision; NOT runtime approved.',
        'Transforms and agent physics require native validation before publication.',
        'Dynamic doors, gameobject states, enemies, phasing and temporary obstacles are not established by this geometry.',
        'Spatial WMO exclusion applies only to this small region; expanding requires WMO groups and doodad collisions.',
        'No edges outside region or swim/transport connections are established.']
    g['statistics']['vertices']=len(g['positions'])//3;g['statistics']['triangles']=len(g['indices'])//3
    g['statistics']['collision']=dict(counts)
    out=pathlib.Path(a.output);out.write_text(json.dumps(g,separators=(',',':'),allow_nan=False))
    print(json.dumps(dict(output=str(out),sha256=t.digest(out.read_bytes()),counts=dict(counts),unresolved=unresolved,vertices=len(g['positions'])//3,triangles=len(g['indices'])//3)))
if __name__=='__main__':main()
