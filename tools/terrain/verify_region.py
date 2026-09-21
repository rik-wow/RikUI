"""Verify actual region topology/provenance and byte-identical deterministic replay."""
import hashlib,json,pathlib,platform,re,subprocess,sys
HERE=pathlib.Path(__file__).resolve().parent
first=HERE/'region';second=HERE/'region-replay'
names=sorted(p.name for p in first.iterdir() if p.is_file())
if names!=sorted(p.name for p in second.iterdir() if p.is_file()):raise ValueError('region-replay-files')
for name in names:
    if (first/name).read_bytes()!=(second/name).read_bytes():raise ValueError('region-replay-difference:'+name)
tests=subprocess.run([sys.executable,'-m','unittest','-v','test_probe','test_wmo_probe','test_acquire','test_region'],cwd=HERE,capture_output=True,text=True)
report=tests.stdout+tests.stderr;(HERE/'region-tests.log').write_text(report)
match=re.search(r'Ran (\d+) tests?',report)
if tests.returncode or not match:raise ValueError('region-tests-failed:'+report)
mesh=subprocess.run(['node','test_mesh_filter.mjs'],cwd=HERE,capture_output=True,text=True);(HERE/'mesh-filter-tests.log').write_text(mesh.stdout+mesh.stderr)
if mesh.returncode:raise ValueError('mesh-filter-tests-failed')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
m=json.loads((first/'manifest.json').read_text())
sourcefiles=sorted(p for p in HERE.iterdir() if p.is_file() and p.suffix in ('.py','.mjs','.ps1','.md'))
value={'schema':'rikui-two-source-region-verification-v1','identity':m['identity'],'regionID':m['regionID'],'tiles':m['tiles'],'manifestSHA256':sha(first/'manifest.json'),'nativeVerified':False,'pythonVersion':platform.python_version(),
 'validation':{'pythonTests':int(match.group(1)),'meshFilterChecks':8,'replayIdenticalFiles':len(names),'polygons':m['statistics']['polygons'],'portals':m['statistics']['directedEdges'],'shards':len(m['regions']),'modelPaths':len(m['probes']),'crossTileModelPath':any(p.get('kind')=='cross-source-tile-seam' and p['success'] for p in m['probes']),'degeneratePolygonsRemoved':m['statistics']['degeneratePolygonsRemoved']},
 'scripts':[{'name':p.name,'sha256':sha(p),'bytes':p.stat().st_size} for p in sourcefiles],
 'sourceProfile':{'file':'acquisition-profile.json','sha256':sha(HERE/'acquisition-profile.json')},'testsSHA256':sha(HERE/'region-tests.log'),'meshTestsSHA256':sha(HERE/'mesh-filter-tests.log'),
 'coverageGates':m['coverageGates'],'exclusions':m['exclusions'],'limitations':['Offline model only. Native floor selection and path following remain unverified.','Cross-seam connectivity is generated from combined geometry; individual quest POI feasibility is not implied.']}
(HERE/'region-verification-receipt.json').write_text(json.dumps(value,indent=2)+'\n');print(json.dumps({'manifestSHA256':value['manifestSHA256'],'validation':value['validation']}))
