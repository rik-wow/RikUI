"""Bounded physical terrain/collision stage for world_source jobs.
Uses existing strict decoders. Unsupported unbounded M2 evidence fails this job;
WMO unknowns retain the complete audited placement footprint as exclusions.
"""
import collections, json, math, pathlib, struct
import terrain_probe as t
import collision_probe as collision
import wmo_probe as wmo
import world_empty_placements as empty
import west_profile as west
from world_source import need, canonical, rect_intersects, tile_rect, expand, sha
MAX_POSITIONS=4_500_000
MAX_INDICES=9_000_000
MAX_PLACEMENTS=16384

def xz(box):return [box[0][0],box[0][2],box[1][0],box[1][2]]
def intersect(box,rect):return rect_intersects(xz(box),rect)
def geometry(source,job,placement_index):
 expected=source.job(job['worldMapID'],*job['batchGrid']);need(job==expected,'job differs from source')
 source.used={};positions=[];indices=[];excluded=[];gates=[];tile_audit=[];placements={};stats=collections.Counter()
 rect=job['inputXZ'];world=job['worldMapID'];models={};roots={};groups={};asset_bounds={}
 def add(vertices,triangles):
  if not triangles:return
  need(len(vertices)%3==0 and len(triangles)%3==0,'mesh arrays')
  need(len(positions)+len(vertices)<=MAX_POSITIONS and len(indices)+len(triangles)<=MAX_INDICES,'world batch geometry bound')
  base=len(positions)//3;positions.extend(vertices);indices.extend(base+i for i in triangles)
 def exclude(bounds,reason,**extra):
  need(len(bounds)==2 and all(len(p)==3 and all(math.isfinite(v) for v in p) for p in bounds),'exclusion shape')
  need(all(bounds[0][i]<=bounds[1][i] for i in range(3)),'exclusion order')
  if intersect(bounds,rect):excluded.append(dict(bounds=bounds,padding=.5,reason=reason,worldMapID=world,**extra))
 def model(ident):
  if ident not in models:
   data=source.asset(ident,'M2')
   try:models[ident]=collision.m2(data)
   except ValueError as error:
    if str(error)!='unsupported-M2-version':raise
    models[ident]=wmo.demonstrated_empty_274(data)
  return models[ident]
 for tile in job['tiles']:
  raw=source.asset(tile['rootADT'],'rootADT');obj=source.asset(tile['obj0ADT'],'obj0ADT')
  rows,inventory=t.root(raw);placed,objtags,names=t.objects(obj);need(not names,'world legacy name placement')
  need(abs(max(r['position'][0] for r in rows)-(32-tile['tile'][1])*t.TILE)<=.002 and abs(max(r['position'][1] for r in rows)-(32-tile['tile'][0])*t.TILE)<=.002,'world MCNK coordinate mismatch')
  unusual=sorted(set(inventory)-{'MVER','MHDR','MCIN','MFBO','MH2O','MCNK'})
  unknown_subs=sorted({tag for r in rows for tag in r['subchunks']}-{'MCVT','MCNR','MCCV','MCSE','MCLQ','MCLV'})
  unknown_objects=sorted(set(objtags)-{'MVER','MMDX','MMID','MWMO','MWID','MDDF','MODF','MCNK'})
  if unusual or unknown_subs or unknown_objects:
   r=tile_rect(*tile['tile']);exclude([[r[0],-100000,r[1]],[r[2],100000,r[3]]],'unsupported-ADT-geometry',tile=tile['tile'],rootChunks=unusual,subchunks=unknown_subs,objectChunks=unknown_objects)
  selected=[r for r in rows if rect_intersects([r['position'][1]-t.CHUNK,r['position'][0]-t.CHUNK,r['position'][1],r['position'][0]],rect)]
  vertices,triangles,holes=t.mesh(selected);add(vertices,triangles);stats['holeTrianglesRemoved']+=holes
  for row in west.liquid_exclusions(raw,rows,tile['tile']):
   if intersect(row['bounds'],rect):excluded.append(dict(row,worldMapID=world))
  for placement in placed:
   key=(placement['kind'],placement['uniqueID'])
   if key in placements:need(placements[key]==placement,'conflicting world placement');stats['duplicatePlacements']+=1
   else:placements[key]=placement
  need(len(placements)<=MAX_PLACEMENTS,'world batch placement bound')
  tile_audit.append(dict(tile=tile['tile'],rootFileDataID=tile['rootADT'],objFileDataID=tile['obj0ADT'],rootChunks=inventory,objectChunks=objtags,selectedChunks=[[r['x'],r['y']] for r in selected]))
 # Carve every absent source-tile intersection. Ocean/gap geometry is never invented.
 a,b,c,d=rect
 for tx in range(max(0,math.floor(32-c/t.TILE)),min(63,math.floor(32-a/t.TILE))+1):
  for ty in range(max(0,math.floor(32-d/t.TILE)),min(63,math.floor(32-b/t.TILE))+1):
   if (world,tx,ty) not in source.tiles:
    r=tile_rect(tx,ty);exclude([[r[0],-100000,r[1]],[r[2],100000,r[3]]],'unsourced-physical-tile',tile=[tx,ty])
 placements={(row['kind'],row['uniqueID']):row for row in placement_index.query(world,rect)}
 need(len(placements)<=MAX_PLACEMENTS,'world indexed placement bound')
 for key,placement in sorted(placements.items()):
  ident=placement['reference'];uid=placement['uniqueID']
  need(0<placement['scale']<=65535,'world placement scale')
  if placement['kind']=='m2':
   # Do not infer a collision footprint from location alone if the format/flags
   # cannot establish it. This fails only the current independently resumable job.
   if placement['flags'] not in (64,576):
    empty.empty_mddf(placement,source.asset(ident,'M2'));stats['pinnedEmptyMDDF']+=1;continue
   m=model(ident);extra=[tag for tag in m['chunks'] if tag in ('PFID','PFDC','PHY2','PCOL')]
   vertices=collision.transformed(m,placement)
   if extra:
    proof=m.get('physicsExtent')
    need(extra==['PCOL'] and proof is not None,'unbounded-model-physics:%d'%ident)
    bounds=collision.bounds(vertices+collision.transformed(proof,placement));exclude(bounds,'extra-model-physics',fileDataID=ident,placementID=uid,chunks=extra)
   if not m['indices']:stats['m2NoStaticCollision']+=1;continue
   if intersect(collision.bounds(vertices),rect):add(vertices,m['indices']);stats['m2Instances']+=1
   continue
  box=wmo.placement_bounds(placement)
  # The full transformed index selected this placement; MODF alone may be smaller.
  reasons=[];all_world=[];local_vertices=[];local_indices=[]
  def wadd(vertices,triangles):
   need(len(local_vertices)+len(vertices)<=MAX_POSITIONS and len(local_indices)+len(triangles)<=MAX_INDICES,'WMO per placement geometry bound')
   base=len(local_vertices)//3;local_vertices.extend(vertices);local_indices.extend(base+i for i in triangles);all_world.extend(vertices)
  if placement['flags']!=12:reasons.append('unsupported-world-MODF-flags:%d'%placement['flags'])
  if ident not in roots:roots[ident]=wmo.root(source.asset(ident,'WMO'))
  root=roots[ident];reasons.extend('root-chunk:'+tag for tag in root['unknownChunks'])
  try:active,selected=wmo.selected_doodads(root,placement['doodadSet'])
  except ValueError as error:reasons.append(str(error));selected=[]
  for gid in root['groups']:
   gkey=(gid,root['flags'])
   if gkey not in groups:groups[gkey]=wmo.group(source.asset(gid,'WMOGroup'),root['flags'])
   group=groups[gkey];need(all(i<len(root['doodads']) for i in group['doodadReferences']),'WMO doodad ref range')
   reasons.extend(group['unsupported']);wadd(collision.transformed(group,placement),group['indices'])
  for index in selected:
   dd=root['doodads'][index]
   if wmo.unsupported_doodad_flags(dd['flags']):reasons.append('unsupported-WMO-doodad-flags');continue
   try:m=model(dd['reference'])
   except ValueError as error:
    if str(error)!='unsupported-M2-version':raise
    reasons.append('unsupported-WMO-doodad-M2-version');continue
   reasons.extend('extra-doodad-physics:'+tag for tag in m['chunks'] if tag in ('PFID','PFDC','PHY2','PCOL'))
   if m['indices']:wadd(collision.transformed(dict(positions=wmo.doodad_positions(m,dd)),placement),m['indices'])
  if all_world:
   actual=collision.bounds(all_world)
   if max(max(box[0][i]-actual[0][i],actual[1][i]-box[1][i]) for i in range(3))>.1:reasons.append('WMO-transform-outside-MODF-bounds')
   box=[[min(box[0][i],actual[0][i]) for i in range(3)],[max(box[1][i],actual[1][i]) for i in range(3)]]
  if reasons:
   reasons=sorted(set(reasons));exclude(box,'unsupported-WMO-footprint',fileDataID=ident,placementID=uid,reasons=reasons)
   gates.append(dict(worldMapID=world,placementID=uid,fileDataID=ident,reasons=reasons,bounds=box));stats['excludedWMOInstances']+=1
  else:add(local_vertices,local_indices);stats['wmoInstances']+=1
 need(positions and indices,'empty world geometry')
 minimum=min(positions[1::3]);maximum=max(positions[1::3]);owned=job['ownedXZ']
 return dict(format='rikui-world-geometry-v1',identity={k:v for k,v in source_identity().items() if k not in ('buildConfig','cdnConfig')},
  worldMapID=world,job=job,coordinateSystem='Y-up; X=game world Y; Z=game world X',
  regionBounds=[[owned[0],minimum,owned[1]],[owned[2],maximum,owned[3]]],positions=positions,indices=indices,exclusions=excluded,
  source=dict(parserSHA256=sha(pathlib.Path(__file__).read_bytes()),jobSHA256=sha(canonical(job)),placementIndexSHA256=placement_index.sha256,assets=[source.used[k] for k in sorted(source.used)],tileAudit=tile_audit),
  coverageGates=gates,statistics=dict(stats,vertices=len(positions)//3,triangles=len(indices)//3,placements=len(placements)),
  status='derived-static-model-with-explicit-exclusions',nativeVerified=False,agentProfileCalibrated=False,
  limitations=['Unknown static features keep explicit exclusions or fail only their batch.','Source completeness does not establish native walkability.','Dynamic state, swimming, transport and phase transitions are not modeled.'])

def source_identity():
 from world_source import IDENTITY
 return IDENTITY
