"""Exact-source multi-ADT region geometry; never synthetic ADT relabeling."""
import argparse,collections,copy,json,math,pathlib,struct
import terrain_probe as t
import west_profile as west
TILES=((32,42),(33,42))
REGION_ID='dun-morogh-kharanos-seam-69913'
BUILD_CONFIG='6c0df97e8e481a9a41600e373367c200'
CDN_CONFIG='5525ea1ce6668e895569c89c2d6a154c'
REGION_XZ=((-1066.6673177083333,-5866.667317708333),(-405.333984375,-5333.333984375))

def check_receipt(receipt):
    if (receipt.get('schema'),receipt.get('product'),receipt.get('version'),receipt.get('locale'),receipt.get('buildConfig'),receipt.get('cdnConfig'))!=('rikui-local-terrain-extraction-evidence-v1','wow_classic_beta','1.60.1.69913','enUS',BUILD_CONFIG,CDN_CONFIG):t.fail('region-receipt-identity')

def input_bytes(entry,registered):
    if not isinstance(entry,dict) or set(entry)!={'path','fileDataID','bytes','sha256'}:t.fail('region-input-shape')
    registered_row=registered.get(entry['fileDataID'])
    if not registered_row or any(entry[k]!=registered_row[k] for k in ('bytes','sha256')):t.fail('region-unregistered-input')
    data=t.load(entry['path'])
    if len(data)!=entry['bytes'] or t.digest(data)!=entry['sha256']:t.fail('region-input-hash')
    return data

def source_inputs(inputs,receipt):
    check_receipt(receipt);registered={r['fileDataID']:r for r in receipt['files']}
    if len(registered)!=len(receipt['files']):t.fail('region-duplicate-source-ID')
    if set(inputs)!={'wdt','tiles'} or inputs['wdt'].get('fileDataID')!=775971:t.fail('region-inputs-shape')
    wdt=input_bytes(inputs['wdt'],registered);parts={tag:wdt[a:b] for tag,a,b in t.chunks(wdt)}
    if len(parts.get('MAID',b''))!=4096*32 or len(parts.get('MAIN',b''))!=4096*8 or parts.get('MVER')!=struct.pack('<I',18):t.fail('region-WDT-layout')
    rows=inputs['tiles']
    tiles=[tuple(r.get('tile',[])) for r in rows] if isinstance(rows,list) else []
    if tiles not in (list(TILES),[tuple(v[0]) for v in west.TILES]):t.fail('region-source-tiles')
    if len(tiles)==8:
        for entry in [inputs['wdt']]+[v[k] for v in rows for k in ('root','obj')]:
            if west.FILES.get(entry['fileDataID'])!=(entry['bytes'],entry['sha256']):t.fail('west-source-pin')
    result=[]
    for row in rows:
        if set(row)!={'tile','root','obj'}:t.fail('region-tile-input-shape')
        x,y=row['tile'];idx=y*64+x
        refs=struct.unpack_from('<8I',parts['MAID'],idx*32);flags=struct.unpack_from('<II',parts['MAIN'],idx*8)
        if not flags[0]&1 or row['root'].get('fileDataID')!=refs[0] or row['obj'].get('fileDataID')!=refs[1]:t.fail('region-WDT-source-mapping')
        result.append((row,input_bytes(row['root'],registered),input_bytes(row['obj'],registered)))
    return result

def merge_placements(rows):
    seen={};duplicates=0;names=False
    for _,_,obj in rows:
        records,_,named=t.objects(obj);names|=named
        for record in records:
            key=(record['kind'],record['uniqueID'])
            if key in seen:
                if seen[key]!=record:t.fail('region-conflicting-placement')
                duplicates+=1
            else:seen[key]=record
    if len(seen)>16384:t.fail('region-placement-budget')
    return [seen[k] for k in sorted(seen)],names,duplicates

def validated_placements(geometry,receipt):
    decoded,names,_=merge_placements(source_inputs(geometry['source']['inputs'],receipt))
    return ([p for p in decoded if west.relevant(p)] if geometry.get('regionID')==west.REGION_ID else decoded),names

def create(directory,receipt_path,profile='kharanos'):
    expanded=profile=='west'
    if profile not in ('west','kharanos'):t.fail('region-profile')
    tiles=[tuple(v[0]) for v in west.TILES] if expanded else TILES
    xz=((west.BOUNDS[0],west.BOUNDS[1]),(west.BOUNDS[2],west.BOUNDS[3])) if expanded else REGION_XZ
    directory=pathlib.Path(directory);receipt_bytes=t.load(receipt_path);receipt=json.loads(receipt_bytes);check_receipt(receipt)
    registered={r['fileDataID']:r for r in receipt['files']}
    def entry(ident):
        row=registered.get(ident)
        if row is None:t.fail('region-missing-source')
        path=pathlib.Path(row['file'])
        # Acquisition receipts retain explicit file paths; only exact hash matches are used.
        return dict(path=str(path.resolve()),fileDataID=ident,bytes=row['bytes'],sha256=row['sha256'])
    inputs={'wdt':entry(775971),'tiles':[{'tile':[32,42],'root':entry(777997),'obj':entry(777998)},{'tile':[33,42],'root':entry(778197),'obj':entry(778198)}]}
    if expanded:inputs['tiles']=[dict(tile=v,root=entry(a),obj=entry(b)) for v,a,b in west.TILES]
    rows=source_inputs(inputs,receipt);positions=[];indices=[];tile_audit=[];liquid=[];terrain_exclusions=[]
    for row,raw,_ in rows:
        records,inventory=t.root(raw);selected=west.selected_chunks(records) if expanded else records
        vertices,faces,holes=t.mesh(selected)
        if expanded:terrain_exclusions.extend(west.liquid_exclusions(raw,records,row['tile']))
        expectedX=(32-row['tile'][1])*t.TILE;expectedY=(32-row['tile'][0])*t.TILE
        if abs(max(p['position'][0] for p in records)-expectedX)>.002 or abs(max(p['position'][1] for p in records)-expectedY)>.002:t.fail('region-MCNK-tile-transform')
        if 'MH2O' in inventory or any('MCLQ' in r['subchunks'] for r in records):liquid.append(row['tile'])
        offset=len(positions)//3;positions.extend(vertices);indices.extend(offset+i for i in faces)
        tile_audit.append(dict(tile=row['tile'],rootFileDataID=row['root']['fileDataID'],objFileDataID=row['obj']['fileDataID'],rootChunks=inventory,areaCounts=dict(collections.Counter(r['areaID'] for r in records)),vertices=len(vertices)//3,triangles=len(faces)//3,holesRemoved=holes,bounds=[[min(vertices[a::3]) for a in range(3)],[max(vertices[a::3]) for a in range(3)]]))
    if liquid and not expanded:t.fail('region-encoded-liquid-needs-model-or-exclusion')
    if len(positions)>(750000 if expanded else 250000) or len(indices)>(1600000 if expanded else 800000):t.fail('region-terrain-budget')
    placements,names,duplicates=merge_placements(rows)
    if names:t.fail('region-legacy-name-references')
    if expanded:placements=[p for p in placements if west.relevant(p)]
    minimumY=min(positions[1::3]);maximumY=max(positions[1::3]);region=[[xz[0][0],minimumY,xz[0][1]],[xz[1][0],maximumY,xz[1][1]]]
    return dict(format='rikui-navigation-geometry-probe-v1',identity=dict(product='wow_classic_beta',edition='Forever',build='1.60.1.69913',locale='enUS'),mapID=0,regionID=west.REGION_ID if expanded else REGION_ID,tiles=[list(x) for x in tiles],regionBounds=region,terrainExclusions=terrain_exclusions,
        source=dict(acquisitionReceipt=dict(path=str(pathlib.Path(receipt_path).resolve()),sha256=t.digest(receipt_bytes)),buildConfig=BUILD_CONFIG,cdnConfig=CDN_CONFIG,parser='rikui-terrain-region-v1',parserSHA256=t.digest(pathlib.Path(__file__).read_bytes()),formatReference=dict(repo='Kruithne/wow.export',commit=t.PIN),inputs=inputs,tileAudit=tile_audit,profileModuleSHA256=t.digest(pathlib.Path(west.__file__).read_bytes())),
        status='incomplete-collision',publishable=False,coordinateSystem='Y-up; X=game world Y; Z=game world X',
        coverage=dict(terrain=True,holes=True,staticM2=False,staticWMO=False,liquids=False,dynamicDoors=False,agentProfileCalibrated=False,placementReferencesAreNames=False),
        limitations=['Exact acquired ADTs; output is cropped to the explicit rectangle.','No walkable seam is inferred from sample proximity; links must come from the combined collision bake.','Dynamic state, floors, player physics and actual path following require native validation.'],
        statistics=dict(vertices=len(positions)//3,triangles=len(indices)//3,tileCount=len(tiles),placementCount=len(placements),identicalPlacementDuplicates=duplicates),
        dependencies=[dict(kind=k,reference=i) for k,i in sorted({(p['kind'],p['reference']) for p in placements})],placements=placements,positions=positions,indices=indices)

def main():
    p=argparse.ArgumentParser();p.add_argument('--directory',required=True);p.add_argument('--out',default='geometry-region.json');p.add_argument('--profile',choices=['kharanos','west'],default='kharanos');a=p.parse_args()
    result=create(a.directory,pathlib.Path(a.directory)/'extraction-manifest.json',a.profile);path=pathlib.Path(a.out);path.write_text(json.dumps(result,separators=(',',':'),allow_nan=False));print(json.dumps(dict(output=str(path),sha256=t.digest(path.read_bytes()),statistics=result['statistics'])))
if __name__=='__main__':main()
