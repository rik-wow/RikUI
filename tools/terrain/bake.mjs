// Offline proof only. Runtime publication is gated by geometry coverage metadata.
import fs from 'node:fs';
import crypto from 'node:crypto';
import { init, NavMeshQuery, exportNavMesh } from 'recast-navigation';
import { generateSoloNavMesh } from 'recast-navigation/generators';
const [input='geometry.json', output='nav-region.json'] = process.argv.slice(2);
const bytes=fs.readFileSync(input);
if(bytes.length>8*1024*1024) throw Error('geometry-size');
const g=JSON.parse(bytes);
if(g.format!=='rikui-navigation-geometry-probe-v1' || g.positions.length>30000 || g.indices.length>100000) throw Error('geometry-contract');
if(g.positions.length%3 || g.indices.length%3 || !g.positions.every(Number.isFinite) || !g.indices.every(i=>Number.isInteger(i)&&i>=0&&i<g.positions.length/3)) throw Error('geometry-index');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
const min=[Infinity,Infinity,Infinity],max=[-Infinity,-Infinity,-Infinity];
for(let i=0;i<g.positions.length;i++) {let axis=i%3;min[axis]=Math.min(min[axis],g.positions[i]);max[axis]=Math.max(max[axis],g.positions[i]);}
const origin=min.map((v,i)=>(v+max[i])/2);
const positions=g.positions.map((v,i)=>v-origin[i%3]);
const config={cs:0.5,ch:0.1,walkableSlopeAngle:40,walkableHeight:18,walkableClimb:3,walkableRadius:1,minRegionArea:0,mergeRegionArea:0,maxSimplificationError:1.3,maxVertsPerPoly:6};
if(g.regionBounds){config.bounds=[g.regionBounds[0].map((v,i)=>(i===1?min[i]:v)-origin[i]),g.regionBounds[1].map((v,i)=>(i===1?max[i]:v)-origin[i])];}
await init();
const start=performance.now();
const result=generateSoloNavMesh(positions,g.indices,config);
if(!result.success) throw Error('navmesh-generation-failed');
const nav=result.navMesh,polygons=[];
const round=v=>Math.round(v*10000)/10000;
const vector=(tile,i)=>[0,1,2].map(axis=>round(tile.verts(i*3+axis)+origin[axis]));
for(let ti=0;ti<nav.getMaxTiles();ti++) {
 const tile=nav.getTile(ti),header=tile.header();
 if(!header) continue;
 if(ti!==0) throw Error('unexpected-multiple-tiles');
 for(let pi=0;pi<header.polyCount();pi++) {
  const poly=tile.polys(pi),points=[];
  for(let vi=0;vi<poly.vertCount();vi++) points.push(vector(tile,poly.verts(vi)));
  const center=[0,1,2].map(axis=>round(points.reduce((s,p)=>s+p[axis],0)/points.length));
  const portals=[];
  for(let vi=0;vi<points.length;vi++) {
   const neighbor=poly.neis(vi);
   if(neighbor && !(neighbor&0x8000)) portals.push({to:neighbor-1,left:points[vi],right:points[(vi+1)%points.length]});
  }
  polygons.push({id:pi,center,points,portals});
 }
}
if(polygons.length>512) throw Error('compact-region-polygon-cap');
let edges=0;
for(const p of polygons) for(const portal of p.portals) {
 if(!polygons[portal.to]) throw Error('invalid-neighbor');
 const reverse=polygons[portal.to].portals.some(e=>e.to===p.id);
 if(!reverse) throw Error('missing-reciprocal-ground-portal');
 const midpoint=portal.left.map((v,i)=>(v+portal.right[i])/2);
 portal.meters=round(Math.hypot(...p.center.map((v,i)=>v-midpoint[i]))+Math.hypot(...polygons[portal.to].center.map((v,i)=>v-midpoint[i])));
 edges++;
}
if(edges>2048) throw Error('compact-region-edge-cap');
// Choose a same-component query by explicit graph reachability, not proximity.
const components=[],seen=new Set();
for(const p of polygons) {
 if(seen.has(p.id)) continue;
 const component=[],queue=[p.id];seen.add(p.id);
 for(let at=0;at<queue.length;at++) {const id=queue[at];component.push(id);for(const e of polygons[id].portals) if(!seen.has(e.to)){seen.add(e.to);queue.push(e.to);}}
 components.push(component);
}
components.sort((a,b)=>b.length-a.length || a[0]-b[0]);
const query=new NavMeshQuery(nav);
let probe=null;
if(components[0]?.length>1) {
 const ids=components[0],a=polygons[ids[0]].center;
 const endID=ids.slice().sort((u,v)=>Math.hypot(...polygons[v].center.map((n,i)=>n-a[i]))-Math.hypot(...polygons[u].center.map((n,i)=>n-a[i])) || u-v)[0];
 const b=polygons[endID].center;
 const local=p=>({x:p[0]-origin[0],y:p[1]-origin[1],z:p[2]-origin[2]});
 const found=query.computePath(local(a),local(b));
 probe={success:found.success,from:ids[0],to:endID,error:found.error??null,path:(found.path??[]).map(p=>[p.x+origin[0],p.y+origin[1],p.z+origin[2]].map(round))};
}
const binary=exportNavMesh(nav);
fs.writeFileSync(output.replace(/\.json$/,'.bin'),binary);
const outputData={format:'rikui-navigation-region-probe-v1',identity:g.identity,mapID:g.mapID,tile:g.tile,
 status:g.status,publishable:false,coverage:g.coverage,limitations:g.limitations,
 source:g.source,collisionAudit:g.collisionAudit,geometrySha256:hash(bytes),generator:{wrapperSHA256:hash(fs.readFileSync(new URL(import.meta.url))),package:'recast-navigation',version:'0.43.1',
 repositoryCommit:'8769e8b9995f127033af9f6e6eeac3fad7d66201',recastForkCommit:'599fd0f023181c0a484df2a18cf1d75a3553852e',
 config,agentProfile:'UNVERIFIED engineering sample:1.8m height,0.5m radius,0.3m climb,40deg slope'},
 coordinateSystem:g.coordinateSystem,bounds:g.regionBounds?{min:g.regionBounds[0],max:g.regionBounds[1]}:{min,max},origin,statistics:{...g.statistics,polygons:polygons.length,
 directedEdges:edges,components:components.map(c=>c.length),binaryBytes:binary.byteLength},
 navmeshSha256:hash(binary),polygons,probe};
fs.writeFileSync(output,JSON.stringify(outputData));
console.log(JSON.stringify({output,sha256:hash(fs.readFileSync(output)),status:outputData.status,publishable:outputData.publishable,statistics:outputData.statistics,bakeMilliseconds:performance.now()-start,probe}));
query.destroy();nav.destroy();
