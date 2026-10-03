// Public previews derive only from reviewed Lua captures and unchanged public addon code.
import {readFile,writeFile,mkdir,copyFile} from "node:fs/promises";
import {createHash} from "node:crypto";
import {fileURLToPath} from "node:url";
import {execFileSync} from "node:child_process";
const reviewOnly=process.argv.includes("--local-review");
if(!reviewOnly)execFileSync(process.env.PYTHON||"python",[fileURLToPath(new URL("../tools/site-renders/check.py",import.meta.url))],{stdio:"inherit"});
const captureRoot=new URL(reviewOnly?(process.argv.includes("--isolated")?"../dist/ui-studio-review/":"../dist/ui-renders/"):"./ui-renders/",import.meta.url);
import {build} from "esbuild";
import {sourcePaths} from "./pack-sources.mjs";
import {createEngine} from "./pack-engine.mjs";
import {prunePublicAssets} from "./prune-public-assets.mjs";
import {loadGuides} from "./docs-source.mjs";
import {modulePages} from "./docs-catalogue.mjs";
const hash=value=>createHash("sha256").update(value).digest("hex");
const sources=await Promise.all(sourcePaths.map(p=>readFile(new URL("../"+p,import.meta.url),"utf8")));
const engine=createEngine(sources);
const manifest=JSON.parse(await readFile(new URL("manifest.json",captureRoot),"utf8"));
const paintBounds=JSON.parse(execFileSync(process.env.PYTHON||"python",[fileURLToPath(new URL("../tools/site-renders/paint_bounds.py",import.meta.url)),"--root",fileURLToPath(captureRoot)],{encoding:"utf8"}));
const assets=[],atlases={},packs=[];
await mkdir(new URL("./public/assets/studio/",import.meta.url),{recursive:true});
async function asset(id,frame){
 const record=manifest.renders.find(c=>c.id===id),c=record&&{...record,...frame};if(!c)throw Error("Missing reviewed Studio capture: "+id);
 const bytes=await readFile(new URL(c.filename,captureRoot));
 if(hash(bytes)!==c.sha256)throw Error("Capture bytes differ: "+id);
 const url="/assets/studio/"+id+(frame?"-"+frame.value:"")+"-"+c.sha256.slice(0,12)+".webp";
 await copyFile(new URL(c.filename,captureRoot),new URL("./public"+url,import.meta.url));assets.push(url);
 return {...c,url};
}
for(const theme of ["classic","ocean","ink"])for(const readability of ["standard","readable"]){
 const components={};
 for(const prefix of ["studio-atlas-","studio-extra-","studio-unitauras-off-"]){
  const id=prefix+theme+"-"+readability,record=manifest.renders.find(c=>c.id===id);
  if(!record?.frames || (prefix==="studio-atlas-"&&record.frames.length!==25))throw Error("Missing individually filtered native component captures: "+id);
  for(const frame of record.frames){const c=await asset(id,frame);if(!c.components)throw Error("Missing native geometry: "+id);
   const paint=paintBounds[c.filename];if(!paint)throw Error("Missing native paint extent: "+c.filename);
   for(const [key,geometry]of Object.entries(c.components))components[key+(prefix==="studio-unitauras-off-"?"NoUnitAuras":"")]={...geometry,paint,url:c.url,atlasHeight:c.height,sha256:c.sha256};
  }
 }
 atlases[theme+"-"+readability]={components};
}
const collection=JSON.parse(await readFile(new URL("./setup-collection.json",import.meta.url),"utf8"));
if(collection.version!==1||!Array.isArray(collection.packs)||collection.packs.length<1||collection.packs.length>32)throw Error("Invalid curated collection");
const identities=new Set(),names=new Set();
for(const entry of collection.packs){
 if(!/^[a-z0-9-]{1,60}$/.test(entry.name)||names.has(entry.name)||typeof entry.description!=="string"||entry.description.length>400)throw Error("Invalid gallery entry");
 const pack=entry.bundled?engine.call("Bundled",entry.bundled):engine.call("Import",entry.code);
 if(identities.has(pack.id))throw Error("Duplicate pack identity");identities.add(pack.id);names.add(entry.name);
 const scene=entry.scene||"exploration";if(!["exploration","party","raid","town"].includes(scene))throw Error("Invalid gallery sample scene");
 const native=engine.call("Resolve",pack,{viewport:pack.viewport,activity:scene,device:"desktop",components:pack.components});
 if(Array.from(native.conflicts||[]).length)throw Error("Gallery setup has unresolved fit conflicts: "+entry.name);
 const capture=await asset(entry.capture);
 if(entry.bundled&&!capture.lua.includes('Studio.Select("'+entry.bundled+'")'))throw Error("Capture is not from this bundled setup");
 if(!entry.bundled){
  // Maintainers add startup data for a submitted pack; metadata has no bearing on its pixels.
  if(!engine.call("Equal",capture.profile,native.profile))throw Error("Creator capture startup data differs from the validated pack");
 }
 packs.push({name:entry.name,description:entry.description,scene,pack,code:engine.call("Encode",pack),image:capture.url,sha256:capture.sha256});
}
const {pages:guides}=await loadGuides();
const modules=[];
for(const choice of Array.from(engine.call("ModuleChoices"))){
 const guide=guides.find(p=>p.slug===modulePages[choice.key]);if(!guide)throw Error("Module needs a canonical guide: "+choice.key);
 const title={unitauras:"Target, focus & pet auras",druidmana:"Druid mana in forms",combatresource:"Combat resource"}[choice.key]||guide.title;
 const native=manifest.renders.find(c=>c.page===guide.slug);
 const sample=native?await asset(native.id,native.frames?.find(f=>f.sha256===native.sha256)||native.frames?.[0]):undefined;
 modules.push({...choice,title,summary:guide.summary,guide:"/docs/"+guide.slug,...(sample?{guideSample:{url:sample.url,title:sample.title,sha256:sample.sha256}}:{})});
}
const data={version:1,reviewOnly,modules,sources:sourcePaths.map((path,i)=>({path,sha256:hash(sources[i]),source:sources[i]})),atlases,packs,
 limitations:["Representative player data is fixture data, not your character.","Dynamic quest, target aura and inventory contents may grow beyond the sample. Review fitting conflicts in the addon.","Only captured coordinated themes and text sizes have appearance previews. Other imported settings are preserved and identified.","QuestTogether uses a compatibility recipe, not a styling API. Missing addons retain RikUI ownership."]};
const dataText=JSON.stringify(data),dataURL="/assets/studio/data-"+hash(dataText).slice(0,12)+".json";
await writeFile(new URL("./public"+dataURL,import.meta.url),dataText);assets.push(dataURL);
const result=await build({entryPoints:[fileURLToPath(new URL("./studio-client.mjs",import.meta.url))],bundle:true,platform:"browser",format:"esm",write:false,minify:true,define:{"process":"undefined","process.env.FENGARICONF":"undefined"},external:["fs","path","os","crypto","child_process"]});
const js=result.outputFiles[0].contents,scriptURL="/assets/studio/editor-"+hash(js).slice(0,12)+".js";
await writeFile(new URL("./public"+scriptURL,import.meta.url),js);assets.push(scriptURL);
await writeFile(new URL("./studio-generated.mjs",import.meta.url),"// Generated from authentic Lua captures; local review builds are never publishable.\nexport const studioReviewOnly="+reviewOnly+";\nexport const studioAssets="+JSON.stringify(assets)+";\nexport const studioDataURL="+JSON.stringify(dataURL)+";\nexport const studioScriptURL="+JSON.stringify(scriptURL)+";\nexport const gallery="+JSON.stringify(packs)+";\n");
if(!reviewOnly)await prunePublicAssets(new URL("./public/assets/studio/",import.meta.url),assets,"studio");
console.log("Built Studio: "+packs.length+" packs, "+Object.keys(atlases).length+" authentic atlases; public addon Lua only.");
