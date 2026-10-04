import test from "node:test";
import assert from "node:assert/strict";
import worker, { byteRange } from "./worker.mjs";
import { catalog } from "./releases.mjs";
import {studioAssets,studioScriptURL} from "./studio-generated.mjs";

const request = (path, options) => new Request("https://rikwow.com" + path, options);
test("site, CSS, manifest, redirects, and method boundaries", async () => {
  const home = await worker.fetch(request("/"), {});
  assert.equal(home.status, 200);
  assert.match(home.headers.get("Cache-Control"), /no-transform/);
  assert.match(await home.text(), /A compact, configurable interface for WoW Forever/);
  const script = await worker.fetch(request(studioScriptURL), {ASSETS:{fetch:async()=>new Response("ArrowRight",{headers:{"Content-Type":"text/javascript"}})}});
  assert.match(script.headers.get("Content-Type"), /text\/javascript/);
  assert.match(await script.text(), /ArrowRight/);
  assert.match(home.headers.get("Content-Security-Policy"), /default-src 'none'/);
  const css = await worker.fetch(request("/site.css"), {});
  assert.match(css.headers.get("Content-Type"), /text\/css/);
  const head = await worker.fetch(request("/", { method: "HEAD" }), {});
  assert.equal(await head.text(), "");
  assert.equal((await worker.fetch(request("/"), {})).status, 200);
  assert.equal((await worker.fetch(request("/", { method: "POST" }), {})).status, 405);
  assert.equal((await worker.fetch(request("/unknown"), {})).status, 404);
  const redirect = await worker.fetch(new Request("https://www.rikwow.com/?a=1"), {});
  assert.equal(redirect.headers.get("Location"), "https://rikwow.com/?a=1");
  assert.equal((await (await worker.fetch(request("/api/v1/releases"), {})).json()).product, "RikUI");
});


test("consumer installation route explains dependencies, local costs and incomplete coverage",async()=>{
 const response=await worker.fetch(request("/install"),{});
 assert.equal(response.status,200);
 const html=await response.text();
 assert.match(html,/Four simple steps/);
 assert.match(html,/16 GiB/);
 assert.match(html,/downloads.*QuestieDB/);
 assert.match(html,/only when all supported regions are ready and checked/);
 assert.match(html,/daily Windows task/);
 assert.equal((await worker.fetch(request("/install/"),{})).headers.get("Location"),"https://rikwow.com/install");
 assert.equal(await (await worker.fetch(request("/install",{method:"HEAD"}),{})).text(),"");
});
test("Studio is paused publicly and enabled only by a development binding", async () => {
  for (const path of ["/studio", "/studio/", "/studio?pack=centered", "/setups", "/setups/submit", "/setups/centered", "/docs/setup-studio", "/docs/setup-studio/"]) {
    const response = await worker.fetch(request(path), {});
    assert.equal(response.status,302,path);
    assert.equal(response.headers.get("Location"),"https://rikwow.com/docs/options",path);
  }
  const home = await (await worker.fetch(request("/"),{})).text();
  assert.doesNotMatch(home,/href="\/(?:studio|setups)|INTRODUCING SETUP STUDIO/);
  for (const flag of [true,"true"]) {
    assert.equal((await worker.fetch(request("/studio"),{STUDIO_PREVIEW:flag})).status,302);
    assert.equal((await worker.fetch(new Request("http://127.0.0.1:8787/studio"),{STUDIO_PREVIEW:flag})).status,200);
  }
  for (const flag of [false,"false",1,"1"]) {
    assert.equal((await worker.fetch(new Request("http://127.0.0.1:8787/studio"),{STUDIO_PREVIEW:flag})).status,302);
  }
  const preview = await worker.fetch(new Request("http://127.0.0.1:8787/studio"),{STUDIO_PREVIEW:"true"});
  assert.equal(preview.status,200);
  assert.match(await preview.text(),/id="studio-app"/);
});

test("reviewed Studio asset preserves conditional responses, security and method boundaries", async () => {
  let reads = 0;
  const env = { ASSETS: { fetch: async req => {
    reads++;
    if (req.headers.get("If-None-Match") === '"world"')
      return new Response(null, { status: 304, headers: { ETag: '"world"' } });
    return new Response(req.method === "HEAD" ? null : "jpeg fixture",
      { headers: { "Content-Type": "image/jpeg", ETag: '"world"' } });
  } } };
  const path = studioAssets.find(p=>p.endsWith(".webp"));
  const image = await worker.fetch(request(path), env);
  assert.equal(await image.text(), "jpeg fixture");
  assert.match(image.headers.get("Cache-Control"), /immutable/);
  assert.equal(image.headers.get("X-Content-Type-Options"), "nosniff");
  const cached = await worker.fetch(request(path, { headers: { "If-None-Match": '"world"' } }), env);
  assert.equal(cached.status, 304);
  assert.equal(cached.headers.get("ETag"), '"world"');
  const head = await worker.fetch(request(path, { method: "HEAD" }), env);
  assert.equal(head.status, 200);
  assert.equal(await head.text(), "");
  assert.equal((await worker.fetch(request(path, { method: "POST" }), env)).status, 405);
  assert.equal((await worker.fetch(request("/assets/private.jpg"), env)).status, 404);
  assert.equal(reads, 3);
  env.ASSETS.fetch = async () => new Response("missing", { status: 404 });
  assert.equal((await worker.fetch(request(path), env)).headers.get("Cache-Control"), "no-store");
});

test("unapproved keys are never read from storage", async () => {
  const env = { RELEASES: { head() { throw new Error("Must not access bucket"); } } };
  assert.equal((await worker.fetch(request("/downloads/private.sql"), env)).status, 404);
  assert.equal((await worker.fetch(request("/sources/dump.zip"), env)).status, 404);
});

test("range parser rejects malformed, empty and out of bounds ranges", () => {
  assert.deepEqual(byteRange("bytes=2-5", 10), { offset: 2, length: 4 });
  assert.deepEqual(byteRange("bytes=-3", 10), { offset: 7, length: 3 });
  assert.deepEqual(byteRange("bytes=8-", 10), { offset: 8, length: 2 });
  assert.deepEqual(byteRange("bytes=0-50", 10), { offset: 0, length: 10 });
  for (const range of ["bytes=10-", "bytes=5-2", "bytes=-0", "bytes=-", "bytes=0-1,3-4", "bytes=9007199254740992-"])
    assert.throws(() => byteRange(range, 10), RangeError);
});

test("approved downloads support streams, conditional reads, HEAD and ranges", async () => {
  const artifact = { path: "/downloads/test.zip", key: "releases/hash/test.zip", bytes: 10,
    sha256: "a".repeat(64), filename: "test.zip", contentType: "application/zip" };
  catalog.releases.push({ artifacts: [artifact] });
  const object = { size: 10, etag: "object-version", customMetadata: { sha256: artifact.sha256 } };
  let gets = 0;
  const env = { RELEASES: { head: async () => object, get: async (key, options) => {
    gets++; assert.equal(key, artifact.key); assert.equal(options.onlyIf.etagMatches, "object-version");
    const bytes = "0123456789";
    const range = options.range;
    return { body: range ? bytes.slice(range.offset, range.offset + range.length) : bytes };
  } } };
  try {
    const partial = await worker.fetch(request(artifact.path, { headers: { Range: "bytes=2-5" } }), env);
    assert.equal(partial.status, 206); assert.equal(await partial.text(), "2345");
    assert.equal(partial.headers.get("Content-Range"), "bytes 2-5/10");
    const head = await worker.fetch(request(artifact.path, { method: "HEAD" }), env);
    assert.equal(head.headers.get("Content-Length"), "10"); assert.equal(gets, 1);
    assert.match(head.headers.get("Cache-Control"), /(?:^|,\s*)no-transform(?:,|$)/);
    assert.equal(head.headers.get("ETag"), '"' + artifact.sha256 + '"');
    const cached = await worker.fetch(request(artifact.path, { headers: { "If-None-Match": '"' + artifact.sha256 + '"' } }), env);
    assert.equal(cached.status, 304); assert.equal(gets, 1);
    assert.equal((await worker.fetch(request(artifact.path, { headers: { "If-None-Match": "*" } }), env)).status, 304);
    assert.equal((await worker.fetch(request(artifact.path, { headers: { Range: "bytes=99-" } }), env)).status, 416);
    object.customMetadata.sha256 = "bad";
    const unavailable = await worker.fetch(request(artifact.path), env);
    assert.equal(unavailable.status, 503);
    assert.equal(unavailable.headers.get("Cache-Control"), "no-store");
  } finally { catalog.releases.pop(); }
});

test("documentation assets preserve cache validation and fail explicitly when missing",async()=>{
 const paths=[];
 const env={ASSETS:{fetch:async req=>{
  paths.push(new URL(req.url).pathname);
  return new Response(req.headers.has("If-None-Match")?null:"<h1>Inventory</h1>",{status:req.headers.has("If-None-Match")?304:200,headers:{ETag:'"docs-v1"'}});
 }}};
 const page=await worker.fetch(request("/docs/bags"),env);
 assert.equal(page.status,200);assert.deepEqual(paths,["/docs/bags.html"]);
 assert.match(page.headers.get("Cache-Control"),/max-age=60, no-transform/);
 const cached=await worker.fetch(request("/docs/bags",{headers:{"If-None-Match":'"docs-v1"'}}),env);
 assert.equal(cached.status,304);assert.equal(cached.headers.get("ETag"),'"docs-v1"');
 assert.equal((await worker.fetch(request("/docs/not-listed"),env)).status,404);
 env.ASSETS.fetch=async()=>new Response("missing",{status:404});
 assert.equal((await worker.fetch(request("/docs/bags"),env)).status,503);
});
