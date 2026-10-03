// Canonical player Markdown is the only source of public guide prose.
import {readFile,readdir} from "node:fs/promises";
import {createHash} from "node:crypto";
import {catalogue} from "./docs-catalogue.mjs";
import {catalog} from "./releases.mjs";
const root=new URL("../",import.meta.url);
export const digest=text=>createHash("sha256").update(text).digest("hex");
export function releaseFields(release=catalog){
 const version=release.latest;
 if(!/^\d+\.\d+\.\d+(?:-[a-z0-9.]+)?$/.test(version))throw Error("Invalid documentation release version");
 const zip="RikUI-v"+version+"-forever.zip";
 return {"release.version":version,"release.channel":release.channel,"release.zip":zip,
  "release.url":release.releasesUrl+"/tag/v"+version,"release.download":release.releasesUrl+"/download/v"+version+"/"+zip};
}
export function resolveRelease(markdown,fields=releaseFields()){
 return markdown.replace(/\{\{([^{}]+)\}\}/g,(_,token)=>{
  if(!Object.hasOwn(fields,token))throw Error("Unknown documentation token: "+token);
  return fields[token];
 });
}
export async function loadGuides(){
 const references=["installation","overview","contributing","web--asset-notice"];
 const slugs=[...catalogue.map(page=>page.slug),...references];
 const files=(await readdir(new URL("../docs/player/",import.meta.url))).filter(file=>file.endsWith(".md")).sort();
 if(JSON.stringify(files)!==JSON.stringify(slugs.map(slug=>slug+".md").sort()))throw Error("Canonical guide files differ from documentation catalogue");
 const release=releaseFields(),releaseSha256=digest(JSON.stringify(release));
 const pages=await Promise.all(slugs.map(async slug=>{
  const file="docs/player/"+slug+".md",source=await readFile(new URL(file,root),"utf8");
  const title=source.match(/^# (.+)\r?$/m)?.[1];
  if(!title)throw Error("Canonical guide needs one title: "+file);
  const feature=catalogue.find(page=>page.slug===slug);
  const markdown=resolveRelease(source,release);
  return {file,slug,title,group:feature?.group||"About RikUI",summary:feature?.summary||"",feature,
   sourceSha256:digest(source),buildSha256:digest(markdown),releaseSha256,markdown};
 }));
 return {pages,release,releaseSha256};
}
