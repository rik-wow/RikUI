// Exercise the actual Recast batch wrapper, rather than replacing it with a mock.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {gzipSync,gunzipSync} from 'node:zlib';
const wrapper=fileURLToPath(new URL('./bake_world_batch.mjs',import.meta.url));
const root=fs.mkdtempSync(path.join(os.tmpdir(),'rikui-compact-batch-'));
const geometry={format:'rikui-world-geometry-v1',worldMapID:0,nativeVerified:false,
 identity:{fixture:true},source:{fixture:true},coverageGates:[],exclusions:[],liquids:[],limitations:[],
 positions:[0,0,0,64,0,0,64,0,64,0,0,64],indices:[0,2,1,0,3,2],
 job:{format:'rikui-world-bake-job-v1',worldMapID:0,id:'fixture',batchGrid:[0,0],
  ownedXZ:[0,0,512,512],bakeXZ:[-64,-64,576,576],
  lattice:{origin:[0,0,0],cell:.25,heightCell:.1,recastTileSize:64,batchTiles:8,border:1.25},
  source:{fixture:true}}};
try{
 const raw=Buffer.from(JSON.stringify(geometry)), manifests=[];
 for(const compressed of [false,true]){
  const input=path.join(root,'geometry.json'+(compressed?'.gz':''));
  const out=path.join(root,compressed?'compressed':'plain');
  fs.writeFileSync(input,compressed?gzipSync(raw,{level:3}):raw);
  const result=spawnSync(process.execPath,[wrapper,input,out],{encoding:'utf8',timeout:120000});
  assert.equal(result.status,0,result.stderr||result.error?.message);
  const manifest=JSON.parse(fs.readFileSync(path.join(out,'manifest.json')));
  assert.ok(manifest.statistics.ownedPolygons>0,'a real navigable surface must be baked');
  assert.deepEqual(manifest.files.map(row=>row.filename),['polygons.json.gz','boundary-witnesses.json.gz']);
  manifests.push(manifest);
 }
 assert.equal(manifests[0].geometrySHA256,manifests[1].geometrySHA256);
 for(const name of ['polygons.json.gz','boundary-witnesses.json.gz']){
  const plain=fs.readFileSync(path.join(root,'plain',name));
  const compressed=fs.readFileSync(path.join(root,'compressed',name));
  assert.deepEqual(plain,compressed,'compression must not change the baked graph');
  assert.ok(JSON.parse(gunzipSync(compressed,{maxOutputLength:64*1024*1024})).polygons);
 }
 const bad=path.join(root,'corrupt.json.gz');
 const zipped=gzipSync(raw);zipped[zipped.length-5]^=1;fs.writeFileSync(bad,zipped);
 const out=path.join(root,'corrupt-output');
 const result=spawnSync(process.execPath,[wrapper,bad,out],{encoding:'utf8',timeout:120000});
 assert.notEqual(result.status,0);assert.equal(fs.existsSync(out),false);
 console.log('Actual Recast plain/compressed geometry produces identical graph bytes; corrupt input rejected.');
}finally{
 assert.equal(path.dirname(path.resolve(root)),path.resolve(os.tmpdir()),'cleanup must stay in the intended temporary directory');
 assert.equal(fs.realpathSync(root),path.resolve(root),'cleanup must not follow a replaced directory');
 fs.rmSync(root,{recursive:true,force:true});
}
