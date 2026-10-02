import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync,readdirSync} from "node:fs";
import {createEngine} from "./pack-engine.mjs";
import {sourcePaths} from "./pack-sources.mjs";
import {StudioModel} from "./studio-model.mjs";
import {sampleAppearanceCovered,componentAppearanceCovered} from "./preview-coverage.mjs";
const engine=()=>createEngine(sourcePaths.map(p=>readFileSync(new URL("../"+p,import.meta.url),"utf8")));
test("import restores the source viewport and export retains an edited viewport",()=>{
 const e=engine(),m=new StudioModel(e),p=e.call("Bundled","centered");p.viewport={width:2560,height:1440};
 m.import(e.call("Encode",p));assert.deepEqual(m.viewport,{width:2560,height:1440});
 m.change(s=>{s.viewport={width:1280,height:800};s.device="handheld";});
 const source=e.call("Encode",m.source),code=m.export(),n=new StudioModel(e);n.import(code);
 assert.deepEqual(n.viewport,m.viewport);assert.equal(e.call("Encode",m.source),source);
 assert.deepEqual(n.resolve().profile.positions,m.resolve().profile.positions);
});
test("visual edits round-trip through the actual pack engine without source drift",()=>{
 const e=engine(),model=new StudioModel(e);model.choose("hud");
 const original=e.call("Encode",model.source);
 model.change(s=>{s.device="handheld";s.viewport={width:1280,height:800};});
 assert.equal(Array.from(model.resolve().conflicts).length,0);
 model.move("main",400,64);const edited=model.export();
 assert.equal(e.call("Encode",model.source),original);
 assert.equal(e.call("Decode",edited).adjustments.positions.main.point,"BOTTOMLEFT");
 const second=new StudioModel(e);second.import(edited);second.viewport={width:1280,height:800};
 assert.deepEqual(second.resolve().profile.positions.main,model.resolve().profile.positions.main);
 assert.equal(second.device,"handheld");assert.equal(e.call("Decode",edited).ancestry.id,"rikui-hud");
 model.undo();assert.equal(model.overrides.positions,undefined);model.undo(true);assert.equal(model.export(),edited);
 model.reset("main");assert.equal(model.overrides.positions.main,undefined);
});
test("readability survives choices; character sharing is explicit; malformed imports leave current state",()=>{
 const e=engine(),m=new StudioModel(e);m.choose("centered");m.change(s=>{s.accessibility="contrast";s.selected={appearance:true};});m.choose("classic");
 assert.equal(m.accessibility,"contrast");assert.equal(m.resolve().profile.textScale,1.15);
 const before=m.export();assert.throws(()=>m.import("return os.execute('x')"));assert.equal(m.export(),before);
 assert.equal(e.call("Decode",m.export()).accessibilityRecipe,"contrast");
 m.theme("ocean");assert.equal(m.resolve().profile.theme.accent,"blue");
 assert.equal(e.call("Decode",m.export()).character,undefined);
 for(let i=0;i<25;i++)m.change(s=>{s.activity=i%2?"town":"exploration";});
 assert.equal(m.history.length,20);
});
test("device defaults cannot overwrite exported density and metadata revisions",()=>{
 const e=engine(),m=new StudioModel(e);m.choose("hud");m.change(s=>{s.device="handheld";s.viewport={width:1280,height:800};s.overrides.scale=1.05;s.authorMetadata={title:"My setup",creator:"Creator",revision:1};});
 const code=m.export(),p=e.call("Decode",code);assert.equal(p.title,"My setup");assert.equal(p.creator,"Creator");
 const n=new StudioModel(e);n.import(code);n.viewport={width:1280,height:800};assert.equal(n.resolve().profile.scale,1.05);
 n.change(s=>{s.maintainIdentity=true;s.overrides.scale=1;});const updated=e.call("Decode",n.export());
 assert.equal(updated.id,p.id);assert.equal(updated.revision,2);assert.equal(updated.creator,"Creator");
 n.change(s=>{s.authorMetadata={revision:1};});assert.throws(()=>n.export(),/increase/);
});
test("selective appearance retains current theme and invalid edits roll back",()=>{
 const e=engine(),m=new StudioModel(e);m.choose("centered");m.change(s=>{s.selected.appearance=false;});m.theme("ocean");assert.equal(m.resolve().profile.theme.accent,"gold");
 const before=m.export();assert.throws(()=>m.change(s=>{s.overrides.scale=100;}));assert.equal(m.export(),before);
 const incoming=e.call("Bundled","centered");incoming.integration="questtogether";m.integrationPresent=true;
 assert.ok(m.resolveWith(incoming).groups);
});
test("creator updates retain only personal differences and keep device fitting adaptive",()=>{
 const e=engine(),m=new StudioModel(e);m.choose("centered");const previous=m.resolveWith(m.source).profile;
 m.theme("ocean");const current=m.resolve().profile;
 const incoming=e.call("Copy",m.source);incoming.revision++;incoming.profile.theme.accent="white";
 const incomingProfile=m.resolveWith(incoming).profile,update=e.call("Update",previous,incomingProfile,current);
 m.change(s=>{s.source=incoming;s.overrides=m.personalDifference(incomingProfile,update.profile);});
 assert.equal(m.resolve().profile.theme.accent,"blue");assert.equal(m.overrides.positions,undefined);
 assert.ok(Array.from(update.conflicts).some(c=>c.path==="theme.accent"));
 const accepted=e.call("Update",previous,incomingProfile,current,{"theme.accent":true});
 m.change(s=>{s.overrides=m.personalDifference(incomingProfile,accepted.profile);});assert.equal(m.resolve().profile.theme.accent,"white");
 m.change(s=>{s.device="handheld";s.viewport={width:1280,height:800};});assert.equal(Array.from(m.resolve().conflicts).length,0);
 incoming.integration="questtogether";incoming.ownership.nameplates="specialist";incoming.profile.modules??={};incoming.profile.modules.nameplates=false;
 const absent=m.resolveWith(incoming);assert.equal(absent.effectivePack.ownership.nameplates,"rikui");assert.equal(absent.profile.modules.nameplates,true);
});
test("selective creator theme conflicts retain complete RGB overrides",()=>{
 const e=engine(),m=new StudioModel(e);m.choose("centered");const previous=m.resolveWith(m.source).profile;
 m.theme("ocean");const current=m.resolve().profile,incoming=e.call("Copy",m.source);incoming.revision=2;incoming.profile=e.call("Merge",incoming.profile,e.call("Theme","ink"));
 const incomingProfile=m.resolveWith(incoming).profile,accepted=e.call("Update",previous,incomingProfile,current,{"theme.accent":true});
 m.change(s=>{s.source=incoming;s.overrides=m.personalDifference(incomingProfile,accepted.profile);});
 assert.equal(m.resolve().profile.theme.accent,"white");assert.deepEqual(m.resolve().profile.borderColor,current.borderColor);assert.ok(Array.isArray(m.overrides.borderColor));
});
test("native preview coverage refuses uncaptured imported appearance",()=>{
 const e=engine(),m=new StudioModel(e);m.choose("centered");const p=m.resolve().profile;
 assert.ok(sampleAppearanceCovered(p,e,"classic"));
 for(const change of [{unitframes:{powerText:"percent"}},{castbars:{height:36}},{bags:{columns:8}},{minimap:{coordinates:false}},{nameplates:{adaptiveNames:false}}]){
  assert.equal(sampleAppearanceCovered({...p,...change},e,"classic"),false);
 }
});
test("uncaptured settings only affect their own component",()=>{
 const e=engine(),m=new StudioModel(e);m.choose("centered");const p=m.resolve().profile;
 const custom={...p,nameplates:{adaptiveNames:false}};
 assert.equal(componentAppearanceCovered("nameplates",custom,e,"classic"),false);
 assert.equal(componentAppearanceCovered("chat",custom,e,"classic"),true);
 assert.equal(componentAppearanceCovered("main",custom,e,"classic"),true);
 assert.equal(componentAppearanceCovered("player",{...p,castbars:{height:36}},e,"classic"),true);
 assert.equal(componentAppearanceCovered("casttarget",{...p,castbars:{height:36}},e,"classic"),false);
});
test("all module registrations belong to the shared component contract",()=>{
 const e=engine();const pack=e.call("Bundled","centered");
 // The live profile export includes module defaults. Unknown settings must fail rather than drop silently.
 const src=new URL("../src/",import.meta.url);
 const registered=readdirSync(src,{recursive:true}).filter(p=>p.endsWith(".lua")).flatMap(p=>Array.from(readFileSync(new URL(p.replaceAll("\\","/"),src),"utf8").matchAll(/:RegisterModule\("([^"]+)"/g),m=>m[1]));
 assert.ok(registered.length>40);
 const all=Object.fromEntries(registered.map(k=>[k,true]));
 pack.profile.modules=all;assert.ok(e.call("Validate",pack));
 pack.profile.modules.unknown=true;assert.throws(()=>e.call("Validate",pack));
});
