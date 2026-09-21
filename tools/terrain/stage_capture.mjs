import {LIMITS,ensure,integer,stageShape,withHooks} from './stage_contract.mjs';
const TYPES=['Heightfield','CompactHeightfield','ContourSet','PolyMesh','PolyMeshDetail'];
// Tracks native intermediates even if a generator or observer fails before return.
export function trackedBuild(core,observers,work){
 const target=core.Raw.Recast,live=new Map(),wrappers={...observers},free=new Map();
 for(const type of TYPES){const allocate='alloc'+type,release='free'+type;free.set(release,target[release]);
  wrappers[allocate]=fn=>function(...args){const raw=fn.apply(this,args);if(!core.Raw.isNull(raw))live.set(core.Raw.Module.getPointer(raw),{release,raw});return raw;};
  wrappers[release]=fn=>function(raw){const value=fn.call(this,raw);live.delete(core.Raw.Module.getPointer(raw));return value;};
 }
 let result,failure;
 try{result=withHooks(target,wrappers,work);}catch(error){failure=error;}
 for(const {release,raw} of live.values())try{free.get(release).call(target,raw);}catch(error){failure??=error;}
 if(failure)throw failure;return result;
}
function metadata(field,origin){
 const b=field.bmin(),meta={width:field.width(),height:field.height(),cs:field.cs(),ch:field.ch(),worldMin:[b.x+origin[0],b.y+origin[1],b.z+origin[2]]};
 stageShape(meta);return meta;
}
function solidRows(field,meta,core,budget){
 const cells=[];let total=0,walkable=0;
 for(let i=0;i<meta.width*meta.height;i++){
  let span=field.spans(i);if(core.Raw.isNull(span.raw))continue;const rows=[];
  for(let n=0;span;n++,span=span.next()){
   ensure(n<LIMITS.perCell&&++total<=LIMITS.spans,'solid-span-limit');
   const row=[span.smin(),span.smax(),span.area()];
   ensure(row.every(v=>integer(v,0,65535))&&row[0]<=row[1],'solid-span-shape');
   budget.row(row);rows.push(row);if(row[2]!==core.Recast.RC_NULL_AREA)walkable++;
  }budget.row([i]);cells.push([i,rows]);
 }return {total,walkable,cells};
}
function compactRows(field,meta,core,budget){
 const rows=[],seen=new Set();let walkable=0;stageShape(meta,field.spanCount());
 for(let cell=0;cell<meta.width*meta.height;cell++){
  const c=field.cells(cell),first=c.index(),count=c.count();
  ensure(integer(first,0,field.spanCount())&&integer(count,0,LIMITS.perCell)&&first+count<=field.spanCount(),'compact-cell-range');
  for(let i=first;i<first+count;i++){
   ensure(!seen.has(i),'compact-overlapping-cells');seen.add(i);const s=field.spans(i);
   const row=[cell,i,s.y(),s.h(),field.areas(i),s.reg(),...[0,1,2,3].map(d=>core.getCon(s,d))];
   ensure(row.slice(2,6).every(v=>integer(v,0,65535))&&row.slice(6).every(v=>integer(v,0,core.Recast.RC_NOT_CONNECTED)),'compact-span-shape');
   budget.row(row);rows.push(row);if(row[4]!==core.Recast.RC_NULL_AREA)walkable++;
  }
 }ensure(rows.length===field.spanCount(),'compact-span-coverage');return {total:rows.length,walkable,rows};
}
export function createCapture(core,grid,budget){
 const stages=[],originalBuild=core.Raw.Recast.buildCompactHeightfield;let failure;
 function compact(raw,label){const f=new core.RecastCompactHeightfield(raw),meta=metadata(f,grid.origin);budget.stage();stages.push({label,kind:'compact',...meta,...compactRows(f,meta,core,budget)});}
 function temporary(raw,label){
  const field=core.allocCompactHeightfield(),ctx=new core.RecastBuildContext();
  try{ensure(originalBuild.call(core.Raw.Recast,ctx.raw,grid.config.walkableHeight,grid.config.walkableClimb,raw,field.raw),'temporary-compaction-failed');compact(field.raw,'temporary-compaction-'+label);}
  finally{core.freeCompactHeightfield(field);core.Raw.Module.destroy(ctx.raw);}
 }
 function solid(raw,label){
  const f=new core.RecastHeightfield(raw),meta=metadata(f,grid.origin);budget.stage();stages.push({label,kind:'solid',...meta,...solidRows(f,meta,core,budget)});
  if(['after-rasterization','after-low-hanging-filter','after-ledge-filter'].includes(label))temporary(raw,label);
 }
 function observe(raw,label,fn){if(!failure)try{fn(raw,label);}catch(error){failure=error;}}
 const specs=[['filterLowHangingWalkableObstacles',2,'after-rasterization','after-low-hanging-filter',solid],
 ['filterLedgeSpans',3,null,'after-ledge-filter',solid],['filterWalkableLowHeightSpans',2,null,'after-clearance-filter',solid],
 ['buildCompactHeightfield',4,null,'after-compaction',compact],['erodeWalkableArea',2,null,'after-radius-erosion',compact],['buildRegions',1,null,'after-region-partition',compact]];
 const observers={};for(const [name,index,before,after,fn] of specs)observers[name]=original=>function(...args){
  if(before)observe(args[index],before,fn);const result=original.apply(this,args);if(after)observe(args[index],after,fn);return result;
 };
 return {stages,observers,assert(){if(failure)throw failure;ensure(stages.length===10,'missing-diagnostic-stages');}};
}
function indexCompact(stage,constants){
 const cells=new Map(),indices=new Set();
 for(const row of stage.rows){
  ensure(integer(row[0],0,stage.width*stage.height-1)&&integer(row[1],0,LIMITS.spans-1)&&!indices.has(row[1]),'compact-row-index');indices.add(row[1]);
  if(!cells.has(row[0]))cells.set(row[0],[]);const list=cells.get(row[0]);ensure(list.length<LIMITS.perCell,'compact-cell-span-limit');list.push(row);
 }
 for(const row of stage.rows)for(let d=0;d<4;d++){
  const con=row[6+d];ensure(integer(con,0,constants.none),'compact-connection-value');if(con===constants.none)continue;
  const x=row[0]%stage.width+constants.dx[d],z=Math.floor(row[0]/stage.width)+constants.dz[d];
  ensure(x>=0&&x<stage.width&&z>=0&&z<stage.height&&(cells.get(z*stage.width+x)?.[con]),'invalid-compact-connection');
 }return cells;
}
function componentsAt(starts,cells,stage,border,constants){
 const components=[];let visits=0;
 for(const start of starts){
  if(start[4]===constants.nullArea){components.push({start:start[1],area:0,size:0,touchesUnpaddedTileBorder:false});continue;}
  const seen=new Set([start[1]]),todo=[start];let touches=false;
  for(let i=0;i<todo.length;i++){
   ensure(++visits<=LIMITS.spans,'component-work-limit');const row=todo[i],x=row[0]%stage.width,z=Math.floor(row[0]/stage.width);
   if(x<=border||z<=border||x>=stage.width-border-1||z>=stage.height-border-1)touches=true;
   for(let d=0;d<4;d++){
    if(row[6+d]===constants.none)continue;const target=cells.get((z+constants.dz[d])*stage.width+x+constants.dx[d])[row[6+d]];
    if(target[4]===constants.nullArea||seen.has(target[1]))continue;seen.add(target[1]);todo.push(target);
   }
  }
  components.push({start:start[1],area:start[4],size:seen.size,touchesUnpaddedTileBorder:touches});
 }return components;
}
export function summarize(stage,site,border,constants){
 stageShape(stage,stage.total);const x=Math.floor((site.x-stage.worldMin[0])/stage.cs),z=Math.floor((site.z-stage.worldMin[2])/stage.cs),cell=z*stage.width+x;
 ensure(x>=0&&x<stage.width&&z>=0&&z<stage.height,'site-outside-stage');
 const result={label:stage.label,total:stage.total,walkable:stage.walkable,cell:[x,z]};
 if(stage.kind==='solid')return {...result,spans:(stage.cells.find(r=>r[0]===cell)?.[1]??[]).map(r=>({bottom:stage.worldMin[1]+r[0]*stage.ch,top:stage.worldMin[1]+r[1]*stage.ch,area:r[2]}))};
 ensure(stage.kind==='compact','unknown-stage-kind');const cells=indexCompact(stage,constants),at=cells.get(cell)??[];
 const floor=at.filter(row=>Math.abs(stage.worldMin[1]+row[2]*stage.ch-site.modelY)<2*stage.ch);
 return {...result,spans:at.map(r=>({index:r[1],floor:stage.worldMin[1]+r[2]*stage.ch,clearance:r[3]*stage.ch,area:r[4],region:r[5],connections:r.slice(6)})),components:componentsAt(floor,cells,stage,border,constants)};
}
