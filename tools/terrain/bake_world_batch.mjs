// Fixed world lattice; independent batches export actual baked portal evidence.
// Neighbour halo rows are witnesses, never a license to connect missing batches.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {init} from 'recast-navigation';
import {generateBoundedTiled} from './world_tiled.mjs';
import {hasHorizontalArea,exclusionLookup,voxelVertex,clipPortalToTarget,pruneStepPortals,pruneFullHeightExcludedTriangles} from './mesh_filter.mjs';
const [input,outdir]=process.argv.slice(2);
if(!input||!outdir||fs.existsSync(outdir))throw Error('new output and input required');
const raw=fs.readFileSync(input);if(raw.length>256*1024*1024)throw Error('geometry-byte-bound');
const g=JSON.parse(raw),j=g.job;
if(g.format!=='rikui-world-geometry-v1'||j?.format!=='rikui-world-bake-job-v1'||g.worldMapID!==j.worldMapID||g.nativeVerified!==false)throw Error('geometry-identity');
if(g.positions.length>4500000||g.indices.length>9000000||g.positions.length%3||g.indices.length%3||!g.positions.every(Number.isFinite)||!g.indices.every(v=>Number.isInteger(v)&&v>=0&&v<g.positions.length/3))throw Error('geometry-arrays');
// Polygon IDs pack the index in 12 bits (road_network.polygon_id, world_stitch).
const POLYS_PER_TILE=4096;
const sha=x=>crypto.createHash('sha256').update(x).digest('hex');
const round=x=>Math.round(x*10000)/10000;
const lattice={origin:[0,0,0],cell:.25,heightCell:.1,recastTileSize:64,batchTiles:8,border:1.25};
if(JSON.stringify(j.lattice)!==JSON.stringify(lattice)){
 for(const key of Object.keys(lattice))if(JSON.stringify(j.lattice[key])!==JSON.stringify(lattice[key]))throw Error('unsupported-lattice');
}
const b=j.bakeXZ,o=j.ownedXZ;
if(b.length!==4||o.length!==4||b.some((v,i)=>v!==o[i]+(i<2?-64:64))||o[2]-o[0]!==512||o[3]-o[1]!==512||o.some(v=>!Number.isInteger(v/64)))throw Error('batch-bounds');
const origin=[0,0,0],positions=g.positions.map((v,i)=>Math.fround(v)-origin[i%3]);
// Both XZ and Y lattice origins are fixed in the WORLD frame. Batch
// recentering changes float32 precision and can change shared tessellation.
const config={cs:.25,ch:.1,tileSize:256,walkableHeight:18,walkableClimb:10,walkableRadius:2,walkableSlopeAngle:40,
 minRegionArea:0,mergeRegionArea:0,maxSimplificationError:1.3,maxVertsPerPoly:6,bounds:[[b[0],0,b[1]],[b[2],1,b[3]]]};
const preRaster=pruneFullHeightExcludedTriangles(positions,g.indices,g.exclusions);
await init();const started=performance.now(),result=generateBoundedTiled(positions,preRaster.indices,config);
if(!result.success)throw Error('world bake failed:'+result.error);
const nav=result.navMesh,byRef=new Map(),owned=[],witnesses=[],all=[],blocked=new Set(),touches=exclusionLookup(g.exclusions);
let removed=0,degenerate=0;
try{
 for(let ti=0;ti<nav.getMaxTiles();ti++){
  const tile=nav.getTile(ti),h=tile.header();if(!h)continue;
  if(h.polyCount()>POLYS_PER_TILE||h.layer()!==0)throw Error('world tile polygon/layer bound');
  const gx=b[0]/64+h.x(),gz=b[1]/64+h.y(),base=nav.getPolyRefBase(tile)>>>0;
  const own=gx*64>=o[0]&&gx*64<o[2]&&gz*64>=o[1]&&gz*64<o[3];
  for(let pi=0;pi<h.polyCount();pi++){
   const p=tile.polys(pi);if(p.getType()!==0)throw Error('unexpected offmesh connection');
   const points=[];
   for(let vi=0;vi<p.vertCount();vi++){
    const vertex=p.verts(vi),pt=[0,1,2].map(a=>tile.verts(vertex*3+a)+origin[a]);
    points.push(voxelVertex(pt,[0,0,0],.25).map(round));
   }
   const ref=base+pi,key=`w${j.worldMapID}:r${gx}:${gz}:0:p${pi}`;
   if(byRef.has(ref))throw Error('duplicate ref');
   if(touches(points)||!hasHorizontalArea(points)){blocked.add(ref);removed++;if(!hasHorizontalArea(points))degenerate++;continue;}
   const portals=[];let link=p.firstLink()>>>0,n=0;
   while(link!==0xffffffff){
    if(link>=h.maxLinkCount()||++n>32)throw Error('portal link bound');
    const edge=tile.links(link);link=edge.next()>>>0;const to=edge.ref()>>>0;if(!to)continue;
    if(edge.edge()>=points.length)throw Error('portal edge index');
    let left=points[edge.edge()],right=points[(edge.edge()+1)%points.length];
    if(edge.side()!==255){const lo=edge.bmin()/255,hi=edge.bmax()/255,a=left,q=right;left=a.map((v,i)=>v+(q[i]-v)*lo);right=a.map((v,i)=>v+(q[i]-v)*hi);}
    portals.push({to,left:left.map(round),right:right.map(round)});
   }
   const row={id:ref,key,grid:[gx,gz,0],points,center:[0,1,2].map(a=>round(points.reduce((s,p)=>s+p[a],0)/points.length)),portals,owned:own};
   byRef.set(ref,row);all.push(row);
  }
 }
 for(const row of all)row.portals=row.portals.filter(p=>!blocked.has(p.to));
 for(const row of all)for(const p of row.portals){
  const target=byRef.get(p.to);if(!target)throw Error('dangling baked portal');
  const clip=clipPortalToTarget(p,target.points);if(!clip)throw Error('no shared portal interval');p.left=clip.left;p.right=clip.right;
 }
 const stepAudit=pruneStepPortals(all,1);
 for(const row of all){
  const exported={key:row.key,grid:row.grid,points:row.points,center:row.center,portals:row.portals.map(p=>{
   const target=byRef.get(p.to),mid=p.left.map((v,i)=>(v+p.right[i])/2);
   return {to:target.key,left:p.left,right:p.right,meters:round(Math.hypot(...row.center.map((v,i)=>v-mid[i]))+Math.hypot(...target.center.map((v,i)=>v-mid[i])))};
  }).sort((a,b)=>a.to.localeCompare(b.to,'en'))};
  if(row.owned)owned.push(exported);else witnesses.push(exported);
 }
 owned.sort((a,b)=>a.key.localeCompare(b.key,'en'));witnesses.sort((a,b)=>a.key.localeCompare(b.key,'en'));
 if(owned.length>262144||all.length>409600)throw Error('batch polygon bound');
 const targetKeys=new Set(owned.flatMap(p=>p.portals.map(e=>e.to))),neededWitnesses=witnesses.filter(p=>targetKeys.has(p.key));
 fs.mkdirSync(outdir);
 const files=[];
 function write(name,object){const data=Buffer.from(JSON.stringify(object));if(data.length>64*1024*1024)throw Error('batch artifact byte bound');fs.writeFileSync(path.join(outdir,name),data,{flag:'wx'});files.push({filename:name,sha256:sha(data),bytes:data.length});}
 write('polygons.json',{format:'rikui-world-owned-polygons-v1',worldMapID:j.worldMapID,jobID:j.id,polygons:owned});
 write('boundary-witnesses.json',{format:'rikui-world-boundary-witnesses-v1',worldMapID:j.worldMapID,jobID:j.id,polygons:neededWitnesses});
 write('manifest.json',{format:'rikui-world-nav-batch-v1',identity:g.identity,worldMapID:j.worldMapID,job:j,
  geometrySHA256:sha(raw),source:g.source,coverageGates:g.coverageGates,exclusions:g.exclusions,liquids:g.liquids??[],
  generator:{package:'recast-navigation',version:'0.43.1',config,origin,wrapperSHA256:sha(fs.readFileSync(new URL(import.meta.url))),boundedWrapperSHA256:sha(fs.readFileSync(new URL('./world_tiled.mjs',import.meta.url))),filterSHA256:sha(fs.readFileSync(new URL('./mesh_filter.mjs',import.meta.url))),heightAudit:result.heightAudit,preRasterExclusionAudit:preRaster.audit},
  statistics:{ownedPolygons:owned.length,boundaryWitnesses:neededWitnesses.length,directedEdges:owned.reduce((n,p)=>n+p.portals.length,0),removedPolygons:removed,degeneratePolygons:degenerate,stepLinksRemoved:stepAudit.removedDirectedLinks},
  files:[...files],seamAdmission:'pending-neighbor-owned-geometry-and-reciprocal-portal-validation',nativeVerified:false,agentProfileCalibrated:false,
  limitations:g.limitations});
 console.log(JSON.stringify({job:j.id,polygons:owned.length,witnesses:neededWitnesses.length,milliseconds:performance.now()-started,manifestSHA256:files.at(-1).sha256}));
}finally{nav.destroy();}
