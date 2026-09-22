"""Hash-pinned acquired Forever 69913 Dun Morogh source profile."""
import hashlib,json,pathlib
REGION_ID='dun-morogh-map-69913'
BOUNDS=[-3122.9165039062,-7160.4165039062,1802.0832519531,-3877.0832519531]
PROFILE_FILE_SHA256='7c522c24d5095907966c03f76c69cfc18c427496fc93f1a3c4def5621e093b92'
PROFILE_CANONICAL_SHA256='fc51a45b8de42ca240b59a8fc3faadc5329e881ec4bc93e15e83f3d514a84958'
RECEIPT_SHA256='80463316410b74d54c0a6b67fe9537e5c313acbb75919e078df4e2cf7371a002'
RECURSIVE_SHA256='65586a247ebcb01c09a4bb13b10595d95cfd4af441f605db0c081b0d09b0376f'
ROOT_RECORDS_SHA256='5a875e0f1a1fadd5f87300f1628ed174454b5d17f63cb30b4bc247a6ac059399'
ALL_RECORDS_SHA256='19be83a923a6752e4ac4fa77813db010de9ef6595718b4f40ff6cb89740cf6c5'
BASES=((28,777182),(29,777382),(30,777582),(31,777782),(32,777982),
       (33,778182),(34,778382),(35,778592),(36,778787),(37,778977))
TILES=[([x,y],base+5*(y-39),base+5*(y-39)+1) for x,base in BASES for y in range(39,46)]
MAX_BYTES=512*1024*1024
MAX_POSITIONS=18000000
MAX_INDICES=30000000
MAX_PLACEMENTS=65536
MAX_EXCLUSIONS=4096
MAX_WMO_PLACEMENTS=1024
def digest(data):return hashlib.sha256(data).hexdigest()
def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
def record_digest(records):
    rows=[{k:r[k] for k in ('fileDataID','bytes','sha256')} for r in records]
    if len({r['fileDataID'] for r in rows})!=len(rows):raise ValueError('map-duplicate-source-ID')
    return digest(canonical(sorted(rows,key=lambda r:r['fileDataID'])))
def pinned(directory,name,sha):
    raw=(directory/name).read_bytes()
    if digest(raw)!=sha:raise ValueError('map-source-pin:'+name)
    return json.loads(raw)
def validate_sources(directory):
    directory=pathlib.Path(directory).resolve()
    profile=pinned(directory,'acquisition-profile-map.json',PROFILE_FILE_SHA256)
    receipt=pinned(directory,'extraction-manifest.json',RECEIPT_SHA256)
    recursive=pinned(directory,'recursive-dependencies-manifest.json',RECURSIVE_SHA256)
    if digest(canonical(profile))!=PROFILE_CANONICAL_SHA256:raise ValueError('map-profile-pin')
    if record_digest(profile['files'])!=ALL_RECORDS_SHA256 or record_digest(receipt['files'])!=ROOT_RECORDS_SHA256:
        raise ValueError('map-inventory-pin')
    if len(profile['files'])!=1590 or len(receipt['files'])!=141:raise ValueError('map-inventory-count')
    for doc in (receipt,recursive):
        if doc['acquisition']['profileCanonicalSHA256']!=PROFILE_CANONICAL_SHA256 or doc['acquisition']['profileFileSHA256']!=PROFILE_FILE_SHA256:
            raise ValueError('map-acquisition-profile-pin')
    if profile['navigationRegion']['regionID']!=REGION_ID or profile['navigationRegion']['navXZBounds']!=BOUNDS:
        raise ValueError('map-projection-pin')
    for row in profile['files']:
        path=(directory/row['path']).resolve()
        if not path.is_relative_to(directory):raise ValueError('map-source-path')
        raw=path.read_bytes()
        if len(raw)!=row['bytes'] or digest(raw)!=row['sha256']:raise ValueError('map-source-bytes:'+row['path'])
    return profile,receipt,recursive
def intersects(box,margin=2):
    return not(box[2]<BOUNDS[0]-margin or box[0]>BOUNDS[2]+margin or box[3]<BOUNDS[1]-margin or box[1]>BOUNDS[3]+margin)
def relevant(placement):
    if placement['kind']!='wmo':return True
    import terrain_probe as t
    b=placement['bounds'];origin=t.TILE*32
    return intersects((origin-b[3],origin-b[5],origin-b[0],origin-b[2]),1)
def selected_chunks(records):
    import terrain_probe as t
    return [r for r in records if intersects((r['position'][1]-t.CHUNK,r['position'][0]-t.CHUNK,r['position'][1],r['position'][0]))]
