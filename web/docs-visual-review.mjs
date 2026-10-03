import {chromium} from "@playwright/test";
import {mkdir,writeFile,readFile} from "node:fs/promises";
import {createHash} from "node:crypto";
const root=new URL("../dist/docs-browser-review/",import.meta.url);await mkdir(root,{recursive:true});
const browser=await chromium.launch(),page=await browser.newPage({viewport:{width:1440,height:1000},reducedMotion:"reduce"});
const site=process.env.SITE_URL||"http://127.0.0.1:8792",images=[];
async function capture(name){const file=new URL(name+".png",root);await page.screenshot({path:file.pathname.replace(/^\/(\w:)/,"$1"),fullPage:false});images.push({name,sha256:createHash("sha256").update(await readFile(file)).digest("hex")});}
for(const slug of ["","setup-studio","installation","options"]){await page.goto(site+"/docs"+(slug?"/"+slug:""));await capture("desktop-"+(slug||"index"));}
for(const width of [320,390]){await page.setViewportSize({width,height:1000});await page.goto(site+"/docs/setup-studio");await capture("mobile-"+width+"-closed");await page.locator(".docs-nav-toggle summary").click();await capture("mobile-"+width+"-open");await page.getByLabel("Find a guide").fill("inventory");await capture("mobile-"+width+"-search");}
const fallback=await browser.newContext({javaScriptEnabled:false,viewport:{width:390,height:1000}});const p=await fallback.newPage();await p.goto(site+"/docs/setup-studio");const f=new URL("mobile-nojs.png",root);await p.screenshot({path:f.pathname.replace(/^\/(\w:)/,"$1"),fullPage:false});images.push({name:"mobile-nojs",sha256:createHash("sha256").update(await readFile(f)).digest("hex")});await fallback.close();
await writeFile(new URL("images.json",root),JSON.stringify(images,null,2)+"\n");await browser.close();console.log("Captured "+images.length+" real docs browser states.");
