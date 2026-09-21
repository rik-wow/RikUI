// Offline observational instrumentation only. No profile or source mutation.
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {LIMITS,ensure,sha,SnapshotBudget} from './stage_contract.mjs';
import {argumentsFor,preflight,newOutput,readBound} from './stage_io.mjs';
import {createCapture,trackedBuild,summarize} from './stage_capture.mjs';
const HERE=path.dirname(fileURLToPath(import.meta.url));
function constants(core){return {nullArea:core.Recast.RC_NULL_AREA,none:core.Recast.RC_NOT_CONNECTED,
 dx:[0,1,2,3].map(core.getDirOffsetX),dz:[0,1,2,3].map(core.getDirOffsetY)};}
function buildSite(core,generators,input,shared,item,budget){
 budget.begin();const capture=createCapture(core,input.grid,budget),ctx=new core.RecastBuildContext(),controlCtx=new core.RecastBuildContext();
 let instrumented,control;
 try{
  const build=context=>generators.generateTileNavMeshData(shared.vertices,shared.indices,shared.rcConfig,shared.chunky,item.tile,{},true,context);
  instrumented=trackedBuild(core,capture.observers,()=>build(ctx));capture.assert();
  ensure(instrumented.success&&instrumented.data,'instrumented-build-failed');
  const payload=Buffer.from(instrumented.data.toTypedArray());
  control=trackedBuild(core,{},()=>build(controlCtx));ensure(control.success&&control.data,'control-build-failed');
  ensure(payload.equals(Buffer.from(control.data.toTypedArray())),'instrumentation-changed-tile-bytes');
  const summary=capture.stages.map(stage=>summarize(stage,item.site,shared.rcConfig.borderSize,constants(core)));
  ensure(ctx.logs.length<=64&&ctx.logs.every(row=>typeof row.msg==='string'&&row.msg.length<=2048),'diagnostic-log-limit');
  const current={...item,stages:capture.stages,instrumentedTileSha256:sha(payload),uninstrumentedReplayIdentical:true,summary,logs:ctx.logs};
  const output=Buffer.from(JSON.stringify(current));budget.encoded(output.length);
  return {output,record:{...item,tileDataSha256:sha(payload),diagnosticFile:'site-'+item.site.name+'.json',diagnosticSha256:sha(output),bytes:output.length,summary}};
 }finally{
  instrumented?.data?.destroy();control?.data?.destroy();core.Raw.Module.destroy(ctx.raw);core.Raw.Module.destroy(controlCtx.raw);
 }
}
function geometryArrays(core,generators,input){
 const vertices=new core.VerticesArray(),indices=new core.TrianglesArray(),chunky=new core.RecastChunkyTriMesh();let rcConfig;
 try{
  vertices.copy(input.geometry.positions.map((v,i)=>v-input.grid.origin[i%3]));indices.copy(input.geometry.indices);
  ensure(chunky.init(vertices,indices,input.geometry.indices.length/3,256),'chunky-build-failed');
  const config=generators.buildTiledNavMeshRcConfig({recastConfig:{...generators.tiledNavMeshGeneratorConfigDefaults,...input.grid.config},navMeshBounds:input.grid.config.bounds});rcConfig=config.config;
  ensure(config.tcs===input.grid.tcs&&config.tileWidth===input.grid.width&&config.tileHeight===input.grid.height
   &&config.gridSize.width===input.grid.gridWidth&&config.gridSize.height===input.grid.gridHeight
   &&rcConfig.width*rcConfig.height<=LIMITS.cells,'computed-grid-mismatch');
  return {vertices,indices,chunky,rcConfig};
 }catch(error){vertices.destroy();indices.destroy();core.Raw.Module.destroy(chunky.raw);if(rcConfig)core.Raw.Module.destroy(rcConfig);throw error;}
}
function receiptFor(input,results,budget){
 const scriptHashes={};for(const name of ['inspect_stages.mjs','stage_contract.mjs','stage_io.mjs','stage_capture.mjs'])scriptHashes[name]=sha(readBound(path.join(HERE,name),65536).bytes);
 return {format:'rikui-recast-stage-diagnostic-v1',status:'diagnostic-only',nativeVerified:false,shippingChanged:false,
 inputs:input.inputs,moduleRoot:input.modules.root,moduleHashes:input.modules.hashes,scriptHashes,
 identity:input.manifest.identity,origin:input.grid.origin,config:input.grid.config,limits:LIMITS,
 totalDiagnosticBytes:budget.actual,results:results.map(row=>row.record),limitations:[
 'Static offline model only; no profile changes, endpoint snapping or inferred portals.',
 'The modelY input is a diagnostic floor reference, never an observed player floor.',
 'Rasterized spans have no triangle IDs; attribution requires separate geometric evidence.',
 'Snapshot row/serialized-byte limits are resource bounds, not a JavaScript heap-memory guarantee.',
 'No game files, deployed model, settings or runtime guidance are modified.']};
}
export async function run(args){
 const input=preflight(args);
 const core=await import(pathToFileURL(input.modules.core)),generators=await import(pathToFileURL(input.modules.generators));
 const wasm=(await import(pathToFileURL(input.modules.wasm))).default;await core.init(wasm);
 const shared=geometryArrays(core,generators,input),budget=new SnapshotBudget();let results;
 try{results=input.sites.map(item=>buildSite(core,generators,input,shared,item,budget));}
 finally{shared.vertices.destroy();shared.indices.destroy();core.Raw.Module.destroy(shared.chunky.raw);core.Raw.Module.destroy(shared.rcConfig);}
 const receipt=Buffer.from(JSON.stringify(receiptFor(input,results,budget),null,2)+'\n');ensure(receipt.length<=1024*1024,'receipt-byte-limit');
 // No output is created until all inputs, snapshots and control builds pass.
 newOutput(input.output);fs.mkdirSync(input.output);
 for(const row of results)fs.writeFileSync(path.join(input.output,row.record.diagnosticFile),row.output,{flag:'wx'});
 fs.writeFileSync(path.join(input.output,'stage-receipt.json'),receipt,{flag:'wx'});
 return {output:input.output,sites:results.length,diagnosticBytes:budget.actual,receiptSHA256:sha(receipt)};
}
const entryPath=value=>process.platform==='win32'?path.toNamespacedPath(path.resolve(value)).toLowerCase():path.resolve(value);
if(process.argv[1]&&entryPath(process.argv[1])===entryPath(fileURLToPath(import.meta.url))){
 try{console.log(JSON.stringify(await run(argumentsFor(process.argv.slice(2)))));}catch(error){console.error(error.message);process.exitCode=1;}
}
