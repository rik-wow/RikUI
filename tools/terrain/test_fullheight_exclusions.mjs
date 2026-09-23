import assert from 'node:assert/strict';
import {pruneFullHeightExcludedTriangles as filter,exclusionLookup} from './mesh_filter.mjs';
const full={reason:'unsupported-ADT-geometry',bounds:[[0,-100000,0],[10,100000,10]],padding:.5};
const vertices=[1,950,1,9,950,1,1,950,9, 9,0,1,11,0,1,9,0,9, 10.25,0,1,10.4,0,2,10.25,0,3];
const indices=[0,1,2,3,4,5,6,7,8];
const a=filter(vertices,indices,[full]);
assert.deepEqual(a.indices,[3,4,5,6,7,8]);
assert.equal(a.audit.removedTriangles,1);
assert.deepEqual(indices,[0,1,2,3,4,5,6,7,8]);
const roof={...full,bounds:[[0,1.5,0],[10,1.8,10]]};
assert.deepEqual(filter([1,1.7,1,9,1.7,1,1,1.7,9],[0,1,2],[roof]).indices,[0,1,2]);
assert.deepEqual(filter(vertices,indices,[{...full,reason:'unsupported-WMO-footprint'}]).indices,indices);
assert.deepEqual(filter(vertices,indices,[{...full,reason:'unmodeled-MH2O-cell'}]).indices,indices);
assert.deepEqual(filter(vertices,indices,[{...full,reason:'unsourced-physical-tile'}]).indices,a.indices);
assert.deepEqual(filter([1,100001,1,9,100001,1,1,100001,9],[0,1,2],[full]).indices,[0,1,2]);
const touches=exclusionLookup([full]);assert(touches([[10.25,0,1],[10.4,0,2],[10.25,0,3]]),'original final padding remains stricter than prefilter');
assert.throws(()=>filter(vertices,indices,[{...full,bounds:[[0,-100000,0],[100000,100000,100000]]}]),/exclusion-index-budget/);
// Adjacent jobs see the same Float32 world triangle, including a sub-ULP boundary.
const on=Float32Array.from([10,500,1,10,501,9,1,500,1]);
assert.deepEqual(filter(Array.from(on),[0,1,2],[full]).indices,[]);
const out=Array.from(on);out[0]=Math.fround(10+.0001);
assert.deepEqual(filter(out,[0,1,2],[full]).indices,[0,1,2]);
console.log('full-height pre-raster exclusions: 12 assertions passed');
// Unswimmable-liquid boxes remove polygons reaching below their surface only.
{
  const {exclusionLookup}=await import('./mesh_filter.mjs');
  const lava=exclusionLookup([{bounds:[[0,-100000,0],[4,5.5,4]],padding:.5,belowSurface:true,reason:'unswimmable-liquid'}]);
  const bridge=[[0,9,0],[4,9,0],[4,9,4]],bed=[[0,2,0],[4,2,0],[4,2,4]],bank=[[3,5,0],[8,6,0],[8,6,4]];
  if(lava(bridge))throw Error('bridge above lava was removed');
  if(!lava(bed))throw Error('lava bed was kept');
  if(!lava(bank))throw Error('bank polygon dipping to the surface was kept');
  const wall=exclusionLookup([{bounds:[[0,0,0],[4,1,4]],padding:.5,reason:'unknown-physics-extent'}]);
  if(!wall(bridge))throw Error('XZ-only exclusions must ignore height');
  console.log('below-surface exclusions: 4 assertions passed');
}
