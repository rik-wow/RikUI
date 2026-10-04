// Review player-facing copy in the actual public browser routes.
import {chromium} from "@playwright/test";
import assert from "node:assert/strict";
import {mkdir,writeFile,readFile} from "node:fs/promises";
import {createHash} from "node:crypto";
import {resolve,join} from "node:path";
import {catalog} from "./releases.mjs";
const options=Object.fromEntries(process.argv.slice(2).filter(v=>v.startsWith("--")).map(v=>[v.slice(2),process.argv[process.argv.indexOf(v)+1]]));
if(!options.output)throw Error("Provide a new --output capture directory");
const origin=options.origin||"http://127.0.0.1:8787";
assert.ok(["http://127.0.0.1:8787","https://rikwow.com"].includes(origin));
const output=resolve(options.output),sha=bytes=>createHash("sha256").update(bytes).digest("hex");
await mkdir(output,{recursive:false});
const routes=["/","/docs/contributing","/docs/installation","/docs/gear-goals","/docs/questplanner","/docs/banners","/docs/layout","/docs/nameplates","/docs/wizard"];
const sources={};
for(const file of ["capture-public-copy.mjs","studio-pages.mjs","build-docs.mjs","docs-catalogue.mjs","docs-styles.mjs","studio-styles.mjs","releases.mjs","docs-generated.mjs",...routes.slice(1).map(path=>"../docs/player/"+path.slice(6)+".md")])
 sources[file]=sha(await readFile(new URL(file,import.meta.url)));
const browser=await chromium.launch({headless:true,args:["--disable-gpu"]}),images=[];
try{
 for(const width of [390,1440]){
  const page=await browser.newPage({viewport:{width,height:1000},deviceScaleFactor:1});
  for(const route of routes){
   const response=await page.goto(origin+route);assert.equal(response.status(),200);
   await page.evaluate(async()=>{await document.fonts.ready;await Promise.all(Array.from(document.images,image=>image.decode().catch(()=>{})));});
   assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),route+" horizontal overflow");
   const filename=(route==="/"?"home":route.slice(6))+"-"+width+".png";
   const bytes=await page.screenshot({path:join(output,filename),fullPage:true,animations:"disabled"});
   images.push({route,filename,width,sha256:sha(bytes)});
  }
  await page.close();
 }
}finally{await browser.close();}
const evidence={format:"rikui-public-copy-browser-capture-v1",origin,version:catalog.latest,sources,images};
await writeFile(join(output,"evidence.json"),JSON.stringify(evidence,null,2)+"\n",{flag:"wx"});
console.log(JSON.stringify(evidence));
