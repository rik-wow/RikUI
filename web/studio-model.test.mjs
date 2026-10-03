import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync,readdirSync} from "node:fs";
import {createEngine} from "./pack-engine.mjs";
import {sourcePaths} from "./pack-sources.mjs";
import {StudioModel} from "./studio-model.mjs";
import {sampleAppearanceCovered,componentAppearanceCovered} from "./preview-coverage.mjs";
const engine=()=>createEngine(sourcePaths.map(p=>readFileSync(new URL("../"+p,import.meta.url),"utf8")));
test("curated layouts reserve the character center and preserve conflicting personal edits",()=>{
 const e=engine(),m=new StudioModel(e);
 for(const name of ["centered","classic","hud","healer"]){
  m.choose(name);const source=e.call("Encode",m.source);
  for(const [width,height,device]of [[1920,1080,"desktop"],[1366,768,"desktop"],[3440,1440,"ultrawide"],[1280,800,"handheld"]]){
   m.viewport={width,height};m.device=device;
   for(const activity of ["exploration","party","raid","town"]){
    m.activity=activity;const r=m.resolve(),zone=Array.from(r.groups).find(g=>g.key==="Character viewing area");
    assert.ok(zone,"Missing character reservation");assert.ok(zone.rect.x<width/2&&zone.rect.x+zone.rect.width>width/2);
    assert.ok(zone.rect.y<height/2&&zone.rect.y+zone.rect.height>height/2);
    const issues=Array.from(r.conflicts);
    if(width===1366&&activity==="raid")assert.ok(issues.every(c=>c.key==="chat"&&c.reason==="Crowded or off-screen"));
    else assert.equal(issues.length,0,name+" "+width+" "+activity+" "+JSON.stringify(issues));
    for(const g of Array.from(r.groups).filter(g=>m.source.groups[g.key]&&!g.floating)){
     const a=g.rect,b=zone.rect;
     assert.ok(!(a.x<b.x+b.width&&a.x+a.width>b.x&&a.y<b.y+b.height&&a.y+a.height>b.y),name+" obstructs character: "+g.key);
    }
   }
  }
  assert.equal(e.call("Encode",m.source),source,"Fitting drifted creator anchors");
 }
 m.choose("centered");m.viewport={width:1920,height:1080};m.device="desktop";m.activity="exploration";
 m.move("player",900,520);const r=m.resolve(),player=Array.from(r.groups).find(g=>g.key==="player");
 assert.ok(player.rect.y>=510&&player.rect.y<=530,"Personal edit was silently moved");
 assert.ok(Array.from(r.conflicts).some(c=>c.key==="player"&&c.reason.includes("character")),"Missing actionable character conflict");
 const code=m.export(),n=new StudioModel(e);n.import(code);assert.deepEqual(n.resolve().profile.positions.player,r.profile.positions.player);
 const importedSource=e.call("Encode",n.source);n.reset("player");assert.equal(Array.from(n.resolve().conflicts).length,0);assert.equal(e.call("Encode",n.source),importedSource);const resetExport=new StudioModel(e);resetExport.import(n.export());assert.equal(Array.from(resetExport.resolve().conflicts).length,0);n.undo();assert.ok(Array.from(n.resolve().conflicts).length);n.undo(true);assert.equal(Array.from(n.resolve().conflicts).length,0);
 m.undo();assert.equal(Array.from(m.resolve().conflicts).length,0);
});

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
