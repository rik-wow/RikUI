"""Reproduce the pinned western Dun Morogh mesh in a new external directory."""
import argparse,json,os,pathlib,shutil,subprocess,sys
import acquire,west_profile
HERE=pathlib.Path(__file__).resolve().parent
FILES=('terrain_probe.py','terrain_region.py','west_profile.py','collision_probe.py','wmo_probe.py',
       'map_profile.py','map_coverage_contract.py','m2_physics_extent.py','height_contract.py',
       'merge_geometry.py','bounded_tiled.mjs','bake_tile.mjs','mesh_filter.mjs','package.json','package-lock.json',
       'm2-274-reference.json','m2-274-collision-profiles.json',
       'compile_quest_terrain.py','terrain_contract.py','region_contract.py','coverage_contract.py')

def verify_source(directory):
    path=acquire.checked_path(directory/'acquisition-profile-west.json')
    if path.stat().st_size>262144:acquire.fail('profile-size')
    profile=json.loads(path.read_text())
    if acquire.digest(acquire.canonical(profile))!=west_profile.PROFILE_SHA256:acquire.fail('west-profile-pin')
    acquire.verify(profile,directory)
    return profile

def run(directory,name,args):
    with (directory/(name+'.log')).open('xb') as log:
        completed=subprocess.run(args,cwd=directory,stdout=log,stderr=subprocess.STDOUT,timeout=240)
    if completed.returncode:acquire.fail('failed:'+name+'; see '+str(directory/(name+'.log')))
    print('Completed '+name,flush=True)

def compare(first,second):
    names={p.name for p in first.iterdir()}
    if names!={p.name for p in second.iterdir()}:acquire.fail('replay-file-inventory')
    for name in sorted(names):
        if (first/name).read_bytes()!=(second/name).read_bytes():acquire.fail('replay-diff:'+name)
    return len(names)

def bake(source,target):
    python=sys.executable;node=shutil.which('node');npm=shutil.which('npm.cmd' if os.name=='nt' else 'npm')
    if not node or not npm:acquire.fail('node-npm-required')
    run(target,'dependencies',[npm,'ci','--ignore-scripts'])
    run(target,'terrain',[python,'-B','terrain_region.py','--directory',str(source),'--profile','west','--out','geometry-west.json'])
    run(target,'m2',[python,'-B','collision_probe.py','--input','geometry-west.json','--directory',str(source/'collision'),'--output','geometry-west-m2.json','--allow-full-tile'])
    run(target,'wmo',[python,'-B','wmo_probe.py','--input','geometry-west.json','--directory',str(source),'--recursive-receipt',str(source/'recursive-dependencies-manifest.json'),'--output','collision-west-wmo.json'])
    run(target,'merge',[python,'-B','merge_geometry.py','--input','geometry-west-m2.json','--wmo','collision-west-wmo.json','--out','geometry-west-full.json'])
    for name in ('region','replay'):
        run(target,name,[node,'bake_tile.mjs','geometry-west-full.json',name,'--half-cell'])
    count=compare(target/'region',target/'replay')
    digest=acquire.digest((target/'region/manifest.json').read_bytes())
    run(target,'compile',[python,'-B','compile_quest_terrain.py','--manifest','region/manifest.json','--expected-sha256',digest,'--out',str(target/'RikUIQuestTerrain')])
    return count,digest

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',required=True);parser.add_argument('--output',required=True)
    args=parser.parse_args();source=acquire.checked_path(args.source);verify_source(source)
    for name in FILES:
        path=acquire.checked_path(HERE/name)
        if not path.is_file() or path.stat().st_size>262144:acquire.fail('tool-bound')
    target=acquire.empty_output(args.output,(source,HERE))
    for name in FILES:
        with (HERE/name).open('rb') as inp,(target/name).open('xb') as out:shutil.copyfileobj(inp,out)
    count,digest=bake(source,target)
    receipt=dict(format='rikui-west-reproduction-v1',sourceProfileSHA256=west_profile.PROFILE_SHA256,
        manifestSHA256=digest,identicalReplayFiles=count,nativeVerified=False,
        tools={name:acquire.digest((target/name).read_bytes()) for name in FILES})
    (target/'verification-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps(receipt))
if __name__=='__main__':main()
