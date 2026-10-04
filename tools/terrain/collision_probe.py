"""Add exact-build M2 collision arrays to the bounded terrain research region.
M2 v272 layout and transforms referenced from wow.export c2fd7bd (MIT).
No unverified data is published as runtime traversability.
"""
import argparse, collections, itertools, json, math, pathlib, struct
import terrain_probe as t
import map_profile as fullmap
from functools import lru_cache

EXTRA_PHYSICS=('PFID','PFDC','PHY2','PCOL')
WORLD_PROFILES_SHA='8e96673c2d0474423911f112bbc0ab1bc818d50e4f48670f34743ac8382b3119'

@lru_cache(maxsize=1)
def profiles274():
    from client_build import RECEIPT as CURRENT
    if CURRENT:
        record=CURRENT.get('m2Proof')
        if not record:t.fail('current-M2-proof-required')
        raw=pathlib.Path(record['path']).read_bytes()
        if t.digest(raw)!=record['sha256']:t.fail('current-M2-proof-changed')
        profile=json.loads(raw)
        if (profile.get('format')!='rikui-current-m2-proof-v1'
                or profile.get('sourceProfileSHA256')!=CURRENT['profileSHA256']):
            t.fail('current-M2-proof-identity')
        return {row['sha256']:row for row in profile['records']}
    profile=json.loads((pathlib.Path(__file__).parent/'m2-274-world-profiles.json').read_bytes())
    if t.digest(json.dumps(profile,sort_keys=True,separators=(',',':')).encode())!=WORLD_PROFILES_SHA:
        t.fail('M2-world-profiles-pin')
    return {row['sha256']:row for row in profile['records']}

def physics_gap(model,placement):
    """Unknown extra physics cannot be spatially excluded by static mesh bounds."""
    extra=[tag for tag in model['chunks'] if tag in EXTRA_PHYSICS]
    if not extra:return None
    proof=model.get('physicsExtent')
    if proof and extra==['PCOL']:
        vertices=transformed(model,placement)+transformed(proof,placement)
        return dict(placementID=placement['uniqueID'],fileDataID=placement['reference'],
            reason='extra-physics-chunks',chunks=extra,bounds=bounds(vertices),padding=.5,
            boundsProof={k:v for k,v in proof.items() if k!='positions'})
    return dict(kind='m2',fileDataID=placement['reference'],uniqueID=placement['uniqueID'],
        reason='extra-physics-chunks',chunks=extra)

def m2(data,validate_profile=True):
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
    profile=profiles274().get(t.digest(data)) if version==274 and validate_profile else None
    # Current reader's v274 empty layout is structurally bounded, rather than
    # tied to a historical decorative asset. Unknown chunks/physics stay closed.
    empty274=(version==274 and set(tags)<={'MD21','TXAC','LDV1','SFID','TXID'}
        and len(tags)==len(set(tags))
        and struct.unpack_from('<6I',payload,216)==(0,0,0,0,0,0)
        and struct.unpack_from('<7f',payload,188)==(1e7,1e7,1e7,-1e7,-1e7,-1e7,0))
    if version not in (272,274) or (version==274 and validate_profile and profile is None and not empty274):t.fail('unsupported-M2-version')
    count,offset,nverts,vertOffset,nnormals,normalOffset=struct.unpack_from('<6I',payload,216)
    if count%3 or count>300000 or nverts>65536 or nnormals>100000:t.fail('M2-collision-count')
    if ((count and offset<240) or (nverts and vertOffset<240) or (nnormals and normalOffset<240) or
        offset+count*2>len(payload) or vertOffset+nverts*12>len(payload) or normalOffset+nnormals*12>len(payload)):
        t.fail('M2-collision-overrun')
    indices=list(struct.unpack_from('<'+'H'*count,payload,offset))
    coords=list(struct.unpack_from('<'+'f'*(nverts*3),payload,vertOffset))
    normals=list(struct.unpack_from('<'+'f'*(nnormals*3),payload,normalOffset))
    if any(i>=nverts for i in indices):t.fail('M2-collision-index')
    if not all(math.isfinite(v) and abs(v)<100000 for v in coords+normals):t.fail('M2-collision-finite')
    if profile and (profile['bytes']!=len(data) or profile['vertices']!=nverts or profile['triangles']*3!=count):
        t.fail('M2-demonstrated-profile-mismatch')
    import m2_physics_extent
    result=dict(version=version,positions=coords,indices=indices,normals=normals,chunks=tags,physicsExtent=m2_physics_extent.extent(data))
    if empty274 and profile is None:
        result['profile']='bounded-v274-empty-static-collision'
    if profile:
        result['referenceProfile']=dict(fileDataID=profile['fileDataID'],sha256=profile['sha256'],
            reference='independent-collision-array-parity',nativeVerified=False)
        if profile['fileDataID']==314951:
            result['profile']='exact-314951-empty-collision-demonstrated-by-pinned-loader'
    return result

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
                or any(tag in model['chunks'] for tag in EXTRA_PHYSICS)):t.fail('unsupported-MDDF-flags')
            counts['pinnedEmptyUninterpretedPlacementFlags']+=1
        gap=physics_gap(model,row)
        if gap:
            if 'bounds' in gap:
                if intersects(gap['bounds'],region):physics_exclusions.append(gap)
            else:unresolved.append(gap)
        if not model['indices']:
            counts['noStaticM2Collision']+=1;continue
        vertices=transformed(model,row)
        if not intersects(bounds(vertices),region):counts['excludedM2ByBounds']+=1;continue
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
