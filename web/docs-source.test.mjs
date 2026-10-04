import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {loadGuides,digest,releaseFields,resolveRelease} from "./docs-source.mjs";
import {catalog} from "./releases.mjs";
test("canonical Markdown, release data and every generated page retain exact source provenance",async()=>{
 const {pages,release,releaseSha256}=await loadGuides();
 const inventory=JSON.parse(await readFile(new URL("./docs-inventory.json",import.meta.url),"utf8"));
 assert.equal(pages.length,56);assert.ok(pages.some(page=>page.slug==="gear-goals"));assert.deepEqual(inventory.release,release);assert.equal(inventory.releaseSha256,releaseSha256);
 for(const p of pages){
  const raw=await readFile(new URL("../"+p.file,import.meta.url),"utf8");
  assert.equal(p.sourceSha256,digest(raw));assert.equal(p.buildSha256,digest(resolveRelease(raw)));
  const entry=inventory.pages.find(x=>x.slug===p.slug),html=await readFile(new URL("./public/docs/"+p.slug+".html",import.meta.url),"utf8");
  assert.equal(entry.htmlSha256,digest(html),p.slug+" generated HTML drift");
  for(const [attribute,value]of [["source",p.sourceSha256],["build",p.buildSha256],["release",releaseSha256]])
   assert.ok(html.includes('data-'+attribute+'-sha256="'+value+'"'),p.slug+" provenance");
  assert.ok(!/aria-label="undefined"|<span>undefined<\/span>/.test(html),p.slug+" unnamed preview control");
  assert.ok(html.includes('data-guide-source="'+p.file+'"'));assert.ok(!html.includes("View or improve this guide"));assert.ok(!/\{\{release\./.test(html));
 }
 const install=await readFile(new URL("./public/docs/installation.html",import.meta.url),"utf8");
 assert.ok(install.includes(release["release.download"]));assert.ok(install.includes(release["release.zip"]));assert.ok(install.includes(catalog.latest));
});
test("release substitution stays bounded and future releases need no guide edits",()=>{
 assert.throws(()=>resolveRelease("{{arbitrary.expression}}"),/Unknown documentation token/);
 assert.throws(()=>releaseFields({...catalog,latest:'<script>'}),/Invalid documentation release version/);
 const fields=releaseFields({...catalog,latest:"9.8.7-beta.12"});
 assert.equal(resolveRelease("{{release.version}} {{release.zip}}",fields),"9.8.7-beta.12 RikUI-v9.8.7-beta.12-forever.zip");
});
