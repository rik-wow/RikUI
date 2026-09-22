"""Record exact offline artifacts, parser revisions and byte-for-byte replay."""
import hashlib,json,pathlib,platform,re,subprocess,sys
root=pathlib.Path(__file__).resolve().parent
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
first=root/'full-tile';second=root/'full-tile-replay'
files=sorted(p.name for p in first.iterdir() if p.is_file())
if files!=sorted(p.name for p in second.iterdir() if p.is_file()):raise ValueError('replay-file-list')
for name in files:
    if (first/name).read_bytes()!=(second/name).read_bytes():raise ValueError('replay-byte-difference:'+name)
scripts=['acquire.py','acquisition-profile.json','portable_bake.py','terrain_probe.py','collision_probe.py','wmo_probe.py','merge_geometry.py','bake.mjs','bake_tile.mjs','test_probe.py','test_wmo_probe.py','test_nav_artifact.py','test_acquire.py','reproduce.ps1','verify_reproduction.py','package.json','package-lock.json','m2-274-reference.json','m2-274-world-profiles.json','m2_physics_extent.py','wmo-transform-validation.json']
artifacts=['geometry-full-collision.json','collision-wmo.json','nav-region-collision.json','full-tile/manifest.json','full-tile/navmesh.bin']
manifest=json.loads((first/'manifest.json').read_text())
tests=subprocess.run([sys.executable,'-m','unittest','-v','test_probe','test_wmo_probe','test_nav_artifact','test_acquire'],cwd=root,capture_output=True,text=True)
report=tests.stdout+tests.stderr
(root/'verification-tests.log').write_text(report)
match=re.search(r'Ran (\d+) tests?',report)
if tests.returncode or not match:raise ValueError('verification-tests-failed:'+report)
result=dict(schema='rikui-offline-navigation-verification-v1',identity=manifest['identity'],
    nativeVerified=False,publishable=False,coverageScope=manifest['coverageScope'],
    pythonVersion=platform.python_version(),nodeVersion=subprocess.check_output(['node','--version'],text=True).strip(),
    validation=dict(unitTests=int(match.group(1)),testReportSha256=sha(root/'verification-tests.log'),replayIdenticalFiles=len(files),parsedPolygons=manifest['statistics']['polygons'],
        directedPortals=manifest['statistics']['directedEdges'],excludedPolygons=manifest['statistics']['excludedPolygons'],
        actualModelPathProbes=len(manifest['probes']),allModelPathsReachTarget=all(p['success'] and p['endpointError']==0 for p in manifest['probes'])),
    scripts=[dict(file=n,bytes=(root/n).stat().st_size,sha256=sha(root/n)) for n in scripts],
    artifacts=[dict(file=n,bytes=(root/n).stat().st_size,sha256=sha(root/n)) for n in artifacts])
target=root/'verification-receipt.json';target.write_text(json.dumps(result,indent=2))
print(json.dumps(dict(receipt=str(target),sha256=sha(target),validation=result['validation'])))
