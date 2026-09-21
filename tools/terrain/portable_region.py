"""Reproduce the bounded two-source Kharanos region entirely outside the repository."""
import argparse,json,os,pathlib,shutil,subprocess,sys
import acquire,portable_bake
HERE=pathlib.Path(__file__).resolve().parent
FILES=tuple(dict.fromkeys(portable_bake.FILES+('terrain_region.py','west_profile.py','portable_region.py','verify_region.py','test_region.py','reproduce-region.ps1','REGION.md','m2-274-collision-profiles.json')))

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--acquisition-directory',required=True);p.add_argument('--output-directory',required=True);a=p.parse_args()
    acquisition=acquire.checked_path(a.acquisition_directory);acquire.verify(acquire.load_profile(),acquisition)
    for name in FILES:
        source=acquire.checked_path(HERE/name)
        if not source.is_file() or source.stat().st_size>262144:acquire.fail('missing-or-large-source:'+name)
    target=acquire.empty_output(a.output_directory,(HERE,acquisition))
    for name in FILES:
        dest=target/name;dest.parent.mkdir(exist_ok=True)
        with (HERE/name).open('rb') as inp,dest.open('xb') as out:shutil.copyfileobj(inp,out)
    env=dict(os.environ);env['RIKUI_TERRAIN_ACQUISITION']=str(acquisition)
    npm=shutil.which('npm.cmd' if os.name=='nt' else 'npm');node=shutil.which('node')
    if not npm or not node:acquire.fail('node-npm-required')
    def run(name,args):
        with (target/(name+'.log')).open('xb') as log:r=subprocess.run(args,cwd=target,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=180)
        if r.returncode:acquire.fail('command-failed:'+name+'; '+str(target/(name+'.log')))
        print('Completed '+name,flush=True)
    run('npm-ci',[npm,'ci','--ignore-scripts','--no-audit','--no-fund'])
    baseline=[sys.executable,'terrain_probe.py','--root',str(acquisition/'Azeroth_33_42.69913.adt'),'--obj',str(acquisition/'Azeroth_33_42_obj0.69913.adt'),'--wdt',str(acquisition/'Azeroth.69913.wdt'),'--receipt',str(acquisition/'extraction-manifest.json')]
    run('baseline-small',baseline+['--out','geometry.json'])
    run('baseline-full',baseline+['--out','geometry-full.json','--chunk-x','0','--chunk-y','0','--span','16','--allow-full-tile'])
    run('baseline-collision',[sys.executable,'collision_probe.py','--directory',str(acquisition/'collision')])
    run('baseline-bake',[node,'bake.mjs','geometry-collision.json','nav-region-collision.json'])
    run('region-source',[sys.executable,'terrain_region.py','--directory',str(acquisition),'--out','geometry-region.json'])
    run('region-M2',[sys.executable,'collision_probe.py','--directory',str(acquisition/'collision'),'--input','geometry-region.json','--output','geometry-region-m2.json','--allow-full-tile'])
    run('region-WMO',[sys.executable,'wmo_probe.py','--input','geometry-region.json','--directory',str(acquisition),'--recursive-receipt',str(acquisition/'recursive-dependencies-manifest.json'),'--output','collision-region-wmo.json'])
    run('region-merge',[sys.executable,'merge_geometry.py','--input','geometry-region-m2.json','--wmo','collision-region-wmo.json','--out','geometry-region-full.json'])
    run('region-bake',[node,'bake_tile.mjs','geometry-region-full.json','region'])
    run('region-replay',[node,'bake_tile.mjs','geometry-region-full.json','region-replay'])
    run('verification',[sys.executable,'verify_region.py'])
    report=json.loads((target/'region-verification-receipt.json').read_text());print(json.dumps({'output':str(target),'manifestSHA256':report['manifestSHA256'],'validation':report['validation']}))
if __name__=='__main__':main()
