"""Validation primitives shared by the offline terrain compiler contracts."""
import math, re
SHA=re.compile(r'[a-f0-9]{64}\Z')
class CompileError(ValueError):pass
def need(ok,message):
    if not ok:raise CompileError(message)
def integer(v,lo,hi,label):need(type(v) is int and lo<=v<=hi,'invalid-'+label);return v
def number(v,label):need(type(v) in (int,float) and math.isfinite(v) and abs(v)<=100000,'invalid-'+label);return v
def text(v,label,limit=512):need(type(v) is str and 0<len(v)<=limit and '\0' not in v,'invalid-'+label);return v
def hash_string(v,label):need(type(v) is str and SHA.fullmatch(v),'invalid-'+label);return v
def array(v,cap,label):need(type(v) is list and len(v)<=cap,'invalid-'+label);return v
def obj(v,label):need(type(v) is dict,'invalid-'+label);return v
def point(v,label):
    need(type(v) is list and len(v)==3,'invalid-'+label)
    for x in v:number(x,label)
    return list(v)
def bounds(value):
    need(type(value) is list and len(value)==2,'invalid-bounds');lo,hi=point(value[0],'bounds'),point(value[1],'bounds')
    need(all(lo[i]<=hi[i] for i in range(3)),'reversed-bounds');return [lo,hi]
def exclusion_rect(entry):
    box=bounds(entry.get('bounds'));pad=number(entry.get('padding'),'exclusion-padding');need(0.5<=pad<=10,'unsafe-exclusion-padding')
    return [box[0][0]-pad,box[0][2]-pad,box[1][0]+pad,box[1][2]+pad]
# Keep these in sync with quest-navmesh.lua and Schema.CopyLimited. A compiled
# addon must fit the same budgets that its runtime loader will enforce.
RUNTIME_CELL = 64
RUNTIME_MAX_POLYGON_SPAN = 128
RUNTIME_MAX_CELLS = 4096
RUNTIME_MAX_CELL_POLYGONS = 512

def runtime_convex(points):
    # Mirror the Lua turn/area tolerance, including its final half-plane check.
    sign, area = 0, 0
    def cross(a,b,c): return (b[0]-a[0])*(c[2]-a[2])-(b[2]-a[2])*(c[0]-a[0])
    for index, a in enumerate(points):
        b, c = points[(index+1)%len(points)], points[(index+2)%len(points)]
        turn = cross(a,b,c)
        if abs(turn) > .00001:
            if sign and sign*turn < 0: return False
            sign = turn
        area += a[0]*b[2]-b[0]*a[2]
    if not sign or abs(area) <= .00001: return False
    return all(cross(a,points[(index+1)%len(points)],p)*sign >= -.00001
               for index,a in enumerate(points) for p in points)

def runtime_geometry(polygons):
    cells = {}
    for polygon in polygons:
        points = polygon['points']
        need(runtime_convex(points), 'runtime-polygon-convexity-limit')
        lo_x, hi_x = min(p[0] for p in points), max(p[0] for p in points)
        lo_z, hi_z = min(p[2] for p in points), max(p[2] for p in points)
        need(hi_x - lo_x <= RUNTIME_MAX_POLYGON_SPAN
             and hi_z - lo_z <= RUNTIME_MAX_POLYGON_SPAN,
             'runtime-polygon-spatial-limit')
        for x in range(math.floor(lo_x / RUNTIME_CELL), math.floor(hi_x / RUNTIME_CELL) + 1):
            for z in range(math.floor(lo_z / RUNTIME_CELL), math.floor(hi_z / RUNTIME_CELL) + 1):
                key = (x, z)
                count = cells.get(key, 0) + 1
                need(count <= RUNTIME_MAX_CELL_POLYGONS, 'runtime-navigation-cell-limit')
                if key not in cells:
                    need(len(cells) < RUNTIME_MAX_CELLS, 'runtime-navigation-spatial-index-limit')
                cells[key] = count

def runtime_metadata(value):
    # Lua's copy counts each key and value, including numeric array keys.
    stack = [(value, 0)]
    nodes = 0
    text_bytes = 0
    while stack:
        current, depth = stack.pop()
        nodes += 1
        need(nodes <= 2048 and depth <= 12, 'runtime-metadata-node-or-depth-limit')
        if type(current) is str:
            try:
                size = len(current.encode('utf-8'))
            except UnicodeEncodeError as error:
                raise CompileError('invalid-runtime-metadata-UTF8') from error
            text_bytes += size
            need(size <= 2048 and text_bytes <= 16384, 'runtime-metadata-text-limit')
        elif type(current) is dict:
            for key, child in current.items():
                stack.extend(((key, depth + 1), (child, depth + 1)))
        elif type(current) is list:
            for key, child in enumerate(current, 1):
                stack.extend(((key, depth + 1), (child, depth + 1)))
        else:
            need(type(current) is bool or (type(current) in (int, float)
                 and math.isfinite(current) and -2147483647 <= current <= 2147483647),
                 'invalid-runtime-metadata-value')
