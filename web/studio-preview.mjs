// Editor annotations over authentic captures; no game widget drawing lives here.
export const labels={main:"Main action bar",bar2:"Action bar 2",bar3:"Action bar 3",bar4:"Action bar 4",bar5:"Action bar 5",stance:"Stance / aura bar",pet:"Pet action bar",player:"Player",target:"Target",tot:"Target of target",focus:"Focus",petframe:"Pet",castplayer:"Player cast",casttarget:"Target cast",castfocus:"Focus cast",castpet:"Pet cast",buffs:"Buffs",debuffs:"Debuffs",cooldowns:"Cooldowns",swingtimer:"Weapon timers",combatresource:"Combat resource",combopoints:"Combo points",totems:"Totems",xpbar:"Experience / reputation",party:"Party frames",raid:"Raid frames",minimap:"Minimap",questtracker:"Quest tracker",questtimers:"Quest timers",chat:"Chat",damagemeter:"Damage meter",bags:"Inventory",loot:"Loot",micromenu:"Micro menu / bags",durability:"Durability",bagspace:"Bag capacity"};
export const labelFor=key=>labels[key]||key;
export function paintPlacement(component,rect,scale,canvasHeight){
 const paint=component.paint;
 if(!paint)throw Error("Native capture has no reviewed paint bounds");
 return {sx:paint.x-(component.bitmap?.x||0),sy:paint.y-(component.bitmap?.y||0),width:paint.width,height:paint.height,
  x:rect.x+(paint.x-component.x)*scale,
  y:canvasHeight-rect.y-(component.atlasHeight-paint.y-component.y)*scale,
  drawWidth:paint.width*scale,drawHeight:paint.height*scale};
}
// Reflow authentic native button pixels using the grid supplied by the shared Lua model.
export function paintGrid(ctx,image,sprite,entry,scale,canvasHeight){
 const source=sprite.cells,grid=entry.geometry.grid,body=entry.bodyRect||entry.rect;
 if(grid.size!==source.size||grid.count>source.count)throw Error("No exact native grid sample");
 for(let i=0;i<grid.count;i++){
  const sx=sprite.x+(i%source.columns)*(source.size+source.spacing);
  const sy=sprite.atlasHeight-sprite.y-sprite.height+Math.floor(i/source.columns)*(source.size+source.spacing);
  const x=body.x+(i%grid.columns)*(grid.size+grid.spacing)*scale;
  const y=canvasHeight-body.y-body.height+Math.floor(i/grid.columns)*(grid.size+grid.spacing)*scale;
  ctx.drawImage(image,sx,sy,grid.size,grid.size,x,y,grid.size*scale,grid.size*scale);
 }
}
const overlaps=(a,b)=>a.x<b.x+b.width+7.998 && a.x+a.width+7.998>b.x && a.y<b.y+b.height+7.998 && a.y+a.height+7.998>b.y;
export function fitDetails(resolved,viewport){
 const groups=Array.from(resolved.groups||[]);
 return Array.from(resolved.conflicts||[]).map(issue=>{
  const index=groups.findIndex(g=>g.key===issue.key),group=groups[index],r=group?.rect;
  const neighbors=group&&!group.floating?groups.slice(0,index).filter(other=>!other.floating && (!group.exclusive||group.exclusive!==other.exclusive) && overlaps(r,other.rect)).map(g=>g.key):[];
  const outside=r&&(r.x<7.998||r.y<7.998||r.x+r.width>viewport.width-7.998||r.y+r.height>viewport.height-7.998);
  const reason=issue.reason==="Below readable minimum"?"Below the pack’s readable minimum":outside?"Outside the screen’s 8-unit safe edge":neighbors.length?"Overlaps or lacks the 8-unit clearance from "+neighbors.map(labelFor).join(", "):issue.reason;
  return {...issue,reason,with:neighbors,rect:r};
 });
}
export const sampleEnabled=(key,profile,engine)=>engine.call("GroupEnabled",key,{modules:profile.modules})&&!profile.presentation?.hidden?.[key];
const conditional=new Set(["bags","loot","pet","petframe","casttarget","castfocus","castpet","combopoints","totems","questtimers","damagemeter"]);
export function sampleShown(key,activity,selected,showConditional=false){
 if(key==="bags")return activity==="town"||key===selected||showConditional;
 if(conditional.has(key))return key===selected||showConditional;
 return true;
}
