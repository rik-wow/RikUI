"""Resumable bounded world bake entry point. Does not install or publish data.
Examples: --build-index new.sqlite; or --placement-index index.sqlite
--index-sha256 SHA --world 30 --batch -1 0 --output new-output.
All jobs continue independently after a recorded failure. Final failures are
reported without upgrading missing bakes or pending seams to navigable coverage.
"""
import argparse,json,os,pathlib,shutil,subprocess,sys,time
from world_source import Source,canonical,sha,need
import world_placements
from world_geometry import geometry
HERE=pathlib.Path(__file__).resolve().parent
TOOLS=('client_build.py','world_empty_placements.py','world_source.py','world_placements.py','world_geometry.py','world_liquid.py','liquid-kinds-69913.json','world_bake.py','world_stitch.py','world_tiled.mjs','bake_world_batch.mjs','terrain_probe.py','world_projection.py','collision_probe.py','wmo_probe.py','west_profile.py','m2_physics_extent.py','m2-274-world-profiles.json','mesh_filter.mjs')

def atomic(path,value):
 temp=path.with_name(path.name+'.next')
 with temp.open('wb') as f:f.write(canonical(value))
 temp.replace(path)
def hashes():return {name:sha((HERE/name).read_bytes()) for name in TOOLS}
def checked_receipt(directory,expected):
 receipt=json.loads((directory/'receipt.json').read_bytes());need(receipt['input']==expected,'resume input changed')
 for row in receipt.get('files',[]):
  path=directory/row['filename'];need(path.resolve().is_relative_to(directory.resolve()),'resume path escape')
  need(path.is_file() and path.stat().st_size==row['bytes'] and sha(path.read_bytes())==row['sha256'],'resume artifact changed')
 return receipt

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--profile',required=True);p.add_argument('--expected-sha256',required=True);p.add_argument('--source-directory',required=True)
 p.add_argument('--tile-csv',required=True);p.add_argument('--topology-inventory',required=True)
 p.add_argument('--build-index');p.add_argument('--placement-index');p.add_argument('--index-sha256')
 p.add_argument('--world',type=int);p.add_argument('--batch',type=int,nargs=2);p.add_argument('--max-jobs',type=int,default=2290)
 p.add_argument('--output');p.add_argument('--resume',action='store_true');a=p.parse_args()
 source=Source(a.profile,a.expected_sha256,a.source_directory,a.tile_csv,a.topology_inventory)
 if a.build_index:
  need(not a.output and not a.placement_index,'index build has separate output')
  meta=world_placements.build(source,a.build_index);path=pathlib.Path(a.build_index)
  receipt=dict(index=str(path.resolve()),sha256=sha(path.read_bytes()),bytes=path.stat().st_size,manifest=meta)
  with path.with_suffix(path.suffix+'.receipt.json').open('xb') as f:f.write(canonical(receipt))
  print(json.dumps(dict(index=receipt['index'],sha256=receipt['sha256'],counts=meta['counts'],unknownExtentGroups=len(meta['unknownExtents']))));return
 need(a.output and a.placement_index and a.index_sha256,'bake needs output and pinned placement index')
 need(1<=a.max_jobs<=2290,'job batch count bound')
 if a.batch:need(a.world is not None,'batch needs world');jobs=[source.job(a.world,*a.batch)]
 else:jobs=source.jobs(a.world)[:a.max_jobs]
 out=pathlib.Path(a.output).resolve();need(not out.is_symlink(),'output symlink')
 if out.exists():need(a.resume and out.is_dir(),'output must be new or explicit resume')
 else:out.mkdir(parents=True)
 tool_hashes=hashes();node=shutil.which('node');need(node is not None,'node required')
 index=world_placements.Index(a.placement_index,a.index_sha256,source)
 plan=dict(format='rikui-world-bake-run-v1',sourceProfileSHA256=source.profile_sha,indexSHA256=a.index_sha256,tools=tool_hashes,jobs=[j['id'] for j in jobs])
 if (out/'plan.json').exists():need(json.loads((out/'plan.json').read_bytes())==plan,'resume plan changed')
 else:
  with (out/'plan.json').open('xb') as f:f.write(canonical(plan))
 results=[];start=time.monotonic()
 try:
  for number,job in enumerate(jobs,1):
   directory=out/job['id'];expected=dict(jobSHA256=sha(canonical(job)),sourceProfileSHA256=source.profile_sha,indexSHA256=a.index_sha256,tools=tool_hashes)
   if directory.exists():
    need(a.resume and (directory/'receipt.json').is_file(),'unfinished job needs inspection/new output')
    receipt=checked_receipt(directory,expected)
   else:
    directory.mkdir();receipt=dict(input=expected,jobID=job['id'],worldMapID=job['worldMapID'],status='failed',files=[],nativeVerified=False)
    try:
     g=geometry(source,job,index);target=directory/'geometry.json'
     with target.open('xb') as f:f.write(canonical(g))
     with (directory/'bake.log').open('xb') as log:
      run=subprocess.run([node,'--preserve-symlinks','--preserve-symlinks-main',str(HERE/'bake_world_batch.mjs'),str(target),str(directory/'bake')],cwd=HERE,stdout=log,stderr=subprocess.STDOUT,timeout=600,
       creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
     need(run.returncode==0,'world bake process failed; see bake.log')
     manifest=json.loads((directory/'bake/manifest.json').read_bytes())
     receipt.update(status='derived-pending-seam-validation',statistics=manifest['statistics'])
    except (ValueError,OSError,subprocess.TimeoutExpired) as error:receipt['error']=str(error)
    for path in sorted(directory.rglob('*')):
     if path.is_file() and path.name!='receipt.json':receipt['files'].append(dict(filename=path.relative_to(directory).as_posix(),bytes=path.stat().st_size,sha256=sha(path.read_bytes())))
    atomic(directory/'receipt.json',receipt)
   results.append(dict(jobID=job['id'],status=receipt['status'],error=receipt.get('error'),receiptSHA256=sha((directory/'receipt.json').read_bytes())))
   atomic(out/'progress.json',dict(format='rikui-world-bake-progress-v1',planSHA256=sha(canonical(plan)),completed=len(results),total=len(jobs),results=results,nativeVerified=False))
   print(json.dumps(dict(job=job['id'],number=number,total=len(jobs),status=receipt['status'],error=receipt.get('error'))),flush=True)
 finally:index.close()
 failed=sum(r['status']=='failed' for r in results)
 print(json.dumps(dict(completed=len(results),failed=failed,seconds=time.monotonic()-start,output=str(out),nativeVerified=False)))
 if failed:raise SystemExit(1)
if __name__=='__main__':main()
