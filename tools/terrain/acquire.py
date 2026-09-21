"""Bounded exact-profile CASC acquisition. Client input is read-only.
Only the pinned TACTTool is executed, in a new external output directory.
Verified-copy mode reproduces receipts using already acquired bytes.
"""
import argparse, hashlib, json, os, pathlib, re, shutil, stat, subprocess

PROFILE_HASH='8577e6eaf7d20c2a04eb8aba0d2e3a9578618c08c094f8105d9efed702a61307'
PROFILE=pathlib.Path(__file__).with_name('acquisition-profile.json')
LAYERS=('root','collision','wmo-groups','wmo-doodads')

def fail(reason):raise ValueError(reason)
def digest(data):return hashlib.sha256(data).hexdigest()
def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=True).encode()
def load_profile(path=PROFILE):
    data=pathlib.Path(path).read_bytes()
    if len(data)>262144:fail('profile-size')
    value=json.loads(data)
    if digest(canonical(value))!=PROFILE_HASH:fail('unpinned-acquisition-profile')
    validate_profile(value)
    return value

def validate_profile(value):
    if value.get('schema')!='rikui-terrain-acquisition-profile-v1':fail('profile-schema')
    if (value.get('product'),value.get('version'),value.get('locale'))!=('wow_classic_beta','1.60.1.69913','enUS'):fail('profile-identity')
    files=value['files']
    if not 1<=len(files)<=512:fail('asset-count')
    identifiers=set();paths=set();total=0
    for row in files:
        path=row['path'];parts=path.split('/')
        if not all(re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]*',p) and p not in ('.','..') for p in parts):fail('unsafe-asset-path')
        if len(parts)>2 or row['layer'] not in LAYERS:fail('asset-layer')
        if row['layer']=='root' and len(parts)!=1 or row['layer']!='root' and parts[0]!=row['layer']:fail('asset-layer-path')
        if path.lower() in paths or type(row['fileDataID']) is not int or not 0<row['fileDataID']<=2147483647 or row['fileDataID'] in identifiers:fail('duplicate-or-invalid-asset')
        if type(row['bytes']) is not int or not 0<row['bytes']<=4*1024*1024 or not re.fullmatch('[0-9a-f]{64}',row['sha256']):fail('asset-size-hash')
        paths.add(path.lower());identifiers.add(row['fileDataID']);total+=row['bytes']
    if total>16*1024*1024:fail('total-asset-bytes')

def checked_path(path):
    """Reject symlinks/junctions in every existing component, without following them."""
    p=pathlib.Path(os.path.abspath(os.fspath(path)))
    for current in reversed([p,*p.parents]):
        try:info=current.lstat()
        except FileNotFoundError:continue
        if stat.S_ISLNK(info.st_mode) or getattr(info,'st_file_attributes',0)&getattr(stat,'FILE_ATTRIBUTE_REPARSE_POINT',0x400):fail('symlink-or-reparse-point:'+str(current))
    return p

def beneath(path,parent):
    try:path.relative_to(parent);return True
    except ValueError:return False

def empty_output(path,forbidden=()):
    target=checked_path(path)
    for root in forbidden:
        if beneath(target,checked_path(root)) or beneath(checked_path(root),target):fail('output-overlaps-input')
    for ancestor in [target,*target.parents]:
        if (ancestor/'.git').exists():fail('generated-output-inside-repository')
    if target.exists():
        if not target.is_dir() or any(target.iterdir()):fail('output-must-be-empty')
    else:target.mkdir(parents=True)
    return checked_path(target)

def asset_path(root,row):
    result=checked_path(root.joinpath(*row['path'].split('/')))
    if not beneath(result,root):fail('asset-path-escape')
    return result

def verify(profile,root):
    root=checked_path(root)
    if not root.is_dir():fail('acquisition-directory-missing')
    for row in profile['files']:
        path=asset_path(root,row)
        if not path.is_file() or path.stat().st_size!=row['bytes']:fail('asset-size:'+row['path'])
        if digest(path.read_bytes())!=row['sha256']:fail('asset-hash:'+row['path'])
    return dict(files=len(profile['files']),bytes=sum(f['bytes'] for f in profile['files']))

def receipts(profile,root,mode,source,tool_path=None):
    def rows(layer):
        return [dict(file=str(asset_path(root,r)),**{k:r[k] for k in ('fileDataID','bytes','sha256','encodingKey')}) for r in profile['files'] if r['layer']==layer]
    tool=json.loads(json.dumps(profile['tool']))
    if tool_path:tool['binary']['file']=str(tool_path)
    provenance=dict(profileCanonicalSHA256=PROFILE_HASH,profileFileSHA256=digest(PROFILE.read_bytes()),
        parserSHA256=digest(pathlib.Path(__file__).read_bytes()),mode=mode,source=str(source))
    base=dict(schema='rikui-local-terrain-extraction-evidence-v1',
        **{k:profile[k] for k in ('product','version','locale','buildConfig','cdnConfig','mappingEvidence','limitations')},
        tool=tool,acquisition=provenance,sourceAccess=dict(mode=mode,gameFilesModified=False,processesModified=False),
        tables=[dict(file=r['name'],**{k:r[k] for k in ('bytes','sha256','url','license')},localBytesIncluded=False) for r in profile['tables']],
        files=rows('root'),collisionDependencies=rows('collision'),publishNavigableRoutes=False)
    base['collisionDependencyCount']=len(base['collisionDependencies']);base['collisionDependencyBytes']=sum(r['bytes'] for r in base['collisionDependencies'])
    recursive=dict(product=profile['product'],build=profile['version'],buildConfig=profile['buildConfig'],cdnConfig=profile['cdnConfig'],baseManifest='extraction-manifest.json',acquisition=provenance,
        additional={layer:dict(files=rows(layer),count=len(rows(layer)),bytes=sum(r['bytes'] for r in rows(layer))) for layer in ('wmo-groups','wmo-doodads')},limitations=profile['limitations'])
    for name,value in [('extraction-manifest.json',base),('recursive-dependencies-manifest.json',recursive)]:
        path=checked_path(root/name)
        with path.open('x',encoding='utf8',newline='\n') as handle:json.dump(value,handle,indent=2);handle.write('\n')

def run(profile,root,game,tool):
    game=checked_path(game);tool=checked_path(tool)
    expected=profile['tool']['binary']
    if not game.is_dir() or not (game/'Data').is_dir():fail('game-root-must-contain-Data')
    if not tool.is_file() or tool.stat().st_size!=expected['bytes'] or digest(tool.read_bytes())!=expected['sha256']:fail('pinned-TACTTool-hash')
    arguments=[str(tool),'-d',str(game),'-p',profile['product'],'-b',profile['buildConfig'],'-c',profile['cdnConfig'],'-l',profile['locale']]
    for layer in LAYERS:
        selected=[r for r in profile['files'] if r['layer']==layer]
        output=root if layer=='root' else root/layer
        if layer!='root':output.mkdir()
        listing=root/(layer+'-dependencies.list')
        with listing.open('x',encoding='utf8',newline='\n') as handle:
            for row in selected:handle.write(str(row['fileDataID'])+';'+pathlib.PurePosixPath(row['path']).name+'\n')
        with (root/(layer+'-extract.log')).open('xb') as log:
            result=subprocess.run(arguments+['-m','list','-i',str(listing),'-o',str(output)],cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=120,check=False)
        if result.returncode:fail('TACTTool-failed:'+layer)
    verify(profile,root)
    receipts(profile,root,'pinned-TACTTool-read-only-CASC',game,tool)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    modes=p.add_mutually_exclusive_group(required=True)
    modes.add_argument('--game-root');modes.add_argument('--from-existing');modes.add_argument('--verify-existing')
    p.add_argument('--tact-tool');p.add_argument('--output-directory');a=p.parse_args()
    profile=load_profile()
    if a.verify_existing:
        if a.output_directory or a.tact_tool:fail('verify-is-read-only')
        result=verify(profile,a.verify_existing);print(json.dumps(dict(status='verified-exact-profile',**result)));return
    if not a.output_directory:fail('output-directory-required')
    source=a.game_root or a.from_existing
    output=empty_output(a.output_directory,(pathlib.Path(__file__).parent,source))
    if a.game_root:
        if not a.tact_tool:fail('tact-tool-required')
        run(profile,output,a.game_root,a.tact_tool)
    else:
        if a.tact_tool:fail('copy-mode-does-not-run-tool')
        original=checked_path(a.from_existing);verify(profile,original)
        for row in profile['files']:
            dest=asset_path(output,row);dest.parent.mkdir(exist_ok=True)
            with asset_path(original,row).open('rb') as source_file,dest.open('xb') as dest_file:shutil.copyfileobj(source_file,dest_file)
        verify(profile,output);receipts(profile,output,'verified-copy-of-exact-acquired-assets',original)
    print(json.dumps(dict(status='acquired-exact-profile',output=str(output),**verify(profile,output),profileCanonicalSHA256=PROFILE_HASH)))
if __name__=='__main__':main()
