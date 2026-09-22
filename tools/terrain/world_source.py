"""Hash-bound physical world source and bounded Recast job planning.
No assignment rectangle, grid adjacency or acquired file is navigation evidence.
"""
from __future__ import annotations
import argparse, csv, hashlib, json, math, pathlib, struct
import terrain_probe as terrain
import world_projection as projection

IDENTITY = dict(product='wow_classic_beta', edition='Forever', build='1.60.1.69913', locale='enUS',
 buildConfig='6c0df97e8e481a9a41600e373367c200', cdnConfig='5525ea1ce6668e895569c89c2d6a154c')
WDT_PINS = {
 0:(775971,'160452dec4c2b0ae4cbe7468ce52fee91ac7ec521d2cb0f28e955def0d087137'),
 1:(782779,'1120509b2ac42a94310bf05f915b5e67ed233be854089a3545829e064b614b44'),
 30:(790112,'e4ee7f629954da6ea89d2b78e2d2f28fb973991570b1935c6122f8d0b492985a'),
 489:(790291,'2f3c9ca85d43a7149016d15dd3d34e1d454b65a287125ba35bdb3a764b20fb29'),
 529:(790377,'21543ccd8fb674d8f7cd791a41cc59d618e662321503bbc81c300c76de526b28'),
 2991:(7198644,'f3710569f77e4d9bc96667e8acf2602321f1633d03d8febf62db5e56ab4aa29c'),
 2997:(7251908,'e495780b448bf98f3fd1cf7aee16c24c990d2760d0e4e65f8c310bf4bde005a0')}
CELL=.25
HEIGHT_CELL=.1
RECAST_TILE=64
BATCH_TILES=8
BATCH_SIZE=RECAST_TILE*BATCH_TILES
BORDER=(2+3)*CELL  # radius cells + Recast border cells, tied to the profile.
MAX_ASSET_BYTES=64*1024*1024

def sha(data): return hashlib.sha256(data).hexdigest()
def canonical(value): return json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
def need(test,reason):
 if not test: raise ValueError(reason)
def integer(value,lower=0,upper=2**31-1):
 need(type(value) is int and lower<=value<=upper,'invalid integer'); return value

def regular(path):
 path=pathlib.Path(path)
 need(path.is_file() and not path.is_symlink(),'source must be regular file')
 return path

def pinned(path, expected, cap=MAX_ASSET_BYTES):
 path=regular(path); need(0<path.stat().st_size<=cap,'source byte bound')
 raw=path.read_bytes();need(sha(raw)==expected,'source hash mismatch:'+str(path));return raw

def rect_intersects(a,b):return a[0]<b[2] and a[2]>b[0] and a[1]<b[3] and a[3]>b[1]
def tile_rect(x,y):
 integer(x,0,63);integer(y,0,63);s=terrain.TILE
 return [(31-x)*s,(31-y)*s,(32-x)*s,(32-y)*s]
def batch_rect(x,z):return [x*BATCH_SIZE,z*BATCH_SIZE,(x+1)*BATCH_SIZE,(z+1)*BATCH_SIZE]
def expand(rect,amount):return [rect[0]-amount,rect[1]-amount,rect[2]+amount,rect[3]+amount]
def world_key(world,x,z):return 'w%d-b%d-%d'%(world,x,z)
def polygon_key(world,grid_x,grid_z,layer,polygon):
 return 'w%d:r%d:%d:%d:p%d'%(integer(world),integer(grid_x,-512,511),integer(grid_z,-512,511),integer(layer,0,255),integer(polygon,0,1023))

class Source:
 def __init__(self,profile,expected_sha,source_directory,tile_csv,topology_inventory):
  self.profile_path=pathlib.Path(profile).resolve();self.profile_sha=expected_sha
  doc=json.loads(pinned(self.profile_path,expected_sha,32*1024*1024))
  need(doc.get('format')=='rikui-forever-world-acquisition-profile-v1' and doc.get('identity')==IDENTITY,'profile identity')
  rows=doc.get('files');need(type(rows) is list and 0<len(rows)<=32768,'profile file count')
  self.files={};self.used={}
  for row in rows:
   ident=integer(row.get('fileDataID'),1);need(ident not in self.files,'duplicate source FDID')
   need(row.get('kind') in ('rootADT','obj0ADT','M2','WMO','WMOGroup'),'unknown source kind')
   integer(row.get('bytes'),1,MAX_ASSET_BYTES)
   need(type(row.get('sha256')) is str and len(row['sha256'])==64,'asset hash shape')
   need(pathlib.Path(row.get('path','')).is_absolute(),'asset path must be absolute')
   self.files[ident]=dict(row)
  raw=pinned(tile_csv,projection.TILE_WORKLIST_SHA256,2*1024*1024)
  self.tiles={}
  for row in csv.DictReader(raw.decode('utf-8-sig').splitlines()):
   world,x,y=map(int,(row['worldMapID'],row['x'],row['y']));key=(world,x,y)
   need(key not in self.tiles and world in WDT_PINS,'duplicate or unsupported tile')
   tile_rect(x,y)
   entry=dict(worldMapID=world,tile=[x,y],rootADT=int(row['rootADT']),obj0ADT=int(row['obj0ADT']))
   for kind in ('rootADT','obj0ADT'):
    asset=self.files.get(entry[kind]);need(asset is not None and asset['kind']==kind,'tile asset missing/wrong kind')
    need(asset.get('tile')==[x,y] and world in asset.get('worldMapIDs',[]),'tile asset namespace mismatch')
   self.tiles[key]=entry
  need(len(self.tiles)==1888,'tile worklist count')
  self.catalog=projection.Catalog(source_directory)
  topo=json.loads(regular(topology_inventory).read_bytes()).get('topologyEvidence',[])
  self.wdts={}
  for world,(ident,digest) in WDT_PINS.items():
   matches=[r for r in topo if r.get('worldMapID')==world]
   need(len(matches)==1 and matches[0].get('fileDataID')==ident,'WDT reference identity')
   row=matches[0];data=pinned(row['path'],digest,1024*1024);parts={}
   for tag,a,b in terrain.chunks(data):
    need(tag not in parts,'duplicate WDT chunk');parts[tag]=data[a:b]
   need(parts.get('MVER')==struct.pack('<I',18) and len(parts.get('MAIN',b''))==32768 and len(parts.get('MAID',b''))==131072,'WDT topology framing')
   need(len(parts.get('MPHD',b''))==32 and not struct.unpack_from('<I',parts['MPHD'])[0]&1 and not parts.get('MODF') and not parts.get('MWMO'),'global WMO topology unsupported')
   count=0
   for at in range(4096):
    flags=struct.unpack_from('<I',parts['MAIN'],at*8)[0];refs=struct.unpack_from('<8I',parts['MAID'],at*32)
    need(bool(flags&1)==bool(refs[0]),'MAIN/MAID disagreement')
    key=(world,at%64,at//64)
    if refs[0]:
     need(key in self.tiles and (self.tiles[key]['rootADT'],self.tiles[key]['obj0ADT'])==refs[:2],'WDT/tile mapping mismatch');count+=1
    else:need(key not in self.tiles,'tile absent in WDT')
   self.wdts[world]=dict(path=str(pathlib.Path(row['path']).resolve()),fileDataID=ident,sha256=digest,bytes=len(data),tiles=count,
    unmodeledMetadata=[tag for tag in parts if tag not in ('MVER','MAIN','MAID','MPHD')])

 def asset(self,ident,kind=None):
  row=self.files.get(ident);need(row is not None,'unregistered asset:'+str(ident))
  if kind is not None:need(row['kind']==kind,'wrong asset kind')
  raw=pinned(row['path'],row['sha256']);need(len(raw)==row['bytes'],'asset size mismatch')
  self.used[ident]={k:row[k] for k in ('fileDataID','path','kind','bytes','sha256')};return raw

 def jobs(self,world=None):
  selected=set()
  for (map_id,x,y) in self.tiles:
   if world is not None and world!=map_id:continue
   a,b,c,d=tile_rect(x,y)
   for bx in range(math.floor(a/BATCH_SIZE),math.ceil(c/BATCH_SIZE)):
    for bz in range(math.floor(b/BATCH_SIZE),math.ceil(d/BATCH_SIZE)):selected.add((map_id,bx,bz))
  return [self.job(*key) for key in sorted(selected)]

 def job(self,world,bx,bz):
  integer(world);integer(bx,-64,63);integer(bz,-64,63)
  need(world in self.wdts,'unsupported world')
  owned=batch_rect(bx,bz);bake=expand(owned,RECAST_TILE);halo=expand(bake,BORDER)
  tiles=[dict(row) for key,row in sorted(self.tiles.items()) if key[0]==world and rect_intersects(tile_rect(*key[1:]),halo)]
  need(0<len(tiles)<=9,'source tile batch bound')
  assignments=[a.record() for a in self.catalog.assignments if a.world_map_id==world and a.supported and rect_intersects([a.game_y_min,a.game_x_min,a.game_y_max,a.game_x_max],owned)]
  return dict(format='rikui-world-bake-job-v1',id=world_key(world,bx,bz),worldMapID=world,batchGrid=[bx,bz],
   ownedXZ=owned,bakeXZ=bake,inputXZ=halo,tiles=tiles,projectionAssignments=assignments,
   lattice=dict(origin=[0,0,0],cell=CELL,heightCell=HEIGHT_CELL,recastTileSize=RECAST_TILE,batchTiles=BATCH_TILES,border=BORDER),
   source=dict(profilePath=str(self.profile_path),profileSHA256=self.profile_sha,tileWorklistSHA256=projection.TILE_WORKLIST_SHA256,wdt=self.wdts[world],projectionSources=projection.SOURCE_HASHES),
   nativeVerified=False)

def main():
 p=argparse.ArgumentParser();p.add_argument('--profile',required=True);p.add_argument('--expected-sha256',required=True)
 p.add_argument('--source-directory',required=True);p.add_argument('--tile-csv',required=True);p.add_argument('--topology-inventory',required=True)
 p.add_argument('--world',type=int);p.add_argument('--output',required=True);a=p.parse_args()
 src=Source(a.profile,a.expected_sha256,a.source_directory,a.tile_csv,a.topology_inventory)
 result=dict(format='rikui-world-bake-plan-v1',identity=IDENTITY,jobs=src.jobs(a.world),nativeVerified=False)
 with pathlib.Path(a.output).open('xb') as f:f.write(canonical(result))
 print(json.dumps(dict(jobs=len(result['jobs']),tiles=len(src.tiles),output=a.output,sha256=sha(canonical(result)))))
if __name__=='__main__':main()
