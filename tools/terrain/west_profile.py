"""Factual exact-build west/central source pins; no native walkability claim."""
import struct
import terrain_probe as t

REGION_ID = 'dun-morogh-west-central-69913'
PROFILE_SHA256 = '150ee6e381a9a0cda778f51d88c5a0e9c2f51d643e1f0c5f0f7430dcd722b640'
BOUNDS = [-1066.6673177083333, -5866.667317708333, 1066.666015625, -5150.0]
TILES = [
    ([30,41], 777592, 777593),
    ([30,42], 777597, 777598),
    ([31,41], 777792, 777793),
    ([31,42], 777797, 777798),
    ([32,41], 777992, 777993),
    ([32,42], 777997, 777998),
    ([33,41], 778192, 778193),
    ([33,42], 778197, 778198),
]
FILES = {
    775971: (294988, '160452dec4c2b0ae4cbe7468ce52fee91ac7ec521d2cb0f28e955def0d087137'),
    777592: (454740, '2528559f42593de5aeb0f4b4bd2e358ce4b83ac425b4011c4eeea36530a29f1b'),
    777593: (12140, 'd0b480256e2afbbd54328aebaeba7011bd4b9214f8463f705d11da434b22d587'),
    777597: (454740, '4cfe5cd3edec2cda2a05c32c34ff091263017bf368a85172076c0b4247836447'),
    777598: (7992, '78fde4f2923bdf30d4bd326b04d67dfb8c112153121653acc33ed83a46506599'),
    777792: (460538, 'a67e5e658ca5afe6d597042b4e1e88446460dbf1866b4f7fb35c62ad5d8a62e4'),
    777793: (27896, '581ee6dd95beccf9d8302818436f84971548c359cfe7d899727e7daa7e2e90ed'),
    777797: (454740, 'c4425c4e1c174bbb3c653d05bbbd51d98b96c103f405cf57061e137465e39393'),
    777798: (34196, 'dda9fb00c1ace49c80c4ce97a9ad51e670efd770e50ea519671851304e025a7f'),
    777992: (454740, '7d715051d91dcfa9ff6f4b1706a6387a3e6867648e93d74833713fa48281b7af'),
    777993: (38704, 'b3824f2114e919b74f1fcf8f2b42831cb1bde071c667ab3d5fae5fe1c97c6a41'),
    777997: (454740, 'dddd2c48191b3cc4db68647063c9e484640651a2facb74910c581d300ed8b1d9'),
    777998: (36984, '77449ed5a2e4c7f748c43b3e42d7172c24dece2a4c4547402eae1d4ce67c3fde'),
    778192: (454740, '8ba851d7d98a8d22b57a6ccd94edf85f101857f4d42de6f8b04552e159ce628e'),
    778193: (27856, '72cba13d2d3a34f30bb58fa3bd9f2fc895ff4fb8ac521acedeaf0bf8c4fdf611'),
    778197: (454740, '3cf93beb9f349f5928c8621eb8e03fba26e619c86560127ecff1d35bdbd02409'),
    778198: (40000, '18a62d51a583c0e263579b95bcf16e87a16918d843c927a69f98aeca54ed6152'),
}

def intersects(box, margin=2):
    return not (box[2]<BOUNDS[0]-margin or box[0]>BOUNDS[2]+margin or
                box[3]<BOUNDS[1]-margin or box[1]>BOUNDS[3]+margin)

def relevant(placement):
    if placement['kind']!='wmo':return True
    b=placement['bounds'];origin=t.TILE*32
    return intersects((origin-b[3],origin-b[5],origin-b[0],origin-b[2]),1)

def selected_chunks(records):
    return [r for r in records if intersects((r['position'][1]-t.CHUNK,
        r['position'][0]-t.CHUNK,r['position'][1],r['position'][0]))]

def liquid_exclusions(raw,records,tile):
    parts={tag:raw[a:b] for tag,a,b in t.chunks(raw) if tag=='MH2O'}
    if any('MCLQ' in r['subchunks'] for r in records):t.fail('west-MCLQ-unsupported')
    if not parts:return []
    data=parts['MH2O']
    if len(data)<3072:t.fail('west-MH2O-header')
    cells={(r['x'],r['y']):r for r in records};result=[]
    for index in range(256):
        offset,count,attrs=struct.unpack_from('<III',data,index*12)
        if count==0:
            if offset or attrs:t.fail('west-MH2O-empty-header')
            continue
        if count>8 or offset<3072 or offset+count*24>len(data):t.fail('west-MH2O-instance-range')
        if attrs and (attrs<3072 or attrs+16>len(data)):t.fail('west-MH2O-attribute-range')
        r=cells[(index%16,index//16)];z,x,_=r['position']
        result.append(dict(tile=list(tile),chunk=[r['x'],r['y']],reason='unmodeled-MH2O-cell',
            bounds=[[x-t.CHUNK,-100000,z-t.CHUNK],[x,100000,z]],padding=.5))
    return result
