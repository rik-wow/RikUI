import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {LIMITS,PROFILE,sha,parseJSON,validateManifest,validateGeometry,validateSites,gridDimensions,stageShape,SnapshotBudget,withHooks} from './stage_contract.mjs';
import {argumentsFor,preflight,newOutput,readBound,boundedReadDescriptor,noLinks,verifyModules,MODULE_HASHES} from './stage_io.mjs';
import {trackedBuild,createCapture,summarize} from './stage_capture.mjs';
let checks=0;const test=(name,fn)=>{try{fn();checks++;}catch(error){error.message=name+': '+error.message;throw error;}};
const fails=(name,fn,pattern)=>test(name,()=>assert.throws(fn,pattern));
function fixture(){
 const identity={product:'wow_classic_beta',edition:'Forever',build:'1.60.1.69913',locale:'enUS'};
 const bounds=[[0,0,0],[64,10,64]],origin=[32,5,32];
 const geometry={format:'rikui-navigation-geometry-probe-v1',identity:{...identity},regionBounds:bounds,positions:[0,0,0,64,10,64,0,0,64],indices:[0,1,2]};
 const manifest={format:'rikui-nav-region-proof-v1',identity,geometrySha256:sha(Buffer.from(JSON.stringify(geometry))),origin,bounds:{min:bounds[0],max:bounds[1]},publishable:false,coverage:{nativeTraversalVerified:false},
 generator:{package:'recast-navigation',version:'0.43.1',repositoryCommit:'8769e8b9995f127033af9f6e6eeac3fad7d66201',recastForkCommit:'599fd0f023181c0a484df2a18cf1d75a3553852e',agentProfileNativeVerified:false,config:{...PROFILE,bounds:[[-32,-5,-32],[32,5,32]]}}};
 return {manifest,geometry,sites:[{name:'synthetic-site',x:2,z:3,modelY:4}]};
}
let f=fixture();
test('valid independent geometry and tile',()=>{const grid=validateManifest(f.manifest);validateGeometry(f.geometry,f.manifest);assert.deepEqual(validateSites(f.sites,f.manifest,grid)[0].tile,{x:0,y:0,bmin:[-32,-5,-32],bmax:[32,5,32]});});
for(const [name,modify] of Object.entries({format:m=>m.format='unknown',product:m=>m.identity.product='classic',locale:m=>m.identity.locale='en-US',version:m=>m.generator.version='0.43.2',coercedBuild:m=>m.identity.build=['1.60.1.69913'],profile:m=>m.generator.config.walkableRadius=0,extraProfile:m=>m.generator.config.unrecognized=true,bounds:m=>m.bounds.max[0]=0,native:m=>m.coverage.nativeTraversalVerified=true,origin:m=>m.origin[0]=Infinity,grid:m=>m.generator.config.bounds[1][0]=100000}))
 fails('manifest '+name,()=>{const d=fixture().manifest;modify(d);validateManifest(d);});
for(const [name,modify] of Object.entries({format:g=>g.format='wrong',identity:g=>g.identity.build='1.60.1.1',positions:g=>g.positions=[],stride:g=>g.positions.push(2),nonfinite:g=>g.positions[0]=NaN,oversized:g=>g.positions=new Array(LIMITS.positions+3),badIndex:g=>g.indices[0]=3,floatIndex:g=>g.indices[0]=.5,indexStride:g=>g.indices.push(1),indices:g=>g.indices=new Array(LIMITS.indices+1),region:g=>g.regionBounds[1][0]=63,origin:g=>g.positions[0]=-1}))
 fails('geometry '+name,()=>{const d=fixture();modify(d.geometry);validateGeometry(d.geometry,d.manifest);});
fails('changed origin cannot shift grid',()=>{const d=fixture();d.manifest.origin[0]+=1;validateGeometry(d.geometry,d.manifest);},/origin/);
fails('changed config bounds cannot shift grid',()=>{const d=fixture();d.manifest.generator.config.bounds[0][0]-=1;validateGeometry(d.geometry,d.manifest);},/grid-bounds/);
for(const [name,sites] of Object.entries({empty:[],many:Array.from({length:5},(_,i)=>({name:'site-'+i,x:2,z:3,modelY:4})),duplicate:[f.sites[0],f.sites[0]],escape:[{...f.sites[0],name:'../escape'}],uppercase:[{...f.sites[0],name:'Upper'}],unknown:[{...f.sites[0],tile:[0,0]}],outside:[{...f.sites[0],x:65}],upperEdge:[{...f.sites[0],x:64}],nan:[{...f.sites[0],z:NaN}],height:[{...f.sites[0],modelY:11}]}))
 fails('sites '+name,()=>validateSites(sites,f.manifest,validateManifest(f.manifest)));
test('fractional extent follows voxel rounding',()=>assert.deepEqual(gridDimensions([[0,0,0],[128.1,10,64]],.5,128),{gridWidth:256,gridHeight:128,width:2,height:1}));
fails('fractional last strip has no generated tile',()=>{const d=fixture();d.geometry.positions[3]=128.1;d.geometry.regionBounds[1][0]=128.1;d.manifest.origin[0]=64.05;d.manifest.generator.config.bounds[0][0]=-64.05;d.manifest.generator.config.bounds[1][0]=64.05;validateGeometry(d.geometry,d.manifest);validateSites([{name:'last-strip',x:128.05,z:3,modelY:4}],d.manifest,validateManifest(d.manifest));},/tile-outside-grid/);
test('half-cell rounding changes tile count',()=>{assert.equal(gridDimensions([[0,0,0],[64.24,10,64]],.5,128).width,1);assert.equal(gridDimensions([[0,0,0],[64.25,10,64]],.5,128).width,2);});
test('descriptor growth cannot cause unbounded read',()=>{let read=0,stats=0;const io={fstatSync(){return {isFile:()=>true,size:++stats===1?2:1000000};},readSync(fd,buffer,offset,length){read+=length;buffer.fill(97,offset,offset+length);return length;}};assert.throws(()=>boundedReadDescriptor(1,1000000,'fixture',io),/size-changed/);assert.equal(read,3);});
test('descriptor oversize rejected without reading',()=>{const io={fstatSync:()=>({isFile:()=>true,size:100}),readSync(){throw Error('must-not-read');}};assert.throws(()=>boundedReadDescriptor(1,10,'fixture',io),/file-size/);});
test('site detached',()=>{const d=fixture(),rows=validateSites(d.sites,d.manifest,validateManifest(d.manifest));rows[0].site.x=50;assert.equal(d.sites[0].x,2);});
fails('JSON input byte limit',()=>parseJSON(Buffer.from('{}'),1,'fixture'),/byte-limit/);
fails('malformed JSON',()=>parseJSON(Buffer.from('{'),10,'fixture'),/invalid-json/);
const cli=['--manifest','m','--manifest-sha256','0'.repeat(64),'--geometry','g','--modules','n','--sites','s','--output','o'];
test('named arguments',()=>assert.equal(argumentsFor(cli).output,'o'));
fails('unknown CLI argument',()=>argumentsFor(cli.map((v,i)=>i===0?'--evil':v)));
fails('duplicate CLI argument',()=>argumentsFor(cli.map((v,i)=>i===10?'--manifest':v)));
fails('missing CLI argument',()=>argumentsFor(cli.slice(2)));
fails('bad cells',()=>stageShape({width:201,height:100,cs:.5,ch:.1,worldMin:[0,0,0]}),/cell-limit/);
fails('bad spans',()=>stageShape({width:100,height:100,cs:.5,ch:.1,worldMin:[0,0,0]},200001),/span-limit/);
test('snapshot rows counted',()=>{const b=new SnapshotBudget();b.begin();b.stage();b.row([1,2,3]);assert.equal(b.total,1024*1024+2048+8);});
fails('snapshot file bound',()=>{const b=new SnapshotBudget();b.begin();b.add(LIMITS.fileBytes);},/budget/);
fails('snapshot stage bound',()=>{const b=new SnapshotBudget();b.begin();for(let i=0;i<11;i++)b.stage();},/stage-limit/);
fails('snapshot file count',()=>{const b=new SnapshotBudget();for(let i=0;i<5;i++)b.begin();},/file-limit/);
fails('negative encoded count',()=>new SnapshotBudget().encoded(-1),/file-limit/);
fails('encoded file bound',()=>new SnapshotBudget().encoded(LIMITS.fileBytes+1),/file-limit/);
fails('encoded aggregate bound',()=>{const b=new SnapshotBudget();for(let i=0;i<5;i++)b.encoded(LIMITS.fileBytes);},/aggregate-limit/);
test('hook return and arguments retained',()=>{const fn=(...args)=>args,target={fn};const args=[{},42];const output=withHooks(target,{fn:old=>function(...xs){return old.apply(this,xs);}},()=>target.fn(...args));assert.equal(output[0],args[0]);assert.equal(output[1],42);assert.equal(target.fn,fn);});
test('hook restoration on callback throw',()=>{const fn=()=>1,target={fn};assert.throws(()=>withHooks(target,{fn:()=>()=>2},()=>{throw Error('fixture');}));assert.equal(target.fn,fn);});
test('partial hook installation restored',()=>{const fn=()=>1,target={fn};assert.throws(()=>withHooks(target,{fn:()=>()=>2,missing:()=>()=>3},()=>{}));assert.equal(target.fn,fn);});
function fakeCore(){
 const freed=[],target={};let pointer=1;
 for(const name of ['Heightfield','CompactHeightfield','ContourSet','PolyMesh','PolyMeshDetail']){target['alloc'+name]=()=>({ptr:pointer++});target['free'+name]=raw=>freed.push(raw.ptr);}
 return {freed,Raw:{Recast:target,isNull:raw=>raw===null,Module:{getPointer:raw=>raw.ptr,destroy:()=>{}}}};
}
test('intermediates freed after generator throws',()=>{const c=fakeCore(),old=c.Raw.Recast.allocHeightfield;assert.throws(()=>trackedBuild(c,{},()=>{c.Raw.Recast.allocHeightfield();c.Raw.Recast.allocPolyMesh();throw Error('fixture');}));assert.equal(c.freed.length,2);assert.equal(new Set(c.freed).size,2);assert.equal(c.Raw.Recast.allocHeightfield,old);});
test('already freed intermediate not freed twice',()=>{const c=fakeCore();trackedBuild(c,{},()=>{const raw=c.Raw.Recast.allocHeightfield();c.Raw.Recast.freeHeightfield(raw);c.Raw.Recast.allocContourSet();});assert.deepEqual(c.freed,[1,2]);});
test('capture failure leaves original call intact',()=>{
 const c=fakeCore();c.Raw.Recast.buildCompactHeightfield=()=>true;c.RecastHeightfield=class{width(){return 1;}height(){return 1;}cs(){return .5;}ch(){return .1;}bmin(){return {x:0,y:0,z:0};}};
 const capture=createCapture(c,{origin:[0,0,0],config:PROFILE},{stage(){throw Error('capture-fixture');}});let calls=0;
 const original=(a,b,raw)=>{calls++;return raw;},wrapped=capture.observers.filterLowHangingWalkableObstacles(original),raw={};assert.equal(wrapped(1,2,raw),raw);assert.equal(calls,1);assert.throws(()=>capture.assert(),/capture-fixture/);
});
const constants={nullArea:0,none:63,dx:[-1,0,1,0],dz:[0,1,0,-1]};
function stage(){return {label:'fixture',kind:'compact',width:2,height:1,cs:1,ch:.1,worldMin:[0,0,0],total:2,walkable:2,rows:[[0,0,0,20,63,0,63,63,0,63],[1,1,0,20,63,0,0,63,63,63]]};}
test('compact component uses actual connections',()=>{const result=summarize(stage(),{x:.2,z:.2,modelY:0},0,constants);assert.equal(result.components[0].size,2);});
fails('compact neighbor outside grid rejected',()=>{const s=stage();s.rows[0][6]=0;summarize(s,{x:.2,z:.2,modelY:0},0,constants);},/connection/);
fails('compact neighbor index missing rejected',()=>{const s=stage();s.rows[0][8]=1;summarize(s,{x:.2,z:.2,modelY:0},0,constants);},/connection/);
fails('compact duplicate span rejected',()=>{const s=stage();s.rows[1][1]=0;summarize(s,{x:.2,z:.2,modelY:0},0,constants);},/row-index/);
test('null area remains blocked',()=>{const s=stage();s.rows[0][4]=0;assert.equal(summarize(s,{x:.2,z:.2,modelY:0},0,constants).components[0].size,0);});
test('model reference never selects an unrelated floor',()=>assert.equal(summarize(stage(),{x:.2,z:.2,modelY:5},0,constants).components.length,0));
const root=fs.mkdtempSync(path.join(os.tmpdir(),'rikui-stage-test-'));
try{
 const source=path.join(root,'source');fs.mkdirSync(source);const empty=path.join(root,'empty');fs.mkdirSync(empty);const output=path.join(root,'output');
 fails('existing even empty output refused',()=>newOutput(empty),/already-exists/);
 test('new output check makes no files',()=>{assert.equal(newOutput(output),output);assert.equal(fs.existsSync(output),false);});
 const repo=path.join(root,'repository');fs.mkdirSync(repo);fs.writeFileSync(path.join(repo,'.git'),'gitdir: fixture');
 fails('Git worktree output refused',()=>newOutput(path.join(repo,'output')),/git-worktree/);
 const regular=path.join(source,'input.json');fs.writeFileSync(regular,'{}');fails('oversized read refused',()=>readBound(regular,1),/size/);
 const junction=path.join(root,'junction');fs.symlinkSync(source,junction,process.platform==='win32'?'junction':'dir');fails('symbolic directory refused',()=>noLinks(path.join(junction,'input.json')),/symbolic/);
 const d=fixture();const manifest=path.join(source,'manifest.json'),geometry=path.join(source,'geometry.json'),sites=path.join(source,'sites.json');
 fs.writeFileSync(manifest,JSON.stringify(d.manifest));fs.writeFileSync(geometry,JSON.stringify(d.geometry));fs.writeFileSync(sites,JSON.stringify(d.sites));
 const args={manifest,'manifest-sha256':'f'.repeat(64),geometry,sites,modules:path.join(root,'missing-modules'),output};
 fails('bad manifest hash before writing',()=>preflight(args),/manifest-hash-mismatch/);test('failed preflight has no output',()=>assert.equal(fs.existsSync(output),false));
 args['manifest-sha256']=sha(fs.readFileSync(manifest));fs.writeFileSync(geometry,'{}');fails('bad geometry hash before writing',()=>preflight(args),/geometry-hash-mismatch/);
 if(process.argv[2]){
  const valid=verifyModules(process.argv[2]);test('real dependency resolution verified',()=>assert.equal(Object.keys(valid.hashes).length,8));
  const modules=path.join(root,'node_modules');for(const relative of Object.keys(MODULE_HASHES)){const destination=path.join(modules,relative);fs.mkdirSync(path.dirname(destination),{recursive:true});fs.copyFileSync(path.join(valid.root,relative),destination);}
  for(const relative of Object.keys(MODULE_HASHES)){const file=path.join(modules,relative),bytes=fs.readFileSync(file);fs.appendFileSync(file,'x');fails('transitive hash '+relative,()=>verifyModules(modules),/module-hash/);fs.writeFileSync(file,bytes);}
  const nested=path.join(modules,'@recast-navigation/generators/node_modules/@recast-navigation/core');fs.mkdirSync(path.join(nested,'dist'),{recursive:true});fs.copyFileSync(path.join(modules,'@recast-navigation/core/package.json'),path.join(nested,'package.json'));fs.copyFileSync(path.join(modules,'@recast-navigation/core/dist/index.mjs'),path.join(nested,'dist/index.mjs'));
  fails('nested package override refused',()=>verifyModules(modules),/unexpected-core-resolution/);
 }
}finally{const relative=path.relative(os.tmpdir(),root);assert.ok(relative.startsWith('rikui-stage-test-')&&!relative.includes(path.sep));fs.rmSync(root,{recursive:true,force:true});}
const cliPath=path.join(path.dirname(fileURLToPath(import.meta.url)),'inspect_stages.mjs');
for(const file of new Set([cliPath,path.toNamespacedPath(cliPath)]))test('CLI rejects missing arguments '+file,()=>{
 const result=spawnSync(process.execPath,['--preserve-symlinks','--preserve-symlinks-main',file],{encoding:'utf8'});
 assert.equal(result.status,1);assert.match(result.stderr,/expected-six-named-arguments/);
});
console.log(checks+' stage diagnostic checks passed'+(process.argv[2]?' (including pinned transitive modules)':''));
