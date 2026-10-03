export const docsScript = `
const nav = document.querySelector(".docs-nav-toggle");
const wide = matchMedia("(min-width:781px)");
function sizeNav(){ if(nav) nav.open = wide.matches; }
sizeNav(); wide.addEventListener("change",sizeNav);
nav?.addEventListener("keydown",event=>{
 if(event.key==="Escape"&&!wide.matches&&nav.open){
  event.preventDefault();nav.open=false;nav.querySelector("summary").focus();
 }
});
const guideNav=document.querySelector('.docs-sidebar nav');
const current=guideNav?.querySelector('[aria-current="page"]');
if(wide.matches&&current){
 const item=current.getBoundingClientRect(),area=guideNav.getBoundingClientRect();
 if(item.top<area.top||item.bottom>area.bottom)guideNav.scrollTop+=item.top-area.top-area.height/2+item.height/2;
}
const input = document.querySelector("#docs-search");
const links = [...document.querySelectorAll("[data-doc-link]")];
input?.addEventListener("input",()=>{
 const value=input.value.trim().toLowerCase();
 let visible=0;
 links.forEach(link=>{link.hidden=!(link.textContent+" "+(link.dataset.keywords||"")).toLowerCase().includes(value);if(!link.hidden)visible++;});
 document.querySelectorAll(".nav-group").forEach(group=>{group.hidden=![...group.querySelectorAll("a")].some(link=>!link.hidden);});
 document.querySelector("#search-empty").hidden=visible!==0;
});
// Setting previews: every frame is already in the page; the control picks which one shows.
for(const figure of document.querySelectorAll("figure[data-sequence]")){
 const frames=[...figure.querySelectorAll(".preview-frames [data-frame]")];
 const label=figure.querySelector(".preview-control");
 const control=label?.querySelector("input,select"), output=label?.querySelector("output");
 if(!control||frames.length<2) continue;
 const values=JSON.parse(label.dataset.values||"[]");
 const show=index=>{
  frames.forEach((frame,i)=>{frame.hidden=i!==index;});
  if(output) output.textContent=values[index]??"";
  if(control.type==="range") control.setAttribute("aria-valuetext",values[index]??"");
  figure.dataset.frame=String(index);
 };
 const indexOf=()=>control.type==="checkbox"?(control.checked?1:0):Number(control.value);
 control.addEventListener("input",()=>show(indexOf()));
 control.addEventListener("change",()=>show(indexOf()));
 label.hidden=false;
 show(indexOf());
}
`;