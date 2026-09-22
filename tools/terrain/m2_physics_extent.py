"""Exact inline physics extent, used only for conservative exclusion, never paths."""
import math,struct
import terrain_probe as t
ASSET_SHA='24c26943fb0a51d68ab3c850870c63a41228d1a2cf9bbd124230f2340cc97ddc'
PAYLOAD_SHA='27524174d9d0362f12142b5a628c3f46ae9133e13fc81fd66c784e7158ddcb44'
TEMPLATE_SHA='78f2da2c7f7512d0b308c7f9bf9d69b4a00e5c756d3c5db8cc3653097b09344a'
def extent(data):
    if t.digest(data)!=ASSET_SHA:return None
    parts={};offset=0
    while offset<len(data):
        if offset+8>len(data):t.fail('PCOL-header')
        tag=data[offset:offset+4].decode('ascii');size=struct.unpack_from('<I',data,offset+4)[0];end=offset+8+size
        if end>len(data) or tag in parts:t.fail('PCOL-framing')
        parts[tag]=data[offset+8:end];offset=end
    p=parts.get('PCOL',b'')
    if t.digest(p)!=PAYLOAD_SHA or parts.get('DPIV')!=bytes.fromhex('0000008000000000000000000000000000000000000000000000000000000000'):
        t.fail('PCOL-pinned-layout')
    vertices,vo,normals,no,indices,io,flags,fo=struct.unpack_from('<8I',p)
    if (vertices,vo,normals,no,indices,io,flags,fo)!=(34,32,64,448,192,1216,64,1600):t.fail('PCOL-array-layout')
    points=list(struct.unpack_from('<102f',p,vo));faces=struct.unpack_from('<192H',p,io)
    normal=struct.unpack_from('<192f',p,no);bits=struct.unpack_from('<64H',p,fo)
    if not all(math.isfinite(v) for v in points+list(normal)) or not all(i<vertices for i in faces) or not set(bits)<={0,1}:
        t.fail('PCOL-array-shape')
    return dict(positions=points,sourceSHA256=ASSET_SHA,payloadSHA256=PAYLOAD_SHA,
        method='pinned-PCOL-static-union-exclusion-only',templateSHA256=TEMPLATE_SHA,nativeVerified=False)
