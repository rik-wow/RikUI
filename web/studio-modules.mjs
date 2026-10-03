// Feature controls use shared Lua semantics and reviewed component bitmaps.
import {labelFor} from "./studio-preview.mjs";
const $=id=>document.getElementById(id);
const array=v=>Array.isArray(v)?v:[];
export function moduleState(model,choice,resolved=model.resolve()){
 const owned=array(choice.components).filter(c=>model.selected[c]&&resolved.effectivePack.ownership[c]==="rikui");
 const on=resolved.profile.modules?.[choice.key]!==false;
 const blocked=on&&!model.engine.call("ModuleEnabled",resolved.profile,choice.key);
 const shared=choice.key==="unitframes"&&!(owned.includes("hud")&&owned.includes("group"));
 return {on,blocked,editable:owned.length>0&&!(shared&&on),
  note:!owned.length?"Kept from your current UI, or managed by another addon.":shared&&on?"Shared by Combat HUD and Party & raid. Adopt both areas to turn off.":blocked?"Required features are off. Toggle this switch off and on to enable its requirements.":"Changes take effect after reloading RikUI.",
  status:!owned.length?"Kept":blocked?"Blocked":on?"On":"Off"};
}
export async function renderModules({model,data,resolved,atlas,loadImage,selectGroup,toggle,selectedKey}){
 const active=document.activeElement?.id,area=$("module-area").value,query=$("module-search").value.trim().toLowerCase();
 const first=["bars","unitframes","castbars","auras","chat","minimap","questtracker","bags","nameplates"],rank=c=>first.includes(c.key)?first.indexOf(c.key):100;
 const choices=[...data.modules].sort((a,b)=>rank(a)-rank(b)||a.title.localeCompare(b.title)).filter(c=>(!area||array(c.components).includes(area))&&(!query||(c.title+" "+c.summary+" "+c.key).toLowerCase().includes(query)));
 const list=$("module-cards");list.replaceChildren();
 $("module-count").textContent=choices.length+" of "+data.modules.length+" features · switches are saved in your export";
 const thumbnails=[];
 for(const choice of choices){
  const state=moduleState(model,choice,resolved),card=document.createElement("article");card.className="module-card"+(!state.on?" module-off":"")+(state.blocked?" module-blocked":"");card.dataset.module=choice.key;
  const key=[...["main","player","castplayer","buffs"].filter(k=>array(choice.groups).includes(k)),...array(choice.groups)].find(k=>atlas.components[k]&&model.source.groups[k])||(choice.key==="nameplates"?"nameplates":undefined),component=atlas.components[key];
  const visual=document.createElement("button");visual.type="button";visual.className="module-visual";visual.disabled=!key||key==="nameplates";
  visual.setAttribute("aria-label",key?"Show "+choice.title+" in preview":"No canvas preview for "+choice.title);
  if(component){
   const canvas=document.createElement("canvas");canvas.width=260;canvas.height=100;canvas.setAttribute("aria-hidden","true");visual.append(canvas);
   thumbnails.push(loadImage(component.url).then(image=>{const p=component.paint,ctx=canvas.getContext("2d"),scale=Math.min(244/p.width,84/p.height);ctx.drawImage(image,p.x,p.y,p.width,p.height,(260-p.width*scale)/2,(100-p.height*scale)/2,p.width*scale,p.height*scale);}));
  }else if(choice.guideSample){const image=document.createElement("img");image.src=choice.guideSample.url;image.alt="Actual RikUI guide example; no canvas preview";image.loading="lazy";visual.append(image);}
  else{const hint=document.createElement("span");hint.textContent="No captured example";visual.append(hint);}
  visual.onclick=()=>selectGroup(key);card.append(visual);
  const title=document.createElement("strong");title.textContent=choice.title;card.append(title);
  const label=document.createElement("label"),check=document.createElement("input");check.id="module-"+choice.key;check.type="checkbox";check.setAttribute("role","switch");check.setAttribute("aria-label",choice.title+" enabled");check.checked=state.on;check.disabled=!state.editable;check.onchange=()=>toggle(choice.key,check.checked);label.append(check,document.createTextNode(state.status));card.append(label);
  const note=document.createElement("p");note.className="fine";note.textContent=state.note+(!key?" Guide example; no canvas preview.":"");card.append(note);
  const link=document.createElement("a");link.href=choice.guide;link.target="_blank";link.rel="noopener";link.textContent="Feature guide ↗";card.append(link);
  list.append(card);
 }
 if(!choices.length)list.textContent="No matching features. Try another area or name.";
 if(active?.startsWith("module-"))$(active)?.focus({preventScroll:true});
 const choice=data.modules.find(c=>array(c.groups).includes(selectedKey));
 const inspector=$("selected-feature");inspector.hidden=!choice;
 if(choice){
  const state=moduleState(model,choice,resolved);$("selected-feature-title").textContent=choice.title+" · "+labelFor(selectedKey);
  const check=$("selected-feature-enabled");check.checked=state.on;check.disabled=!state.editable;check.setAttribute("aria-label",choice.title+" enabled in selected frame");check.onchange=()=>toggle(choice.key,check.checked);
  $("selected-feature-note").textContent=state.status+" · "+state.note;
  $("selected-feature-guide").href=choice.guide;
 }
 await Promise.all(thumbnails);
}
