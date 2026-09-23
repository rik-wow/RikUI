// A tile taller than Recast's 13-bit span keeps its densest height window.
import assert from 'node:assert/strict';
import {heightWindow} from './world_tiled.mjs';
const flat=[0,10,0, 1,10.5,0, 0,11,1];
const plain=heightWindow(flat,0,.1);
assert.equal(plain.clipped,undefined);
assert.equal(plain.lo,10);assert.equal(plain.hi,11);
// Ground near y=0 (many vertices) and one spire at y=2000.
const tall=[];for(let i=0;i<30;i++)tall.push(i,Math.random()*5,0);
tall.push(0,2000,0);
const w=heightWindow(tall,0,.1);
assert.ok(w.clipped);assert.equal(w.clipped.keptVertices,30);assert.ok(w.hi<=5);
assert.ok(w.v1-w.v0<=8190);
console.log('height window tests passed');
