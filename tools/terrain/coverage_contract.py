"""Validate admitted collision gaps and their complete footprint exclusions."""
import json
import west_profile as west
from terrain_contract import need, integer, number, array, obj, exclusion_rect
GATE='MOHD-doodad-count-disagrees-with-framed-MODD'
LIQUID_GATE='WMO-liquid-not-modeled'
FLAG_GATE='WMO-doodad-flags'
ROOT_GATE='WMO-unsupported-root-layout'
MITIGATION='exclude-entire-MODF-horizontal-footprint-with-agent-radius'
REASONS=(GATE,LIQUID_GATE,FLAG_GATE,ROOT_GATE)

def profile(manifest):
    cov=obj(manifest.get('coverage'),'coverage')
    generator=obj(manifest.get('generator'),'generator');config=obj(generator.get('config'),'agent-config')
    expected_profile={'cs':.5,'ch':.1,'walkableRadius':1,'walkableHeight':18,'walkableClimb':3,'walkableSlopeAngle':40,'maxVertsPerPoly':6}
    if config.get('cs')==.25:expected_profile.update(cs=.25,walkableRadius=2)
    reference=generator.get('agentProfile')
    need(reference in (None,'classic-reference-step-v1'),'unsupported-agent-profile')
    if reference:
        need(config.get('cs')==.25,'unsupported-agent-profile')
        expected_profile['walkableClimb']=10
    need(generator.get('agentProfileNativeVerified') is False and all(type(config.get(k)) in (int,float) and config[k]==v for k,v in expected_profile.items()),'unsupported-agent-profile')
    expected={'terrain':True,'holes':True,'staticM2':True,'dynamicDoors':False,'agentProfileCalibrated':False,'placementReferencesAreNames':False,'modelExcludesUnresolvedStaticFootprints':True,'nativeTraversalVerified':False}
    need(all(cov.get(k) is v for k,v in expected.items()),'unsupported-coverage-state')
    need(set(cov)==set(expected)|{'staticWMO','liquids','framedSelectedStaticDecoded'},'unknown-coverage-field')
    need(type(cov.get('staticWMO')) is bool,'invalid-static-WMO-coverage')
    need(manifest.get('coverageScope') in ('outside-exclusions','whole-source-region'),'unsupported-coverage-scope')
    need(obj(manifest.get('collisionAudit'),'collision-audit').get('unresolved')==[],'unmitigated-M2-collision')
    return cov,config

def placements_by_id(audit):
    placements={}
    for row in array(audit.get('placements'),64,'WMO-placements'):
        row=obj(row,'WMO-placement');uid=integer(row.get('placementID'),1,2**32-1,'placement-ID')
        need(uid not in placements,'duplicate-WMO-placement');placements[uid]=row
    return placements

def exclusions_by_id(entries,placements):
    exclusions={};rectangles=[]
    for row in entries:
        row=obj(row,'exclusion');uid=integer(row.get('placementID'),1,2**32-1,'exclusion-ID')
        need(uid not in exclusions,'duplicate-exclusion')
        reasons=array(row.get('reasons'),4,'exclusion-reasons')
        need(reasons and all(r in REASONS for r in reasons) and len(set(reasons))==len(reasons),'unknown-exclusion-reason')
        need(uid in placements and row.get('bounds')==placements[uid].get('MODFworldBounds'),'exclusion-does-not-cover-audited-footprint')
        exclusions[uid]=row;rectangles.append(exclusion_rect(row))
    return exclusions,rectangles

def validate_flag_gate(gate,placement,exclusion,region_bounds):
    need(gate['fileDataID']==placement.get('fileDataID'),'flag-gate-not-placement-root')
    flags=array(gate.get('flags'),255,'unsupported-doodad-flags')
    for flag in flags:integer(flag,1,255,'unsupported-doodad-flag')
    need(flags and len(set(flags))==len(flags),'invalid-unsupported-doodad-flags')
    exclusion_rect(exclusion) # Entire audited footprint is removed, including inside the region.

def validate_gate(gate,placement,exclusion,region_bounds):
    reason=gate['reason'];fid=gate['fileDataID']
    if reason==GATE:
        need(fid==placement.get('fileDataID'),'gate-missing-exclusion')
        a=integer(gate.get('advertised'),0,2**32-1,'advertised-count')
        f=integer(gate.get('framed'),0,20000,'framed-count');need(a!=f,'invalid-count-mismatch-gate')
    elif reason==LIQUID_GATE:
        group_ids=array(placement.get('groupIDs'),512,'WMO-group-IDs')
        for ident in group_ids:integer(ident,1,2**32-1,'WMO-group-ID')
        need(len(set(group_ids))==len(group_ids) and fid in group_ids,'liquid-gate-not-a-placement-group')
    elif reason==ROOT_GATE:
        need(fid==placement.get('fileDataID') and gate.get('layout')=='WMO-LOD-or-group-count'
             and placement.get('unsupportedRootLayout')==gate['layout']
             and placement.get('groupIDs')==[],'unsupported-root-layout-gate')
    else:
        validate_flag_gate(gate,placement,exclusion,region_bounds)

def checked_gates(gates,placements,exclusions,region_bounds):
    checked=[];keys=set();reasons_by_id={}
    for gate in gates:
        gate=obj(gate,'gate');uid=integer(gate.get('placementID'),1,2**32-1,'gate-ID')
        fid=integer(gate.get('fileDataID'),1,2**32-1,'gate-file-ID');reason=gate.get('reason')
        need(reason in REASONS and gate.get('modelMitigation')==MITIGATION,'unknown-or-unmitigated-gate')
        key=(uid,reason,fid);need(key not in keys,'duplicate-coverage-gate');keys.add(key)
        need(uid in exclusions,'gate-missing-exclusion')
        validate_gate(gate,placements[uid],exclusions[uid],region_bounds)
        reasons_by_id.setdefault(uid,set()).add(reason)
        checked.append({k:v for k,v in gate.items() if k!='modelMitigation'})
    need(set(reasons_by_id)==set(exclusions),'unmapped-exclusion')
    for uid,reasons in reasons_by_id.items():need(reasons==set(exclusions[uid]['reasons']),'exclusion-reason-mismatch')
    return checked,{g['reason'] for g in gates}

def terrain_rectangles(manifest):
    entries=array(manifest.get('terrainExclusions',[]),64,'terrain-exclusions')
    expanded=manifest.get('regionID')==west.REGION_ID
    expected={(x,y) for x in (14,15) for y in (11,12,13)} if expanded else set()
    seen=set();rectangles=[]
    for row in entries:
        row=obj(row,'terrain-exclusion');chunk=row.get('chunk')
        need(type(chunk) is list and len(chunk)==2 and all(type(x) is int for x in chunk),'liquid-cell')
        cell=tuple(chunk)
        need(row.get('tile')==[31,41] and cell in expected and cell not in seen
             and row.get('reason')=='unmodeled-MH2O-cell','unrecognized-liquid-cell')
        seen.add(cell);rect=exclusion_rect(row)
        x,y=cell;right=(32-31)*west.t.TILE-x*west.t.CHUNK;top=(32-41)*west.t.TILE-y*west.t.CHUNK
        wanted=[right-west.t.CHUNK-.5,top-west.t.CHUNK-.5,right+.5,top+.5]
        need(all(abs(a-b)<.002 for a,b in zip(rect,wanted)),'liquid-cell-footprint')
        rectangles.append(rect)
    need(seen==expected,'missing-liquid-cell-exclusion')
    return rectangles

def validate(manifest,region_bounds):
    cov,config=profile(manifest)
    audit=obj(manifest.get('wmoAudit'),'WMO-audit');gates=array(manifest.get('coverageGates'),64,'coverage-gates')
    unresolved=array(audit.get('unsupported'),64,'WMO-unsupported')
    entries=array(manifest.get('exclusions'),64,'exclusions')
    placements=placements_by_id(audit)
    exclusions,rectangles=exclusions_by_id(entries,placements)
    checked,reasons=checked_gates(gates,placements,exclusions,region_bounds)
    canonical=lambda items:sorted(json.dumps(x,sort_keys=True) for x in items)
    need(canonical(checked)==canonical(unresolved),'unrecorded-WMO-coverage-gate')
    need(cov['staticWMO'] is (not gates),'inconsistent-WMO-coverage')
    need(cov.get('framedSelectedStaticDecoded') is (not reasons.intersection((LIQUID_GATE,FLAG_GATE,ROOT_GATE))),'inconsistent-static-decoding-coverage')
    terrain=terrain_rectangles(manifest)
    liquids='excluded-unmodeled-terrain-liquids' if terrain else 'excluded-unmodeled-WMO-liquids' if LIQUID_GATE in reasons else 'no-MH2O-or-MCLQ-in-root-and-no-MLIQ-or-liquid-type-in-selected-WMO-groups'
    need(cov.get('liquids')==liquids,'unsupported-liquid-coverage')
    need(manifest['coverageScope']==('outside-exclusions' if entries or terrain else 'whole-source-region'),'inconsistent-coverage-scope')
    return rectangles+terrain,gates,round(config['walkableClimb']*config['ch'],10)
