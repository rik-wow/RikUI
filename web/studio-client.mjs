import {createEngine} from "./pack-engine.mjs";
import {StudioModel,components} from "./studio-model.mjs";
import {sampleAppearanceCovered} from "./preview-coverage.mjs";
const $=id=>document.getElementById(id);
const status=$("studio-status"),root=$("studio-app");
const message=text=>{status.textContent=text;};
const images=new Map();
let model,data,resolved,selectedKey,drag,metadataStamp,renderEpoch=0;
const asArray=value=>Array.isArray(value)?value:[];
async function loadImage(url){
 if(!images.has(url))images.set(url,new Promise((resolve,reject)=>{const im=new Image();im.onload=()=>resolve(im);im.onerror=()=>reject(Error("Preview image unavailable. Export and install are still available."));im.src=url;}));
 return images.get(url);
}
function operation(fn,success,keepUpdate=false){try{if(!keepUpdate)$("update-conflicts")?.replaceChildren();fn();if(success)message(success);render();}catch(error){message(error.message);}}
function visibleGroups(){return asArray(resolved?.groups).filter(g=>model.source.groups[g.key]);}
function setOptions(select,items){select.replaceChildren(...items.map(([value,label])=>{const o=document.createElement("option");o.value=value;o.textContent=label;return o;}));}
function themeKey(profile){
 if(profile.theme?.accent==="blue")return "ocean";
 if(profile.theme?.accent==="white")return "ink";
 return "classic";
}
function same(a,b){return JSON.stringify(a)===JSON.stringify(b);}
async function render(){
 const epoch=++renderEpoch;
 try{
  resolved=model.resolve();
  const groups=visibleGroups();
  if(!groups.some(g=>g.key===selectedKey))selectedKey=groups[0]?.key;
  setOptions($("frame-group"),groups.map(g=>[g.key,g.key]));
  $("frame-group").value=selectedKey||"";
  $("pack-picker").value=data.packs.find(p=>p.pack.id===model.source.id)?.name||"";
  for(const c of components){const check=$("part-"+c);check.checked=!!model.selected[c];check.disabled=c==="character"&&!model.source.character;}
  for(const id of ["device","activity","accessibility"])$(id).value=model[id];
  $("viewport").value=model.viewport.width+"x"+model.viewport.height;
  $("undo").disabled=!model.history.length;$("redo").disabled=!model.future.length;
  const metadata=model.authorMetadata||{...model.source,revision:model.maintainIdentity?model.source.revision+1:model.source.revision};
  const stamp=JSON.stringify(metadata);if(stamp!==metadataStamp){$("pack-title").value=metadata.title;$("pack-creator").value=metadata.creator;$("pack-revision").value=metadata.revision;metadataStamp=stamp;}
  $("maintain-identity").checked=!!model.maintainIdentity;
  $("pack-description").textContent=model.source.title+" · "+model.source.creator+" · revision "+model.source.revision+(model.source.ancestry?" · remix of "+model.source.ancestry.id+" r"+model.source.ancestry.revision:"");
  $("ownership").textContent=components.filter(c=>model.selected[c]).map(c=>c+": "+resolved.effectivePack.ownership[c]).join(" · ");
  const conflicts=asArray(resolved.conflicts);
  $("fit-status").textContent=conflicts.length?conflicts.map(c=>c.key+": "+c.reason).join("; "):"Fits within the declared group footprints. Dynamic contents can grow; review again in the addon.";
  $("fit-status").className=conflicts.length?"issue":"";
  $("export").disabled=$("share").disabled=conflicts.length>0;
  $("character-details").textContent=model.source.character?JSON.stringify(model.source.character,null,2):"No action-bar preset, macros or bindings included.";
  const profile=resolved.profile,key=themeKey(profile),readability=(profile.textScale||1)>1?"readable":"standard";
  $("theme").value=key;const density=String(profile.scale||1);if(!Array.from($("density").options).some(o=>o.value===density)){const o=document.createElement("option");o.value=density;o.textContent=Math.round(Number(density)*100)+"% (imported)";$("density").append(o);}$("density").value=density;
  $("questtogether").checked=!!model.integrationPresent;
  const atlas=structuredClone(data.atlases[key+"-"+readability]);
  if(profile.questtracker?.collapsed)atlas.components.questtracker=atlas.components.questtrackerCollapsed;
  const appearanceCovered=sampleAppearanceCovered(profile,model.engine,key);
  const unsupported=groups.filter(g=>!atlas.components[g.key]).map(g=>g.key);
  $("preview-limit").textContent=(appearanceCovered?"Authentic captured appearance.":"This appearance has no exact component capture. Geometry-only view; settings are preserved. Choose a captured coordinated theme and text size to restore the visual preview.")+
   (unsupported.length?" Groups without a component capture: "+unsupported.join(", ")+".":"")+
   " Representative fixture data. World imagery, live names and optional addon widgets are outside this preview.";
  const showPlates=appearanceCovered&&model.selected.nameplates&&resolved.effectivePack?.ownership?.nameplates!=="specialist"&&resolved.effectivePack.ownership.nameplates==="rikui"&&profile.modules?.nameplates!==false;
  const bitmap=new Map(await Promise.all([...groups.filter(g=>atlas.components[g.key]),...(showPlates&&atlas.components.nameplates?[{key:"nameplates"}]:[])].map(async g=>[g.key,await loadImage(atlas.components[g.key].url)])));if(epoch!==renderEpoch)return;
  const canvas=$("game-preview"),ctx=canvas.getContext("2d");
  canvas.width=model.viewport.width;canvas.height=model.viewport.height;
  ctx.fillStyle="#0c1117";ctx.fillRect(0,0,canvas.width,canvas.height);
  const scale=profile.scale||1;
  for(const g of groups){
   const r=g.rect,component=atlas.components[g.key];
   if(component&&appearanceCovered){
    // Native sample bitmap; no game widget is reconstructed by the browser.
    const topPad=g.key==="target"?32:0,pad=3;
    const sx=Math.max(0,component.x-pad),sy=Math.max(0,component.atlasHeight-component.y-component.height-topPad-pad);
    const w=component.width+pad*2,h=component.height+topPad+pad*2;
    ctx.drawImage(bitmap.get(g.key),sx,sy,w,h,r.x-pad*scale,canvas.height-r.y-(component.height+topPad+pad)*scale,w*scale,h*scale);
   }
   if(g.key===selectedKey){ctx.strokeStyle="#ecc98a";ctx.lineWidth=2;ctx.strokeRect(r.x,canvas.height-r.y-r.height,r.width,r.height);}
  }
  if(showPlates&&atlas.components.nameplates){const c=atlas.components.nameplates,im=bitmap.get("nameplates");ctx.drawImage(im,c.x,c.atlasHeight-c.y-c.height,c.width,c.height,canvas.width/2-c.width/2,Math.max(8,canvas.height*0.16),c.width,c.height);}
  canvas.setAttribute("aria-label","Authentic RikUI preview. Selected group "+(selectedKey||"none")+". Use frame controls or arrow keys to adjust it.");
  $("geometry").textContent=selectedKey?(()=>{const r=groups.find(g=>g.key===selectedKey).rect;return selectedKey+": "+Math.round(r.x)+", "+Math.round(r.y)+" · "+Math.round(r.width)+" × "+Math.round(r.height);})():"No selected movable groups.";
 }catch(error){message(error.message);}
}
function point(event){const bounds=$("game-preview").getBoundingClientRect();return {x:(event.clientX-bounds.left)/bounds.width*model.viewport.width,y:(bounds.bottom-event.clientY)/bounds.height*model.viewport.height};}
function move(dx,dy){const group=visibleGroups().find(g=>g.key===selectedKey);if(group)model.move(selectedKey,group.rect.x+dx,group.rect.y+dy);}
function exportCode(){const code=model.export();$("result-code").value=code;$("result-panel").hidden=false;return code;}
async function copy(text){try{await navigator.clipboard.writeText(text);message("Copied.");}catch{const panel=$("result-panel"),code=$("result-code")||$("pack-code");if(panel)panel.hidden=false;code?.focus();code?.select();message("Select the text and copy it with your keyboard.");}}
async function start(){
 try{
  const response=await fetch(root.dataset.source);if(!response.ok)throw Error("Editor data is unavailable. Use a gallery import code or install RikUI directly.");
  data=await response.json();model=new StudioModel(createEngine(data.sources.map(s=>s.source)));model.choose("centered");
  const name=new URL(location.href).searchParams.get("pack");if(data.packs.some(p=>p.name===name))model.choose(name,data.packs.find(p=>p.name===name).pack);
  const scene=new URL(location.href).searchParams.get("activity");if(["exploration","party","raid","town"].includes(scene))model.activity=scene;
  if(location.hash.length>1)model.import(decodeURIComponent(location.hash.slice(1)));
  setOptions($("pack-picker"),[["","Imported / custom"],...data.packs.map(p=>[p.name,p.pack.title])]);
  for(const c of components)$("part-"+c).addEventListener("change",e=>operation(()=>model.change(s=>{s.selected[c]=e.target.checked;}),"Component choice staged."));
  $("pack-picker").onchange=e=>{if(e.target.value)operation(()=>model.choose(e.target.value,data.packs.find(p=>p.name===e.target.value).pack));};
  $("import").onclick=()=>operation(()=>model.import($("import-code").value),"Imported for editing. Nothing has been applied to your addon.");
  for(const id of ["device","activity","accessibility"])$(id).onchange=e=>operation(()=>model.change(s=>{
   s[id]=e.target.value;if(id==="accessibility")s.accessibilityPinned=true;if(id==="device"){s.viewport=id&&s.device==="handheld"?{width:1280,height:800}:s.device==="ultrawide"?{width:3440,height:1440}:{width:1920,height:1080};}
  }));
  $("viewport").onchange=e=>operation(()=>model.change(s=>{const [width,height]=e.target.value.split("x").map(Number);s.viewport={width,height};}));
  $("theme").onchange=e=>operation(()=>model.theme(e.target.value),"Theme staged. Module, font and theme changes can require an addon reload.");
  $("density").onchange=e=>operation(()=>model.change(s=>{s.overrides.scale=Number(e.target.value);}));
  $("questtogether").onchange=e=>operation(()=>model.change(s=>{
   s.integrationPresent=e.target.checked;s.source.integration="questtogether";s.source.ownership.nameplates=e.target.checked?"specialist":"rikui";
   s.overrides.modules??={};s.overrides.modules.nameplates=!e.target.checked;
  }),"QuestTogether recipe: use stock nameplates, QT icons Left, health tint off, and its personal bubble in the reserved upper-left area. Missing QT keeps RikUI in charge.");
  $("undo").onclick=()=>operation(()=>model.undo());$("redo").onclick=()=>operation(()=>model.undo(true));
  $("frame-group").onchange=e=>{selectedKey=e.target.value;render();};
  for(const b of document.querySelectorAll("[data-move]"))b.onclick=()=>operation(()=>move(...b.dataset.move.split(",").map(Number)));
  $("reset-frame").onclick=()=>operation(()=>model.reset(selectedKey));
  $("align-center").onclick=()=>operation(()=>{const g=visibleGroups().find(g=>g.key===selectedKey);if(g)model.move(g.key,(model.viewport.width-g.rect.width)/2,g.rect.y);});
  $("game-preview").onpointerdown=e=>{
   const p=point(e),group=[...visibleGroups()].reverse().find(g=>p.x>=g.rect.x&&p.x<=g.rect.x+g.rect.width&&p.y>=g.rect.y&&p.y<=g.rect.y+g.rect.height);
   if(!group)return;selectedKey=group.key;drag={key:group.key,offset:{x:p.x-group.rect.x,y:p.y-group.rect.y},point:p,base:e.currentTarget.getContext("2d").getImageData(0,0,e.currentTarget.width,e.currentTarget.height),rect:group.rect};
   e.currentTarget.setPointerCapture(e.pointerId);e.currentTarget.focus({preventScroll:true});render();
  };
  $("game-preview").onpointermove=e=>{if(drag){drag.point=point(e);const canvas=e.currentTarget,ctx=canvas.getContext("2d");ctx.putImageData(drag.base,0,0);ctx.strokeStyle="#75cedb";ctx.lineWidth=3;ctx.setLineDash([8,5]);ctx.strokeRect(drag.point.x-drag.offset.x,canvas.height-(drag.point.y-drag.offset.y)-drag.rect.height,drag.rect.width,drag.rect.height);ctx.setLineDash([]);$("geometry").textContent="Move "+drag.key+" to "+Math.round(drag.point.x-drag.offset.x)+", "+Math.round(drag.point.y-drag.offset.y)+" (snaps when released)";}};
  $("game-preview").onpointerup=()=>{if(drag){const d=drag;drag=null;operation(()=>model.move(d.key,d.point.x-d.offset.x,d.point.y-d.offset.y));}};
  $("game-preview").onpointercancel=()=>{drag=null;render();};
  $("game-preview").onkeydown=e=>{
   const directions={ArrowLeft:[-8,0],ArrowRight:[8,0],ArrowUp:[0,8],ArrowDown:[0,-8]};
   if(directions[e.key]){e.preventDefault();operation(()=>move(...directions[e.key]));}
   if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==="z"){e.preventDefault();operation(()=>model.undo(e.shiftKey));}
  };
  $("export").onclick=()=>operation(()=>{exportCode();message("Import this code in /rik studio. Review ownership, conflicts and reload requirements, then Apply. Your personal accessibility preferences remain in charge.");});
  $("copy-code").onclick=()=>copy($("result-code").value);
  $("download-code").onclick=()=>operation(()=>{const code=exportCode(),url=URL.createObjectURL(new Blob([code],{type:"text/plain"})),a=document.createElement("a");a.href=url;a.download="rikui-setup.txt";a.click();URL.revokeObjectURL(url);});
  $("share").onclick=()=>operation(()=>{const code=exportCode(),url=new URL("/studio",location.origin);url.hash=encodeURIComponent(code);$("share-link").value=url.href;$("share-link").hidden=false;copy(url.href);message("Shareable result created. The pack is in the link fragment; no library or private records are stored on our server.");});
  $("theme-export").onclick=()=>operation(()=>{const p=model.pack();p.components={appearance:true};delete p.character;p.groups={};const resolved=model.resolve().profile;p.profile={theme:resolved.theme,font:resolved.font,borderColor:resolved.borderColor,textScale:resolved.textScale};delete p.adjustments;delete p.activities;delete p.devices;for(const k of Object.keys(p.profile))if(p.profile[k]===undefined)delete p.profile[k];p.id=p.id.slice(0,58)+"-theme";p.title=p.title.slice(0,74)+" theme";$("result-code").value=model.engine.call("Encode",p);$("result-panel").hidden=false;});
  $("maintain-identity").onchange=e=>operation(()=>model.change(s=>{s.maintainIdentity=e.target.checked;}));
  $("metadata-apply").onclick=()=>operation(()=>model.change(s=>{s.authorMetadata={title:$("pack-title").value,creator:$("pack-creator").value,revision:Number($("pack-revision").value)};}),"Attribution updated. Metadata changes do not rerender game captures.");
  $("creator-update").onclick=()=>operation(()=>{
   const incoming=model.engine.call("Import",$("import-code").value.trim());
   if(incoming.id!==model.source.id||incoming.revision<=model.source.revision)throw Error("Choose a newer revision of the same pack identity.");
   const previous=model.engine.call("Copy",model.source);
   const previousProfile=model.resolveWith(previous).profile,current=model.resolve().profile,incomingProfile=model.resolveWith(incoming).profile;
   const update=model.engine.call("Update",previousProfile,incomingProfile,current);
   $("update-conflicts").replaceChildren();
   for(const c of asArray(update.conflicts)){
    const label=document.createElement("label"),check=document.createElement("input");check.type="checkbox";
    label.append(check,document.createTextNode(" Accept creator change: "+c.path));
    $("update-conflicts").append(label);
    check.onchange=()=>{
     const choices={};for(const el of $("update-conflicts").querySelectorAll("input"))choices[el.dataset.path]=el.checked;
     operation(()=>{const merged=model.engine.call("Update",previousProfile,incomingProfile,current,choices);
      model.change(s=>{s.overrides=model.personalDifference(incomingProfile,merged.profile);});},undefined,true);
    };check.dataset.path=c.path;
   }
   model.change(s=>{s.source=incoming;s.overrides=model.personalDifference(incomingProfile,update.profile);s.authorMetadata=undefined;s.remixId=undefined;s.maintainIdentity=false;});message(asArray(update.conflicts).length+" update conflicts. Personal changes kept; select any creator changes you want.");
  });
  $("recipe").onchange=e=>operation(()=>model.change(s=>{for(const c of components)s.selected[c]=e.target.value==="all"?c!=="character":c===e.target.value;}));
  $("pack-title").value=model.source.title;$("pack-creator").value=model.source.creator;$("pack-revision").value=model.source.revision;
  $("studio-loading").hidden=true;root.hidden=false;message("Ready. Choose parts and adjust the actual captured components.");await render();
 }catch(error){message(error.message);$("studio-loading").firstChild.textContent="Editor could not start. "; }
}
if(root)start();
for(const button of document.querySelectorAll("[data-copy-pack]"))button.onclick=()=>{const code=document.getElementById(button.dataset.copyPack);if(code)copy(code.value);};
