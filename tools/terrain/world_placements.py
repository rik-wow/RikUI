"""Stream physical-world placements into a hash-bound, read-only bake index.
The index stores full transformed model extents; object origin never selects
collision. Unknown extents remain explicit and block affected world jobs.
"""
import collections, itertools, json, pathlib, sqlite3
import collision_probe as c
import terrain_probe as t
import wmo_probe as w
import world_empty_placements as empty
from world_source import canonical, sha, need

def corners(bounds):return [v for p in itertools.product(*zip(*bounds)) for v in p]
def bounds_of(model):return c.bounds(model['positions']) if model['positions'] else None

def model_extent_positions(model,ident):
 # Unknown physics cannot inherit a static mesh's finite footprint, including
 # when that mesh is empty. A known PCOL proof contributes exclusion bounds.
 extra=[tag for tag in model['chunks'] if tag in ('PFID','PFDC','PCOL','PHY2')]
 if extra:
  need(extra==['PCOL'] and model.get('physicsExtent') is not None,'unbounded-model-physics:'+str(ident))
  return model['positions']+model['physicsExtent']['positions']
 return model['positions']

def doodad_extent_scope(root,selected_set):
 try:
  _,selected=w.selected_doodads(root,selected_set);return selected,None
 except ValueError as error:
  if str(error)!='WMO-selected-set-range':raise
  # This is an extent-only union, not a replacement selected set. Geometry must
  # retain the reason and exclude the whole placement instead of adding it.
  return list(range(len(root['doodads']))),str(error)

def decoder_hashes():
 return {name:sha(pathlib.Path(module.__file__).read_bytes()) for name,module in [('terrain',t),('collision',c),('wmo',w),('emptyPlacements',empty)]}

def build(source,path):
 path=pathlib.Path(path);need(not path.exists(),'placement index must be new')
 db=sqlite3.connect(path);source.used={};models={};root_extents={};roots={};group_bounds={};unknown=collections.Counter();counts=collections.Counter()
 try:
  db.executescript('CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL); CREATE TABLE placements(id INTEGER PRIMARY KEY,world INTEGER NOT NULL,kind TEXT NOT NULL,uid INTEGER NOT NULL,body TEXT NOT NULL,bounds TEXT,reason TEXT,UNIQUE(world,kind,uid)); CREATE VIRTUAL TABLE extents USING rtree(id,minX,maxX,minZ,maxZ); CREATE INDEX world_placements ON placements(world);')
  def model(ident):
   if ident not in models:
    data=source.asset(ident,'M2')
    try: m=c.m2(data)
    except ValueError as error:
     if str(error)!='unsupported-M2-version':raise
     m=w.demonstrated_empty_274(data)
    pts=model_extent_positions(m,ident)
    models[ident]=c.bounds(pts) if pts else None
   return models[ident]
  def wmo_points(ident,selected_set):
   key=(ident,selected_set)
   if key not in root_extents:
    if ident not in roots:roots[ident]=w.root(source.asset(ident,'WMO'))
    root=roots[ident];pts=[]
    for gid in root['groups']:
     if gid not in group_bounds:
      parsed=w.group(source.asset(gid,'WMOGroup'),root['flags']);group_bounds[gid]=bounds_of(parsed)
     if group_bounds[gid]:pts.extend(corners(group_bounds[gid]))
    selected,selection_gap=doodad_extent_scope(root,selected_set)
    if selection_gap:counts['boundedUnknownDoodadScopes']+=1
    for at in selected:
     dd=root['doodads'][at]
     need(not w.unsupported_doodad_flags(dd['flags']),'unbounded-WMO-doodad-flags:'+str(ident))
     box=model(dd['reference'])
     if box:pts.extend(w.doodad_positions(dict(positions=corners(box)),dd))
    root_extents[key]=c.bounds(pts) if pts else None
   return root_extents[key]
  for (world,x,y),tile in sorted(source.tiles.items()):
   placed,_,names=t.objects(source.asset(tile['obj0ADT'],'obj0ADT'));need(not names,'named placements unsupported')
   for row in placed:
    body=canonical(row).decode();previous=db.execute('SELECT body FROM placements WHERE world=? AND kind=? AND uid=?',(world,row['kind'],row['uniqueID'])).fetchone()
    if previous:
     need(previous[0]==body,'conflicting world placement');counts['duplicates']+=1;continue
    box=None;reason=None
    try:
     need(0<row['scale']<=65535,'unsupported placement scale')
     if row['kind']=='m2':
      if row['flags'] not in (64,576):
       empty.empty_mddf(row,source.asset(row['reference'],'M2'));raw=None;counts['pinnedEmptyMDDF']+=1
      else:raw=model(row['reference'])
      if raw:box=c.bounds(c.transformed(dict(positions=corners(raw)),row))
     else:
      raw=wmo_points(row['reference'],row['doodadSet']);box=w.placement_bounds(row)
      if raw:
       actual=c.bounds(c.transformed(dict(positions=corners(raw)),row))
       box=[[min(box[0][a],actual[0][a]) for a in range(3)],[max(box[1][a],actual[1][a]) for a in range(3)]]
    except ValueError as error:
     # Preserve every source placement. An unknown extent cannot safely be
     # localized by source tile or placement origin, so query returns it for
     # every job in its world until a supported extent proof is available.
     reason=str(error);unknown[(world,reason)]+=1
    cursor=db.execute('INSERT INTO placements(world,kind,uid,body,bounds,reason) VALUES(?,?,?,?,?,?)',(world,row['kind'],row['uniqueID'],body,canonical(box).decode() if box else None,reason))
    if box is not None and reason is None:
     db.execute('INSERT INTO extents VALUES(?,?,?,?,?)',(cursor.lastrowid,box[0][0],box[1][0],box[0][2],box[1][2]))
    counts[row['kind']]+=1
   if (x*64+y)%64==0:db.commit()
  meta=dict(format='rikui-world-placement-index-v1',sourceProfileSHA256=source.profile_sha,
   sourceAssets=[source.used[k] for k in sorted(source.used)],counts=dict(counts),
   unknownExtents=[dict(worldMapID=k[0],reason=k[1],placements=n) for k,n in sorted(unknown.items())],
   indexModuleSHA256=sha(pathlib.Path(__file__).read_bytes()),decoderSHA256=decoder_hashes(),nativeVerified=False)
  db.execute('INSERT INTO metadata VALUES(?,?)',('manifest',canonical(meta).decode()));db.commit()
 finally:db.close()
 return meta

class Index:
 def __init__(self,path,expected_sha,source):
  self.path=pathlib.Path(path);need(sha(self.path.read_bytes())==expected_sha,'placement index hash mismatch')
  self.sha256=expected_sha;self.db=sqlite3.connect(self.path.resolve().as_uri()+'?mode=ro',uri=True)
  row=self.db.execute('SELECT value FROM metadata WHERE key=?',('manifest',)).fetchone();need(row is not None,'incomplete placement index')
  self.manifest=json.loads(row[0]);need(self.manifest.get('format')=='rikui-world-placement-index-v1' and self.manifest.get('sourceProfileSHA256')==source.profile_sha,'placement index source identity')
  need(self.manifest.get('indexModuleSHA256')==sha(pathlib.Path(__file__).read_bytes()) and self.manifest.get('decoderSHA256')==decoder_hashes(),'placement index decoder changed')
 def query(self,world,rect):
  gaps=self.db.execute('SELECT uid,reason FROM placements WHERE world=? AND reason IS NOT NULL ORDER BY kind,uid',(world,)).fetchall()
  need(not gaps,'unbounded world placement extents:'+json.dumps(gaps[:8]))
  # SQLite RTree bounds are outward-rounded float32, used only as a conservative
  # candidate query. Exact stored float64 bounds perform the final intersection.
  rows=self.db.execute('SELECT p.body,p.bounds FROM placements p JOIN extents e ON p.id=e.id WHERE p.world=? AND e.maxX>=? AND e.minX<=? AND e.maxZ>=? AND e.minZ<=? ORDER BY p.kind,p.uid',(world,rect[0],rect[2],rect[1],rect[3]))
  result=[]
  for body,encoded in rows:
   b=json.loads(encoded)
   if b[1][0]>=rect[0] and b[0][0]<=rect[2] and b[1][2]>=rect[1] and b[0][2]<=rect[3]:result.append(json.loads(body))
  return result
 def close(self):self.db.close()
