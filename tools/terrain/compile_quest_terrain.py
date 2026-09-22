"""Compile hash-pinned carved Forever terrain JSON into RikUIQuestTerrain.
Stdlib only; output must be nonexistent or empty. No raw assets are copied.
Hash integrity does not independently authenticate source or native traversal.
"""
import argparse, hashlib, json, math, pathlib, re, stat, tempfile
import region_contract, coverage_contract
from terrain_contract import CompileError, need, integer, number, text, hash_string, array, obj, point, bounds, exclusion_rect, runtime_geometry, runtime_metadata
from coverage_contract import GATE, LIQUID_GATE, FLAG_GATE, MITIGATION
coverage=coverage_contract.validate
PARSER='rikui-terrain-compiler-v1'
IDENTITY={'product':'wow_classic_beta','edition':'Forever','build':'1.60.1.69913','locale':'enUS'}
RUNTIME_IDENTITY={'product':'forever','build':'1.60.1.69913','locale':'enUS'}
BUILD_CONFIG='6c0df97e8e481a9a41600e373367c200'
CDN_CONFIG='5525ea1ce6668e895569c89c2d6a154c'
PROJECTION={'originX':-3877.0832519531,'originY':1802.0832519531,'width':4924.9997558593,'height':3283.3332519531}
PROJECTION_SOURCE={'url':'https://wago.tools/db2/UiMapAssignment/csv?build=1.60.1.69913','sha256':'79267e8be8034e47daab14350411b3acc0b1f64e86efc9d821a217497254ca0a','rowID':46736,'uiMapID':1426,'mapID':0,'areaID':1,'region':[-7160.4165039062,-3122.9165039062,-1000000,-3877.0832519531,1802.0832519531,1000000],'interpretation':'Nav X=game world Y; Nav Z=game world X; UI axes reverse these extents.'}
MAX_MANIFEST=2*1024*1024
MAX_SHARD=2*1024*1024
# Offline JSON/Lua byte bound; polygon, portal, shard and runtime limits remain independent.
# Restored cave collision produces 17.4 MB of JSON within the existing graph limits.
MAX_TOTAL=32*1024*1024
MAX_SHARDS=512
MAX_POLYGONS=65536
MAX_PORTALS=131072
MAX_SHARD_POLYGONS=1024
MAX_SHARD_PORTALS=4096
MAX_NODES=1000000
REGION=re.compile(r'region-[0-9]{1,3}-[0-9]{1,3}-[0-9]{1,3}\.json\Z')
def sha(data):return hashlib.sha256(data).hexdigest()
def reparse(path):
    info=path.lstat()
    return path.is_symlink() or bool(getattr(info,'st_file_attributes',0)&getattr(stat,'FILE_ATTRIBUTE_REPARSE_POINT',0x400))
def read_bounded(path,cap):
    path=pathlib.Path(path);need(not reparse(path) and path.is_file(),'input-not-regular-file')
    need(0<path.stat().st_size<=cap,'input-size-bound')
    with path.open('rb') as stream:data=stream.read(cap+1)
    need(0<len(data)<=cap,'input-size-bound');return data
def parse_json(data):
    def pairs(items):
        result={}
        for key,value in items:need(key not in result,'duplicate-json-key');result[key]=value
        return result
    def constant(value):raise CompileError('nonfinite-json-number')
    def parse_int(value):need(len(value)<=20,'json-integer-bound');return int(value)
    try:result=json.loads(data.decode('utf-8'),object_pairs_hook=pairs,parse_constant=constant,parse_int=parse_int)
    except (UnicodeError,json.JSONDecodeError,RecursionError,OverflowError) as error:raise CompileError('invalid-json') from error
    stack=[(result,0)];count=0
    while stack:
        value,depth=stack.pop();count+=1;need(count<=MAX_NODES and depth<=32,'json-resource-bound')
        if isinstance(value,dict):
            need(all(type(k) is str and len(k)<=256 for k in value),'json-key-bound');stack.extend((v,depth+1) for v in value.values())
        elif isinstance(value,list):stack.extend((v,depth+1) for v in value)
        elif type(value) is float:need(math.isfinite(value),'nonfinite-json-number')
        elif type(value) is str:need(len(value)<=8192 and '\0' not in value,'json-string-bound')
    return result
def identity(value):need(value==IDENTITY,'unsupported-product-build-locale')
def carve_aabb(points,rect):
    xs=[p[0] for p in points];zs=[p[2] for p in points]
    return max(xs)>=rect[0] and min(xs)<=rect[2] and max(zs)>=rect[1] and min(zs)<=rect[3]
def exclusion_index(rectangles):
    cells={}
    for rect in rectangles:
        for x in range(math.floor(rect[0]/64),math.floor(rect[2]/64)+1):
            for z in range(math.floor(rect[1]/64),math.floor(rect[3]/64)+1):cells.setdefault((x,z),[]).append(rect)
    def near(points):
        xs=[p[0] for p in points];zs=[p[2] for p in points];seen=set()
        for x in range(math.floor(min(xs)/64),math.floor(max(xs)/64)+1):
            for z in range(math.floor(min(zs)/64),math.floor(max(zs)/64)+1):
                for rect in cells.get((x,z),[]):
                    key=tuple(rect)
                    if key not in seen:seen.add(key);yield rect
    return near

def polygon(row,exclusions,region_bounds):
    row=obj(row,'polygon');need(set(row)=={'id','points','portals','center'},'unsupported-polygon-fields')
    ident=integer(row.get('id'),1,2147483647,'polygon-ID');pts=array(row.get('points'),6,'polygon-points');need(len(pts)>=3,'polygon-too-small')
    pts=[point(p,'polygon-point') for p in pts];point(row.get('center'),'polygon-center')
    need(len({(p[0],p[2]) for p in pts})==len(pts),'duplicate-horizontal-vertex')
    need(all(region_bounds[0]-.002<=p[0]<=region_bounds[2]+.002 and region_bounds[1]-.002<=p[2]<=region_bounds[3]+.002 for p in pts),'polygon-outside-supported-tile')
    turns=[]
    for i in range(len(pts)):
        a,b,c=pts[i-2],pts[i-1],pts[i];cross=(b[0]-a[0])*(c[2]-b[2])-(b[2]-a[2])*(c[0]-b[0])
        if abs(cross)>1e-7:turns.append(cross)
    need(turns and (all(v>0 for v in turns) or all(v<0 for v in turns)),'nonconvex-or-degenerate-polygon')
    orientation=1 if turns[0]>0 else -1
    for i,a in enumerate(pts):
        b=pts[(i+1)%len(pts)]
        need(all(((b[0]-a[0])*(v[2]-a[2])-(b[2]-a[2])*(v[0]-a[0]))*orientation>=-1e-5 for v in pts),'nonconvex-or-self-intersecting-polygon')
    need(not any(carve_aabb(pts,r) for r in (exclusions(pts) if callable(exclusions) else exclusions)),'polygon-touches-exclusion');portals=[];targets=set()
    for portal in array(row.get('portals'),32,'polygon-portals'):
        portal=obj(portal,'portal');need(set(portal)=={'to','left','right','meters'},'unsupported-portal-fields')
        target=integer(portal.get('to'),1,2147483647,'portal-target');need(target!=ident and target not in targets,'self-or-duplicate-portal');targets.add(target)
        left,right=point(portal.get('left'),'portal-left'),point(portal.get('right'),'portal-right')
        need(math.hypot(left[0]-right[0],left[2]-right[2])>1e-6 and math.dist(left,right)>=.0001,'degenerate-portal');need(number(portal.get('meters'),'portal-distance')>0,'invalid-portal-distance')
        portals.append({'to':target,'left':left,'right':right})
    return {'id':ident,'points':pts,'portals':portals}
def boundary_sample(p,points):
    x,z=p[0],p[2]
    best=(math.inf,None)
    for i,a in enumerate(points):
        b=points[(i+1)%len(points)];dx,dz=b[0]-a[0],b[2]-a[2];norm=dx*dx+dz*dz
        if norm<=.00001:continue
        q=max(0,min(1,((x-a[0])*dx+(z-a[2])*dz)/norm))
        distance=math.hypot(x-a[0]-q*dx,z-a[2]-q*dz)
        if distance<best[0]:best=(distance,a[1]+q*(b[1]-a[1]))
    return best

def point_on_boundary(p,points,tolerance=0.01):return boundary_sample(p,points)[0]<=tolerance

def contains(points,p):
    signs=[]
    for i,a in enumerate(points):
        b=points[(i+1)%len(points)]
        value=(b[0]-a[0])*(p[2]-a[2])-(b[2]-a[2])*(p[0]-a[0])
        if abs(value)>1e-5:signs.append(value>0)
    return not signs or all(v==signs[0] for v in signs)

def portal_heights(portal,source,target,modeled_max_step):
    left,right=portal['left'],portal['right'];midpoint=[(a+b)/2 for a,b in zip(left,right)]
    need(contains(source,midpoint) and contains(target,midpoint),'portal-midpoint-outside-polygon')
    for point in (left,right,midpoint):
        source_error,source_y=boundary_sample(point,source)
        target_error,target_y=boundary_sample(point,target)
        need(source_error<=.002 and target_error<=.01,'portal-not-on-both-boundaries')
        need(abs(point[1]-source_y)<=.002,'portal-height-disagrees-with-source-edge')
        need(abs(source_y-target_y)<=modeled_max_step+.002,'portal-exceeds-modeled-step')
def validate(manifest_path,expected_sha,*,regional=False):
    hash_string(expected_sha,'expected-manifest-SHA256');manifest_path=pathlib.Path(manifest_path).absolute();data=read_bounded(manifest_path,16*1024*1024 if regional else MAX_MANIFEST)
    need(sha(data)==expected_sha,'manifest-hash-mismatch');m=obj(parse_json(data),'manifest');identity(m.get('identity'))
    large=regional and m.get('regionID')=='dun-morogh-map-69913'
    polygon_cap,portal_cap,shard_cap,total_cap=(524288,1048576,4096,512*1024*1024) if large else (MAX_POLYGONS,MAX_PORTALS,MAX_SHARDS,MAX_TOTAL)
    need(m.get('format') in ('rikui-nav-tile-proof-v1',region_contract.REGION_FORMAT),'unsupported-manifest-format')
    need(m.get('status')=='derived-pending-validation' and m.get('publishable') is False,'unsupported-publication-state')
    need(m.get('coordinateSystem')=='Y-up; X=game world Y; Z=game world X','unsupported-coordinate-system')
    source=obj(m.get('source'),'source');need(source.get('buildConfig')==BUILD_CONFIG and source.get('cdnConfig')==CDN_CONFIG,'unsupported-source-build')
    acq=obj(source.get('acquisitionReceipt'),'acquisition-receipt');hash_string(acq.get('sha256'),'acquisition-receipt-hash');text(acq.get('path'),'acquisition-receipt-path',4096)
    region=obj(m.get('bounds'),'source-bounds');box=bounds([region.get('min'),region.get('max')]);region_bounds=[box[0][0],box[0][2],box[1][0],box[1][2]]
    source_region=region_contract.validate(m,source,region_bounds,need)
    rectangles,gates,modeled_max_step=coverage(m,region_bounds);limitations=[text(v,'limitation') for v in array(m.get('limitations'),24,'limitations')];need(limitations,'missing-model-limitations')
    if m['generator'].get('agentProfile')=='classic-reference-step-v1':
        limitations.append('One-yard step uses a Classic server reference rounded down; Forever player physics are unverified.')
    for gate in gates:
        limitations.append('Excluded placement %d: %s (source file %s).'%(gate['placementID'],gate['reason'],gate.get('fileDataID','unknown')))
    rectangle_query=exclusion_index(rectangles) if large else rectangles
    stats=obj(m.get('statistics'),'statistics');pc=integer(stats.get('polygons'),1,polygon_cap,'polygon-count');ec=integer(stats.get('directedEdges'),0,portal_cap,'portal-count');rc=integer(stats.get('regions'),1,shard_cap,'region-count')
    regions=array(m.get('regions'),shard_cap,'regions');need(len(regions)==rc,'region-count-mismatch')
    parent=manifest_path.parent.resolve();names=set();ids=set();grids=set();polys={};shards=[];total=0;edges=0;inputs=[]
    for record in regions:
        record=obj(record,'region-reference');name=record.get('filename');need(type(name) is str and REGION.fullmatch(name),'unsafe-region-path')
        need(name.casefold() not in names,'duplicate-region-path');names.add(name.casefold())
        rid=integer(record.get('id'),0,shard_cap-1,'region-ID');need(rid not in ids,'duplicate-region-ID');ids.add(rid)
        grid=record.get('grid');need(type(grid) is list and len(grid)==3,'invalid-region-grid')
        for x in grid:integer(x,0,127,'region-grid')
        need(tuple(grid) not in grids,'duplicate-region-grid');grids.add(tuple(grid));need(name=='region-%d-%d-%d.json'%tuple(grid),'region-name-grid-mismatch')
        path=parent/name;need(path.resolve().parent==parent,'escaped-region-path');raw=read_bounded(path,MAX_SHARD);total+=len(raw);need(total<=total_cap,'total-input-size-bound')
        need(len(raw)==integer(record.get('bytes'),1,MAX_SHARD,'region-bytes'),'region-size-mismatch');need(sha(raw)==hash_string(record.get('sha256'),'region-hash'),'region-hash-mismatch')
        shard=obj(parse_json(raw),'shard');identity(shard.get('identity'));need(set(shard)=={'format','identity','mapID','status','publishable','id','grid','polygons'},'unsupported-shard-fields')
        need(shard.get('format')=='rikui-nav-shard-v1' and shard.get('status')=='derived-pending-validation' and shard.get('publishable') is False,'unsupported-shard-format-or-state')
        need(type(shard.get('mapID')) is int and shard['mapID']==0 and type(shard.get('id')) is int and shard['id']==rid and shard.get('grid')==grid,'shard-identity-mismatch')
        rows=array(shard.get('polygons'),MAX_SHARD_POLYGONS,'shard-polygons');need(len(rows)==integer(record.get('polygons'),0,MAX_SHARD_POLYGONS,'region-polygon-count'),'region-polygon-count-mismatch');runtime=[];region_edges=0
        for row in rows:
            p=polygon(row,rectangle_query,region_bounds);need(p['id'] not in polys,'duplicate-polygon-ID');polys[p['id']]=p;runtime.append(p);region_edges+=len(p['portals']);need(len(polys)<=polygon_cap,'polygon-resource-bound')
            need(region_edges<=MAX_SHARD_PORTALS,'shard-portal-resource-bound')
        need(region_edges==integer(record.get('directedEdges'),0,MAX_SHARD_PORTALS,'region-edge-count'),'region-edge-count-mismatch');edges+=region_edges;need(edges<=portal_cap,'portal-resource-bound')
        shards.append({'identity':dict(RUNTIME_IDENTITY),'polygons':runtime});inputs.append(dict(filename=name,sha256=sha(raw),bytes=len(raw),polygons=len(rows),directedEdges=region_edges))
    need(len(polys)==pc and edges==ec,'manifest-count-mismatch');need(total==integer(stats.get('jsonShardBytes'),1,total_cap,'json-shard-byte-count'),'total-shard-byte-count-mismatch')
    runtime_geometry(polys.values(),max_cells=16384 if large else 4096)
    for p in polys.values():
        for portal in p['portals']:
            need(portal['to'] in polys,'dangling-portal');target=polys[portal['to']]
            need(all(point_on_boundary(v,p['points']) and point_on_boundary(v,target['points']) for v in (portal['left'],portal['right'])),'portal-not-on-both-boundaries')
            portal_heights(portal,p['points'],target['points'],modeled_max_step)
    for probe in array(m.get('probes',[]),8,'validation-probes'):
        probe=obj(probe,'probe');need(probe.get('success') is True,'unsupported-validation-probe')
        need(integer(probe.get('from'),1,2**32-1,'probe-from') in polys and integer(probe.get('to'),1,2**32-1,'probe-to') in polys,'probe-polygon-missing')
        need(number(probe.get('meters'),'probe-distance')>=0,'invalid-probe-distance')
        for pos in array(probe.get('path'),32768 if large else 4096,'probe-path'):point(pos,'probe-position')
        for ident in array(probe.get('polygonPath'),polygon_cap,'probe-polygon-path'):need(integer(ident,1,2**32-1,'probe-path-ID') in polys,'probe-path-polygon-missing')
    meta={'format':'rikui-navmesh-v1','identity':dict(RUNTIME_IDENTITY),'revision':expected_sha,'uiMapID':1426,'worldMapID':0,'source':{'sha256':expected_sha,'parser':PARSER},'projection':dict(PROJECTION),'counts':{'polygons':pc,'portals':ec},'exclusions':rectangles,'bounds':region_bounds,'blockers':[],'coverageScope':m['coverageScope'],'modeledMaxStep':modeled_max_step,'nativeVerified':False,'agentProfileCalibrated':False,'limitations':limitations}
    receipt={'format':'rikui-terrain-compile-receipt-v1','compiler':PARSER,'compilerSha256':sha(pathlib.Path(__file__).read_bytes()),'inputManifest':{'path':str(manifest_path.resolve()),'bytes':len(data),'sha256':expected_sha},'inputRegions':inputs,'sourceAudit':source,'inputCoverage':m['coverage'],'coverageGates':gates,'excludedFootprints':m['exclusions'],'projection':PROJECTION,'projectionSource':PROJECTION_SOURCE,'counts':{'shards':rc,'polygons':pc,'directedPortals':ec},'runtimeIdentity':RUNTIME_IDENTITY,'sourceAuthenticity':'Caller supplied expected hash; integrity does not independently authenticate acquisition claims.','modeledTraversal':'Only carved JSON graph compiled; raw Detour binary and game assets are not copied.','nativeVerified':False,'agentProfileCalibrated':False,'limitations':limitations,'geometryTolerance':{'polygonContainment':0.002,'portalBoundary':0.01},'validationProbes':array(m.get('probes',[]),8,'validation-probes')}
    meta['sourceRegion']=source_region
    meta['agentProfile']=m['generator'].get('agentProfile','uncalibrated-conservative-v1')
    receipt['agentProfile']=meta['agentProfile']
    if not regional:runtime_metadata(meta)
    receipt['sourceRegion']=source_region
    receipt['regionContractSha256']=sha(pathlib.Path(region_contract.__file__).read_bytes())
    receipt['coverageContractSha256']=sha(pathlib.Path(coverage_contract.__file__).read_bytes())
    receipt['primitiveContractSha256']=sha(pathlib.Path(__file__).with_name('terrain_contract.py').read_bytes())
    receipt['modeledMaxStep']=modeled_max_step
    receipt['modeledMaxStepSource']='Pinned Recast config walkableClimb * ch; not verified player physics.'
    receipt['geometryTolerance'].update(sourcePortalHeight=.002,targetPortalStepSlack=.002,sourcePortalBoundary=.002)
    return meta,shards,receipt
def lua(value):
    if isinstance(value,str):return '"'+''.join(chr(b) if 32<=b<=126 and b not in (34,92) else '\\%03d'%b for b in value.encode('utf-8'))+'"'
    if value is True:return 'true'
    if value is False:return 'false'
    if type(value) in (int,float):return repr(value)
    if isinstance(value,list):return '{'+','.join(lua(v) for v in value)+'}'
    if isinstance(value,dict):return '{'+','.join('['+lua(k)+']='+lua(v) for k,v in value.items())+'}'
    raise CompileError('unsupported-Lua-value')
def output_ready(out):
    need(out.parent.is_dir(),'output-parent-missing');need(out.name not in ('','.', '..'),'unsafe-output-directory')
    if out.exists():need(not reparse(out) and out.is_dir() and not any(out.iterdir()),'output-must-be-new-or-empty')
    else:need(not out.is_symlink(),'unsafe-output-symlink')
def compile_addon(manifest_path,expected_sha,out):
    out=pathlib.Path(out).absolute();output_ready(out);meta,shards,receipt=validate(manifest_path,expected_sha)
    names=['manifest.lua']+['shard-%03d.lua'%(i+1) for i in range(len(shards))]+['register.lua'];files={}
    files['RikUIQuestTerrain.toc']='## Interface: 16001\n## Title: RikUI Quest Terrain\n## Notes: Calculated terrain model outside excluded areas; native validation pending.\n## Version: 1\n## Dependencies: RikUI\n\n'+'\n'.join(names)+'\n'
    files['manifest.lua']='-- Generated by '+PARSER+'. Source integrity is separate from native traversal.\nlocal _, data = ...\ndata.meta = '+lua(meta)+'\ndata.shards = {}\n'
    for i,shard in enumerate(shards):files['shard-%03d.lua'%(i+1)]='local _, data = ...\ndata.shards[%d] = %s\n'%(i+1,lua(shard))
    files['register.lua']='local _, data = ...\nlocal RikUI = _G.RikUI\nif RikUI and RikUI.QuestPlanner and RikUI.QuestPlanner.Terrain then\n    RikUI.QuestPlanner.Terrain.Install(data.meta, data.shards)\nend\ndata.meta = nil\ndata.shards = nil\n'
    payloads={name:body.encode('utf-8') for name,body in files.items()};receipt['outputs']=[{'filename':n,'sha256':sha(b),'bytes':len(b)} for n,b in payloads.items()]
    payloads['validation-probes.json']=(json.dumps({'manifestSha256':expected_sha,'probes':receipt['validationProbes']},indent=2,allow_nan=False)+'\n').encode('utf-8')
    payloads['validation-probes.lua']=('return '+lua([{'from':p['from'],'to':p['to']} for p in receipt['validationProbes']])+'\n').encode('utf-8')
    receipt['outputs']=[{'filename':n,'sha256':sha(b),'bytes':len(b)} for n,b in payloads.items()]
    payloads['compile-receipt.json']=(json.dumps(receipt,indent=2,ensure_ascii=True,allow_nan=False)+'\n').encode('utf-8');need(sum(map(len,payloads.values()))<=MAX_TOTAL,'output-size-bound')
    staging=pathlib.Path(tempfile.mkdtemp(prefix='.'+out.name+'-compile-',dir=out.parent));written=[]
    try:
        for name,data in payloads.items():
            path=staging/name
            with path.open('xb') as stream:stream.write(data)
            written.append(path)
        output_ready(out)
        if out.exists():out.rmdir() # Only empty directory; never recursively remove user content.
        staging.rename(out)
    finally:
        if staging.exists():
            for path in written:
                if path.is_file() or path.is_symlink():path.unlink()
            try:staging.rmdir()
            except OSError:pass
    return {'output':str(out.resolve()),'manifestSha256':expected_sha,'files':len(payloads),'bytes':sum(map(len,payloads.values())),'counts':receipt['counts'],'receiptSha256':sha(payloads['compile-receipt.json'])}
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--manifest',required=True);parser.add_argument('--expected-sha256',required=True);parser.add_argument('--out',required=True);args=parser.parse_args()
    try:result=compile_addon(args.manifest,args.expected_sha256,args.out)
    except (CompileError,OSError) as error:parser.exit(2,'terrain compile rejected: '+str(error)+'\n')
    print(json.dumps(result,sort_keys=True))
if __name__=='__main__':main()
