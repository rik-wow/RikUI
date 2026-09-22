"""Reject Recast span overflow and inconsistent per-tile vertical bounds."""
import math
from terrain_contract import need,number as finite,integer,array,obj,bounds
def number(value,low,high,label):
    value=finite(value,label);need(low<=value<=high,label);return value
def validate(generator):
    config=obj(generator.get('config'),'agent-config')
    if 'bounds' not in config:return
    extent=bounds(config['bounds']);ch=number(config.get('ch'),.01,1,'cell-height')
    if generator.get('heightStrategy')!='per-tile-bounded-v1':
        need((extent[1][1]-extent[0][1])/ch<=8191,'Recast-height-span-overflow');return
    audit=obj(generator.get('heightAudit'),'tile-height-audit')
    need(audit.get('method')=='tile-local-Y-common-ch-lattice','tile-height-method')
    import struct
    ch=struct.unpack('<f',struct.pack('<f',ch))[0] # rcConfig stores float32.
    need(audit.get('ch')==ch and audit.get('globalYOrigin')==extent[0][1],'tile-height-lattice')
    grid=array(audit.get('grid'),2,'tile-grid');need(len(grid)==2,'tile-grid')
    width,height=[integer(n,1,4096,'tile-grid') for n in grid];need(width*height<=4096,'tile-budget')
    cell=number(config.get('cs'),.1,1,'cell-size')*integer(config.get('tileSize'),1,1024,'tile-size')
    # Recast grid rounds voxel dimensions to the nearest cell before tiling.
    expected=[math.ceil(int((extent[1][a]-extent[0][a])/config['cs']+.5)/config['tileSize']) for a in (0,2)]
    need(grid==expected,'tile-grid-bounds')
    rows=array(audit.get('tiles'),4096,'tile-height-rows');need(len(rows)==width*height,'tile-height-missing')
    seen=set();max_span=0;max_geometry=0;max_chunks=0;counts=dict(built=0,emptyGeometry=0,emptyWalkable=0)
    for row in rows:
        row=obj(row,'tile-height-row')
        x=integer(row.get('x'),0,width-1,'tile-x');z=integer(row.get('z'),0,height-1,'tile-z')
        need((x,z) not in seen,'duplicate-height-tile');seen.add((x,z))
        flags=[k for k in counts if row.get(k) is True];need(len(flags)==1,'tile-height-result')
        counts[flags[0]]+=1
        if flags[0]=='emptyGeometry':continue
        lo=number(row.get('geometryMinY'),-100000,100000,'tile-geometry-height')
        hi=number(row.get('geometryMaxY'),lo,100000,'tile-geometry-height')
        mn=number(row.get('minY'),-100000,lo,'tile-min-height')
        mx=number(row.get('maxY'),hi,100000,'tile-max-height')
        span=integer(row.get('spanVoxels'),1,8190,'tile-height-span')
        need(abs((mx-mn)/ch-span)<.00001,'tile-height-span-mismatch')
        need(abs((mn-extent[0][1])/ch-round((mn-extent[0][1])/ch))<.00001,'tile-height-origin')
        need(lo-mn>=ch-.00001 and mx-hi>=ch-.00001,'tile-height-guard')
        chunks=integer(row.get('overlappingChunks'),1,512,'tile-chunk-overflow')
        max_span=max(max_span,span);max_geometry=max(max_geometry,hi-lo);max_chunks=max(max_chunks,chunks)
    need(audit.get('maxSpanVoxels')==max_span and abs(audit.get('maxGeometrySpan',-1)-max_geometry)<.00001
         and audit.get('maxOverlappingChunks')==max_chunks,'tile-height-summary')
    for key,value in counts.items():need(audit.get(key+'Tiles')==value,'tile-result-count')
