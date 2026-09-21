// Full-tile offline Recast proof. Generated shards remain explicitly unverified.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {init,NavMeshQuery,exportNavMesh} from 'recast-navigation';
import {generateTiledNavMesh} from 'recast-navigation/generators';
import {hasHorizontalArea,removeBlockedPortals,clipPortalToTarget} from './mesh_filter.mjs';
const [input='geometry-full-m2.json',outdir='full-tile',resolution,profile] = process.argv.slice(2);
if(resolution!==undefined&&resolution!=='--half-cell')throw Error('unsupported-resolution');
if(profile!==undefined&&(profile!=='--reference-step'||resolution!=='--half-cell'))throw Error('unsupported-agent-profile');
const bytes=fs.readFileSync(input);
if(bytes.length>64*1024*1024) throw Error('input-byte-budget');
const g=JSON.parse(bytes);
if(g.format!=='rikui-navigation-geometry-probe-v1'||g.positions.length>1500000||g.indices.length>2000000) throw Error('geometry-budget');
if(g.positions.length%3||g.indices.length%3||!g.positions.every(Number.isFinite)||!g.indices.every(v=>Number.isInteger(v)&&v>=0&&v<g.positions.length/3))throw Error('geometry-shape');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const round=v=>Math.round(v*10000)/10000;
const min=[Infinity,Infinity,Infinity],max=[-Infinity,-Infinity,-Infinity];
for(let i=0;i<g.positions.length;i++){const a=i%3;min[a]=Math.min(min[a],g.positions[i]);max[a]=Math.max(max[a],g.positions[i]);}
const region=g.regionBounds??[min,max];
const origin=min.map((v,i)=>(v+max[i])/2);
const config={cs:0.5,ch:0.1,tileSize:128,walkableHeight:18,walkableClimb:3,walkableRadius:1,
 walkableSlopeAngle:40,minRegionArea:0,mergeRegionArea:0,maxSimplificationError:1.3,maxVertsPerPoly:6,
 bounds:[region[0].map((v,i)=>(i===1?min[i]:v)-origin[i]),region[1].map((v,i)=>(i===1?max[i]:v)-origin[i])]};
// Half-cell keeps the 64-yard tile and physical radius/height/climb/slope unchanged.
if(resolution==='--half-cell')Object.assign(config,{cs:.25,tileSize:256,walkableRadius:2});
// Explicit reference hypothesis, not Forever calibration; see MOVEMENT.md.
// Classic reference 4 * .2666666 yards, rounded down to 1 yard on this grid.
if(profile==='--reference-step')config.walkableClimb=10;
await init();const started=performance.now();
const result=generateTiledNavMesh(g.positions.map((v,i)=>v-origin[i%3]),g.indices,config);
if(!result.success)throw Error('bake-failed');
const nav=result.navMesh,byRef=new Map(),shards=[];
const exclusions=[...(g.exclusions??[]),...(g.terrainExclusions??[])];
if(exclusions.length>64)throw Error('exclusion-budget');
for(const box of exclusions)if(box.bounds?.length!==2||!box.bounds.every(p=>p.length===3&&p.every(Number.isFinite))||!Number.isFinite(box.padding)||box.padding<0||box.padding>10)throw Error('exclusion-shape');
const excludedIDs=[],degeneratePolygons=[];
let outsideSourceRegionPolygons=0;
let edges=0;
for(let ti=0;ti<nav.getMaxTiles();ti++){
 const tile=nav.getTile(ti),header=tile.header();if(!header)continue;
 if(header.polyCount()>1024)throw Error('shard-polygon-budget');
 const base=nav.getPolyRefBase(tile)>>>0,polygons=[];
 const vertex=i=>[0,1,2].map(a=>tile.verts(i*3+a)+origin[a]);
 for(let pi=0;pi<header.polyCount();pi++){
  const poly=tile.polys(pi);if(poly.getType()!==0)throw Error('unexpected-offmesh-connection');
  const points=[];for(let vi=0;vi<poly.vertCount();vi++)points.push(vertex(poly.verts(vi)));
  const center=[0,1,2].map(a=>points.reduce((s,p)=>s+p[a],0)/points.length);
  const portals=[];let link=poly.firstLink()>>>0,count=0;
  while(link!==0xffffffff){
   if(link>=header.maxLinkCount()||++count>32)throw Error('link-budget:'+JSON.stringify({link,maximum:header.maxLinkCount(),count,ti,pi}));
   const edge=tile.links(link);link=edge.next()>>>0;const to=edge.ref()>>>0;if(!to)continue;
   if(edge.edge()>=points.length)throw Error('portal-edge');
   let left=points[edge.edge()],right=points[(edge.edge()+1)%points.length];
   if(edge.side()!==255){const a=edge.bmin()/255,b=edge.bmax()/255,p=left,q=right;left=p.map((v,i)=>v+(q[i]-v)*a);right=p.map((v,i)=>v+(q[i]-v)*b);}
   portals.push({to,left:left.map(round),right:right.map(round)});
  }
  portals.sort((a,b)=>a.to-b.to);
  const row={id:base+pi,center:center.map(round),points:points.map(p=>p.map(round)),portals};
  if(byRef.has(row.id))throw Error('duplicate-polygon-ref');
  // Deliberately conservative polygon AABB exclusion, including touching bounds.
  const denied=exclusions.some(box=>[0,2].every(a=>Math.max(...points.map(p=>p[a]))>=box.bounds[0][a]-box.padding&&Math.min(...points.map(p=>p[a]))<=box.bounds[1][a]+box.padding));
  // Recast rounds the last shard to tileSize cells; source collision models can
  // protrude beyond the source ADT. Never admit that unsourced outer strip.
  const outside=points.some(p=>[0,2].some(a=>p[a]<region[0][a]-0.0001||p[a]>region[1][a]+0.0001));
  const degenerate=!hasHorizontalArea(row.points);
  if(degenerate)degeneratePolygons.push({id:row.id,reason:'degenerate-horizontal-projection',points:row.points});
  if(denied||outside||degenerate){excludedIDs.push(row.id);if(outside)outsideSourceRegionPolygons++;continue;}
  byRef.set(row.id,row);polygons.push(row);
 }
 const count=polygons.reduce((s,p)=>s+p.portals.length,0);if(count>4096)throw Error('shard-edge-budget');
 edges+=count;shards.push({id:ti,grid:[header.x(),header.y(),header.layer()],polygons});
}
const blocked=new Set(excludedIDs);
edges=0;
for(const shard of shards)for(const poly of shard.polygons){poly.portals=removeBlockedPortals(poly.portals,blocked);edges+=poly.portals.length;}
if(shards.length>512||byRef.size>65536||edges>262144)throw Error('whole-tile-budget');
let clippedPortals=0;
for(const poly of byRef.values())for(const portal of poly.portals){
 const target=byRef.get(portal.to);if(!target)throw Error('dangling-portal');
 const clipped=clipPortalToTarget(portal,target.points);if(!clipped)throw Error('no-shared-portal-interval');
 if(JSON.stringify([portal.left,portal.right])!==JSON.stringify([clipped.left,clipped.right]))clippedPortals++;
 portal.left=clipped.left;portal.right=clipped.right;
 if(!target.portals.some(p=>p.to===poly.id))throw Error('one-way-walk-portal');
 const middle=portal.left.map((v,i)=>(v+portal.right[i])/2);
 portal.meters=round(Math.hypot(...poly.center.map((v,i)=>v-middle[i]))+Math.hypot(...target.center.map((v,i)=>v-middle[i])));
}
const seen=new Set(),components=[];
for(const poly of byRef.values()){
 if(seen.has(poly.id))continue;const todo=[poly.id];seen.add(poly.id);
 for(let at=0;at<todo.length;at++)for(const portal of byRef.get(todo[at]).portals)if(!seen.has(portal.to)){seen.add(portal.to);todo.push(portal.to);}
 components.push(todo);
}
components.sort((a,b)=>b.length-a.length||a[0]-b[0]);
const probes=[];
function modelPath(from,to){
 const dist=new Map([[from,0]]),previous=new Map(),heap=[];
 const less=(a,b)=>a.cost<b.cost||a.cost===b.cost&&a.id<b.id;
 const push=value=>{let i=heap.length;heap.push(value);while(i){const p=(i-1)>>1;if(!less(value,heap[p]))break;heap[i]=heap[p];i=p;}heap[i]=value;};
 const pop=()=>{const top=heap[0],tail=heap.pop();if(heap.length){let i=0;while(i*2+1<heap.length){let child=i*2+1;if(child+1<heap.length&&less(heap[child+1],heap[child]))child++;if(!less(heap[child],tail))break;heap[i]=heap[child];i=child;}heap[i]=tail;}return top;};
 push({id:from,cost:0});let pops=0;
 while(heap.length){
  if(++pops>131072)throw Error('model-query-budget');
  const at=pop();if(at.cost!==dist.get(at.id))continue;if(at.id===to)break;
  for(const portal of byRef.get(at.id).portals){const cost=at.cost+portal.meters;if(cost<(dist.get(portal.to)??Infinity)){dist.set(portal.to,cost);previous.set(portal.to,{id:at.id,portal});push({id:portal.to,cost});}}
 }
 if(!dist.has(to))return{success:false,path:[],error:'disconnected-filtered-graph'};
 const links=[];let id=to;while(id!==from){const step=previous.get(id);if(!step)throw Error('model-parent');links.push({to:id,...step});id=step.id;}
 links.reverse();const points=[byRef.get(from).center];for(const step of links){points.push(step.portal.left.map((v,a)=>round((v+step.portal.right[a])/2)),byRef.get(step.to).center);}
 return{success:true,path:points,meters:dist.get(to),polygonPath:[from,...links.map(s=>s.to)],error:null};
}
for(const component of components.slice(0,3)){
 if(component.length<2)continue;
 const start=byRef.get(component[0]).center;
 const far=component.reduce((best,id)=>{const p=byRef.get(id).center;return Math.hypot(...p.map((v,i)=>v-start[i]))>best.distance?{id,distance:Math.hypot(...p.map((v,i)=>v-start[i]))}:best;},{id:component[0],distance:0});
 const goal=byRef.get(far.id).center;
 const found=modelPath(component[0],far.id);
 const points=found.path;
 const last=points.at(-1);const endpointError=last?Math.hypot(...last.map((v,i)=>v-goal[i])):null;
 probes.push({success:found.success,from:component[0],to:far.id,componentPolygons:component.length,
  endpointError,path:points,meters:found.meters,polygonPath:found.polygonPath,error:found.error??null});
}
// This region has real source on both sides of the ADT seam; demonstrate a path using only baked portals.
if(g.tiles){
 const audit=g.source.tileAudit,west=audit.find(r=>r.tile[0]===32&&r.tile[1]===42),east=audit.find(r=>r.tile[0]===33&&r.tile[1]===42);
 const seam=(west.bounds[0][0]+east.bounds[1][0])/2;
 const centerZ=(region[0][2]+region[1][2])/2,component=components[0];
 const nearest=side=>component.filter(id=>side*(byRef.get(id).center[0]-seam)>8).reduce((best,id)=>{
  const p=byRef.get(id).center,cost=Math.hypot(p[0]-seam,p[2]-centerZ);
  return !best||cost<best.cost?{id,cost}:best;
 },null);
 const from=nearest(-1),to=nearest(1);if(!from||!to)throw Error('missing-cross-source-seam-endpoints');
 const found=modelPath(from.id,to.id);if(!found.success)throw Error('no-cross-source-seam-model-path');
 const goal=byRef.get(to.id).center,last=found.path.at(-1);
 probes.push({kind:'cross-source-tile-seam',sourceTiles:[[33,42],[32,42]],success:true,from:from.id,to:to.id,
  componentPolygons:component.length,endpointError:Math.hypot(...last.map((v,i)=>v-goal[i])),path:found.path,
  meters:found.meters,polygonPath:found.polygonPath,error:null});
}
fs.mkdirSync(outdir,{recursive:true});
const binary=exportNavMesh(nav);fs.writeFileSync(path.join(outdir,'navmesh.bin'),binary);
const entries=[];
for(const shard of shards){
 const filename=`region-${shard.grid.join('-')}.json`;
 const artifact={format:'rikui-nav-shard-v1',identity:g.identity,mapID:g.mapID,
  status:'derived-pending-validation',publishable:false,id:shard.id,grid:shard.grid,polygons:shard.polygons};
 const data=Buffer.from(JSON.stringify(artifact));if(data.length>524288)throw Error('shard-byte-budget');
 fs.writeFileSync(path.join(outdir,filename),data);
 entries.push({filename,sha256:sha(data),bytes:data.length,id:shard.id,grid:shard.grid,
  polygons:shard.polygons.length,directedEdges:shard.polygons.reduce((s,p)=>s+p.portals.length,0)});
}
const manifest={format:g.tiles?'rikui-nav-region-proof-v1':'rikui-nav-tile-proof-v1',identity:g.identity,mapID:g.mapID,
 ...(g.tiles?{regionID:g.regionID,tiles:g.tiles}:{tile:g.tile}),
 status:'derived-pending-validation',publishable:false,geometryStatus:g.status,coverage:g.coverage,
 clippedPortals,collisionAudit:g.collisionAudit,wmoAudit:g.wmoAudit,exclusions:g.exclusions??[],terrainExclusions:g.terrainExclusions??[],coverageGates:g.coverageGates,degeneratePolygons,
 coverageScope:exclusions.length?'outside-exclusions':'whole-source-region',
 limitations:g.limitations,source:g.source,
 geometrySha256:sha(bytes),navmeshSha256:sha(binary),coordinateSystem:g.coordinateSystem,
 bounds:{min:region[0],max:region[1]},origin,
 generator:{wrapperSHA256:sha(fs.readFileSync(new URL(import.meta.url))),filterSHA256:sha(fs.readFileSync(new URL('./mesh_filter.mjs',import.meta.url))),package:'recast-navigation',version:'0.43.1',repositoryCommit:'8769e8b9995f127033af9f6e6eeac3fad7d66201',
 recastForkCommit:'599fd0f023181c0a484df2a18cf1d75a3553852e',config,agentProfileNativeVerified:false,
 ...(profile?{agentProfile:'classic-reference-step-v1'}:{})},
 statistics:{inputVertices:g.positions.length/3,inputTriangles:g.indices.length/3,
 regions:shards.length,polygons:byRef.size,directedEdges:edges,excludedPolygons:excludedIDs.length,outsideSourceRegionPolygons,degeneratePolygonsRemoved:degeneratePolygons.length,components:components.map(c=>c.length),
 binaryBytes:binary.length,jsonShardBytes:entries.reduce((s,e)=>s+e.bytes,0)},regions:entries,probes};
const data=Buffer.from(JSON.stringify(manifest));fs.writeFileSync(path.join(outdir,'manifest.json'),data);
console.log(JSON.stringify({outdir,sha256:sha(data),statistics:manifest.statistics,
 probes:probes.map(p=>({success:p.success,from:p.from,to:p.to,points:p.path.length,endpointError:p.endpointError})),milliseconds:performance.now()-started}));
nav.destroy();
