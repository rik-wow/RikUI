import {createEngine} from "./pack-engine.mjs";
import {StudioModel,components} from "./studio-model.mjs";
import {componentAppearanceCovered} from "./preview-coverage.mjs";
import {labelFor,paintPlacement,fitDetails,sampleShown,sampleEnabled} from "./studio-preview.mjs";
const $=id=>document.getElementById(id);
const status=$("studio-status"),root=$("studio-app");
const message=text=>{status.textContent=text;};
const images=new Map();
let model,data,resolved,selectedKey,drag,metadataStamp,renderEpoch=0,paintedKeys=new Set();
let currentStep="choose",currentTab="parts";
const partLabels={appearance:"Appearance & chat",hud:"Combat HUD",nameplates:"Nameplates",group:"Party & raid",navigation:"Map & quests",inventory:"Bags & loot",character:"Character setup"};
function workflow(step=currentStep,tab=currentTab,focus=true){
 currentStep=step;currentTab=tab;
 for(const b of document.querySelectorAll("[data-step]")){if(b.closest(".studio-steps")){if(b.dataset.step===step)b.setAttribute("aria-current","step");else b.removeAttribute("aria-current");}}
 for(const panel of document.querySelectorAll("[data-panel]"))panel.hidden=panel.dataset.panel!==step;
 for(const panel of document.querySelectorAll("[data-custom]"))panel.hidden=panel.dataset.custom!==tab;
 for(const b of document.querySelectorAll("[data-tab]")){const on=b.dataset.tab===tab;b.setAttribute("aria-selected",String(on));b.tabIndex=on?0:-1;}
 $("show-movers").checked=step==="customize"&&tab==="layout";
 if(focus)document.querySelector('[data-panel="'+step+'"] h2')?.focus({preventScroll:innerWidth>760});
 render();
}
const asArray=value=>Array.isArray(value)?value:[];
async function loadImage(url){
 if(!images.has(url))images.set(url,new Promise((resolve,reject)=>{const im=new Image();im.onload=()=>resolve(im);im.onerror=()=>reject(Error("Preview image unavailable. Export and install are still available."));im.src=url;}));
 return images.get(url);
}
function operation(fn,success,keepUpdate=false){try{if(!keepUpdate)$("update-conflicts")?.replaceChildren();fn();if(success)message(success);render();}catch(error){message(error.message);render();}}
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
  setOptions($("frame-group"),groups.map(g=>[g.key,labelFor(g.key)]));
  $("frame-group").value=selectedKey||"";
  $("pack-picker").value=data.packs.find(p=>p.pack.id===model.source.id)?.name||"";
  for(const c of components){const check=$("part-"+c);check.checked=!!model.selected[c];check.disabled=c==="character"&&!model.source.character;}
  for(const id of ["device","activity","accessibility"])$(id).value=model[id];
  const viewportValue=model.viewport.width+"x"+model.viewport.height;
  if(!Array.from($("viewport").options).some(o=>o.value===viewportValue)){const o=document.createElement("option");o.value=viewportValue;o.textContent=model.viewport.width+" × "+model.viewport.height+" (imported)";$("viewport").append(o);}
  $("viewport").value=viewportValue;
  $("undo").disabled=!model.history.length;$("redo").disabled=!model.future.length;
  const metadata=model.authorMetadata||{...model.source,revision:model.maintainIdentity?model.source.revision+1:model.source.revision};
  const stamp=JSON.stringify(metadata);if(stamp!==metadataStamp){$("pack-title").value=metadata.title;$("pack-creator").value=metadata.creator;$("pack-revision").value=metadata.revision;metadataStamp=stamp;}
  $("maintain-identity").checked=!!model.maintainIdentity;
  $("pack-description").textContent=model.source.title+" · "+model.source.creator+" · revision "+model.source.revision+(model.source.ancestry?" · remix of "+model.source.ancestry.id+" r"+model.source.ancestry.revision:"");
  $("ownership").textContent="Adopting: "+components.filter(c=>model.selected[c]).map(c=>partLabels[c]+" ("+resolved.effectivePack.ownership[c]+")").join(" · ");
  for(const b of document.querySelectorAll("[data-pack]"))b.setAttribute("aria-pressed",String(data.packs.find(p=>p.name===b.dataset.pack)?.pack.id===model.source.id));
  const conflicts=fitDetails(resolved,model.viewport);
  $("fit-status").textContent=conflicts.length?conflicts.length+" fitting conflict(s). Red outlines show affected footprints; select a conflict below.":"Keeps the character viewing area clear and fits the declared frame footprints. Dynamic contents can grow; review again in the addon.";
  $("fit-status").className=conflicts.length?"issue":"";
  $("fit-badge").textContent=conflicts.length?conflicts.length+" fit issues to resolve":"Layout fits";$("fit-badge").className="fit-badge"+(conflicts.length?" issue":"");
  $("export-help").textContent=conflicts.length?"Resolve the highlighted frames before exporting. Select an issue to open its layout controls.":"Export the code, then open /rik studio → Import in the addon. Review and apply there.";
  $("export").disabled=$("share").disabled=conflicts.length>0;
  $("character-details").textContent=model.source.character?JSON.stringify(model.source.character,null,2):"No action-bar preset, macros or bindings included.";
  const profile=resolved.profile,key=themeKey(profile),readability=(profile.textScale||1)>1?"readable":"standard";
  $("theme-description").textContent={classic:"Gold accent · RikUI font · textured panels · thin border",ocean:"Blue accent · RikUI font · flat panels · thin border",ink:"White accent · game font · flat panels · strong border · relaxed spacing"}[key];
  $("theme").value=key;
  const effectiveScale=profile.scale||1,requestedScale=model.selected.appearance?(model.overrides.scale??effectiveScale):effectiveScale;
  const percent=value=>Number((value*100).toFixed(3)),requestedPercent=percent(requestedScale),effectivePercent=percent(effectiveScale);
  $("ui-scale").value=String(requestedPercent);$("ui-scale-percent").value=String(requestedPercent);
  $("ui-scale").setAttribute("aria-valuetext",requestedPercent+"%; effective "+effectivePercent+"%");
  for(const id of ["ui-scale","ui-scale-percent","ui-scale-reset"])$(id).disabled=!model.selected.appearance;
  $("ui-scale-summary").textContent=!model.selected.appearance?"Kept from your current setup. Select Appearance & chat to edit UI scale.":
   "Effective UI scale: "+effectivePercent+"%."+(effectiveScale>requestedScale+0.000001?" Readability or theme spacing requires at least "+effectivePercent+"%; your "+requestedPercent+"% choice is preserved.":"");
  $("questtogether").checked=!!model.integrationPresent;
  const atlas=structuredClone(data.atlases[key+"-"+readability]);
  if(profile.questtracker?.collapsed)atlas.components.questtracker=atlas.components.questtrackerCollapsed;
  const covered=g=>!!atlas.components[g.key]&&componentAppearanceCovered(g.key,profile,model.engine,key);
  const shown=g=>sampleEnabled(g.key,profile)&&covered(g)&&sampleShown(g.key,model.activity,selectedKey,$("show-conditional").checked);
  const unsupported=groups.filter(g=>!covered(g)).map(g=>labelFor(g.key));
  $("preview-limit").textContent="Actual RikUI component captures, positioned by the addon’s fitting engine. Dashed labeled boxes show reserved mover footprints, including currently inactive frames."+
   (unsupported.length?" Geometry-only (no exact capture): "+unsupported.join(", ")+".":"")+
   " The center guide reserves character viewing space; it is an editor annotation, not a rendered character. Representative fixture data; world imagery, live names and optional addon widgets are outside this preview.";
  const showPlates=model.selected.nameplates&&resolved.effectivePack.ownership.nameplates==="rikui"&&profile.modules?.nameplates!==false&&componentAppearanceCovered("nameplates",profile,model.engine,key);
  const drawn=groups.filter(shown);
  $("game-preview").dataset.previewReady="false";
  const bitmap=new Map(await Promise.all([...drawn,...(showPlates&&atlas.components.nameplates?[{key:"nameplates"}]:[])].map(async g=>[g.key,await loadImage(atlas.components[g.key].url)])));if(epoch!==renderEpoch)return;
  const canvas=$("game-preview"),ctx=canvas.getContext("2d");
  canvas.width=model.viewport.width;canvas.height=model.viewport.height;
  ctx.fillStyle="#0c1117";ctx.fillRect(0,0,canvas.width,canvas.height);
  const scale=profile.scale||1;paintedKeys=new Set(drawn.map(g=>g.key));
  for(const g of drawn){
   const c=atlas.components[g.key],p=paintPlacement(c,g.rect,scale,canvas.height);
   ctx.drawImage(bitmap.get(g.key),p.sx,p.sy,p.width,p.height,p.x,p.y,p.drawWidth,p.drawHeight);
  }
  if(showPlates&&atlas.components.nameplates){
   const c=atlas.components.nameplates,p=paintPlacement(c,{x:canvas.width/2-c.width*scale/2,y:canvas.height*0.7},scale,canvas.height);
   ctx.drawImage(bitmap.get("nameplates"),p.sx,p.sy,p.width,p.height,p.x,p.y,p.drawWidth,p.drawHeight);
  }
  renderAnnotations(groups,conflicts,covered);
  canvas.dataset.paintedGroups=JSON.stringify([...paintedKeys]);canvas.dataset.previewReady="true";
  canvas.setAttribute("aria-label","Authentic RikUI preview. Selected group "+(selectedKey||"none")+". Use frame controls or arrow keys to adjust it.");
  $("geometry").textContent=selectedKey?(()=>{const r=groups.find(g=>g.key===selectedKey).rect;return selectedKey+": "+Math.round(r.x)+", "+Math.round(r.y)+" · "+Math.round(r.width)+" × "+Math.round(r.height);})():"No selected movable groups.";
 }catch(error){message(error.message);}
}

function selectGroup(key){selectedKey=key;render();}
function renderAnnotations(groups,conflicts,covered){
 const layer=$("mover-layer"),list=$("frame-list"),issues=$("fit-conflicts");
 layer.replaceChildren();list.replaceChildren();issues.replaceChildren();
 const troubled=new Set(conflicts.flatMap(c=>[c.key,...c.with]));
 const place=(node,r)=>{
  const w=model.viewport.width,h=model.viewport.height;
  node.style.left=100*Math.max(0,Math.min(w-4,r.x))/w+"%";
  node.style.top=100*Math.max(0,Math.min(h-4,h-r.y-r.height))/h+"%";
  node.style.width=100*Math.max(4,Math.min(r.width,w-Math.max(0,r.x)))/w+"%";
  node.style.height=100*Math.max(4,Math.min(r.height,h-Math.max(0,h-r.y-r.height)))/h+"%";
 };
 for(const g of groups){
  const state=!sampleEnabled(g.key,resolved.profile)?"disabled module":paintedKeys.has(g.key)?"sample":covered(g)?"inactive sample":"geometry only";
  const button=document.createElement("button");button.type="button";button.dataset.group=g.key;
  button.className="studio-mover"+(g.key===selectedKey?" selected":"")+(troubled.has(g.key)?" conflict":"");
  button.setAttribute("aria-label","Select "+labelFor(g.key)+" — "+state);
  button.title=labelFor(g.key)+" — "+state+"; outline is the reserved footprint";
  const label=document.createElement("span");label.textContent=labelFor(g.key);button.append(label);place(button,g.rect);
  button.hidden=!$("show-movers").checked&&!troubled.has(g.key)&&g.key!==selectedKey;
  button.onclick=()=>selectGroup(g.key);layer.append(button);
  const entry=document.createElement("button");entry.type="button";entry.dataset.group=g.key;
  entry.textContent=labelFor(g.key)+" · "+state;entry.setAttribute("aria-pressed",String(g.key===selectedKey));
  entry.onclick=()=>selectGroup(g.key);list.append(entry);
 }
 for(const g of asArray(resolved.groups).filter(g=>!model.source.groups[g.key])){
  const box=document.createElement("div");box.className="studio-reservation"+(g.character?" character-area":"")+(troubled.has(g.key)?" conflict":"");
  const label=document.createElement("span");label.textContent=labelFor(g.key);box.append(label);
  if(g.character){box.dataset.characterArea="true";const center=document.createElement("small");center.textContent="Your character · screen center";box.append(center);box.setAttribute("aria-label","Character viewing area. Persistent frames keep clear; temporary windows can cover it.");}
  place(box,g.rect);layer.append(box);
 }
 for(const c of conflicts){
  const b=document.createElement("button");b.type="button";b.className="fit-conflict";b.dataset.group=c.key;
  b.textContent=labelFor(c.key)+": "+c.reason;b.onclick=()=>{selectedKey=c.key;workflow("customize","layout");$("preview-stage").scrollIntoView({block:"nearest"});};issues.append(b);
 }
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
  if(location.hash.length>1){model.import(decodeURIComponent(location.hash.slice(1)));currentStep="customize";}
  setOptions($("pack-picker"),[["","Imported / custom"],...data.packs.map(p=>[p.name,p.pack.title])]);
  for(const c of components)$("part-"+c).addEventListener("change",e=>operation(()=>model.change(s=>{s.selected[c]=e.target.checked;}),"Component choice staged."));
  const choose=name=>operation(()=>model.choose(name,data.packs.find(p=>p.name===name).pack),"Starting setup selected. Continue to choose parts.");
  $("pack-picker").onchange=e=>{if(e.target.value)choose(e.target.value);};
  for(const b of document.querySelectorAll("[data-pack]"))b.onclick=()=>choose(b.dataset.pack);
  for(const b of document.querySelectorAll("[data-step]"))b.onclick=()=>workflow(b.dataset.step);
  for(const b of document.querySelectorAll("[data-tab]")){b.onclick=()=>workflow("customize",b.dataset.tab);b.onkeydown=e=>{const order=["parts","style","layout"],index=order.indexOf(b.dataset.tab);let next;if(e.key==="ArrowRight")next=(index+1)%3;if(e.key==="ArrowLeft")next=(index+2)%3;if(e.key==="Home")next=0;if(e.key==="End")next=2;if(next!==undefined){e.preventDefault();workflow("customize",order[next],false);$("tab-"+order[next]).focus();}};}
  $("edit-positions").onclick=()=>workflow("customize","layout");$("review-fit").onclick=()=>workflow("review");
  $("preview-zoom").onchange=e=>{$("preview-stage").style.setProperty("--preview-zoom",e.target.value);};
  $("import").onclick=()=>operation(()=>{model.import($("import-code").value);workflow("customize","parts");},"Imported for editing. Nothing has been applied to your addon.");
  for(const id of ["device","activity","accessibility"])$(id).onchange=e=>operation(()=>model.change(s=>{
   s[id]=e.target.value;if(id==="accessibility")s.accessibilityPinned=true;if(id==="device"){s.viewport=id&&s.device==="handheld"?{width:1280,height:800}:s.device==="ultrawide"?{width:3440,height:1440}:{width:1920,height:1080};}
  }));
  $("viewport").onchange=e=>operation(()=>model.change(s=>{const [width,height]=e.target.value.split("x").map(Number);s.viewport={width,height};}));
  $("theme").onchange=e=>operation(()=>model.theme(e.target.value),"Theme staged. Module, font and theme changes can require an addon reload.");
  const setScale=e=>operation(()=>{
   const value=Number(e.target.value);if(!e.target.value.trim()||!Number.isFinite(value)||value<25||value>300)throw Error("Choose a UI scale from 25% to 300%.");
   model.change(s=>{s.overrides.scale=value/100;});
  });
  $("ui-scale").oninput=e=>{$("ui-scale-percent").value=e.target.value;e.target.setAttribute("aria-valuetext",e.target.value+"%");};
  $("ui-scale").onchange=$("ui-scale-percent").onchange=setScale;
  $("ui-scale-reset").onclick=()=>operation(()=>model.change(s=>{delete s.overrides.scale;}),"Setup UI scale restored; personal readability remains in charge.");
  $("questtogether").onchange=e=>operation(()=>model.change(s=>{
   s.integrationPresent=e.target.checked;s.source.integration="questtogether";s.source.ownership.nameplates=e.target.checked?"specialist":"rikui";
   s.overrides.modules??={};s.overrides.modules.nameplates=!e.target.checked;
  }),"QuestTogether recipe: use stock nameplates, QT icons Left, health tint off, and its personal bubble in the reserved upper-left area. Missing QT keeps RikUI in charge.");
  $("undo").onclick=()=>operation(()=>model.undo());$("redo").onclick=()=>operation(()=>model.undo(true));
  $("frame-group").onchange=e=>{selectedKey=e.target.value;render();};
  for(const b of document.querySelectorAll("[data-move]"))b.onclick=()=>operation(()=>move(...b.dataset.move.split(",").map(Number)));
  $("reset-frame").onclick=()=>operation(()=>model.reset(selectedKey));
  $("align-center").onclick=()=>operation(()=>{const g=visibleGroups().find(g=>g.key===selectedKey);if(g)model.move(g.key,(model.viewport.width-g.rect.width)/2,g.rect.y);});
  $("show-movers").onchange=()=>render();$("show-conditional").onchange=()=>render();
  const stage=$("preview-stage"),canvas=$("game-preview");
  stage.onpointerdown=e=>{
   if(e.button!==0||canvas.dataset.previewReady!=="true")return;
   const p=point(e),explicit=e.target.closest("[data-group]")?.dataset.group;
   const group=explicit?visibleGroups().find(g=>g.key===explicit):[...visibleGroups()].reverse().find(g=>($("show-movers").checked||paintedKeys.has(g.key)||g.key===selectedKey)&&p.x>=g.rect.x&&p.x<=g.rect.x+g.rect.width&&p.y>=g.rect.y&&p.y<=g.rect.y+g.rect.height);
   if(!group)return;selectedKey=group.key;
   drag={start:{x:e.clientX,y:e.clientY},moved:false,key:group.key,offset:{x:p.x-group.rect.x,y:p.y-group.rect.y},point:p,base:canvas.getContext("2d").getImageData(0,0,canvas.width,canvas.height),rect:group.rect};
   stage.setPointerCapture(e.pointerId);canvas.focus({preventScroll:true});e.preventDefault();
  };
  stage.onpointermove=e=>{if(drag){if(!drag.moved&&Math.hypot(e.clientX-drag.start.x,e.clientY-drag.start.y)<3)return;drag.moved=true;drag.point=point(e);const ctx=canvas.getContext("2d");ctx.putImageData(drag.base,0,0);ctx.strokeStyle="#75cedb";ctx.lineWidth=3;ctx.setLineDash([8,5]);ctx.strokeRect(drag.point.x-drag.offset.x,canvas.height-(drag.point.y-drag.offset.y)-drag.rect.height,drag.rect.width,drag.rect.height);ctx.setLineDash([]);$("geometry").textContent="Move "+labelFor(drag.key)+" to "+Math.round(drag.point.x-drag.offset.x)+", "+Math.round(drag.point.y-drag.offset.y)+" (snaps when released)";}};
  stage.onpointerup=e=>{if(drag){const d=drag;drag=null;stage.releasePointerCapture(e.pointerId);if(d.moved)operation(()=>model.move(d.key,d.point.x-d.offset.x,d.point.y-d.offset.y));else render();}};
  stage.onpointercancel=()=>{drag=null;render();};
  $("game-preview").onkeydown=e=>{
   const directions={ArrowLeft:[-8,0],ArrowRight:[8,0],ArrowUp:[0,8],ArrowDown:[0,-8]};
   if(directions[e.key]){e.preventDefault();operation(()=>move(...directions[e.key]));}
   if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==="z"){e.preventDefault();operation(()=>model.undo(e.shiftKey));}
  };
  $("export").onclick=()=>operation(()=>{exportCode();message("Import this code in /rik studio. Review ownership, conflicts and reload requirements, then Apply. Your personal accessibility preferences remain in charge.");});
  $("copy-code").onclick=()=>copy($("result-code").value);
  $("download-code").onclick=()=>operation(()=>{const code=exportCode(),url=URL.createObjectURL(new Blob([code],{type:"text/plain"})),a=document.createElement("a");a.href=url;a.download="rikui-setup.txt";a.click();URL.revokeObjectURL(url);});
  $("share").onclick=()=>operation(()=>{const code=exportCode(),url=new URL("/studio",location.origin);url.hash=encodeURIComponent(code);$("share-link").value=url.href;$("share-link").hidden=false;$("share-link-label").hidden=false;copy(url.href);message("Shareable result created. The pack is in the link fragment; no library or private records are stored on our server.");});
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
  $("studio-loading").hidden=true;root.hidden=false;message("Ready. Choose a starting setup or import your current UI.");workflow(currentStep,currentTab,false);await render();
 }catch(error){message(error.message);$("studio-loading").firstChild.textContent="Editor could not start. "; }
}
if(root)start();
for(const button of document.querySelectorAll("[data-copy-pack]"))button.onclick=()=>{const code=document.getElementById(button.dataset.copyPack);if(code)copy(code.value);};