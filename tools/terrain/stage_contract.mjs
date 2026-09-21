// Pure, bounded contracts for an offline diagnostic; never runtime navigation input.
import crypto from 'node:crypto';
export const LIMITS=Object.freeze({manifestBytes:4*1024*1024,geometryBytes:32*1024*1024,
 sitesBytes:8192,positions:600000,indices:2000000,sites:4,cells:20000,spans:200000,
 perCell:128,stages:10,fileBytes:24*1024*1024,aggregateBytes:96*1024*1024});
export const PROFILE=Object.freeze({cs:.5,ch:.1,tileSize:128,walkableHeight:18,walkableClimb:3,
 walkableRadius:1,walkableSlopeAngle:40,minRegionArea:0,mergeRegionArea:0,maxSimplificationError:1.3,maxVertsPerPoly:6});
export const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
export function ensure(ok,reason){if(!ok)throw Error(reason);}
export function plain(value){return value!==null&&typeof value==='object'&&!Array.isArray(value)&&Object.getPrototypeOf(value)===Object.prototype;}
export function integer(value,low,high){return Number.isSafeInteger(value)&&value>=low&&value<=high;}
export function vector(value){return Array.isArray(value)&&value.length===3&&value.every(v=>Number.isFinite(v)&&Math.abs(v)<=100000);}
export function box(value){return Array.isArray(value)&&value.length===2&&value.every(vector)&&value[0].every((v,i)=>v<value[1][i]);}
export function sameVector(a,b){return vector(a)&&vector(b)&&a.every((v,i)=>Math.abs(v-b[i])<=1e-9);}
export function exactKeys(value,keys){return plain(value)&&Object.keys(value).length===keys.length&&keys.every(k=>Object.hasOwn(value,k));}
export function parseJSON(bytes,maximum,label){
 ensure(bytes.length<=maximum,label+'-byte-limit');
 try{return JSON.parse(bytes.toString('utf8'));}catch{throw Error(label+'-invalid-json');}
}
// Match pinned rcCalcGridSize float32 rounding before deriving tile counts.
export function gridDimensions(bounds,cs,tileSize){
 const cells=axis=>Math.trunc(Math.fround(Math.fround(Math.fround(Math.fround(bounds[1][axis])-Math.fround(bounds[0][axis]))/Math.fround(cs))+.5));
 const gridWidth=cells(0),gridHeight=cells(2);
 return {gridWidth,gridHeight,width:Math.floor((gridWidth+tileSize-1)/tileSize),height:Math.floor((gridHeight+tileSize-1)/tileSize)};
}
export function validateManifest(m){
 ensure(plain(m)&&['rikui-nav-region-proof-v1','rikui-nav-tile-proof-v1'].includes(m.format),'manifest-format');
 ensure(exactKeys(m.identity,['product','edition','build','locale'])&&m.identity.product==='wow_classic_beta'
  &&m.identity.edition==='Forever'&&typeof m.identity.build==='string'&&typeof m.identity.locale==='string'&&/^1\.60\.\d+\.\d+$/.test(m.identity.build)&&/^[a-z]{2}[A-Z]{2}$/.test(m.identity.locale),'manifest-identity');
 ensure(/^[0-9a-f]{64}$/.test(m.geometrySha256??''),'geometry-hash-shape');
 const g=m.generator,c=g?.config;
 ensure(g?.package==='recast-navigation'&&g.version==='0.43.1'
  &&g.repositoryCommit==='8769e8b9995f127033af9f6e6eeac3fad7d66201'
  &&g.recastForkCommit==='599fd0f023181c0a484df2a18cf1d75a3553852e','generator-revision');
 ensure(exactKeys(c,[...Object.keys(PROFILE),'bounds'])&&Object.entries(PROFILE).every(([k,v])=>c[k]===v),'unsupported-profile');
 ensure(vector(m.origin)&&box(c.bounds)&&box([m.bounds?.min,m.bounds?.max]),'manifest-bounds');
 ensure(m.publishable===false&&m.coverage?.nativeTraversalVerified===false&&g.agentProfileNativeVerified===false,'unexpected-native-claims');
 const tcs=c.cs*c.tileSize,{width,height,gridWidth,gridHeight}=gridDimensions(c.bounds,c.cs,c.tileSize);
 ensure(integer(width,1,128)&&integer(height,1,128)&&width*height<=128,'tile-grid-limit');
 return {origin:[...m.origin],config:structuredClone(c),tcs,width,height,gridWidth,gridHeight};
}
export function validateGeometry(g,m){
 ensure(plain(g)&&g.format==='rikui-navigation-geometry-probe-v1'&&plain(g.identity),'geometry-format');
 ensure(Object.keys(m.identity).every(k=>g.identity[k]===m.identity[k]),'geometry-identity');
 ensure(Array.isArray(g.positions)&&g.positions.length>0&&g.positions.length<=LIMITS.positions&&g.positions.length%3===0,'geometry-position-count');
 ensure(Array.isArray(g.indices)&&g.indices.length>0&&g.indices.length<=LIMITS.indices&&g.indices.length%3===0,'geometry-index-count');
 const low=[Infinity,Infinity,Infinity],high=[-Infinity,-Infinity,-Infinity];
 for(let i=0;i<g.positions.length;i++){const v=g.positions[i],a=i%3;ensure(Number.isFinite(v)&&Math.abs(v)<=100000,'geometry-position');low[a]=Math.min(low[a],v);high[a]=Math.max(high[a],v);}
 ensure(g.indices.every(v=>integer(v,0,g.positions.length/3-1)),'geometry-index');
 ensure(box(g.regionBounds)&&sameVector(g.regionBounds[0],m.bounds.min)&&sameVector(g.regionBounds[1],m.bounds.max),'geometry-region-bounds');
 ensure(sameVector(low.map((v,i)=>(v+high[i])/2),m.origin),'geometry-origin');
 const expected=[g.regionBounds[0].map((v,i)=>(i===1?low[i]:v)-m.origin[i]),g.regionBounds[1].map((v,i)=>(i===1?high[i]:v)-m.origin[i])];
 ensure(sameVector(expected[0],m.generator.config.bounds[0])&&sameVector(expected[1],m.generator.config.bounds[1]),'geometry-grid-bounds');
 return {low,high};
}
export function tileFor(site,m,grid){
 const x=Math.floor((site.x-m.origin[0]-grid.config.bounds[0][0])/grid.tcs);
 const y=Math.floor((site.z-m.origin[2]-grid.config.bounds[0][2])/grid.tcs);
 ensure(integer(x,0,grid.width-1)&&integer(y,0,grid.height-1),'site-tile-outside-grid');
 const c=grid.config.bounds,t=grid.tcs;
 return {x,y,bmin:[c[0][0]+x*t,c[0][1],c[0][2]+y*t],bmax:[c[0][0]+(x+1)*t,c[1][1],c[0][2]+(y+1)*t]};
}
export function validateSites(sites,m,grid){
 ensure(Array.isArray(sites)&&sites.length>0&&sites.length<=LIMITS.sites,'site-count');
 const names=new Set();return sites.map(site=>{
  ensure(exactKeys(site,['name','x','z','modelY'])&&typeof site.name==='string'&&/^[a-z][a-z0-9_-]{0,47}$/.test(site.name),'site-shape');
  ensure(!names.has(site.name),'duplicate-site-name');names.add(site.name);
  ensure([site.x,site.z,site.modelY].every(Number.isFinite),'site-nonfinite');
  ensure(site.x>=m.bounds.min[0]&&site.x<m.bounds.max[0]&&site.z>=m.bounds.min[2]&&site.z<m.bounds.max[2]
   &&site.modelY>=m.bounds.min[1]&&site.modelY<=m.bounds.max[1],'site-outside-source-bounds');
  return {site:{...site},tile:tileFor(site,m,grid)};
 });
}
export function stageShape(meta,spans){
 ensure(integer(meta.width,1,LIMITS.cells)&&integer(meta.height,1,LIMITS.cells)&&meta.width*meta.height<=LIMITS.cells,'stage-cell-limit');
 ensure(Number.isFinite(meta.cs)&&meta.cs>0&&Number.isFinite(meta.ch)&&meta.ch>0&&vector(meta.worldMin),'stage-metadata');
 if(spans!==undefined)ensure(integer(spans,0,LIMITS.spans),'stage-span-limit');
}
export class SnapshotBudget{
 constructor(){this.total=0;this.files=0;this.actual=0;}
 begin(){ensure(++this.files<=LIMITS.sites,'snapshot-file-limit');this.file=1024*1024;this.stages=0;this.total+=this.file;}
 stage(){ensure(++this.stages<=LIMITS.stages,'snapshot-stage-limit');this.add(2048);}
 add(bytes){ensure(integer(bytes,0,LIMITS.fileBytes),'snapshot-charge');this.file+=bytes;this.total+=bytes;
  ensure(this.file<=LIMITS.fileBytes&&this.total<=LIMITS.aggregateBytes,'snapshot-serialized-budget');}
 row(value){this.add(Buffer.byteLength(JSON.stringify(value))+1);}
 encoded(bytes){ensure(integer(bytes,0,LIMITS.fileBytes),'diagnostic-file-limit');this.actual+=bytes;ensure(this.actual<=LIMITS.aggregateBytes,'diagnostic-aggregate-limit');}
}
// Restores partial installations as well as failures within the callback.
export function withHooks(target,wrappers,work){
 const originals=[];
 try{for(const [key,wrap] of Object.entries(wrappers)){
  ensure(typeof target[key]==='function','hook-target-missing:'+key);const original=target[key];
  originals.push([key,original]);target[key]=wrap(original);
 }return work();}finally{for(const [key,original] of originals.reverse())target[key]=original;}
}
