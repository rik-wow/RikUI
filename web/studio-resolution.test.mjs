import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {createEngine} from "./pack-engine.mjs";
import {sourcePaths} from "./pack-sources.mjs";
import {StudioModel} from "./studio-model.mjs";
test("resolution cache tracks every semantic input, skips attribution, and recovers invalid changes",()=>{
 const actual=createEngine(sourcePaths.map(p=>readFileSync(new URL("../"+p,import.meta.url),"utf8")));
 let solves=0,validations=0;const engine={call(method,...args){if(method==="Resolve")solves++;if(method==="Validate")validations++;return actual.call(method,...args);}};
 const m=new StudioModel(engine);m.choose("centered");m.resolve();m.resolve();assert.equal(solves,1);
 m.source.title="Renamed";m.source.revision=2;assert.equal(m.resolve().effectivePack.title,"Renamed");assert.equal(solves,1);
 const variants=[
 ()=>{m.viewport={width:2560,height:1440};},()=>{m.device="ultrawide";},()=>{m.activity="party";},
 ()=>{m.accessibility="readable";},()=>{m.overrides.scale=1.2;},()=>{m.selected.appearance=false;},
 ()=>{m.baseline.scale=1.3;},()=>{m.integrationPresent=true;m.source.integration="questtogether";},
 ()=>{m.resetPositions.chat=true;},()=>{m.source.profile.modules.chat=false;}
 ];
 for(const change of variants){const before=solves;change();assert.deepEqual(m.resolve().profile,m.resolveWith(m.source,m.overrides).profile);assert.equal(solves,before+2);m.resolve();assert.equal(solves,before+2);}
 const before=m.export(),current=m.resolve().profile;assert.throws(()=>m.change(s=>{s.overrides.scale=100;}));assert.equal(m.export(),before);assert.deepEqual(m.resolve().profile,current);
 const count=validations;m.change(s=>{s.overrides.scale=1;});assert.equal(validations-count,1,"one shared validation per edit");m.undo();assert.deepEqual(m.resolve().profile,current);
});
test("pure VM caches preserve null-table output, isolate mutation and agree with full module profiles",()=>{
 const e=createEngine(sourcePaths.map(p=>readFileSync(new URL("../"+p,import.meta.url),"utf8")));
 const original=e.call("Theme","classic"),theme=e.call("Theme","classic");assert.deepEqual(theme,original);theme.theme.accent="red";assert.deepEqual(e.call("Theme","classic"),original);
 const profile=e.call("Resolve",e.call("Bundled","centered"),{}).profile;
 for(const choice of e.call("ModuleChoices")){
  assert.equal(e.call("ModuleEnabled",profile,choice.key),e.call("ModuleEnabled",{modules:profile.modules},choice.key));
  for(const key of Array.from(choice.groups))assert.equal(e.call("GroupEnabled",key,profile),e.call("GroupEnabled",key,{modules:profile.modules}));
 }
 assert.equal(e.call("ModuleEnabled",{modules:{chat:false}},"chat"),false);
 assert.equal(e.call("ModuleEnabled",{modules:{chat:true}},"chat"),true);
 e.call("Equal",null,null);
 assert.throws(()=>e.call("Equal",NaN,null),/Invalid number/);
 assert.throws(()=>e.call("Equal",()=>{},null),/must be data/);
 assert.throws(()=>e.call("Equal",{constructor:null},null),/Invalid key/);
});
