// Precision workspace is presentation-only; it never changes a pack or UI scale.
export function setupWorkspace(root,message){
 const enter=document.getElementById("fullscreen"),exit=document.getElementById("exit-fullscreen"),toggle=document.getElementById("workspace-controls"),shell=root.querySelector(".preview-shell"),stage=document.getElementById("preview-stage");
 let active=false,previousFocus,previousOverflow,inert=[],wasNative=false;
 const fit=()=>{
  if(!active&&(!root.classList.contains("layout-workspace")||innerWidth<=760)){stage.style.removeProperty("--fit-width");return;}
  const canvas=document.getElementById("game-preview"),width=Math.min(shell.clientWidth,Math.max(160,shell.clientHeight)*canvas.width/canvas.height);
  stage.style.setProperty("--fit-width",width+"px");
 };
 const setActive=on=>{
  if(active===on){fit();return;}active=on;
  root.classList.toggle("precision-workspace",on);enter.setAttribute("aria-pressed",String(on));
  if(on){
   previousFocus=document.activeElement;previousOverflow=document.body.style.overflow;document.body.style.overflow="hidden";
   let child=root;while(child.parentElement){for(const sibling of child.parentElement.children)if(sibling!==child){inert.push([sibling,sibling.inert]);sibling.inert=true;}child=child.parentElement;}
   exit.focus({preventScroll:true});
  }else{
   document.body.style.overflow=previousOverflow;for(const [node,value]of inert)node.inert=value;inert=[];
   root.classList.remove("controls-collapsed");toggle.setAttribute("aria-expanded","true");toggle.textContent="Hide controls";
   (previousFocus?.isConnected?previousFocus:enter).focus({preventScroll:true});
  }
  fit();
 };
 const leave=async()=>{if(document.fullscreenElement===root)await document.exitFullscreen();setActive(false);};
 enter.onclick=async()=>{
  if(active){await leave();return;}
  // requestFullscreen must happen synchronously inside the user's activation.
  const request=root.requestFullscreen&&document.fullscreenEnabled?root.requestFullscreen():null;
  setActive(true);message("Precision workspace. Zoom for detail; Escape returns to the page.");
  try{if(request){await request;wasNative=true;}}catch{message("Browser fullscreen unavailable. Expanded workspace is active; Escape returns to the page.");}
 };
 exit.onclick=()=>leave();
 toggle.onclick=()=>{if(root.classList.contains("layout-workspace")){document.getElementById("show-inspector").click();const on=!document.getElementById("layout-inspector").hidden;toggle.setAttribute("aria-expanded",String(on));toggle.textContent=on?"Hide controls":"Show controls";fit();return;}const collapsed=root.classList.toggle("controls-collapsed");toggle.setAttribute("aria-expanded",String(!collapsed));toggle.textContent=collapsed?"Show controls":"Hide controls";fit();};
 document.addEventListener("fullscreenchange",()=>{if(document.fullscreenElement===root){wasNative=true;setActive(true);}else if(wasNative){wasNative=false;setActive(false);}});
 root.addEventListener("keydown",e=>{
  if(!active)return;
  if(e.key==="Escape"){e.preventDefault();leave();return;}
  if(e.key==="Tab"){
   const nodes=[...root.querySelectorAll('button:not(:disabled),input:not(:disabled),select:not(:disabled),textarea:not(:disabled),a[href],[tabindex="0"]')].filter(n=>n.getClientRects().length&&!n.closest("[hidden]"));
   const first=nodes[0],last=nodes.at(-1);
   if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus();}
   else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus();}
  }
 });
 const observer=new ResizeObserver(fit);observer.observe(shell);observer.observe(document.getElementById("game-preview"));
 const presentation=new MutationObserver(fit);presentation.observe(root,{attributes:true,attributeFilter:["class"]});
 return {fit};
}
