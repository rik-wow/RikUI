// Publish only byte-verified public setup artifacts to the existing release bucket.
// Uses the documented Wrangler platform proxy with an explicitly remote R2 binding.
import {getPlatformProxy} from "wrangler";
import {readFile,writeFile,stat} from "node:fs/promises";
import {createHash} from "node:crypto";
import {resolve,dirname,join} from "node:path";
import {fileURLToPath} from "node:url";
const HERE=dirname(fileURLToPath(import.meta.url));
const FILES=["RikUI-Setup.exe","RikUI-Setup-manifest.json","RikUI-Setup-SHA256SUMS","RikUI-Setup-NOTICES.txt"];
const sha=raw=>createHash("sha256").update(raw).digest("hex");
const options=Object.fromEntries(process.argv.slice(2).filter(value=>value.startsWith("--")&&value!=="--check-only").map(value=>[value.slice(2),process.argv[process.argv.indexOf(value)+1]]));
const check=process.argv.includes("--check-only");
if(!options.directory||!options.proof||!options.version||(!check&&!options.output))throw Error("Provide --directory --proof --version and --output for publication; --check-only reads storage");
const directory=resolve(options.directory),version=options.version;
if(!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(version))throw Error("Invalid release version");
const proof=JSON.parse(await readFile(options.proof,"utf8"));
if(proof.format!=="rikui-published-setup-verification-v1"||proof.version!==version||resolve(proof.directory)!==directory||proof.importedDatasetsIncluded!==false||proof.clientGeometryIncluded!==false)throw Error("Reviewed public download proof mismatch");
const bodies=new Map();
for(const name of FILES){
 const path=join(directory,name),info=await stat(path);
 if(!info.isFile()||info.size<=0||info.size>256*1024*1024)throw Error("Public artifact byte bound");
 const body=await readFile(path);
 if(name!==FILES[2]&&proof.checksums[name]!==sha(body))throw Error("Reviewed bytes changed: "+name);
 bodies.set(name,body);
}
const sums=bodies.get(FILES[2]).toString("utf8").trim().split(/\r?\n/);
if(sums.length!==3||new Set(sums).size!==3||sums.some(line=>{const row=/^([a-f0-9]{64})  (RikUI-Setup[^/\\]+)$/.exec(line);return !row||!FILES.filter(name=>name!==FILES[2]).includes(row[2])||proof.checksums[row[2]]!==row[1];}))throw Error("Published checksum file changed");
const manifest=JSON.parse(bodies.get(FILES[1]));
if(manifest.version!==version||manifest.importedDatasetsIncluded!==false||manifest.clientGeometryIncluded!==false||manifest.artifact.sha256!==sha(bodies.get(FILES[0])))throw Error("Public data boundary mismatch");
const platform=await getPlatformProxy({configPath:join(HERE,"wrangler-release.jsonc"),remoteBindings:true,persist:false});
const artifacts=[];
try{
 for(const name of FILES){
  const body=bodies.get(name),digest=sha(body),key=`v${version}/${name}`;
  const contentType=name.endsWith(".exe")?"application/vnd.microsoft.portable-executable":name.endsWith(".json")?"application/json":"text/plain; charset=utf-8";
  const row={path:`/downloads/${key}`,key,bytes:body.length,sha256:digest,filename:name,contentType};
  let head=await platform.env.RELEASES.head(key);
  if(check){artifacts.push({...row,exists:!!head,metadataMatches:!!head&&head.size===row.bytes&&head.customMetadata?.sha256===digest});continue;}
  if(!head){
   const saved=await platform.env.RELEASES.put(key,body,{onlyIf:{etagDoesNotMatch:"*"},httpMetadata:{contentType},customMetadata:{sha256:digest}});
   if(!saved)throw Error("Immutable release key appeared during publication: "+key);
   head=await platform.env.RELEASES.head(key);
  }
  if(!head||head.size!==row.bytes||head.customMetadata?.sha256!==digest)throw Error("Immutable published metadata differs: "+key);
  const object=await platform.env.RELEASES.get(key,{onlyIf:{etagMatches:head.etag}});
  if(!object||sha(Buffer.from(await object.arrayBuffer()))!==digest)throw Error("Published storage bytes differ: "+key);
  artifacts.push(row);
 }
}finally{await platform.dispose();}
const result={format:"rikui-public-storage-verification-v1",version,bucket:"rik-wow-releases",checkedOnly:check,artifacts};
if(!check)await writeFile(resolve(options.output),JSON.stringify(result,null,2)+"\n",{flag:"wx"});
console.log(JSON.stringify(result));
