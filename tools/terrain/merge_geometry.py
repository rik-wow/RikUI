"""Merge independently decoded exact-build static geometry with explicit exclusions.
Derived navigation models never become verified game traversal through this tool.
"""
import argparse, copy, json, math, pathlib
import terrain_probe as t

def validate_mesh(value):
    p=value['positions'];i=value['indices']
    if len(p)%3 or len(i)%3 or len(p)>1500000 or len(i)>2000000:t.fail('mesh-budget')
    if not all(type(v) in (int,float) and math.isfinite(v) and abs(v)<100000 for v in p):t.fail('mesh-position')
    if not all(type(v) is int and 0<=v<len(p)//3 for v in i):t.fail('mesh-index')

def merge(geometry,wmo):
    g=copy.deepcopy(geometry)
    if g['format']!='rikui-navigation-geometry-probe-v1' or wmo['schema']!='rikui-wmo-collision-proof-v1':t.fail('mesh-format')
    if wmo['product']!=g['identity']['product'] or wmo['build']!=g['identity']['build']:t.fail('identity-mismatch')
    if wmo['source']['acquisitionReceipt']['sha256']!=g['source']['acquisitionReceipt']['sha256']:t.fail('receipt-mismatch')
    if wmo['source']['geometry']['sha256']!=g['source']['geometryBeforeCollisionSha256']:t.fail('terrain-base-mismatch')
    validate_mesh(g);validate_mesh(wmo)
    observed={p['uniqueID']:p['reference'] for p in g['placements'] if p['kind']=='wmo'}
    decoded={p['placementID']:p['fileDataID'] for p in wmo['audit']['placements']}
    if decoded!=observed or len(decoded)!=len(wmo['audit']['placements']):t.fail('WMO-placement-coverage')
    base=len(g['positions'])//3
    g['positions'].extend(wmo['positions']);g['indices'].extend(i+base for i in wmo['indices'])
    validate_mesh(g)
    unresolved=[r for r in g['collisionAudit']['unresolved'] if not(r['reason']=='overlapping-WMO-unprocessed' and decoded.get(r['uniqueID'])==r['fileDataID'])]
    gates=copy.deepcopy(wmo['audit']['unsupported'])
    placements={p['placementID']:p for p in wmo['audit']['placements']}
    excluded={}
    for gate in gates:
        ident=gate.get('placementID')
        if ident not in placements:t.fail('unlocated-coverage-gate')
        bounds=placements[ident]['MODFworldBounds']
        if len(bounds)!=2 or any(len(p)!=3 for p in bounds):t.fail('exclusion-bounds')
        if not all(math.isfinite(v) for row in bounds for v in row):t.fail('exclusion-finite')
        if any(bounds[0][a]>bounds[1][a] for a in range(3)):t.fail('exclusion-order')
        reasons=excluded.setdefault(ident,dict(placementID=ident,bounds=bounds,padding=0.5,reasons=[]))['reasons']
        if gate['reason'] not in reasons:reasons.append(gate['reason'])
        gate['modelMitigation']='exclude-entire-MODF-horizontal-footprint-with-agent-radius'
    if unresolved:t.fail('unlocated-M2-coverage-gate')
    g['collisionAudit']['unresolved']=unresolved
    g['wmoAudit']=wmo['audit'];g['exclusions']=[excluded[k] for k in sorted(excluded)]
    g['coverageGates']=gates
    g['coverage'].update(staticWMO=wmo['coverage']['staticWMO'],
        framedSelectedStaticDecoded=wmo['coverage']['framedSelectedStaticDecoded'],
        modelExcludesUnresolvedStaticFootprints=True,
        liquids=('excluded-unmodeled-terrain-liquids' if g.get('terrainExclusions') else 'excluded-unmodeled-WMO-liquids' if any(v['reason']=='WMO-liquid-not-modeled' for v in gates) else 'no-MH2O-or-MCLQ-in-root-and-no-MLIQ-or-liquid-type-in-selected-WMO-groups'),
        nativeTraversalVerified=False)
    g['status']='derived-static-model-with-excluded-uncertain-footprints'
    g['publishable']=False
    g['statistics']['vertices']=len(g['positions'])//3;g['statistics']['triangles']=len(g['indices'])//3
    g['statistics']['WMO']=wmo['audit']['counts']
    g['source']['WMO']=wmo['source']
    g['source']['mergeParserSHA256']=t.digest(pathlib.Path(__file__).read_bytes())
    g['limitations']=[
        'Exact local source bytes; independently decoded and generated static model, never verified native walkability.',
        'MOHD count differences remain audit notes. Unsupported liquid/group features remove entire affected MODF footprints plus agent radius.',
        'Player collision dimensions, movement physics, transforms and path following need native validation.',
        'Dynamic doors, gameobjects, phasing, enemies and temporary obstacles are not established by static geometry.',
        'Encoded WMO liquids, where present, remain unmodeled and their footprints are excluded; no swim capability is inferred.',
        'No outgoing links beyond the explicit sourced region; no transport or flight connections inferred.',
        'Coarse convex polygon heights approximate Detour detail mesh; center/portal route distances are model estimates.',
        'Raw Detour binary retains excluded diagnostic geometry; only filtered exported shards are candidate runtime data.'
    ]
    return g

def main():
    p=argparse.ArgumentParser();p.add_argument('--input',default='geometry-full-m2.json');p.add_argument('--wmo',default='collision-wmo.json');p.add_argument('--out',default='geometry-full-collision.json');a=p.parse_args()
    first=t.load(a.input);second=t.load(a.wmo)
    result=merge(json.loads(first),json.loads(second))
    result['source']['mergeInputs']=[dict(path=str(pathlib.Path(path).resolve()),sha256=t.digest(data)) for path,data in ((a.input,first),(a.wmo,second))]
    target=pathlib.Path(a.out);target.write_text(json.dumps(result,separators=(',',':'),allow_nan=False))
    print(json.dumps(dict(output=str(target),sha256=t.digest(target.read_bytes()),vertices=len(result['positions'])//3,triangles=len(result['indices'])//3,excludedPlacements=len(result['exclusions']),preservedGates=len(result['coverageGates']))))
if __name__=='__main__':main()
