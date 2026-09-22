import assert from 'node:assert/strict';
import {hasHorizontalArea,removeBlockedPortals,exclusionLookup,voxelVertex,pruneStepPortals,clipPortalToTarget} from './mesh_filter.mjs';
assert.equal(hasHorizontalArea([[0,0,0],[1,0,0],[0,0,1]]),true);
assert.equal(hasHorizontalArea([[0,9,0],[0,3,1],[1,4,0]]),true);
assert.equal(hasHorizontalArea([[-959.1673,403.5862,-5501.6673],[-959.1673,403.1862,-5499.6673],[-959.1673,403.6862,-5502.6673]]),false);
assert.equal(hasHorizontalArea([[0,0,0],[1,1,1],[2,2,2]]),false);
assert.equal(hasHorizontalArea([[0,0,0],[0,8,0],[0,12,0]]),false);
assert.equal(hasHorizontalArea([[0,0,0],[Infinity,0,0],[0,0,1]]),false);
const edges=[{to:3},{to:4},{to:5}],blocked=new Set([4]);
assert.deepEqual(removeBlockedPortals(edges,blocked),[{to:3},{to:5}]);
assert.deepEqual(edges,[{to:3},{to:4},{to:5}]);
const lookup=exclusionLookup([{bounds:[[-65,-10,-1],[0,10,1]],padding:.5}]);
assert.equal(lookup([[-65.5,100,0],[-66,100,1],[-66,100,-1]]),true);
assert.equal(lookup([[.501,0,0],[1,0,0],[1,0,1]]),false);
assert.throws(()=>exclusionLookup([{bounds:[[1,0,0],[0,1,1]],padding:0}]),/exclusion-shape/);
assert.deepEqual(voxelVertex([.60001,17.123,.89999],[0,0,0],.3),[.6,17.123,.8999999999999999]);
assert.throws(()=>voxelVertex([.61,0,0],[0,0,0],.3),/voxel-lattice/);
function pair(height) {
  return [{id:1,points:[[0,0,0],[1,0,0],[1,0,1],[0,0,1]],
    portals:[{to:2,left:[1,0,0],right:[1,0,1]}]},
    {id:2,points:[[1,height,0],[2,height,0],[2,height,1],[1,height,1]],
    portals:[{to:1,left:[1,height,1],right:[1,height,0]}]}];
}
let polygons=pair(.3);
assert.equal(pruneStepPortals(polygons,.3).removedDirectedLinks,0);
polygons=pair(.31);
assert.equal(pruneStepPortals(polygons,.3).removedDirectedLinks,2);
assert.equal(polygons[0].portals.length+polygons[1].portals.length,0);
polygons=pair(.1);polygons[1].points[3][1]=.5;
assert.equal(pruneStepPortals(polygons,.3).removedDirectedLinks,2);
polygons=pair(0);polygons[1].points.forEach(p=>p[0]+=1);
assert.throws(()=>pruneStepPortals(polygons,.3),/portal-height-unresolved/);
const clipped=clipPortalToTarget({to:2,left:[1,0,-.1],right:[1,0,1.1]},pair(0)[1].points);
assert.deepEqual(clipped,{to:2,left:[1,0,0],right:[1,0,1]});
assert.equal(clipPortalToTarget({left:[3,0,0],right:[3,0,1]},pair(0)[1].points),null);
console.log('20 mesh-filter regression checks passed');
