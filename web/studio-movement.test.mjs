import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {createEngine} from "./pack-engine.mjs";
import {sourcePaths} from "./pack-sources.mjs";
import {StudioModel} from "./studio-model.mjs";
const engine=()=>createEngine(sourcePaths.map(p=>readFileSync(new URL("../"+p,import.meta.url),"utf8")));
test("fine movement, exact coordinates and optional grid snapping preserve geometry and source",()=>{
 const e=engine(),m=new StudioModel(e);m.choose("centered");m.change(s=>{s.overrides.scale=1.073;});
 const original=e.call("Encode",m.source),free={grid:0,align:false};
 let g=Array.from(m.resolve().groups).find(g=>g.key==="main");
 m.move("main",g.rect.x+1,g.rect.y,free);
 let next=Array.from(m.resolve().groups).find(g=>g.key==="main");
 assert.ok(Math.abs(next.rect.x-g.rect.x-1)<0.001);assert.ok(Math.abs(next.rect.y-g.rect.y)<0.001);
 const snapped=m.previewMove("main",501,113,{grid:16,align:false});assert.equal(snapped.x,496);assert.equal(snapped.y,112);
 const history=m.history.length;m.previewMove("main",505,117,free);assert.equal(m.history.length,history);
 m.move("main",501.125,113.25,free);g=Array.from(m.resolve().groups).find(g=>g.key==="main");
 assert.ok(Math.abs(g.rect.x-501.125)<0.001);assert.ok(Math.abs(g.rect.y-113.25)<0.001);
 m.undo();assert.ok(Math.abs(Array.from(m.resolve().groups).find(g=>g.key==="main").rect.x-next.rect.x)<0.001);
 const bounds=m.previewMove("main",-999,99999,free);assert.equal(bounds.x,8);assert.equal(bounds.y,1080-bounds.entry.rect.height-8);
 const n=new StudioModel(e);n.import(m.export());assert.deepEqual(n.resolve().profile.positions.main,m.resolve().profile.positions.main);
 assert.equal(e.call("Encode",m.source),original);
 assert.throws(()=>m.previewMove("main",NaN,0,free));assert.throws(()=>m.previewMove("main",0,0,{grid:3}));
});
test("native snap bridge selects nearest edges and centers on both axes",()=>{
 const e=engine(),r={left:101,bottom:201,right:141,top:221},obstacles=[{left:100,bottom:200,right:140,top:220},{left:103,bottom:203,right:143,top:223}];
 const snapped=e.call("EditorSnap",r,obstacles,{width:1000,height:800},6,8);
 assert.equal(snapped.dx,-1);assert.equal(snapped.dy,-1);assert.ok(Array.from(snapped.guides).length>=2);
});
