// Reproducible interaction profile; does not alter packs or native captures.
import {chromium} from "@playwright/test";
import {mkdir,writeFile} from "node:fs/promises";
const browser=await chromium.launch(),page=await browser.newPage({viewport:{width:1440,height:1000}});
const url=process.env.SITE_URL||"http://127.0.0.1:8792",name=process.env.REVIEW_NAME||"current";
await page.goto(url+"/studio");
await page.waitForFunction(()=>document.getElementById("game-preview")?.dataset.previewReady==="true",{timeout:60000});
await page.locator('[data-step="customize"]').first().click();
await page.waitForTimeout(500);
const cdp=await page.context().newCDPSession(page);
await cdp.send("Profiler.enable");await cdp.send("Profiler.start");
const metrics=await page.evaluate(async()=>{
 const samples={selection:[],movers:[],search:[],move:[]},paint=()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
 const measure=async(key,fn)=>{const start=performance.now();fn();await paint();samples[key].push(performance.now()-start);};
 for(let i=0;i<8;i++)await measure("selection",()=>{const el=document.getElementById("frame-group");el.value=i%2?"player":"chat";el.dispatchEvent(new Event("change"));});
 for(let i=0;i<8;i++)await measure("movers",()=>document.getElementById("show-movers").click());
 for(let i=0;i<8;i++)await measure("search",()=>{const el=document.getElementById("module-search");el.value=i%2?"":"chat";el.dispatchEvent(new Event("input"));});
 document.getElementById("module-search").value="";document.getElementById("module-search").dispatchEvent(new Event("input"));
 document.getElementById("frame-group").value="chat";document.getElementById("frame-group").dispatchEvent(new Event("change"));
 for(let i=0;i<8;i++)await measure("move",()=>document.getElementById("game-preview").dispatchEvent(new KeyboardEvent("keydown",{key:i%2?"ArrowLeft":"ArrowRight",bubbles:true})));
 return Object.fromEntries(Object.entries(samples).map(([key,values])=>[key,{median:values.sort((a,b)=>a-b)[4],max:Math.max(...values),samples:values}]));
});
const {profile}=await cdp.send("Profiler.stop"),counts=new Map();
for(let i=0;i<(profile.samples||[]).length;i++){const id=profile.samples[i],n=profile.nodes.find(n=>n.id===id);const f=n?.callFrame.functionName||"(anonymous)";counts.set(f,(counts.get(f)||0)+(profile.timeDeltas?.[i]||0));}
const result={url,name,capturedAt:new Date().toISOString(),browser:browser.version(),metrics,cpuTop:[...counts].sort((a,b)=>b[1]-a[1]).slice(0,20)};
await mkdir(new URL("../dist/studio-performance/",import.meta.url),{recursive:true});
await writeFile(new URL("../dist/studio-performance/"+name+".json",import.meta.url),JSON.stringify(result,null,2)+"\n");
console.log(JSON.stringify(result));await browser.close();
