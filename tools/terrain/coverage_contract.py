"""Validate admitted collision gaps and their complete footprint exclusions."""
import json
from terrain_contract import need, integer, number, array, obj, exclusion_rect
GATE='MOHD-doodad-count-disagrees-with-framed-MODD'
LIQUID_GATE='WMO-liquid-not-modeled'
FLAG_GATE='WMO-doodad-flags'
MITIGATION='exclude-entire-MODF-horizontal-footprint-with-agent-radius'
REASONS=(GATE,LIQUID_GATE,FLAG_GATE)

def profile(manifest):
    cov=obj(manifest.get('coverage'),'coverage')
    generator=obj(manifest.get('generator'),'generator');config=obj(generator.get('config'),'agent-config')
    expected_profile={'cs':.5,'ch':.1,'walkableRadius':1,'walkableHeight':18,'walkableClimb':3,'walkableSlopeAngle':40,'maxVertsPerPoly':6}
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
        reasons=array(row.get('reasons'),3,'exclusion-reasons')
        need(reasons and all(r in REASONS for r in reasons) and len(set(reasons))==len(reasons),'unknown-exclusion-reason')
        need(uid in placements and row.get('bounds')==placements[uid].get('MODFworldBounds'),'exclusion-does-not-cover-audited-footprint')
        exclusions[uid]=row;rectangles.append(exclusion_rect(row))
    return exclusions,rectangles

def validate_flag_gate(gate,placement,exclusion,region_bounds):
    need(gate['fileDataID']==placement.get('fileDataID'),'flag-gate-not-placement-root')
    flags=array(gate.get('flags'),255,'unsupported-doodad-flags')
    for flag in flags:integer(flag,1,255,'unsupported-doodad-flag')
    need(flags and len(set(flags))==len(flags),'invalid-unsupported-doodad-flags')
    rect=exclusion_rect(exclusion)
    need(rect[2]<region_bounds[0] or rect[0]>region_bounds[2]
         or rect[3]<region_bounds[1] or rect[1]>region_bounds[3],
         'unsupported-doodad-flags-inside-region')

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
    need(cov.get('framedSelectedStaticDecoded') is (not reasons.intersection((LIQUID_GATE,FLAG_GATE))),'inconsistent-static-decoding-coverage')
    liquids='excluded-unmodeled-WMO-liquids' if LIQUID_GATE in reasons else 'no-MH2O-or-MCLQ-in-root-and-no-MLIQ-or-liquid-type-in-selected-WMO-groups'
    need(cov.get('liquids')==liquids,'unsupported-liquid-coverage')
    need(manifest['coverageScope']==('outside-exclusions' if entries else 'whole-source-region'),'inconsistent-coverage-scope')
    return rectangles,gates,round(config['walkableClimb']*config['ch'],10)
