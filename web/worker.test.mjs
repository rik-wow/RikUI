import test from "node:test";
import assert from "node:assert/strict";
import worker, { byteRange } from "./worker.mjs";
import { catalog } from "./releases.mjs";

const request = (path, options) => new Request("https://rikwow.com" + path, options);
test("site, CSS, manifest, redirects, and method boundaries", async () => {
  const home = await worker.fetch(request("/"), {});
  assert.equal(home.status, 200);
  assert.match(home.headers.get("Cache-Control"), /no-transform/);
  assert.match(await home.text(), /Your interface\./);
  const script = await worker.fetch(request("/site.js"), {});
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
