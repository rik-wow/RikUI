// Browser controls only. Geometry, fitting and captured pixels stay in the shared engine.
const $=id=>document.getElementById(id);
export const barKeys=["main","bar2","bar3","bar4","bar5","stance","pet"];
const shortNames={main:"Main",bar2:"Bar 2",bar3:"Bar 3",bar4:"Bar 4",bar5:"Bar 5",stance:"Stance",pet:"Pet"};
export function setupBarEditor({root,select,change}){
 const tabs=root.querySelector(".studio-tabs"),home=tabs.parentElement,anchor=tabs.nextElementSibling;
 $("layout-tools").append($("custom-layout"));$("shape-slot").append($("frame-shape"));
 $("position-settings").before($("geometry"));
 let layout=false,closed=false,arrangementCount,previousKey;
 for(const key of barKeys){
  const b=document.createElement("button");b.type="button";b.dataset.bar=key;b.textContent=shortNames[key];
  b.onclick=()=>{closed=false;select(key);};$("bar-picker").append(b);
 }
 const setOpen=on=>{
  closed=!on;$("layout-inspector").hidden=!on;
  $("show-inspector").setAttribute("aria-expanded",String(on));
  $("show-inspector").textContent=on?"Hide frame controls":"Show frame controls";
  $("workspace-controls").setAttribute("aria-expanded",String(on));$("workspace-controls").textContent=on?"Hide controls":"Show controls";
 };
 $("close-inspector").onclick=()=>{setOpen(false);$("show-inspector").focus();};
 $("show-inspector").onclick=()=>setOpen(closed);
 for(const b of $("bar-gaps").querySelectorAll("button"))b.onclick=()=>change("spacing",b.dataset.gap);
 return {
  workflow(on){
   if(layout!==on){
    layout=on;root.classList.toggle("layout-workspace",on);
    if(on){$("layout-tabs").append(tabs);closed=false;window.scrollTo({top:0,behavior:"instant"});}
    else home.insertBefore(tabs,anchor);
   }
   for(const id of ["layout-navigation","bar-picker","layout-tools"])$(id).hidden=!on;
   $("workspace-controls").setAttribute("aria-controls",on?"layout-inspector":"studio-controls");
   setOpen(!closed);
  },
  select(){closed=false;setOpen(true);},
  render({selectedKey,groups,shape,count,editable,labelFor}){
   for(const b of $("bar-picker").children){
    const g=groups.find(g=>g.key===b.dataset.bar);
    b.hidden=!g;b.setAttribute("aria-pressed",String(b.dataset.bar===selectedKey));
    b.title=labelFor(b.dataset.bar)+(g?.disabled?" · off; stored shape":" · edit this bar");
    b.classList.toggle("bar-off",!!g?.disabled);
   }
   const isBar=barKeys.includes(selectedKey);
   $("inspector-title").textContent=labelFor(selectedKey);
   if(previousKey!==selectedKey){$("position-settings").open=!isBar;previousKey=selectedKey;}
   if(!isBar)return;
   if(count!==arrangementCount){
    arrangementCount=count;
    const columns=[count,Math.ceil(count/2),Math.ceil(count/3),Math.ceil(count/4),2,1].filter((c,i,a)=>a.indexOf(c)===i);
    $("bar-arrangements").replaceChildren(...columns.map(cols=>{
     const rows=Math.ceil(count/cols),b=document.createElement("button");
     b.type="button";b.dataset.columns=cols;
     b.setAttribute("aria-label",cols+" buttons per row, "+rows+(rows===1?" row":" rows"));
     const icon=document.createElement("span");icon.className="arrangement-icon";icon.setAttribute("aria-hidden","true");icon.style.setProperty("--columns",cols);icon.style.setProperty("--rows",rows);
     for(let i=0;i<count;i++)icon.append(document.createElement("i"));
     const text=document.createElement("span");text.textContent=rows===1?"One row":cols===1?"Vertical":cols+" × "+rows;
     b.append(icon,text);b.onclick=()=>change("columns",String(cols));return b;
    }));
   }
   for(const b of $("bar-arrangements").children){b.disabled=!editable;b.setAttribute("aria-pressed",String(Number(b.dataset.columns)===shape.columns));}
   for(const b of $("bar-gaps").children){b.disabled=!editable;b.setAttribute("aria-pressed",String(Number(b.dataset.gap)===shape.spacing));}
   $("bar-shape-reset").disabled=!editable;
  }
 };
}
