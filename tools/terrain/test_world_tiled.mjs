import assert from 'node:assert/strict';
import {canonicalTriangles} from './world_tiled.mjs';
// Independent triangle encounter order/cyclic starts must not affect raster input.
const points=[0,0,0,64,0,0,64,0,64,0,0,64];
const a=canonicalTriangles(points,[0,1,2,0,2,3],[0,3]);
const b=canonicalTriangles(points,[2,3,0,1,2,0],[3,0]);
assert.deepEqual(a,b);
const reverse=canonicalTriangles(points,[0,2,1,0,3,2],[0,3]);
assert.notDeepEqual(a,reverse,'orientation is collision input and must survive');
const translated=canonicalTriangles(points.map((v,i)=>v+(i%3===0?512:0)),[0,1,2,0,2,3],[3,0]);
assert.deepEqual(translated.indices,a.indices);
assert.deepEqual(translated.positions.map((v,i)=>v-(i%3===0?512:0)),a.positions);
console.log('world triangle ordering: 4 assertions passed');
