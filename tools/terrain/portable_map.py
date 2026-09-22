"""Reproduce the pinned full-map corpus and compare a second bake, outside Git."""
import argparse,json,os,pathlib,shutil,subprocess,sys
import acquire,map_profile,portable_west
HERE=pathlib.Path(__file__).resolve().parent
FILES=tuple(dict.fromkeys(portable_west.FILES+(
    'compile_terrain_regions.py','terrain_partition.py','test_bounded_tiled.mjs','test_mesh_filter.mjs',
    'licenses/wow-export-MIT.txt','licenses/recast-navigation-js-MIT.txt','licenses/recast-Detour-zlib-notice.txt')))
def run(directory,name,args):
    with (directory/(name+'.log')).open('xb') as log:
        completed=subprocess.run(args,cwd=directory,stdout=log,stderr=subprocess.STDOUT,timeout=600)
    if completed.returncode:raise ValueError('failed:'+name+'; see '+str(directory/(name+'.log')))
    print('Completed '+name,flush=True)
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',required=True);parser.add_argument('--output',required=True)
    args=parser.parse_args();source=acquire.checked_path(args.source);map_profile.validate_sources(source)
    for name in FILES:
        path=acquire.checked_path(HERE/name)
        if not path.is_file() or path.stat().st_size>262144:raise ValueError('tool-bound:'+name)
    target=acquire.empty_output(args.output,(source,HERE))
    for name in FILES:
        dest=target/name;dest.parent.mkdir(parents=True,exist_ok=True)
        with (HERE/name).open('rb') as inp,dest.open('xb') as out:shutil.copyfileobj(inp,out)
    python=sys.executable;node=shutil.which('node');npm=shutil.which('npm.cmd' if os.name=='nt' else 'npm')
    if not node or not npm:raise ValueError('node-npm-required')
    run(target,'dependencies',[npm,'ci','--ignore-scripts','--no-audit','--no-fund'])
    run(target,'height-tests',[node,'test_bounded_tiled.mjs'])
    run(target,'filter-tests',[node,'test_mesh_filter.mjs'])
    run(target,'terrain',[python,'-B','terrain_region.py','--directory',str(source),'--profile','map','--out','geometry-map.json'])
    run(target,'m2',[python,'-B','collision_probe.py','--input','geometry-map.json','--directory',str(source/'collision'),'--output','geometry-map-m2.json','--allow-full-tile'])
    run(target,'wmo',[python,'-B','wmo_probe.py','--input','geometry-map.json','--directory',str(source),'--recursive-receipt',str(source/'recursive-dependencies-manifest.json'),'--output','collision-map-wmo.json'])
    run(target,'merge',[python,'-B','merge_geometry.py','--input','geometry-map-m2.json','--wmo','collision-map-wmo.json','--out','geometry-map-full.json'])
    for name in ('region','replay'):run(target,name,[node,'bake_tile.mjs','geometry-map-full.json',name,'--half-cell','--reference-step'])
    count=portable_west.compare(target/'region',target/'replay')
    digest=acquire.digest((target/'region/manifest.json').read_bytes())
    run(target,'compile',[python,'-B','compile_terrain_regions.py','--manifest','region/manifest.json','--expected-sha256',digest,'--out',str(target/'compiled')])
    receipt=dict(format='rikui-map-reproduction-v1',sourceProfileSHA256=map_profile.PROFILE_CANONICAL_SHA256,
        manifestSHA256=digest,identicalReplayFiles=count,nativeVerified=False,
        tools={name:acquire.digest((target/name).read_bytes()) for name in FILES})
    (target/'verification-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps(receipt))
if __name__=='__main__':main()
