"""Strict, bounded ADT terrain/placement proof. Not a collision-complete navigator.
Format reference: wow.export c2fd7bde36a712be78a5da896c995b84fbfa2545 (MIT).
This wrapper is independently authored; geometry remains local extracted game data.
"""
import argparse, collections, hashlib, json, math, pathlib, struct
TILE = 1600.0 / 3.0
CHUNK = TILE / 16
UNIT = CHUNK / 8
PIN = 'c2fd7bde36a712be78a5da896c995b84fbfa2545'

def fail(message):
    raise ValueError(message)

def digest(data):
    return hashlib.sha256(data).hexdigest()

def load(path):
    p = pathlib.Path(path)
    if not 0 < p.stat().st_size <= 64 * 1024 * 1024:
        fail('input-size')
    return p.read_bytes()

def chunks(data, start=0, end=None):
    end = len(data) if end is None else end
    at = start
    while at < end:
        if end - at < 8: fail('truncated-chunk-header')
        tag = data[at:at+4][::-1].decode('ascii')
        size, = struct.unpack_from('<I', data, at+4)
        stop = at + 8 + size
        if stop > end: fail('chunk-overrun:' + tag)
        yield tag, at+8, stop
        at = stop
    if at != end: fail('chunk-framing')

def root(data):
    output, seen, counts = [], set(), collections.Counter()
    version = None
    for tag, start, end in chunks(data):
        counts[tag] += 1
        if tag == 'MVER':
            if version is not None or end-start != 4: fail('MVER-size-or-duplicate')
            version, = struct.unpack_from('<I', data, start)
        if tag != 'MCNK': continue
        if end-start < 128 or len(output) >= 256: fail('MCNK-size-count')
        flags, x, y = struct.unpack_from('<III', data, start)
        if not (x < 16 and y < 16) or (x,y) in seen: fail('MCNK-index')
        seen.add((x,y))
        area, = struct.unpack_from('<I', data, start+52)
        low, = struct.unpack_from('<H', data, start+60)
        high = list(data[start+20:start+28])
        position = struct.unpack_from('<fff', data, start+104)
        heights = None
        subs = []
        for sub, a, b in chunks(data, start+128, end):
            subs.append(sub)
            if sub == 'MCVT':
                if heights is not None or b-a != 145*4: fail('MCVT-size-or-duplicate')
                heights = struct.unpack_from('<145f', data, a)
        if heights is None: fail('missing-MCVT')
        if not all(math.isfinite(v) for v in (*position, *heights)): fail('nonfinite-height')
        if any(abs(v) > 100000 for v in (*position, *heights)): fail('coordinate-bound')
        output.append(dict(x=x,y=y,flags=flags,areaID=area,holesLow=low,
            holesHigh=high,position=position,heights=heights,subchunks=subs))
    if version != 18 or len(output) != 256: fail('unsupported-ADT-or-incomplete-tile')
    return output, dict(counts)

def mesh(records):
    vertices, indices = [], []
    removed = 0
    for record in records:
        base = len(vertices)//3
        x,y,z = record['position']
        index = 0
        for row in range(17):
            for col in range(8 if row % 2 else 9):
                # Right-handed Y-up; X=game world Y, Z=game world X.
                vertices.extend((y-(col+0.5*(row%2))*UNIT,
                    z+record['heights'][index],x-row*UNIT/2))
                index += 1
        for row in range(8):
            for col in range(8):
                hole = ((record['holesHigh'][row] >> col) & 1) if record['flags'] & 0x10000 else ((record['holesLow'] >> ((row//2)*4+col//2)) & 1)
                if hole:
                    removed += 4
                    continue
                center = base + row*17 + 9 + col
                for a,b,c in ((center,center-9,center+8),(center,center-8,center-9),
                              (center,center+9,center-8),(center,center+8,center+9)):
                    indices.extend((a,b,c))
    if len(vertices)//3 > 40000 or len(indices)//3 > 140000: fail('geometry-cap')
    return vertices, indices, removed

def objects(data):
    rows, counts = [], collections.Counter()
    version = None
    names = False
    for tag,start,end in chunks(data):
        counts[tag] += 1
        if tag == 'MVER':
            if version is not None or end-start != 4: fail('object-version')
            version, = struct.unpack_from('<I', data, start)
        if tag in ('MMDX','MMID','MWMO','MWID') and end>start: names=True
        if tag not in ('MDDF','MODF'): continue
        stride = 36 if tag=='MDDF' else 64
        if (end-start)%stride: fail('placement-stride')
        if (end-start)//stride>100000: fail('placement-cap')
        for at in range(start,end,stride):
            ident,uid = struct.unpack_from('<II',data,at)
            pos = struct.unpack_from('<fff',data,at+8)
            rot = struct.unpack_from('<fff',data,at+20)
            if not all(math.isfinite(v) for v in (*pos,*rot)): fail('placement-nonfinite')
            if tag=='MDDF':
                scale,flags = struct.unpack_from('<HH',data,at+32)
                extra = {}
            else:
                bounds = struct.unpack_from('<6f',data,at+32)
                flags,doodadSet,nameSet,scale = struct.unpack_from('<HHHH',data,at+56)
                extra = dict(bounds=list(bounds),doodadSet=doodadSet,nameSet=nameSet)
            rows.append(dict(kind='m2' if tag=='MDDF' else 'wmo',reference=ident,
                uniqueID=uid,position=list(pos),rotation=list(rot),scale=scale,
                flags=flags,**extra))
    if version != 18: fail('object-version')
    return rows, dict(counts), names

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--root',required=True);p.add_argument('--obj',required=True)
    p.add_argument('--wdt',required=True);p.add_argument('--out',required=True);p.add_argument('--receipt',required=True)
    p.add_argument('--chunk-x',type=int,default=7);p.add_argument('--chunk-y',type=int,default=7)
    p.add_argument('--span',type=int,default=2);p.add_argument('--allow-full-tile',action='store_true')
    a=p.parse_args()
    if not ((1<=a.span<=4 or (a.allow_full_tile and 1<=a.span<=16)) and 0<=a.chunk_x<=16-a.span and 0<=a.chunk_y<=16-a.span): fail('region-bounds')
    inputs={k:load(getattr(a,k)) for k in ('root','obj','wdt')}
    receiptBytes=load(a.receipt);receipt=json.loads(receiptBytes)
    if receipt.get('schema')!='rikui-local-terrain-extraction-evidence-v1' or receipt.get('product')!='wow_classic_beta' or receipt.get('version')!='1.60.1.69913' or receipt.get('locale')!='enUS':fail('extraction-receipt-identity')
    registered={f.get('fileDataID'):f for f in receipt.get('files',[])}
    for role,ident in dict(wdt=775971,root=778197,obj=778198).items():
        entry=registered.get(ident,{})
        if entry.get('sha256')!=digest(inputs[role]) or entry.get('bytes')!=len(inputs[role]):fail('extraction-receipt-hash:'+role)
    if receipt.get('buildConfig')!='6c0df97e8e481a9a41600e373367c200' or receipt.get('cdnConfig')!='5525ea1ce6668e895569c89c2d6a154c':fail('extraction-build-keys')
    records,inventory=root(inputs['root'])
    placements,objInventory,hasNames=objects(inputs['obj'])
    selected=[r for r in records if a.chunk_x<=r['x']<a.chunk_x+a.span and a.chunk_y<=r['y']<a.chunk_y+a.span]
    if len(selected)!=a.span*a.span: fail('region-count')
    vertices,indices,holes=mesh(selected)
    stats=dict(vertices=len(vertices)//3,triangles=len(indices)//3,holeTrianglesRemoved=holes,
        selectedChunks=[dict(x=r['x'],y=r['y'],areaID=r['areaID']) for r in selected],
        allAreaIDs=dict(collections.Counter(r['areaID'] for r in records)),rootChunks=inventory,
        objectChunks=objInventory,placementCount=len(placements))
    dependencies=[dict(kind=k,reference=i) for k,i in sorted({(r['kind'],r['reference']) for r in placements})]
    result=dict(format='rikui-navigation-geometry-probe-v1',identity=dict(product='wow_classic_beta',
        edition='Forever',build='1.60.1.69913',locale='enUS'),mapID=0,tile=[33,42],
        source=dict(acquisitionReceipt=dict(path=str(pathlib.Path(a.receipt).resolve()),sha256=digest(receiptBytes)),buildConfig=receipt['buildConfig'],cdnConfig=receipt['cdnConfig'],parser='rikui-terrain-probe-v1',parserSHA256=digest(pathlib.Path(__file__).read_bytes()),formatReference=dict(repo='Kruithne/wow.export',commit=PIN),
            inputs={k:dict(path=str(pathlib.Path(getattr(a,k)).resolve()),bytes=len(v),sha256=digest(v)) for k,v in inputs.items()}),
        status='incomplete-collision',publishable=False,coordinateSystem='Y-up; X=game world Y; Z=game world X',
        coverage=dict(terrain=True,holes=True,staticM2=False,staticWMO=False,liquids=False,
            dynamicDoors=False,agentProfileCalibrated=False,placementReferencesAreNames=hasNames),
        limitations=['Terrain-only research bake; NOT a validated traversability graph.',
            'All placed model collisions and liquids still require inclusion or explicit exclusion.',
            'Agent radius, height, climb and slope are engineering parameters, not verified Forever player physics.',
            'A single region does not establish connections outside its bounds.'],
        statistics=stats,dependencies=dependencies,placements=placements,positions=vertices,indices=indices)
    out=pathlib.Path(a.out);out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,separators=(',',':'),allow_nan=False),encoding='utf8')
    print(json.dumps(dict(output=str(out),sha256=digest(out.read_bytes()),vertices=stats['vertices'],triangles=stats['triangles'],selectedChunks=len(selected),holeTrianglesRemoved=holes,placementCount=len(placements))))

if __name__=='__main__':main()
