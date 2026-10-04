// Compare only the unchanged publisher collision method; no textures/animation/CASC calls.
const fs=require('node:fs'),path=require('node:path'),Module=require('node:module'),crypto=require('node:crypto');
const [reader,asset,expected]=process.argv.slice(2);
const root=path.resolve(reader,'src/js'),raw=fs.readFileSync(asset);
const hash=body=>crypto.createHash('sha256').update(body).digest('hex');
if(hash(raw)!==expected)throw Error('Current model hash mismatch');
const original=Module._load;
Module._load=function(request,parent,...args){
 const full=request.startsWith('.')?path.resolve(path.dirname(parent.filename),request):request;
 if(['core','log','generics','constants','casc/export-helper','3D/AnimMapper'].some(name=>full===path.join(root,name)))return {};
 if(['3D/Texture','3D/Skin','3D/loaders/ANIMLoader'].some(name=>full===path.join(root,name)))return class {};
 if(request==='webp-wasm')return {};
 return original.call(this,request,parent,...args);
};
const BufferWrapper=require(path.join(root,'buffer.js'));
const Reader=require(path.join(root,'3D/loaders/M2Loader.js'));
let at=0,payload;
while(at<raw.length){
 if(at+8>raw.length)throw Error('Truncated chunk');
 const end=at+8+raw.readUInt32LE(at+4);
 if(end>raw.length)throw Error('Chunk overrun');
 if(raw.toString('ascii',at,at+4)==='MD21'){if(payload)throw Error('Duplicate MD21');payload=raw.subarray(at+8,end);}
 at=end;
}
if(!payload||payload.length<240)throw Error('Missing MD21');
const data=new BufferWrapper(payload),model=new Reader(data);
data.seek(160);model.parseChunk_MD21_collision(0);
console.log(JSON.stringify({assetSHA256:expected,version:payload.readUInt32LE(4),
 readerSHA256:hash(fs.readFileSync(path.join(root,'3D/loaders/M2Loader.js'))),
 collisionIndices:model.collisionIndices,collisionPositions:model.collisionPositions,
 collisionNormals:model.collisionNormals,collisionBox:model.collisionBox,collisionSphereRadius:model.collisionSphereRadius}));
