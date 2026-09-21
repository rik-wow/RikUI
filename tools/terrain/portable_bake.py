"""Copy only authored tools/metadata into a new external directory and bake there."""
import argparse, json, os, pathlib, shutil, subprocess
import acquire

HERE=pathlib.Path(__file__).resolve().parent
FILES=('acquire.py','acquisition-profile.json','portable_bake.py','reproduce.ps1',
    'terrain_probe.py','collision_probe.py','wmo_probe.py','merge_geometry.py','bake.mjs','bake_tile.mjs',
    'test_probe.py','test_wmo_probe.py','test_nav_artifact.py','test_acquire.py','verify_reproduction.py',
    'plot_proof.py','package.json','package-lock.json','README.md','m2-274-reference.json','wmo-transform-validation.json',
    'licenses/wow-export-MIT.txt','licenses/recast-navigation-js-MIT.txt','licenses/recast-Detour-zlib-notice.txt')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--acquisition-directory',required=True);parser.add_argument('--output-directory',required=True)
    args=parser.parse_args();acquisition=acquire.checked_path(args.acquisition_directory)
    acquire.verify(acquire.load_profile(),acquisition)
    if not (acquisition/'extraction-manifest.json').is_file() or not (acquisition/'recursive-dependencies-manifest.json').is_file():acquire.fail('acquisition-receipts-required')
    # Validate all copied inputs before creating output, including lockfile/proofs.
    for name in FILES:
        source=acquire.checked_path(HERE/name)
        if not source.is_file() or source.stat().st_size>262144:acquire.fail('missing-or-oversize-tool-file:'+name)
    target=acquire.empty_output(args.output_directory,(HERE,acquisition))
    for name in FILES:
        dest=target/name;dest.parent.mkdir(exist_ok=True)
        with (HERE/name).open('rb') as inp,dest.open('xb') as out:shutil.copyfileobj(inp,out)
    env=dict(os.environ);env['RIKUI_TERRAIN_ACQUISITION']=str(acquisition)
    npm=shutil.which('npm.cmd' if os.name=='nt' else 'npm')
    node=shutil.which('node')
    if not npm or not node:acquire.fail('node-and-npm-required')
    import sys
    def run(name,arguments):
        with (target/(name+'.log')).open('xb') as log:
            done=subprocess.run(arguments,cwd=target,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=180,check=False)
        if done.returncode:acquire.fail('command-failed:'+name+'; see '+str(target/(name+'.log')))
        print('Completed '+name,flush=True)
    run('npm-ci',[npm,'ci','--ignore-scripts','--no-audit','--no-fund'])
    root=[sys.executable,'terrain_probe.py','--root',str(acquisition/'Azeroth_33_42.69913.adt'),
        '--obj',str(acquisition/'Azeroth_33_42_obj0.69913.adt'),'--wdt',str(acquisition/'Azeroth.69913.wdt'),
        '--receipt',str(acquisition/'extraction-manifest.json')]
    run('terrain-small',root+['--out','geometry.json'])
    run('terrain-full',root+['--out','geometry-full.json','--chunk-x','0','--chunk-y','0','--span','16','--allow-full-tile'])
    collision=[sys.executable,'collision_probe.py','--directory',str(acquisition/'collision')]
    run('collision-small',collision)
    run('collision-full',collision+['--input','geometry-full.json','--output','geometry-full-m2.json','--allow-full-tile'])
    run('collision-wmo',[sys.executable,'wmo_probe.py','--input','geometry-full.json','--directory',str(acquisition),'--recursive-receipt',str(acquisition/'recursive-dependencies-manifest.json'),'--output','collision-wmo.json'])
    run('merge',[sys.executable,'merge_geometry.py'])
    run('bake-small',[node,'bake.mjs','geometry-collision.json','nav-region-collision.json'])
    run('bake-full',[node,'bake_tile.mjs','geometry-full-collision.json','full-tile'])
    run('bake-replay',[node,'bake_tile.mjs','geometry-full-collision.json','full-tile-replay'])
    run('verification',[sys.executable,'verify_reproduction.py'])
    report=json.loads((target/'verification-receipt.json').read_text())
    print(json.dumps(dict(output=str(target),validation=report['validation'],manifestSHA256=acquire.digest((target/'full-tile/manifest.json').read_bytes()))))
if __name__=='__main__':main()
