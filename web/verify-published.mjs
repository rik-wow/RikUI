// Verify the deployed installation page, catalog and every public setup byte.
import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {mkdir,writeFile} from "node:fs/promises";
import {resolve,join} from "node:path";
import {catalog} from "./releases.mjs";
const options=Object.fromEntries(process.argv.slice(2).filter(v=>v.startsWith("--")).map(v=>[v.slice(2),process.argv[process.argv.indexOf(v)+1]]));
if(!options.origin||!options.output)throw Error("Provide --origin and a new --output proof directory");
const origin=new URL(options.origin);
if(origin.protocol!=="https:"||origin.hostname!=="rikwow.com")throw Error("Verify the project's existing production origin");
const output=resolve(options.output),sha=raw=>createHash("sha256").update(raw).digest("hex");
await mkdir(output,{recursive:false});
const get=(path,init={})=>fetch(new URL(path,origin),{...init,signal:AbortSignal.timeout(120000)});
const published=await get("/api/v1/releases");
assert.equal(published.status,200);
assert.deepEqual(await published.json(),catalog);
assert.ok(catalog.installer);
for(const path of ["/install","/docs/installation"]){
 const response=await get(path);assert.equal(response.status,200);
 const html=await response.text();assert.ok(html.includes(catalog.latest));
 assert.ok(html.includes("QuestieDB"));assert.ok(html.includes("16 GiB"));
 assert.ok(html.includes("English game text (enUS)"));
 if(path==="/install")assert.ok(html.includes(catalog.installer.url));
 await writeFile(join(output,path==="/install"?"install.html":"installation.html"),html,{flag:"wx"});
}
const artifacts=catalog.releases.find(r=>r.version===catalog.latest)?.artifacts;
assert.equal(artifacts?.length,4);
const verified=[];
for(const row of artifacts){
 assert.ok(/^\/downloads\/v[0-9A-Za-z.-]+\/RikUI-Setup[^/]*$/.test(row.path));
 const etag='"'+row.sha256+'"';
 const head=await get(row.path,{method:"HEAD"});
 assert.equal(head.status,200);assert.equal(head.headers.get("content-length"),String(row.bytes));
 assert.equal(head.headers.get("etag"),etag);assert.equal(head.headers.get("accept-ranges"),"bytes");
 const response=await get(row.path);assert.equal(response.status,200);
 const bytes=Buffer.from(await response.arrayBuffer());
 assert.equal(bytes.length,row.bytes);assert.equal(sha(bytes),row.sha256);
 await writeFile(join(output,row.filename),bytes,{flag:"wx"});
 const range=await get(row.path,{headers:{Range:"bytes=0-31","If-Range":etag}});
 assert.equal(range.status,206);assert.equal(range.headers.get("content-range"),"bytes 0-31/"+row.bytes);
 assert.deepEqual(Buffer.from(await range.arrayBuffer()),bytes.subarray(0,32));
 const conditional=await get(row.path,{headers:{"If-None-Match":etag}});
 assert.equal(conditional.status,304);assert.equal((await conditional.arrayBuffer()).byteLength,0);
 verified.push({...row,headVerified:true,rangeVerified:true,conditionalVerified:true});
}
const result={format:"rikui-production-download-verification-v1",origin:origin.origin,
 version:catalog.latest,checkedAt:new Date().toISOString(),artifacts:verified,
 installationDocumentationVerified:true,importedDatasetsIncluded:false,clientGeometryIncluded:false};
await writeFile(join(output,"evidence.json"),JSON.stringify(result,null,2)+"\n",{flag:"wx"});
console.log(JSON.stringify(result));
