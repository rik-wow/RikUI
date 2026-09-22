"""Map-specific conservative collision exclusions, pinned to acquired source cells."""
import hashlib,json
import map_profile as profile
from terrain_contract import need,array,obj,integer,number,exclusion_rect
LIQUID_SHA='295763b1f5d6568e6f5621ea68232f5dab8aafa91def4f74b7a015308520aa3e'
def numeric(value):
    if type(value) is float and value.is_integer():return int(value)
    if isinstance(value,list):return [numeric(v) for v in value]
    if isinstance(value,dict):return {k:numeric(v) for k,v in value.items()}
    return value
def validate(manifest,region_bounds):
    import coverage_contract as common
    cov,config=common.profile(manifest)
    audit=obj(manifest.get('wmoAudit'),'WMO-audit')
    placements={}
    for row in array(audit.get('placements'),profile.MAX_WMO_PLACEMENTS,'WMO-placements'):
        uid=integer(row.get('placementID'),1,2**32-1,'placement-ID')
        need(uid not in placements,'duplicate-WMO-placement');placements[uid]=row
    gates=array(manifest.get('coverageGates'),4096,'coverage-gates')
    unresolved=array(audit.get('unsupported'),4096,'WMO-unsupported')
    exclusions={};rectangles=[]
    for row in array(manifest.get('exclusions'),profile.MAX_WMO_PLACEMENTS,'exclusions'):
        uid=integer(row.get('placementID'),1,2**32-1,'exclusion-ID')
        need(uid not in exclusions and uid in placements,'unknown-excluded-placement')
        wanted=placements[uid].get('MODFworldBounds');decoded=placements[uid].get('decodedGroupWorldBounds')
        if decoded:wanted=[[min(wanted[0][a],decoded[0][a]) for a in range(3)],[max(wanted[1][a],decoded[1][a]) for a in range(3)]]
        need(row.get('bounds')==wanted,'exclusion-footprint-mismatch')
        reasons=array(row.get('reasons'),16,'exclusion-reasons')
        need(reasons and len(reasons)==len(set(reasons)),'duplicate-exclusion-reason')
        exclusions[uid]=row;rectangles.append(exclusion_rect(row))
    checked=[];keys=set();reasons={}
    allowed=set(common.REASONS)|{'unknown-group-chunk:MLIQ','unknown-group-chunk:MDAL',
        'WMO-selected-set-range','WMO-transform-outside-MODF-bounds'}
    for gate in gates:
        uid=integer(gate.get('placementID'),1,2**32-1,'gate-ID');reason=gate.get('reason')
        need(uid in exclusions and reason in allowed and gate.get('modelMitigation')==common.MITIGATION,'unknown-map-coverage-gate')
        placement=placements[uid];fid=gate.get('fileDataID')
        if reason=='WMO-transform-outside-MODF-bounds':
            need(number(gate.get('yards'),'transform-error')>.1 and gate['yards']==placement.get('maxGroupBoundsViolation'),'transform-gate')
        elif reason=='WMO-selected-set-range':
            need(fid==placement.get('fileDataID') and placement.get('unsupportedRootLayout')==reason and placement.get('groupIDs')==[],'selected-set-gate')
        elif reason.startswith('unknown-group-chunk:'):
            need(fid in array(placement.get('groupIDs'),512,'WMO-group-IDs'),'chunk-gate-not-group')
        else:common.validate_gate(gate,placement,exclusions[uid],region_bounds)
        key=(uid,reason,fid);need(key not in keys,'duplicate-gate');keys.add(key)
        reasons.setdefault(uid,set()).add(reason)
        checked.append({k:v for k,v in gate.items() if k!='modelMitigation'})
    need(set(reasons)==set(exclusions),'unmapped-exclusion')
    for uid,values in reasons.items():need(values==set(exclusions[uid]['reasons']),'exclusion-reason-mismatch')
    canonical=lambda rows:sorted(json.dumps(r,sort_keys=True) for r in rows)
    need(canonical(checked)==canonical(unresolved),'unrecorded-map-gate')
    need(cov['staticWMO'] is (not gates) and cov['framedSelectedStaticDecoded'] is (not gates),'inconsistent-map-decoding')
    terrain=array(manifest.get('terrainExclusions'),profile.MAX_EXCLUSIONS,'terrain-exclusions')
    need(len(terrain)==3265,'map-liquid-count')
    try:ordered=sorted(terrain,key=lambda row:tuple(row['tile']+row['chunk']))
    except (TypeError,KeyError):raise ValueError('map-liquid-shape')
    digest=hashlib.sha256(profile.canonical(numeric(ordered))).hexdigest()
    need(digest==LIQUID_SHA,'map-liquid-source-or-footprint-mismatch')
    rectangles.extend(exclusion_rect(row) for row in terrain)
    physics=array(manifest.get('m2Exclusions'),2,'map-physics-exclusions')
    need(hashlib.sha256(profile.canonical(sorted(physics,key=lambda row:row['placementID']))).hexdigest()
        =='4e7ff4578006c4c21a6fbd2f02b555df8e2470943581f80012b5ec541c1aaa3a','map-physics-world-bounds-pin')
    need(hashlib.sha256(profile.canonical(sorted(manifest['exclusions'],key=lambda row:row['placementID']))).hexdigest()
        =='787b427163d6ecc183f03f2eb3572664bd1ab8f3b2e878d52926a356788ceef1','map-WMO-exclusion-pin')
    need(len(physics)==2 and {r.get('placementID') for r in physics}=={340724,396148},'map-physics-placements')
    for row in physics:
        proof=obj(row.get('boundsProof'),'physics-bounds-proof')
        need(row.get('fileDataID')==200767 and row.get('reason')=='extra-physics-chunks' and row.get('chunks')==['PCOL']
            and proof.get('sourceSHA256')=='24c26943fb0a51d68ab3c850870c63a41228d1a2cf9bbd124230f2340cc97ddc'
            and proof.get('payloadSHA256')=='27524174d9d0362f12142b5a628c3f46ae9133e13fc81fd66c784e7158ddcb44'
            and proof.get('method')=='pinned-PCOL-static-union-exclusion-only' and proof.get('nativeVerified') is False,'map-physics-proof')
        rectangles.append(exclusion_rect(row))
    need(cov.get('liquids')=='excluded-unmodeled-terrain-liquids' and manifest.get('coverageScope')=='outside-exclusions','map-liquid-coverage')
    return rectangles,gates,round(config['walkableClimb']*config['ch'],10)
