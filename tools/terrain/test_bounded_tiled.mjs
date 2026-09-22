import assert from 'node:assert/strict';
import {init,getNavMeshPositionsAndIndices,NavMeshQuery} from '@recast-navigation/core';
import {generateBoundedTiled} from './bounded_tiled.mjs';
await init();
const settings={cs:.25,ch:.1,tileSize:256,walkableRadius:2,walkableHeight:18,walkableClimb:10,minRegionArea:0,mergeRegionArea:0};
const indices=[0,2,1,0,3,2,4,6,5,4,7,6];
const rectangle=(x0,x1,y)=>[x0,y,0,x1,y,0,x1,y,64,x0,y,64];
const build=(positions,bounds)=>generateBoundedTiled(positions,indices,{...settings,bounds});
{
 const r=build([...rectangle(0,64,-450),...rectangle(192,256,800)],[[0,-500,0],[256,900,64]]);
 assert.equal(r.success,true,r.error);
 try {
  const [positions]=getNavMeshPositionsAndIndices(r.navMesh),heights=positions.filter((_,i)=>i%3===1);
  assert.ok(Math.abs(Math.min(...heights)+450)<=.11,'low floor changed');
  assert.ok(Math.abs(Math.max(...heights)-800)<=.11,'upper floor clamped');
  assert.equal(r.heightAudit.builtTiles,2);assert.equal(r.heightAudit.emptyWalkableTiles,2);
  assert.ok(r.heightAudit.maxSpanVoxels<=8190);
 }finally{r.navMesh.destroy();}
}
{
 const r=build([...rectangle(0,128,400),...rectangle(0,32,-400)],[[0,-500,0],[128,900,64]]);
 assert.equal(r.success,true,r.error);const query=new NavMeshQuery(r.navMesh);
 try {
  assert.equal(r.heightAudit.builtTiles,2);
  const [first,second]=r.heightAudit.tiles;
  assert.ok(first.minY < -399 && second.minY>399,'fixture needs distinct tile origins');
  const route=query.computePath({x:10,y:400,z:32},{x:118,y:400,z:32},{halfExtents:{x:1,y:1,z:1}});
  assert.equal(route.success,true,JSON.stringify(route.error));
  assert.equal(route.path.length,2,'flat upper floor should give a direct path');
  assert.ok(Math.abs(route.path.at(-1).x-118)<.01,'partial path mistaken for arrival');
  assert.ok(route.path.every(p=>Math.abs(p.y-400)<=.11),'path changed floor');
 }finally{query.destroy();r.navMesh.destroy();}
}
{
 const r=build([...rectangle(0,32,-450),...rectangle(0,32,500)],[[0,-500,0],[64,900,64]]);
 assert.equal(r.success,false);assert.equal(r.navMesh,undefined);
 assert.match(r.error,/tile-heightfield-span-overflow:0,0/);
}
console.log('bounded tiled height regression: 3 cases passed');
