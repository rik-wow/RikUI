// Independent geometry cases for the explicit reference-step hypothesis.
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import path from 'node:path';
import {clipPortalToTarget} from './mesh_filter.mjs';
const modules=path.resolve(process.argv[2]??'node_modules');
const {init,NavMeshQuery}=await import(pathToFileURL(path.join(modules,'recast-navigation/index.mjs')).href);
const {generateTiledNavMesh}=await import(pathToFileURL(path.join(modules,'recast-navigation/generators.mjs')).href);
await init();
function scene(step=0){
  const positions=[],indices=[];
  function quad(a,b,c,d){const n=positions.length/3;positions.push(...a,...b,...c,...d);indices.push(n,n+1,n+2,n,n+2,n+3);}
  quad([0,0,0],[0,0,10],[10,0,10],[10,0,0]);
  quad([10,step,0],[10,step,10],[20,step,10],[20,step,0]);
  return {positions,indices,quad};
}
function reaches(g,climb,end={x:15,y:0,z:5}){
  const result=generateTiledNavMesh(g.positions,g.indices,{cs:.25,ch:.1,tileSize:256,
    walkableRadius:2,walkableHeight:18,walkableClimb:climb,walkableSlopeAngle:40,
    minRegionArea:0,mergeRegionArea:0,maxSimplificationError:1.3,maxVertsPerPoly:6});
  assert.ok(result.success);
  const query=new NavMeshQuery(result.navMesh);
  const found=query.computePath({x:5,y:0,z:5},end),last=found.path?.at(-1);
  const success=found.success&&last&&Math.hypot(last.x-end.x,last.y-end.y,last.z-end.z)<.25;
  query.destroy();result.navMesh.destroy();return !!success;
}
assert.ok(reaches(scene(),3),'flat control');
assert.equal(reaches(scene(.6),3,{x:15,y:.6,z:5}),false,'old limit blocks a step');
assert.ok(reaches(scene(.6),10,{x:15,y:.6,z:5}),'reference limit handles the independently chosen step');
assert.equal(reaches(scene(1.4),10,{x:15,y:1.4,z:5}),false,'higher ledge stays blocked');
const wall=scene();wall.quad([10,0,0],[10,4,0],[10,4,10],[10,0,10]);
assert.equal(reaches(wall,10),false,'wall stays blocked');
const narrow=scene();
for(const [lo,hi] of [[0,4.6],[5.4,10]])narrow.quad([10,0,lo],[10,4,lo],[10,4,hi],[10,0,hi]);
assert.equal(reaches(narrow,10),false,'radius still rejects narrow opening');
const ceiling=scene();ceiling.quad([8,1.5,0],[12,1.5,0],[12,1.5,10],[8,1.5,10]);
assert.equal(reaches(ceiling,10),false,'height still rejects low clearance');
const edge={to:2,left:[0,0,0],right:[10.02,1.002,0]};
const clipped=clipPortalToTarget(edge,[[0,0,0],[10,1,0],[10,1,10],[0,0,10]]);
assert.deepEqual(clipped.right,[10,1,0],'seam overshoot clipped to the shared edge');
assert.equal(clipPortalToTarget(edge,[[0,0,1],[10,1,1],[10,1,10],[0,0,10]]),null,'parallel separated edges cannot link');
assert.deepEqual(edge.right,[10.02,1.002,0],'input left intact');
console.log('10 movement profile and portal geometry checks passed; native movement unverified.');
