"""Bounded exact-build WMO static collision proof; never runtime approved.
Independently authored parser. Binary layouts and transforms: wow.export c2fd7bd (MIT).
Collision flag semantics cross-checked against TrinityCore 1f70838 (GPL2+ reference only).
No reference implementation code or extracted game asset is intended for repository inclusion.
"""
import argparse, collections, json, math, pathlib, struct
import terrain_probe as t
import collision_probe as c

BUILD='1.60.1.69913'
BUILD_CONFIG='6c0df97e8e481a9a41600e373367c200'
CDN_CONFIG='5525ea1ce6668e895569c89c2d6a154c'
TC_PIN='1f70838eff729a099c32b2e50f8c122bf385c970'


def unpack(fmt,data,offset=0):
    size=struct.calcsize(fmt)
    if offset<0 or offset+size>len(data): t.fail('WMO-field-overrun')
    return struct.unpack_from(fmt,data,offset)


def table(data):
    result={}; inventory=[]
    for tag,a,b in t.chunks(data):
        inventory.append(dict(tag=tag,bytes=b-a))
        if tag in result: t.fail('WMO-duplicate-chunk:'+tag)
        result[tag]=data[a:b]
    return result,inventory


def require(parts,key,stride=None):
    if key not in parts:t.fail('WMO-missing:'+key)
    data=parts[key]
    if stride and len(data)%stride:t.fail('WMO-stride:'+key)
    return data


def version(parts):
    data=require(parts,'MVER')
    if len(data)!=4 or unpack('<I',data)[0]!=17:t.fail('unsupported-WMO-version')


def finite(values):
    if not all(math.isfinite(v) and abs(v)<100000 for v in values):t.fail('WMO-nonfinite-or-bound')


def root(data):
    parts,inventory=table(data);version(parts)
    h=require(parts,'MOHD')
    if len(h)!=64:t.fail('WMO-MOHD-size')
    group_count=unpack('<I',h,4)[0];doodad_count=unpack('<I',h,20)[0];set_count=unpack('<I',h,24)[0]
    if not 0<group_count<=512 or set_count>256:t.fail('WMO-root-cap')
    groups=require(parts,'GFID',4)
    if len(groups)!=group_count*4:t.fail('WMO-LOD-or-group-count')
    groups=list(unpack('<'+'I'*group_count,groups))
    if not all(groups) or len(set(groups))!=len(groups):t.fail('WMO-group-reference')
    if len(require(parts,'MOGI',32))!=group_count*32:t.fail('WMO-MOGI-count')
    sets_data=require(parts,'MODS',32)
    if len(sets_data)!=set_count*32:t.fail('WMO-set-count')
    sets=[]
    for at in range(0,len(sets_data),32):
        start,count,pad=unpack('<3I',sets_data,at+20)
        if pad:t.fail('WMO-set-padding')
        sets.append(dict(name=sets_data[at:at+20].split(b'\0')[0].decode('ascii'),first=start,count=count))
    defs=require(parts,'MODD',40)
    ref_data=require(parts,'MODI',4) if defs or 'MODI' in parts else b''
    references=list(unpack('<'+'I'*(len(ref_data)//4),ref_data))
    actual_doodad_count=len(defs)//40
    # MODD framing, not MOHD's advisory count, controls actual allocation/ranges.
    # Independently corroborated by pinned wow.export and WoWFormatLib parsers.
    if actual_doodad_count>20000:t.fail('WMO-framed-doodad-cap')
    if any(v['first']+v['count']>actual_doodad_count for v in sets):t.fail('WMO-selected-range-exceeds-framed-doodads')
    doodads=[]
    for at in range(0,len(defs),40):
        packed=unpack('<I',defs,at)[0];offset=packed&0xffffff;flags=packed>>24
        if offset>=len(references):t.fail('WMO-doodad-reference-range')
        pos=unpack('<3f',defs,at+4);quat=unpack('<4f',defs,at+16);scale=unpack('<f',defs,at+32)[0]
        finite((*pos,*quat,scale))
        if not 0<scale<=100 or abs(sum(q*q for q in quat)-1)>0.0001:t.fail('WMO-doodad-transform')
        doodads.append(dict(reference=references[offset],referenceIndex=offset,flags=flags,position=pos,rotation=quat,scale=scale))
    rootflags,lod=unpack('<2H',h,60)
    finite(unpack('<6f',h,36))
    known={'MVER','MOHD','MOMT','MOGN','MOGI','MOSB','MOPV','MOPT','MOPR','MOVV','MOVB','MOLT','MODS','MODD','MFOG','GFID','MODI'}
    unknown=sorted(set(parts)-known)
    return dict(groups=groups,sets=sets,doodads=doodads,inventory=inventory,flags=rootflags,lod=lod,unknownChunks=unknown,advertisedDoodadCount=doodad_count,framedDoodadCount=actual_doodad_count)


def collision_face(flags):
    # Binary format flags: 0x08 collision, 0x20 rendered solid, 0x04 detail.
    # Material 0xff is permitted: these often supply simplified collision ramps.
    return bool(flags&8 or (flags&32 and not flags&4))


def group(data,root_flags=None):
    parts,inventory=table(data);version(parts)
    raw=require(parts,'MOGP')
    if len(raw)<68:t.fail('WMO-MOGP-header')
    flags=unpack('<I',raw,8)[0];liquid=unpack('<I',raw,52)[0];flags2=unpack('<I',raw,60)[0]
    sub,subs=table(raw[68:]);verts=require(sub,'MOVT',12);inds=require(sub,'MOVI',6);mopy=require(sub,'MOPY',2)
    nv=len(verts)//12;nt=len(inds)//6
    if nv>65536 or nt>100000 or len(mopy)!=nt*2:t.fail('WMO-geometry-count')
    positions=list(unpack('<'+'f'*(nv*3),verts));finite(positions)
    allindices=list(unpack('<'+'H'*(nt*3),inds))
    if any(i>=nv for i in allindices):t.fail('WMO-vertex-index')
    indices=[];faceflags=collections.Counter();material255=0
    for i in range(nt):
        f,material=mopy[2*i:2*i+2];faceflags[f]+=1
        if collision_face(f):
            indices.extend(allindices[i*3:i*3+3]);material255+=material==255
    unsupported=[]
    if flags&0x80:unsupported.append('unreachable-group-flag')
    if flags&0x4000000:unsupported.append('antiportal-group-flag')
    if flags2:unsupported.append('secondary-group-flags-or-split-group')
    # Root bit 4 selects modern type IDs; legacy 15 means no liquid.
    # Unknown root semantics never establish absence. MLIQ/has-liquid still wins.
    absent=root_flags is not None and liquid==(0 if root_flags&4 else 15)
    if 'MLIQ' in sub or flags&0x1000 or not absent:unsupported.append('WMO-liquid-not-modeled')
    known={'MOPY','MOVI','MOVT','MONR','MOTV','MOBA','MOBS','MOLR','MODR','MOBN','MOBR','MOCV'}
    unsupported.extend('unknown-group-chunk:'+tag for tag in sorted(set(sub)-known))
    if set(parts)!={'MVER','MOGP'}:unsupported.append('unknown-group-top-level-chunk')
    doodad_refs=require(sub,'MODR',2) if 'MODR' in sub else b''
    return dict(positions=positions,indices=indices,flags=flags,flags2=flags2,liquidType=liquid,liquidRootFlags=root_flags,
        inventory=inventory,subchunks=subs,faceFlags=dict(faceflags),sourceTriangles=nt,
        collisionTriangles=len(indices)//3,collisionOnlyMaterialTriangles=material255,
        unsupported=unsupported,doodadReferences=list(unpack('<'+'H'*(len(doodad_refs)//2),doodad_refs)))


def unsupported_doodad_flags(flags):
    # MODD high-byte bit 2 is InteriorLighting, not collision/placement behavior.
    # wowlib's SMODoodadDef enum and TrinityCore's collision extractor agree.
    # Other bits remain unsupported until their collision implications are checked.
    return flags & ~2

def selected_doodads(wmo,index):
    if not isinstance(index,int) or not 0<=index<len(wmo['sets']):t.fail('WMO-selected-set-range')
    sets=sorted({0,index});selected=set()
    for ident in sets:
        row=wmo['sets'][ident];selected.update(range(row['first'],row['first']+row['count']))
    return sets,sorted(selected)


def doodad_positions(model,row):
    x,y,z,w=row['rotation'];s=row['scale'];p=row['position']
    # Standard quaternion rotation in raw WoW axes. WMO placement applies axis conversion next.
    mat=((1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)),
         (2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)),
         (2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)))
    out=[]
    for at in range(0,len(model['positions']),3):
        v=model['positions'][at:at+3]
        out.extend(p[i]+s*sum(mat[i][j]*v[j] for j in range(3)) for i in range(3))
    return out


def demonstrated_empty_274(data):
    # Narrow support for the exact acquired 274 sample independently decoded by the
    # unmodified pinned wow.export M2Loader; no broad compatibility inference.
    if t.digest(data)!='4e3be9da12879a6de2e441391b4deba8c5fa45ee721051cb3279d2168ca7cae8':
        t.fail('unsupported-M2-version')
    at=0;tags=[];payload=None
    while at<len(data):
        if len(data)-at<8:t.fail('M2-274-truncated-header')
        tag=data[at:at+4].decode('ascii');size=unpack('<I',data,at+4)[0];end=at+8+size
        if end>len(data):t.fail('M2-274-overrun')
        tags.append(tag)
        if tag=='MD21':
            if payload is not None:t.fail('M2-274-duplicate-payload')
            payload=data[at+8:end]
        at=end
    if tags!=['MD21','TXAC','SFID','TXID'] or payload is None or payload[:4]!=b'MD20' or unpack('<I',payload,4)[0]!=274:t.fail('unsupported-M2-version')
    if unpack('<6I',payload,216)!=(0,0,0,0,0,0):t.fail('M2-274-not-empty-collision')
    if unpack('<7f',payload,188)!=(1e7,1e7,1e7,-1e7,-1e7,-1e7,0):t.fail('M2-274-empty-bounds-sentinel')
    return dict(version=274,positions=[],indices=[],chunks=tags,
        profile='exact-314951-empty-collision-demonstrated-by-pinned-loader')


def receipt_identity(receipt,recursive=False):
    if receipt.get('product')!='wow_classic_beta' or receipt.get('build' if recursive else 'version')!=BUILD or receipt.get('buildConfig')!=BUILD_CONFIG or receipt.get('cdnConfig')!=CDN_CONFIG:t.fail('WMO-receipt-identity')
    if not recursive and receipt.get('schema')!='rikui-local-terrain-extraction-evidence-v1':t.fail('WMO-receipt-schema')


def placement_bounds(placement):
    lo=placement['bounds'][:3];hi=placement['bounds'][3:]
    return [[t.TILE*32-hi[0],lo[1],t.TILE*32-hi[2]],
            [t.TILE*32-lo[0],hi[1],t.TILE*32-lo[2]]]

def build(geometry_path,directory,recursive_path):
    directory=pathlib.Path(directory);geometry_path=pathlib.Path(geometry_path)
    import map_profile as fullmap
    geometry_bytes=t.load(geometry_path,fullmap.MAX_BYTES);geometry=json.loads(geometry_bytes)
    large=geometry.get('regionID')==fullmap.REGION_ID
    if not large and len(geometry_bytes)>64*1024*1024:t.fail('input-size')
    if large:fullmap.validate_sources(directory)
    receipt_info=geometry['source']['acquisitionReceipt'];receipt_bytes=t.load(receipt_info['path'])
    if t.digest(receipt_bytes)!=receipt_info['sha256']:t.fail('WMO-changed-receipt')
    receipt=json.loads(receipt_bytes);receipt_identity(receipt)
    recursive_bytes=t.load(recursive_path);recursive=json.loads(recursive_bytes);receipt_identity(recursive,True)
    registered={e['fileDataID']:e for e in receipt['collisionDependencies']}
    for layer in recursive['additional'].values():
        for e in layer['files']:
            if e['fileDataID'] in registered:t.fail('WMO-duplicate-source-ID')
            registered[e['fileDataID']]=e
    if 'tiles' in geometry['source']['inputs']:
        import terrain_region
        decoded,names=terrain_region.validated_placements(geometry,receipt)
    else:
        obj_info=geometry['source']['inputs']['obj'];obj_bytes=t.load(obj_info['path'])
        expected=next(e for e in receipt['files'] if e['fileDataID']==778198)
        if t.digest(obj_bytes)!=expected['sha256'] or obj_info['sha256']!=expected['sha256']:t.fail('WMO-object-source-hash')
        decoded,_,names=t.objects(obj_bytes)
    if names or decoded!=geometry['placements']:t.fail('WMO-placement-provenance')
    placements=[p for p in decoded if p['kind']=='wmo']
    if len(placements)>(fullmap.MAX_WMO_PLACEMENTS if large else 64):t.fail('WMO-placement-cap')
    assets={};models={};roots={};groups={};unsupported=[];countNotes=[];audit=[];positions=[];indices=[];counts=collections.Counter()
    def asset(ident):
        entry=registered.get(ident)
        if entry is None:t.fail('WMO-unregistered-file:'+str(ident))
        options=[directory/k/f'{ident}.bin' for k in ('collision','wmo-groups','wmo-doodads')]
        paths=[p for p in options if p.is_file()]
        if len(paths)!=1:t.fail('WMO-missing-or-ambiguous-file:'+str(ident))
        data=t.load(paths[0])
        if len(data)!=entry['bytes'] or t.digest(data)!=entry['sha256']:t.fail('WMO-asset-hash:'+str(ident))
        assets[ident]=dict(fileDataID=ident,path=str(paths[0].resolve()),bytes=len(data),sha256=t.digest(data))
        return data
    def add(verts,inds):
        base=len(positions)//3;positions.extend(verts);indices.extend(i+base for i in inds)
        if len(positions)>(fullmap.MAX_POSITIONS if large else 1500000) or len(indices)>(fullmap.MAX_INDICES if large else 3000000):t.fail('WMO-output-cap')
    for placement in placements:
        ident=placement['reference'];uid=placement['uniqueID']
        if placement['flags']!=12:t.fail('WMO-unsupported-MODF-flags')
        if not 0<placement['scale']<=10240:t.fail('WMO-placement-scale')
        if ident not in roots:
            try:roots[ident]=root(asset(ident))
            except ValueError as error:
                if str(error)!='WMO-LOD-or-group-count':raise
                unsupported.append(dict(placementID=uid,fileDataID=ident,
                    reason='WMO-unsupported-root-layout',layout=str(error)))
                audit.append(dict(placementID=uid,fileDataID=ident,groupIDs=[],
                    unsupportedRootLayout=str(error),MODFworldBounds=placement_bounds(placement),
                    transformNativeVerified=False))
                continue
        wmo=roots[ident]
        unsupported.extend(dict(placementID=uid,reason='root-chunk:'+x) for x in wmo['unknownChunks'])
        if wmo['advertisedDoodadCount']!=wmo['framedDoodadCount']:
            countNotes.append(dict(placementID=uid,fileDataID=ident,reason='MOHD-count-advisory-MODD-framing-authoritative',advertised=wmo['advertisedDoodadCount'],framed=wmo['framedDoodadCount']))
        try:active,selected=selected_doodads(wmo,placement['doodadSet'])
        except ValueError as error:
            if not large or str(error)!='WMO-selected-set-range':raise
            unsupported.append(dict(placementID=uid,fileDataID=ident,reason='WMO-selected-set-range'))
            audit.append(dict(placementID=uid,fileDataID=ident,groupIDs=[],
                unsupportedRootLayout=str(error),MODFworldBounds=placement_bounds(placement),transformNativeVerified=False))
            continue
        rowaudit=dict(placementID=uid,fileDataID=ident,selectedSetIndices=active,
            selectedSets=[wmo['sets'][i] for i in active],selectedDoodads=len(selected),groupIDs=wmo['groups'],
            nameSet=placement['nameSet'],transformNativeVerified=False)
        percounts=collections.Counter()
        wmo_vertices=[]
        for gid in wmo['groups']:
            if gid not in groups:groups[gid]=group(asset(gid),wmo['flags'])
            gr=groups[gid]
            if gr['liquidRootFlags']!=wmo['flags']:t.fail('WMO-conflicting-group-liquid-semantics')
            if any(i>=len(wmo['doodads']) for i in gr['doodadReferences']):t.fail('WMO-group-doodad-reference-range')
            unsupported.extend(dict(placementID=uid,fileDataID=gid,reason=r) for r in gr['unsupported'])
            world=c.transformed(gr,placement);add(world,gr['indices']);wmo_vertices.extend(world)
            counts['WMOGroupInstances']+=1;counts['WMOGroupTriangles']+=len(gr['indices'])//3
            percounts['groupTriangles']+=len(gr['indices'])//3
        flagged=[i for i in selected if unsupported_doodad_flags(wmo['doodads'][i]['flags'])]
        rowaudit['unsupportedDoodadFlagIndices']=flagged
        if flagged:
            unsupported.append(dict(placementID=uid,fileDataID=ident,reason='WMO-doodad-flags',
                flags=sorted({wmo['doodads'][i]['flags'] for i in flagged})))
        for idx in selected:
            dd=wmo['doodads'][idx];did=dd['reference']
            if not did:t.fail('WMO-selected-null-doodad')
            if unsupported_doodad_flags(dd['flags']):
                counts['selectedDoodadInstances']+=1;counts['unsupportedDoodadFlagInstances']+=1
                continue
            if did not in models:
                data=asset(did)
                try:models[did]=c.m2(data)
                except ValueError as error:
                    if str(error)!='unsupported-M2-version':raise
                    try:models[did]=demonstrated_empty_274(data)
                    except ValueError:models[did]=dict(unsupported=str(error),version=unpack('<I',data,12)[0])
            model=models[did]
            counts['selectedDoodadInstances']+=1
            if 'unsupported' in model:
                unsupported.append(dict(placementID=uid,fileDataID=did,doodadIndex=idx,reason=model['unsupported'],version=model['version']))
                counts['unsupportedDoodadInstances']+=1
                continue
            if model.get('profile'):counts['demonstratedEmpty274Instances']+=1
            extra=[tag for tag in model['chunks'] if tag in ('PFID','PHY2','PCOL')]
            unsupported.extend(dict(placementID=uid,fileDataID=did,doodadIndex=idx,reason='extra-model-physics:'+tag) for tag in extra)
            if not model['indices']:
                counts['doodadsWithoutStaticCollision']+=1;continue
            raw=doodad_positions(model,dd);world=c.transformed(dict(positions=raw),placement)
            add(world,model['indices']);counts['collisionDoodadInstances']+=1
            counts['WMOdoodadTriangles']+=len(model['indices'])//3
            percounts['doodadTriangles']+=len(model['indices'])//3
        rowaudit['counts']=dict(percounts);rowaudit['decodedGroupWorldBounds']=c.bounds(wmo_vertices)
        lo=placement['bounds'][:3];hi=placement['bounds'][3:]
        expectedbox=[[t.TILE*32-hi[0],lo[1],t.TILE*32-hi[2]],[t.TILE*32-lo[0],hi[1],t.TILE*32-lo[2]]]
        rowaudit['MODFworldBounds']=expectedbox
        # Group meshes must lie inside stored placement bounds, allowing float precision only.
        bounds=rowaudit['decodedGroupWorldBounds'];violation=max(max(expectedbox[0][i]-bounds[0][i],bounds[1][i]-expectedbox[1][i]) for i in range(3))
        rowaudit['maxGroupBoundsViolation']=violation
        if violation>0.1:unsupported.append(dict(placementID=uid,reason='WMO-transform-outside-MODF-bounds',yards=violation))
        audit.append(rowaudit)
    counts['placements']=len(placements);counts['uniqueWMORoots']=len(roots);counts['uniqueWMOGroups']=len(groups);counts['uniqueSelectedDoodadModels']=len(models)
    result=dict(schema='rikui-wmo-collision-proof-v1',product='wow_classic_beta',build=BUILD,status='derived-pending-validation',
        publishable=False,nativeVerified=False,positions=positions,indices=indices,
        source=dict(geometry=dict(path=str(geometry_path.resolve()),sha256=t.digest(geometry_bytes)),
            acquisitionReceipt=dict(path=receipt_info['path'],sha256=t.digest(receipt_bytes)),
            recursiveReceipt=dict(path=str(pathlib.Path(recursive_path).resolve()),sha256=t.digest(recursive_bytes)),
            buildConfig=BUILD_CONFIG,cdnConfig=CDN_CONFIG,assets=list(assets.values()),
            parser='rikui-wmo-probe-v1',parserSha256=t.digest(pathlib.Path(__file__).read_bytes()),dependencyScriptSha256={name:t.digest((pathlib.Path(__file__).parent/name).read_bytes()) for name in (('terrain_probe.py','collision_probe.py')+(('terrain_region.py','west_profile.py') if 'tiles' in geometry['source']['inputs'] else ()))},formatReference=dict(repo='Kruithne/wow.export',commit=t.PIN,license='MIT'),
            empty274Reference=dict(path=str(pathlib.Path(__file__).parent/'m2-274-reference.json'),sha256=t.digest(t.load(pathlib.Path(__file__).parent/'m2-274-reference.json')),sourceSha256='4e3be9da12879a6de2e441391b4deba8c5fa45ee721051cb3279d2168ca7cae8'),
            collisionFlagReference=dict(repo='TrinityCore/TrinityCore',commit=TC_PIN,files=['src/tools/vmap4_extractor/wmo.h','src/tools/vmap4_extractor/wmo.cpp'],license='GPL-2.0-or-later; semantics reference only; no implementation copied')),
        coverage=dict(staticWMO=not unsupported,selectedDoodads=not unsupported,framedSelectedStaticDecoded=not unsupported,allGroupDoodadRefsInRange=True,liquids=('present-and-unmodeled-in-selected-WMO-groups' if any(v['reason']=='WMO-liquid-not-modeled' for v in unsupported) else 'no-encoded-liquids-and-no-effective-WMO-liquid-types'),
            transformsNativeVerified=False,dynamicObjects=False,phaseState=False),
        audit=dict(placements=audit,counts=dict(counts),unsupported=unsupported,headerCountNotes=countNotes,
            roots=[dict(fileDataID=i,groups=r['groups'],sets=r['sets'],flags=r['flags'],chunks=r['inventory'],advertisedDoodadCount=r['advertisedDoodadCount'],framedDoodadCount=r['framedDoodadCount']) for i,r in roots.items()],
            groups=[dict(fileDataID=i,**{k:v for k,v in g.items() if k not in ('positions','indices')}) for i,g in groups.items()]),
        limitations=['Static collision interpretation is an offline derived candidate, not verified Forever client traversal.',
            'Doodad sets include the default set and selected MODF set; dynamic doors, gameobjects and phasing remain unknown.',
            'Triangle collision semantics are inferred from independently maintained format implementations; native verification remains required.',
            'No authorization to publish or redistribute extracted game assets is implied.'])
    if unsupported:result['status']='incomplete-collision'
    return result


def main():
    p=argparse.ArgumentParser();p.add_argument('--input',required=True);p.add_argument('--directory',required=True)
    p.add_argument('--recursive-receipt',required=True);p.add_argument('--output',default='collision-wmo.json')
    a=p.parse_args();result=build(a.input,a.directory,a.recursive_receipt)
    out=pathlib.Path(a.output);out.write_text(json.dumps(result,separators=(',',':'),allow_nan=False))
    print(json.dumps(dict(output=str(out.resolve()),sha256=t.digest(out.read_bytes()),vertices=len(result['positions'])//3,
        triangles=len(result['indices'])//3,counts=result['audit']['counts'],unsupported=result['audit']['unsupported'],status=result['status'])))
if __name__=='__main__':main()
