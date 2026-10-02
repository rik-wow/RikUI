import { readFile, readdir, writeFile, mkdir, copyFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { Marked } from "marked";
import { catalogue, modulePages } from "./docs-catalogue.mjs";
import { renderFigure, sequenceFigure, escapeHTML as esc } from "./docs-visuals.mjs";
import { checkCoverage } from "./docs-coverage.mjs";
import {prunePublicAssets} from "./prune-public-assets.mjs";
import startGuides from "./guides-start.mjs";
import studioGuides from "./guides-studio.mjs";
import combatGuides from "./guides-combat.mjs";
import worldGuides from "./guides-world.mjs";
import windowGuides from "./guides-windows.mjs";
import extraGuides from "./guides-extra.mjs";
import { execFileSync } from "node:child_process";
execFileSync(process.env.PYTHON || "python", [fileURLToPath(new URL("../tools/site-renders/check.py",import.meta.url))], {stdio:"inherit"});
const guides={...studioGuides,...startGuides,...combatGuides,...worldGuides,...windowGuides,...extraGuides};
const visualPaths=new Map();
const renderManifest=JSON.parse(await readFile(new URL("./ui-renders/manifest.json",import.meta.url),"utf8"));
const liveRenders=new Map();
for(const capture of renderManifest.renders){
 const list=liveRenders.get(capture.page)||[];list.push(capture);liveRenders.set(capture.page,list);
}
await mkdir(new URL("./public/assets/docs/",import.meta.url),{recursive:true});
// Publish only captures placed in an actual guide. Studio owns its gallery/component assets.
// A capture is one image, or a sequence of frames (one per setting value) whose default frame stands for it.
for(const capture of renderManifest.renders){
 if(!Object.hasOwn(guides,capture.page))continue;
 for(const frame of capture.frames||[capture]){
  // Public asset names keep to letters, digits and dashes; a frame's value joins the id that way.
  const stem=capture.frames?capture.id+"-"+String(frame.value).replace(/[^a-z0-9]+/gi,"-"):capture.id;
  const name=stem+"-"+frame.sha256.slice(0,12)+".webp";
  frame.url="/assets/docs/"+name;
  await copyFile(new URL("./ui-renders/"+frame.filename,import.meta.url),new URL("./public/assets/docs/"+name,import.meta.url));
  visualPaths.set("render:"+stem,frame.url);
 }
 if(capture.frames)capture.url=capture.frames.find(frame=>frame.sha256===capture.sha256)?.url??capture.frames[0].url;
}
const root = fileURLToPath(new URL("../", import.meta.url));
const git = "https://github.com/rik-wow/RikUI/blob/main/";
let files = [];
async function scan(dir) {
 for (const entry of await readdir(path.join(root,dir), { withFileTypes:true })) {
  if (["node_modules","target",".venv","__pycache__"].includes(entry.name)) continue;
  const name=path.posix.join(dir,entry.name);
  if(entry.isDirectory()) await scan(name);
  else if(entry.name.endsWith(".md")) files.push(name);
 }
}
await scan("docs"); await scan("tools"); await scan("installer");
files.push("README.md","CONTRIBUTING.md","CHANGELOG.md","SDD.md","web/ASSET-NOTICE.md");
const slugOf = file => file.startsWith("docs/") ? path.posix.basename(file,".md")
 : file==="README.md" ? "overview" : file==="installer/README.md" ? "installation"
 : file.toLowerCase().replace(/\.md$/,"").replaceAll("/","--");
files = files.filter(file=>Object.hasOwn(guides,slugOf(file)));
const sources = new Map(files.map(file=>[file,guides[slugOf(file)]]));
const routes = new Map(files.map(file=>[file,"/docs/"+slugOf(file)]));
const pages=files.map(file=>{
 const feature=catalogue.find(entry=>entry.slug===slugOf(file));
 const markdown=sources.get(file);
 return {file,slug:slugOf(file),title:feature?.title||markdown.match(/^#\s+(.+)/m)?.[1]||file,
 group:feature?.group||"About RikUI",summary:feature?.summary||"",feature};
});
for(const guide of catalogue)if(!pages.some(page=>page.slug===guide.slug))throw Error("Missing Markdown guide: "+guide.slug);
const sourceFiles=[];
async function luaFiles(dir) {
 for(const entry of await readdir(path.join(root,dir),{withFileTypes:true})){
  const name=path.posix.join(dir,entry.name);
  if(entry.isDirectory())await luaFiles(name);
  else if(entry.name.endsWith(".lua"))sourceFiles.push(name);
 }
}
await luaFiles("src");
const registrations=[];
for(const file of sourceFiles){
 const source=await readFile(path.join(root,file),"utf8");
 for(const match of source.matchAll(/RegisterModule\("([^"]+)"/g))registrations.push({name:match[1],file,page:modulePages[match[1]]});
}
const missing=registrations.filter(item=>!item.page);
if(missing.length)throw Error("Missing module visual documentation: "+missing.map(x=>x.name).join(", "));
const inventory={modules:registrations,surfaces:catalogue.flatMap(page=>page.surfaces.map(name=>({page:page.slug,name,kind:page.kind}))),renders:renderManifest.renders.map(({id,page,title,width,height})=>({id,page,title,width,height}))};
const groupOrder=["Getting started","Combat","Questing","Everyday interface","Notifications","Windows and controls","About RikUI"];
const groups=groupOrder.filter(group=>pages.some(page=>page.group===group));
const sidebar=current=>'<aside class="docs-sidebar"><details class="docs-nav-toggle" open><summary>Browse documentation</summary><div class="nav-content"><label for="docs-search">Find a guide</label><input id="docs-search" type="search" placeholder="Nameplates, bags, profiles…" autocomplete="off"><p id="search-empty" hidden>No matching guides.</p><nav aria-label="Documentation">'+groups.map(group=>'<section class="nav-group"><h2>'+esc(group)+'</h2>'+pages.filter(p=>p.group===group).map(p=>'<a data-doc-link data-keywords="'+esc(p.slug+' '+p.summary)+'" href="/docs/'+p.slug+'"'+(p.slug===current?' aria-current="page"':"")+'>'+esc(p.title)+'</a>').join("")+'</section>').join("")+'</nav></div></details></aside>';
const shell=(title,slug,body,toc="")=>'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>'+esc(title)+' · RikUI</title><meta name="description" content="'+esc(title+' — RikUI documentation, controls and visual examples.')+'"><link rel="canonical" href="https://rikwow.com/docs'+(slug?'/'+slug:"")+'"><link rel="stylesheet" href="/site.css"><link rel="stylesheet" href="/docs.css"><script defer src="/docs.js"></script></head><body class="docs-page"><a class="skip" href="#main">Skip to content</a><header class="site-header wrap"><a class="brand" href="/">RikUI</a><nav aria-label="Main navigation"><a href="/docs/installation">Installation</a><a href="/docs" aria-current="page">Documentation</a><a href="https://github.com/rik-wow/RikUI">GitHub</a></nav></header><div class="docs-layout wrap">'+sidebar(slug)+'<main id="main" tabindex="-1">'+body+'</main>'+toc+'</div><footer class="wrap"><p>RikUI · <a href="/docs/web--asset-notice">Artwork notice</a> · <a href="/docs/contributing">Contributing</a></p><p id="asset-notice">World of Warcraft imagery and game icons © Blizzard Entertainment, Inc. RikUI is an independent fan project, not affiliated with or endorsed by Blizzard. Blizzard artwork is excluded from RikUI’s MIT code license.</p></footer></body></html>';
const RENDER_REFERENCE="render:", PREVIEW_REFERENCE="preview:";
// Surfaces no capture can show yet, and surfaces shown inside another capture; checked against the catalogue.
const knownGaps=JSON.parse(await readFile(new URL("../tools/site-renders/known-gaps.json",import.meta.url),"utf8"));
const placed={};
function placeFigure(page,href,caption,used){
 if(href.startsWith(RENDER_REFERENCE)||href.startsWith(PREVIEW_REFERENCE)){
  const preview=href.startsWith(PREVIEW_REFERENCE);
  const id=href.slice(preview?PREVIEW_REFERENCE.length:RENDER_REFERENCE.length);
  const capture=(liveRenders.get(page.slug)||[]).find(item=>item.id===id);
  if(!capture)throw Error(page.slug+": unknown Lua render reference "+id);
  if(preview!==!!capture.frames)throw Error(page.slug+": "+id+(preview?" is a single capture; reference it with render:":" is a sequence; reference it with preview:"));
  used.add("render:"+id);
  return preview?sequenceFigure(page.feature,capture,caption):renderFigure(page.feature,capture,caption);
 }
 if(href==="mockup")throw Error(page.slug+": (mockup) drawings are retired; place a render: or preview: capture for "+caption);
 throw Error(page.slug+": unsupported image reference "+href);
}
function expectedFigures(page){
 return (liveRenders.get(page.slug)||[]).map(capture=>"render:"+capture.id);
}
function verifyPlacement(page,used){
 const expected=expectedFigures(page);
 const missing=expected.filter(key=>!used.has(key));
 if(missing.length)throw Error(page.slug+": examples not placed in the guide: "+missing.join(", "));
}
const groupFigures=html=>html.replace(/<p>((?:\s*<figure[\s\S]*?<\/figure>)+\s*)<\/p>/g,(_,figures)=>'<div class="example-grid">'+figures.trim()+'</div>');
function render(page){
 const headings=[],counts=new Map(),used=new Set();
 const md=new Marked({gfm:true,renderer:{
  html({text}){return esc(text);},
  heading({tokens,depth}){
   const text=this.parser.parseInline(tokens),plain=text.replace(/<[^>]*>/g,"");
   const base="ref-"+plain.toLowerCase().replace(/[^a-z0-9]+/g,"-").replace(/^-|-$/g,"");
   const n=counts.get(base)||0;counts.set(base,n+1);const id=base+(n?"-"+n:"");
   if(depth<=3)headings.push({id,text:plain,depth});
   return '<h'+depth+' id="'+id+'">'+text+'</h'+depth+'>';
  },
  link({href,title,tokens}){
   let target=href||"";
   if(!/^(https?:|mailto:|#)/i.test(target)){
    const [local,hash]=target.split("#");
    const resolved=path.posix.normalize(path.posix.join(path.posix.dirname(page.file),local));
    target=(routes.get(resolved)||git+resolved)+(hash?"#ref-"+hash:"");
   }else if(target.startsWith("#"))target="#ref-"+target.slice(1);
   if(!/^(https?:|mailto:|\/docs(?:\/|$)|#)/i.test(target))target="#";
   return '<a href="'+esc(target)+'"'+(title?' title="'+esc(title)+'"':"")+'>'+this.parser.parseInline(tokens)+'</a>';
  },
  image({href,text}){
   const key=(href||"").startsWith(RENDER_REFERENCE)?"render:"+href.slice(RENDER_REFERENCE.length):(href||"").startsWith(PREVIEW_REFERENCE)?"render:"+href.slice(PREVIEW_REFERENCE.length):href;
   if(used.has(key))throw Error(page.slug+": example placed twice: "+text);
   const figure=placeFigure(page,href||"",text,used);
   const record=placed[page.slug]||(placed[page.slug]={captions:[],captures:[]});
   record.captions.push(text);record.captures.push(key.slice("render:".length));
   return figure;
  }
 }});
 const markdown=sources.get(page.file).replace(/^# .+\r?\n/,"");
 const content=groupFigures(md.parse(markdown));
 verifyPlacement(page,used);
 const toc='<aside class="docs-toc"><nav aria-label="On this page"><h2>On this page</h2>'+headings.map(h=>'<a href="#'+h.id+'" class="toc-depth-'+h.depth+'">'+esc(h.text)+'</a>').join("")+'</nav></aside>';
 const header='<div class="doc-breadcrumb"><a href="/docs">Documentation</a><span>/</span>'+esc(page.group)+'</div><h1>'+esc(page.title)+'</h1>'+(!page.feature&&page.summary?'<p class="doc-lead">'+esc(page.summary)+'</p>':"");
 return shell(page.title,page.slug,header+'<article class="doc-prose">'+content+'</article>',toc);
}
const all = Object.fromEntries(pages.map(page=>["/docs/"+page.slug,render(page)]));
const coverage=checkCoverage(catalogue,placed,knownGaps);
const featureGroups=groups.filter(g=>g!=="About RikUI");
const index='<div class="doc-breadcrumb">RikUI / Documentation</div><h1>Using RikUI</h1><p class="doc-lead">Set up your interface, learn the controls and see what each module changes.</p><div class="docs-start"><a href="/docs/installation">Install RikUI</a><a href="/docs/wizard">First setup</a><a href="/docs/layout">Arrange your frames</a><a href="/docs/options">Settings and profiles</a></div><h2 id="interface-guides">Interface guides</h2>'+featureGroups.map(group=>'<section class="guide-group"><h3>'+esc(group)+'</h3><dl>'+catalogue.filter(p=>p.group===group).map(p=>'<div data-guide><dt><a href="/docs/'+p.slug+'">'+esc(p.title)+'</a></dt><dd>'+esc(p.summary)+'</dd></div>').join("")+'</dl></section>').join("")+'<section class="guide-group"><h2>About RikUI</h2><p>Installation, support and artwork information.</p><ul class="reference-list">'+pages.filter(p=>p.group==="About RikUI").map(p=>'<li><a href="/docs/'+p.slug+'">'+esc(p.title)+'</a></li>').join("")+'</ul></section>';
all["/docs"]=shell("Documentation","",index);
await mkdir(new URL("./public/docs/",import.meta.url),{recursive:true});
const documentation={};
for(const [route,html] of Object.entries(all)){
 const file=route==="/docs"?"index":route.slice("/docs/".length);
 documentation[route]="/docs/"+file+".html";
 await writeFile(new URL("./public/docs/"+file+".html",import.meta.url),html);
}
await writeFile(new URL("./docs-generated.mjs",import.meta.url),"// Generated by build-docs.mjs.\nexport const documentation = "+JSON.stringify(documentation,null,2)+";\nexport const documentationImages = "+JSON.stringify([...visualPaths.values()])+";\n");
await writeFile(new URL("./docs-inventory.json",import.meta.url),JSON.stringify({pages:pages.map(({slug,file,title})=>({slug,file,title})),...inventory},null,2)+"\n");
await prunePublicAssets(new URL("./public/assets/docs/",import.meta.url),[...visualPaths.values()],"docs");
console.log("Built "+pages.length+" documentation pages, "+registrations.length+" modules, "+inventory.renders.length+" Lua renders.");
console.log("Catalogue: "+coverage.surfaces+" surfaces, "+coverage.captioned+" captioned, "+coverage.inCapture+" shown inside another capture, "+coverage.gaps+" known gaps.");
