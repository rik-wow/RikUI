// Editor state uses the exact addon engine. Fitting never rewrites the creator source.
const clone=value=>structuredClone(value);
export const components=["appearance","hud","nameplates","group","navigation","inventory","character"];
export const accessibility={
 standard:{},readable:{scale:1.15,textScale:1.15,nonColor:true},
 contrast:{scale:1.15,textScale:1.15,contrast:true,nonColor:true,reducedMotion:true},
 calm:{reducedMotion:true,nonColor:true}
};
export function normalizeImportCode(value){
 if(typeof value!=="string"||value.length>24000)throw Error("Export exceeds the supported copy/paste capacity.");
 const code=value.replace(/\s+/g,""),header=code.match(/^!RIKS1!([0-9]+):[0-9a-fA-F]{8}:(.*)$/);
 if(header&&Number(header[1])>header[2].length)throw Error("Incomplete export: missing "+(Number(header[1])-header[2].length)+" characters. Select all text in the addon export box and copy again.");
 return code;
}
export class StudioModel {
 constructor(engine){this.engine=engine;this.authorMetadata=undefined;this.history=[];this.future=[];this.accessibility="standard";this.viewport={width:1920,height:1080};this.activity="exploration";this.device="desktop";}
 snapshot(){return clone({source:this.source,overrides:this.overrides,selected:this.selected,viewport:this.viewport,device:this.device,activity:this.activity,accessibility:this.accessibility,accessibilityPinned:this.accessibilityPinned,remixId:this.remixId,integrationPresent:this.integrationPresent,authorMetadata:this.authorMetadata,maintainIdentity:this.maintainIdentity,baseline:this.baseline});}
 restore(state){Object.assign(this,clone(state));}
 remember(){if(this.source)this.history.push(this.snapshot());if(this.history.length>20)this.history.shift();this.future=[];}
 choose(name,pack){this.remember();this.remixId=undefined;this.authorMetadata=undefined;this.source=pack?this.engine.call("Validate",pack):this.engine.call("Bundled",name);this.maintainIdentity=false;this.baseline=this.engine.call("Merge",this.engine.call("Copy",this.source.profile),this.source.adjustments||{});this.overrides={};this.selected=clone(this.source.components);this.selected.character=false;}
 import(code){const pack=this.engine.call("Import",normalizeImportCode(code));this.remember();this.remixId=undefined;this.authorMetadata=undefined;this.source=pack;this.viewport=clone(pack.viewport);this.maintainIdentity=false;this.baseline=this.engine.call("Merge",this.engine.call("Copy",this.source.profile),this.source.adjustments||{});this.overrides={};this.selected=clone(pack.components);this.selected.character=false;this.device=pack.defaultDevice||this.device;this.activity=pack.defaultActivity||this.activity;if(!this.accessibilityPinned&&this.accessibility==="standard"&&accessibility[pack.accessibilityRecipe])this.accessibility=pack.accessibilityRecipe;}
 change(fn){const before=this.snapshot();const oldFuture=this.future;const oldHistory=[...this.history];this.remember();try{fn(this);this.engine.call("Validate",this.pack(false));}catch(error){this.restore(before);this.history=oldHistory;this.future=oldFuture;throw error;}}
 undo(forward=false){const from=forward?this.future:this.history,to=forward?this.history:this.future;if(!from.length)return false;to.push(this.snapshot());this.restore(from.pop());return true;}
 resolve(){return this.resolveWith(this.source,this.overrides);}
 resolveWith(source,overrides={}){const value=this.engine.call("Copy",source);overrides=this.engine.call("Copy",overrides);
  if(!this.selected.appearance){const base={...this.engine.call("Theme","classic"),textScale:1,scale:1,...this.baseline};for(const k of ["theme","font","borderColor","textScale","scale"])overrides[k]=base[k];}if(value.integration==="questtogether"&&!this.integrationPresent){value.ownership.nameplates="rikui";value.profile.modules??={};value.profile.modules.nameplates=true;}const result=this.engine.call("Resolve",value,{overrides,components:this.selected,viewport:this.viewport,device:this.device,activity:this.activity,accessibility:accessibility[this.accessibility],
  reservations:source.integration==="questtogether" && this.integrationPresent?[{x:8,y:this.viewport.height-200,width:320,height:180}]:[]});result.effectivePack=value;return result;}
 move(key,x,y){const resolved=this.resolve(),entry=Array.from(resolved.groups||[]).find(g=>g.key===key);if(!entry)throw Error("Choose a visible movable group");
  const scale=resolved.profile.scale||1;const r=entry.rect;
  x=Math.max(8,Math.min(this.viewport.width-r.width-8,x));y=Math.max(8,Math.min(this.viewport.height-r.height-8,y));
  const xs=[8,this.viewport.width-r.width-8,this.viewport.width/2-r.width/2],ys=[8,this.viewport.height-r.height-8];
  for(const g of Array.from(resolved.groups||[]))if(g.key!==key){xs.push(g.rect.x,g.rect.x+g.rect.width+8,g.rect.x-r.width-8);ys.push(g.rect.y,g.rect.y+g.rect.height+8,g.rect.y-r.height-8);}
  const snap=(v,lines)=>lines.reduce((best,line)=>Math.abs(line-v)<6?line:best,Math.round(v/8)*8);
  this.change(s=>{s.overrides.positions??={};s.overrides.positions[key]={point:"BOTTOMLEFT",relativePoint:"BOTTOMLEFT",x:Math.round(snap(x,xs)/scale*1000)/1000,y:Math.round(snap(y,ys)/scale*1000)/1000};});
 }
 reset(key){this.change(s=>{if(s.overrides.positions)delete s.overrides.positions[key];});}
 personalDifference(baseline,current){
  const overrides={};for(const entry of Array.from(this.engine.call("Diff",baseline,current)||[])){
   if(entry.after===undefined)continue;
   // Lua numeric paths are one-based. Keep complete array values (not sparse
   // string-key objects), including RGB colors required by the shared schema.
   let path=entry.path,value=current;
   for(let i=0;i<path.length;i++){if(Array.isArray(value)){path=path.slice(0,i);break;}value=value?.[path[i]];}
   let target=overrides;for(const key of path.slice(0,-1))target=target[key]??={};target[path.at(-1)]=clone(value);
  }return overrides;
 }
 pack(remix=true){
  const p=this.engine.call("Copy",this.source);
  p.adjustments=this.engine.call("Merge",p.adjustments||{},this.overrides);
  p.components=clone(this.selected);if(!p.components.character)delete p.character;p.viewport=clone(this.viewport);p.defaultDevice=this.device;p.defaultActivity=this.activity;p.accessibilityRecipe=this.accessibility;
  const edited=JSON.stringify(p.viewport)!==JSON.stringify(this.source.viewport) || Object.keys(this.overrides||{}).length || JSON.stringify(p.components)!==JSON.stringify(this.source.components) || this.authorMetadata || this.device!==(this.source.defaultDevice||"desktop") || this.activity!==(this.source.defaultActivity||"exploration") || this.accessibility!==(this.source.accessibilityRecipe||"standard");
  if(remix && edited && !this.maintainIdentity){
   p.ancestry={id:this.source.id,revision:this.source.revision,creator:this.source.creator};
   this.remixId??="remix-"+crypto.randomUUID();p.id=this.remixId;p.revision=1;p.creator="You";p.title=this.source.title.slice(0,72)+" remix";
  }
  if(remix&&edited&&this.maintainIdentity)p.revision=this.source.revision+1;
  if(this.authorMetadata)Object.assign(p,this.authorMetadata);
  if(remix&&this.maintainIdentity&&edited&&p.revision<=this.source.revision)throw Error("Maintained revisions must increase.");
  // Accessibility stays personal; no hidden personal records enter the pack.
  return this.engine.call("Validate",p);
 }
 export(){return this.engine.call("Encode",this.pack());}
 theme(name){this.change(s=>{s.overrides=this.engine.call("Merge",s.overrides,this.engine.call("Theme",name));});}
}
