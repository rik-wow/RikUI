// Capture the real installation route and its disclosure at supported widths.
import {chromium} from "@playwright/test";
import assert from "node:assert/strict";
import {mkdir,readFile,writeFile} from "node:fs/promises";
import {createHash} from "node:crypto";
import {resolve,join} from "node:path";
import {catalog} from "./releases.mjs";
const options=Object.fromEntries(process.argv.slice(2).filter(v=>v.startsWith("--")).map(v=>[v.slice(2),process.argv[process.argv.indexOf(v)+1]]));
if(!options.output)throw Error("Provide a new --output capture directory");
const origin=options.origin||"http://127.0.0.1:8787";
if(!["http://127.0.0.1:8787","https://rikwow.com"].includes(origin))throw Error("Unsupported capture origin");
assert.ok(catalog.installer);
const output=resolve(options.output),sha=raw=>createHash("sha256").update(raw).digest("hex");
await mkdir(output,{recursive:false});
const sources={};
for(const file of ["install-page.mjs","releases.mjs","studio-styles.mjs","capture-install.mjs"])
 sources[file]=sha(await readFile(new URL(file,import.meta.url)));
const browser=await chromium.launch({headless:true,args:["--disable-gpu"]}),images=[];
try{
 for(const width of [390,1440]){
  const page=await browser.newPage({viewport:{width,height:1000},deviceScaleFactor:1});
  await page.goto(origin+"/install");await page.evaluate(()=>document.fonts.ready);
  assert.equal(await page.getByRole("link",{name:"Download RikUI setup for Windows"}).getAttribute("href"),catalog.installer.url);
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  for(const state of ["closed","measured-cost"]){
   if(state==="measured-cost")await page.getByText("Why does preparation take time?",{exact:true}).click();
   const filename="install-"+width+"-"+state+".png";
   const bytes=await page.screenshot({path:join(output,filename),fullPage:true,animations:"disabled"});
   images.push({filename,width,state,sha256:sha(bytes)});
  }
  await page.close();
 }
}finally{await browser.close();}
const evidence={format:"rikui-installation-page-capture-v1",origin,version:catalog.latest,sources,images};
await writeFile(join(output,"evidence.json"),JSON.stringify(evidence,null,2)+"\n",{flag:"wx"});
console.log(JSON.stringify(evidence));
