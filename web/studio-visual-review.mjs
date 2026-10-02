// Real browser screenshots complement the original-size native capture review.
import {chromium} from "@playwright/test";
import {mkdir} from "node:fs/promises";
const root=new URL("../dist/studio-browser-review/",import.meta.url);await mkdir(root,{recursive:true});
const browser=await chromium.launch(),page=await browser.newPage({viewport:{width:1440,height:1000},reducedMotion:"reduce"});
const site=process.env.SITE_URL||"http://127.0.0.1:8788";
for(const [name,path] of [["home","/"],["gallery","/setups"],["pack","/setups/centered"]]){
 await page.goto(site+path);await page.locator("img").evaluateAll(imgs=>Promise.all(imgs.map(im=>im.decode().catch(()=>{}))));
 await page.screenshot({path:new URL(name+".png",root).pathname.replace(/^\/(\w:)/,"$1"),fullPage:true});
}
await page.goto(site+"/studio");await page.locator("#studio-app").waitFor();
await page.waitForFunction(()=>document.querySelector("#geometry").textContent.includes("×"));
for(const [name,settings] of [["desktop",{}],["party-ocean",{activity:"party",theme:"ocean"}],["raid-ink",{activity:"raid",theme:"ink"}],["handheld",{device:"handheld",theme:"classic"}]]){
 for(const [key,value] of Object.entries(settings))await page.locator("#"+key).selectOption(value);
 await page.waitForTimeout(300);await page.locator("#game-preview").scrollIntoViewIfNeeded();
 await page.locator("#game-preview").screenshot({path:new URL(name+"-canvas.png",root).pathname.replace(/^\/(\w:)/,"$1")});
 await page.screenshot({path:new URL(name+".png",root).pathname.replace(/^\/(\w:)/,"$1"),fullPage:true});
}
await page.setViewportSize({width:390,height:1000});await page.screenshot({path:new URL("mobile.png",root).pathname.replace(/^\/(\w:)/,"$1"),fullPage:true});
await browser.close();console.log("Captured actual home, gallery, pack and four editor presentations plus mobile.");
