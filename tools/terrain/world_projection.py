"""Exact-build map projection inventory; no bake or reachability claims.

Navigation coordinates: Y-up; X=game world Y; Z=game world X.
UiMapAssignment Region[0,3] is game X (north/south), [1,4] game Y
(west/east), [2,5] vertical. UI coordinates increase east/south.
Every transform is keyed by assignment, preserving partial rectangles and
alternative/overlapping UI views instead of conflating them with world maps.
"""
from __future__ import annotations
import argparse, csv, hashlib, json, math
from dataclasses import dataclass
from pathlib import Path

from client_build import BUILD, SOURCE_HASHES
PRODUCT = 'wow_classic_beta'
COORDINATES = 'Y-up; X=game world Y; Z=game world X'
TILE_SIZE = 1600.0 / 3.0
TILE_WORKLIST_SHA256 = '944a435972c6108c4e7f068cfa792823f82f8f4a4491e1630524dac1e78533f9'



def finite(value):
 value = float(value)
 if not math.isfinite(value): raise ValueError('nonfinite coordinate')
 return value


def within(value, lower, upper):
 # Eight float64 ULPs cover affine roundtrip cancellation at exact corners;
 # this is numerical tolerance, not expanded source or navigable coverage.
 tolerance = 8 * math.ulp(max(1.0, abs(value), abs(lower), abs(upper)))
 return lower - tolerance <= value <= upper + tolerance


def integer(value, low=0, high=2**31-1):
 number = finite(value)
 if number != int(number) or not low <= number <= high:
  raise ValueError('integer outside range')
 return int(number)


def read_source(directory, name):
 path = Path(directory) / (name + '-' + BUILD + '.csv')
 raw = path.read_bytes()
 actual = hashlib.sha256(raw).hexdigest()
 if actual != SOURCE_HASHES[name]: raise ValueError(name + ' source hash mismatch')
 return list(csv.DictReader(raw.decode('utf-8-sig').splitlines()))


@dataclass(frozen=True)
class Assignment:
 id: int
 ui_map_id: int
 world_map_id: int
 area_id: int
 order: int
 u_min: float
 v_min: float
 u_max: float
 v_max: float
 game_x_min: float
 game_y_min: float
 height_min: float
 game_x_max: float
 game_y_max: float
 height_max: float
 wmo_placement_id: int = 0
 wmo_group_id: int = 0

 @classmethod
 def from_row(cls, row):
  a = cls(integer(row['ID']), integer(row['UiMapID']), integer(row['MapID']),
   integer(row['AreaID']), integer(row['OrderIndex']),
   *(finite(row[k]) for k in ['UiMin_0','UiMin_1','UiMax_0','UiMax_1']),
   *(finite(row['Region_' + str(i)]) for i in range(6)),
   integer(row['WMODoodadPlacementID']), integer(row['WMOGroupID']))
  if not (0 <= a.u_min < a.u_max <= 1 and 0 <= a.v_min < a.v_max <= 1):
   raise ValueError('invalid UI rectangle')
  if not (a.game_x_min < a.game_x_max and a.game_y_min < a.game_y_max
          and a.height_min <= a.height_max): raise ValueError('invalid world rectangle')
  return a

 @property
 def supported(self):
  return self.wmo_placement_id == 0 and self.wmo_group_id == 0

 def projection(self):
  # Extrapolated affine coefficients for the WHOLE UI rectangle. The valid
  # assignment rectangle is retained separately and must gate navigation.
  width = (self.game_y_max - self.game_y_min) / (self.u_max - self.u_min)
  height = (self.game_x_max - self.game_x_min) / (self.v_max - self.v_min)
  return {'originX': self.game_x_max + self.v_min * height,
          'originY': self.game_y_max + self.u_min * width,
          'width': width, 'height': height}

 def contains_ui(self, u, v):
  u, v = finite(u), finite(v)
  return within(u,self.u_min,self.u_max) and within(v,self.v_min,self.v_max)

 def contains_world(self, x, z, elevation=None):
  x, z = finite(x), finite(z)
  return (within(x,self.game_y_min,self.game_y_max) and
          within(z,self.game_x_min,self.game_x_max) and
          (elevation is None or self.height_min <= finite(elevation) <= self.height_max))

 def to_world(self, u, v, *, allow_extrapolation=False):
  if not self.supported: raise ValueError('WMO-selected projection requires explicit support')
  u, v = finite(u), finite(v)
  if not allow_extrapolation and not self.contains_ui(u, v):
   raise ValueError('point outside assignment UI rectangle')
  p = self.projection()
  return {'x': p['originY'] - u * p['width'],
          'z': p['originX'] - v * p['height'],
          'worldMapID': self.world_map_id, 'assignmentID': self.id}

 def to_ui(self, x, z, *, allow_extrapolation=False):
  if not self.supported: raise ValueError('WMO-selected projection requires explicit support')
  x, z = finite(x), finite(z)
  if not allow_extrapolation and not self.contains_world(x, z):
   raise ValueError('point outside assignment world rectangle')
  p = self.projection()
  return {'x': (p['originY'] - x) / p['width'],
          'y': (p['originX'] - z) / p['height'],
          'uiMapID': self.ui_map_id, 'assignmentID': self.id}

 def intersects_tile(self, tile_x, tile_y):
  b = tile_bounds(tile_x, tile_y)
  # Positive area, not boundary-touch, determines required source tiles.
  return (b['minX'] < self.game_y_max and b['maxX'] > self.game_y_min and
          b['minZ'] < self.game_x_max and b['maxZ'] > self.game_x_min)

 def record(self):
  return {'assignmentID': self.id, 'uiMapID': self.ui_map_id,
   'worldMapID': self.world_map_id, 'areaID': self.area_id, 'orderIndex': self.order,
   'coordinateSystem': COORDINATES, 'projection': self.projection(),
   'validUIRectangle': {'minX': self.u_min, 'minY': self.v_min,
                        'maxX': self.u_max, 'maxY': self.v_max},
   'validWorldRectangle': {'minX': self.game_y_min, 'maxX': self.game_y_max,
                          'minZ': self.game_x_min, 'maxZ': self.game_x_max,
                          'minY': self.height_min, 'maxY': self.height_max},
   'wmoPlacementID': self.wmo_placement_id, 'wmoGroupID': self.wmo_group_id,
   'supportedAffineProjection': self.supported,
   'boundaryTolerance': 'eight float64 ULPs; no coverage or navigation claim'}


class Catalog:
 def __init__(self, directory):
  self.map_rows = read_source(directory, 'Map')
  self.ui_rows = read_source(directory, 'UiMap')
  self.assignments = tuple(sorted((Assignment.from_row(r) for r in
   read_source(directory, 'UiMapAssignment')), key=lambda a:(a.ui_map_id,a.order,a.id)))
  self.by_id = {a.id:a for a in self.assignments}
  if len(self.by_id) != len(self.assignments): raise ValueError('duplicate assignment identity')
  maps = {integer(r['ID']) for r in self.map_rows}
  uis = {integer(r['ID']) for r in self.ui_rows}
  if any(a.world_map_id not in maps or a.ui_map_id not in uis for a in self.assignments):
   raise ValueError('unknown assignment map')

 def candidates_ui(self, ui_map_id, u, v, world_map_id=None):
  # Return every candidate; orderIndex is preserved, not interpreted as a
  # license to guess server area/WMO/phase selection.
  return tuple(a for a in self.assignments if a.ui_map_id == ui_map_id and
   (world_map_id is None or a.world_map_id == world_map_id) and a.contains_ui(u,v))

 def views_world(self, world_map_id, x, z, elevation=None):
  return tuple(a for a in self.assignments if a.world_map_id == world_map_id
               and a.contains_world(x,z,elevation))


def tile_bounds(x, y):
 x,y = integer(x,0,63),integer(y,0,63)
 return {'minX':(31-x)*TILE_SIZE,'maxX':(32-x)*TILE_SIZE,
         'minZ':(31-y)*TILE_SIZE,'maxZ':(32-y)*TILE_SIZE}


def tile_key(world_map_id, x, y):
 return (PRODUCT,BUILD,integer(world_map_id),integer(x,0,63),integer(y,0,63))


def seam_key(world_map_id, a, b):
 # Grid adjacency identity only; does NOT assert a traversable connection.
 a=(integer(a[0],0,63),integer(a[1],0,63))
 b=(integer(b[0],0,63),integer(b[1],0,63))
 if abs(a[0]-b[0])+abs(a[1]-b[1]) != 1: raise ValueError('tiles do not share an edge')
 a,b=sorted((a,b))
 return (PRODUCT,BUILD,integer(world_map_id),a,b)


def inventory(directory, tile_csv):
 cat=Catalog(directory)
 tile_raw=Path(tile_csv).read_bytes()
 if hashlib.sha256(tile_raw).hexdigest()!=TILE_WORKLIST_SHA256:raise ValueError('tile worklist source hash mismatch')
 tiles=list(csv.DictReader(tile_raw.decode('utf-8-sig').splitlines()))
 unique={};fdids={}
 for r in tiles:
  key=tile_key(r['worldMapID'],r['x'],r['y']);value=(integer(r['rootADT'],1),integer(r['obj0ADT'],1))
  if key in unique and unique[key] != value:raise ValueError('conflicting tile source identity')
  if value[0] in fdids and fdids[value[0]] != key:raise ValueError('root FDID aliases different world tiles')
  unique[key]=value;fdids[value[0]]=key
 assignment_tiles={a.id:[] for a in cat.assignments}
 annotated=[];seams=set()
 for key,fdids in sorted(unique.items()):
  _,_,world,x,y=key
  views=[a for a in cat.assignments if a.world_map_id==world and a.intersects_tile(x,y)]
  for a in views:assignment_tiles[a.id].append([x,y])
  annotated.append({'worldMapID':world,'x':x,'y':y,'rootADT':fdids[0],'obj0ADT':fdids[1],
   'assignmentIDs':[a.id for a in views],'uiMapIDs':sorted({a.ui_map_id for a in views})})
  for target in [(x+1,y),(x,y+1)]:
   if target[0]<64 and target[1]<64 and tile_key(world,*target) in unique:
    seams.add(seam_key(world,(x,y),target))
 maps=[]
 for r in cat.map_rows:
  world=integer(r['ID']);assignments=[a.id for a in cat.assignments if a.world_map_id==world]
  maps.append({'worldMapID':world,'name':r['MapName_lang'],'directory':r['Directory'],
   'instanceType':integer(r['InstanceType']),'wdtFileDataID':integer(r['WdtFileDataID']),
   'assignmentIDs':assignments,'sourceTileCount':sum(1 for k in unique if k[2]==world),
   'projectionStatus':'source-affine-assignments' if assignments else 'no-UiMapAssignment-source',
   'topologyStatus':'inspected' if any(k[2]==world for k in unique) else 'not-inspected',
   'globalWMOStatus':'not-determined-by-projection'})
 return {'format':'rikui-world-projection-inventory-v1','identity':{'product':PRODUCT,'build':BUILD},
  'coordinateSystem':COORDINATES,'sourceHashes':dict(SOURCE_HASHES,tileWorklist=TILE_WORKLIST_SHA256),
  'assignments':[dict(a.record(),sourceTiles=assignment_tiles[a.id]) for a in cat.assignments],
  'maps':maps,'tiles':annotated,'gridSeams':[list(s) for s in sorted(seams)],
  'counts':{'maps':len(maps),'uiMaps':len(cat.ui_rows),'assignments':len(cat.assignments),
   'zoneViews':sum(integer(r['Type'])==3 for r in cat.ui_rows),
   'worldsWithAssignments':len({a.world_map_id for a in cat.assignments}),
   'worldTiles':len(unique),'gridSeams':len(seams)},
  'limitations':['Affine projection is not navigation or native-client verification.',
   'Assignment rectangles and area/WMO/phase selection remain explicit.',
   'Overlapping UI views share source tiles; no geometry is duplicated by UI identity.',
   'Grid seam identity does not assert mesh connectivity.',
   'Map rows without assignments still require topology/projection/global-WMO investigation.']}


def main():
 parser=argparse.ArgumentParser();parser.add_argument('--source-directory',required=True)
 parser.add_argument('--tile-csv',required=True);parser.add_argument('--output',required=True)
 parser.add_argument('--verify-output',action='store_true')
 args=parser.parse_args();output=Path(args.output)
 result=inventory(args.source_directory,args.tile_csv)
 raw=(json.dumps(result,sort_keys=True,indent=2,allow_nan=False)+'\n').encode('utf8')
 if args.verify_output:
  if output.read_bytes()!=raw:raise ValueError('projection output bytes differ')
 else:
  with output.open('xb') as stream:stream.write(raw)
 print(json.dumps(result['counts'],sort_keys=True))
if __name__=='__main__': main()
