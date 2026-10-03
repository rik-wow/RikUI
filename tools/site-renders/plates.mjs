// World plates for the Lua captures: photographs of the Forever world taken from isometric-wow-sim's fly camera.
//
//   node tools/site-renders/plates.mjs [name…] [--out dir] [--url http://localhost:5173]
//   node tools/site-renders/plates.mjs --probe <map> <x> <z> [radius]     # ground height and the named actors around a point
//
// The app (D:/Code/isometric-wow-sim, `npm run dev` on port 5173) renders the installed client's terrain, buildings,
// lighting and realm creatures. Nothing in it is changed: this script only drives the objects it exposes at runtime
// (window.nativeScene, its fly camera and its realm actor layer), hides the app's own chrome and nameplates, and
// screenshots the canvas. Every plate is written with a JSON record of the app commit, the request, the resolved
// camera pose and the actors in frame with their screen positions, so fixtures can put RikUI's nameplates over them.
import { createRequire } from "node:module";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(new URL("../../web/package.json", import.meta.url));
const { chromium } = require("@playwright/test");
const HERE = path.dirname(fileURLToPath(import.meta.url));
const WORLDS = path.join(HERE, "worlds");
const GPU_ARGS = ["--use-gl=angle", "--use-angle=d3d11", "--ignore-gpu-blocklist", "--enable-gpu-rasterization"];
const KINDS = ["creature", "adventurer", "gameobject", "corpse"];
const FLAG = { inCombat: 1, dead: 2, ghost: 4, casting: 8, moving: 16, hostile: 32, friendly: 64, rare: 128 };

const args = process.argv.slice(2);
const option = (name, fallback) => { const i = args.indexOf("--" + name); return i >= 0 ? args[i + 1] : fallback; };
const URL_BASE = option("url", "http://localhost:5173");
const OUT = path.resolve(option("out", WORLDS));

const INIT = `(() => {
  window.__inflight = 0;
  const fetch0 = window.fetch.bind(window);
  window.fetch = async (...a) => { window.__inflight++; try { return await fetch0(...a); } finally { window.__inflight--; } };
})();`;
// Only the canvas: every sibling of the viewport's ancestors and every non-canvas child of the viewport is hidden.
const HIDE = `(() => {
  const canvas = document.querySelector('.native-viewport canvas'); if (!canvas) return false;
  let el = canvas;
  while (el && el !== document.body) { for (const s of el.parentElement.children) if (s !== el) s.style.setProperty('display', 'none', 'important'); el = el.parentElement; }
  const vp = document.querySelector('.native-viewport');
  Object.assign(vp.style, { position: 'fixed', inset: '0', width: '100vw', height: '100vh' });
  for (const c of vp.children) if (c.tagName !== 'CANVAS') c.style.setProperty('display', 'none', 'important');
  return true;
})();`;

async function openApp(browser, plate) {
  const page = await browser.newPage({ viewport: { width: plate.width, height: plate.height }, deviceScaleFactor: 1 });
  const errors = [];
  page.on("pageerror", error => errors.push(error.message));
  await page.addInitScript(INIT);
  const query = new URLSearchParams({ quality: plate.quality, hour: String(plate.hour), realm: plate.realm ? "1" : "0", seed: String(plate.seed) });
  await page.goto(URL_BASE + "/?" + query, { waitUntil: "domcontentloaded", timeout: 120000 });
  await page.waitForSelector('[data-ready="true"]', { timeout: 120000 });
  if (await page.evaluate(() => window.nativeScene?.map?.id) !== plate.map) {
    const select = page.locator('select[aria-label="Map or instance"]');
    if (!await select.count()) await page.getByRole("button", { name: "World atlas", exact: true }).click();
    await select.selectOption(String(plate.map));
  }
  await page.waitForFunction(id => window.nativeScene?.map?.id === id && document.querySelector(".native-viewport")?.dataset.ready === "true", plate.map, { timeout: 120000 });
  if (!await page.evaluate(HIDE)) throw new Error("The app viewport was not found");
  // Panels that mount later (the realm chronicle) stay hidden too.
  await page.addStyleTag({ content: ".native-viewport > :not(canvas) { display: none !important; }" });
  await page.evaluate(radius => { const s = window.nativeScene; s.streamRadius = radius; s.setFly(true); s.flySpeed = 0; },plate.streamRadius??3);
  return { page, errors };
}

// Streaming is finished when nothing is in flight and the tile, model and grass counts stop changing.
async function settle(page, quietMs = 1500, maxMs = 90000) {
  const started = Date.now();
  let last = "", calmSince = Date.now();
  while (Date.now() - started < maxMs) {
    const probe = await page.evaluate(() => { const h = document.querySelector(".native-viewport"); return `${window.__inflight}|${h.dataset.tiles}|${h.dataset.models}|${h.dataset.grass ?? ""}`; });
    if (probe.startsWith("0|") && probe === last) { if (Date.now() - calmSince >= quietMs) return true; } else calmSince = Date.now();
    last = probe;
    await page.waitForTimeout(100);
  }
  return false;
}

const place = ({ p, camera, lookAt }) => {
  const s = window.nativeScene;
  const ground = (x, z) => s.height(x, z, NaN);
  const eye = { x: camera.x, z: camera.z, y: camera.y ?? ground(camera.x, camera.z) + (camera.above ?? 5) };
  s.flyCamera.position.set(eye.x, eye.y, eye.z);
  if (lookAt) {
    const target = { x: lookAt.x, z: lookAt.z, y: lookAt.y ?? ground(lookAt.x, lookAt.z) + (lookAt.above ?? 1.6) };
    const dx = target.x - eye.x, dz = target.z - eye.z, dy = target.y - eye.y;
    s.yaw = Math.atan2(dx, dz) + Math.PI;
    s.pitch = Math.atan2(dy, Math.hypot(dx, dz));
  } else { s.yaw = p.yaw ?? 0; s.pitch = p.pitch ?? -0.3; }
  s.flyCamera.rotation.set(s.pitch, s.yaw, 0, "YXZ");
  s.signature = "";
  return { x: eye.x, y: eye.y, z: eye.z, yaw: s.yaw, pitch: s.pitch, groundKnown: !Number.isNaN(ground(eye.x, eye.z)) };
};

// The named actors inside the frame, with their screen positions (one yard above the feet, where a plate sits).
const actorsInFrame = () => {
  const s = window.nativeScene, a = s.actors;
  if (!a) return [];
  const state = a.state, rows = [];
  for (let i = 0; i < state.count; i++) {
    const id = state.ids[i], screen = a.screenPositionOf(id, s.flyCamera);
    if (!screen || screen.x < 0 || screen.y < 0 || screen.x > innerWidth || screen.y > innerHeight) continue;
    const name = a.names.get(id);
    const camera = s.flyCamera.position;
    rows.push({ id, entry: state.entry[i], kind: state.kind[i], flags: state.flags[i], name: name?.name ?? null, level: name?.level ?? null,
      x: state.x[i], y: state.y[i], z: state.z[i], distance: Math.hypot(state.x[i] - camera.x, state.y[i] - camera.y, state.z[i] - camera.z),
      screen: { x: Math.round(screen.x), y: Math.round(screen.y) } });
  }
  return rows.filter(row => row.name).sort((a, b) => a.distance - b.distance).slice(0, 80);
};

const describe = actor => ({ ...actor, kind: KINDS[actor.kind] ?? actor.kind,
  flags: Object.entries(FLAG).filter(([, bit]) => actor.flags & bit).map(([name]) => name) });

async function findActor(page, follow) {
  return page.evaluate(follow => {
    const s = window.nativeScene, a = s.actors;
    if (!a) return null;
    const state = a.state; let best = null;
    for (let i = 0; i < state.count; i++) {
      const kind = ["creature", "adventurer", "gameobject", "corpse"][state.kind[i]];
      if (follow.kind && kind !== follow.kind) continue;
      const name = a.names.get(state.ids[i])?.name;
      if (follow.name && name !== follow.name) continue;
      if (follow.entry && state.entry[i] !== follow.entry) continue;
      if (state.flags[i] & 2) continue; // dead
      const d = Math.hypot(state.x[i] - follow.near[0], state.z[i] - follow.near[1]);
      if (!best || d < best.d) best = { d, id: state.ids[i], name: name ?? null, x: state.x[i], y: state.y[i], z: state.z[i], yaw: state.yaw[i] };
    }
    return best;
  }, follow);
}

function appProvenance(root) {
  // Porcelain lines start with two status columns; trimming the whole output would eat the first line's leading space.
  const git = (...argv) => execFileSync("git", ["-C", root, ...argv], { encoding: "utf8" }).trimEnd();
  const dirty = git("status", "--porcelain", "--untracked-files=no").split("\n").filter(Boolean).map(line => line.slice(3));
  return { root, commit: git("rev-parse", "HEAD").trim(), dirty };
}

async function capturePlate(browser, config, plate) {
  const spec = { width: config.width, height: config.height, quality: "ultra", realm: true, seed: 24401, hour: 10, map: 0, settleMs: 8000, ...plate };
  const { page, errors } = await openApp(browser, spec);
  try {
    // Stream the tiles under the camera first: ground heights only exist once a tile's patch has arrived.
    await page.evaluate(place, { p: spec, camera: { x: spec.camera.x, z: spec.camera.z, y: 400 }, lookAt: null });
    if (!await settle(page)) throw Error(spec.name + ": terrain streaming did not settle");
    let pose = await page.evaluate(place, { p: spec, camera: spec.camera, lookAt: spec.lookAt ?? null });
    if (!pose.groundKnown) throw new Error(spec.name + ": no terrain under the camera at " + spec.camera.x + ", " + spec.camera.z);
    if (!await settle(page)) throw Error(spec.name + ": model streaming did not settle");
    await page.waitForTimeout(spec.settleMs);
    let followed = null;
    if (spec.follow) {
      followed = await findActor(page, spec.follow);
      if (!followed) throw new Error(spec.name + ": no actor matches " + JSON.stringify(spec.follow));
      await page.evaluate(id => window.nativeScene.actors.follow(id), followed.id);
      await page.waitForTimeout(spec.follow.chaseMs ?? 2500);
      await page.evaluate(() => { const s = window.nativeScene; s.actors.follow(0); s.actors.onFollowEnd(); });
      pose = await page.evaluate(() => { const s = window.nativeScene, p = s.flyCamera.position; return { x: p.x, y: p.y, z: p.z, yaw: s.yaw, pitch: s.pitch, groundKnown: true }; });
      await settle(page);
    }
    // Names arrive from the realm worker on request; the app only asks for actors it labels itself.
    await page.evaluate(() => { const s = window.nativeScene, a = s.actors; if (!a) return; const ids = []; for (let i = 0; i < a.state.count; i++) if (!a.names.has(a.state.ids[i])) ids.push(a.state.ids[i]); for (let k = 0; k < ids.length; k += 64) a.post({ type: "names", ids: ids.slice(k, k + 64) }); });
    await page.waitForTimeout(1500);
    const actors = (await page.evaluate(actorsInFrame)).map(describe);
    await page.evaluate(HIDE);
    await page.evaluate(() => { const s = window.nativeScene; if (s.actors) s.actors.overlay.visible = false; });
    await page.waitForTimeout(400);
    const image = await page.screenshot({ type: "jpeg", quality: spec.jpegQuality ?? 92, clip: { x: 0, y: 0, width: spec.width, height: spec.height } });
    await page.evaluate(() => { const s = window.nativeScene; if (s.actors) s.actors.overlay.visible = true; });
    if (errors.length) throw new Error(spec.name + ": page errors: " + errors.join(" | "));
    await mkdir(OUT, { recursive: true });
    const file = path.join(OUT, spec.name + ".jpg");
    await writeFile(file, image);
    const record = { name: spec.name, caption: spec.caption ?? "", file: path.basename(file), width: spec.width, height: spec.height,
      sha256: createHash("sha256").update(image).digest("hex"), capturedAt: new Date().toISOString(),
      app: { ...appProvenance(config.appRoot), url: URL_BASE, browser: browser.version() },
      ...(config.verifiedInputs?{inputs:config.verifiedInputs}:{}),
      request: { map: spec.map, hour: spec.hour, quality: spec.quality, realm: spec.realm, seed: spec.seed, camera: spec.camera, lookAt: spec.lookAt ?? null, follow: spec.follow ?? null },
      camera: { x: pose.x, y: pose.y, z: pose.z, yaw: pose.yaw, pitch: pose.pitch, fov: 62 }, followed, actors };
    await writeFile(path.join(OUT, spec.name + ".json"), JSON.stringify(record, null, 2) + "\n");
    console.log(`${spec.name}: ${image.length} bytes, ${actors.length} actors in frame` + (followed ? `, behind ${followed.name ?? followed.id}` : ""));
    return record;
  } finally {
    await page.close();
  }
}

async function probe(browser, config, map, x, z, radius) {
  const spec = { width: 1280, height: 720, quality: "low", realm: true, seed: 24401, hour: 10, map };
  const { page } = await openApp(browser, spec);
  try {
    await page.evaluate(place, { p: spec, camera: { x, z, y: 400 }, lookAt: null });
    await settle(page);
    await page.evaluate(place, { p: spec, camera: { x, z, above: 40 }, lookAt: { x, z, above: 0 } });
    await settle(page);
    await page.waitForTimeout(10000);
    await page.evaluate(() => { const a = window.nativeScene.actors; if (!a) return; const ids = []; for (let i = 0; i < a.state.count; i++) ids.push(a.state.ids[i]); for (let k = 0; k < ids.length; k += 64) a.post({ type: "names", ids: ids.slice(k, k + 64) }); });
    await page.waitForTimeout(1500);
    const report = await page.evaluate(([x, z, radius]) => {
      const s = window.nativeScene, a = s.actors, rows = [];
      if (a) for (let i = 0; i < a.state.count; i++) {
        const d = Math.hypot(a.state.x[i] - x, a.state.z[i] - z);
        if (d > radius) continue;
        const name = a.names.get(a.state.ids[i]);
        rows.push({ id: a.state.ids[i], entry: a.state.entry[i], kind: a.state.kind[i], flags: a.state.flags[i], name: name?.name ?? null, level: name?.level ?? null,
          x: +a.state.x[i].toFixed(1), y: +a.state.y[i].toFixed(1), z: +a.state.z[i].toFixed(1), yaw: +a.state.yaw[i].toFixed(2), distance: +d.toFixed(1) });
      }
      return { ground: s.height(x, z, NaN), actors: rows.sort((p, q) => p.distance - q.distance) };
    }, [x, z, radius]);
    console.log(`ground at ${x}, ${z}: ${report.ground}`);
    for (const actor of report.actors.map(describe)) console.log(JSON.stringify(actor));
  } finally {
    await page.close();
  }
}

const config = JSON.parse(await readFile(option("config", path.join(WORLDS, "plates.json")), "utf8"));
if(config.inputs){
 const provenance=JSON.parse(await readFile(config.inputs,"utf8"));
 const current=execFileSync("git",["ls-remote","https://github.com/Gethe/wow-ui-source.git","refs/heads/forever"],{encoding:"utf8"}).split(/\s+/)[0];
 if(provenance.identity.uiHead!==current)throw Error("World inputs are not from the current Forever head");
 if(appProvenance(config.appRoot).commit!==provenance.appCommit||appProvenance(config.appRoot).dirty.length)throw Error("World renderer source changed");
 for(const row of [...provenance.outputs,...provenance.extraction,...provenance.rendererSource]){
  const file=path.resolve(path.dirname(config.inputs),row.file),base=path.resolve(path.dirname(config.inputs));
  if(!file.startsWith(base+path.sep))throw Error("World input escaped isolated root");
  if(createHash("sha256").update(await readFile(file)).digest("hex")!==row.sha256)throw Error("World input changed: "+row.file);
 }
 config.verifiedInputs={identity:provenance.identity,manifestSHA256:createHash("sha256").update(await readFile(config.inputs)).digest("hex"),limitations:provenance.limitations};
}
const browser = await chromium.launch({ headless: true, args: GPU_ARGS });
try {
  if (args.includes("--probe")) {
    const i = args.indexOf("--probe");
    await probe(browser, config, Number(args[i + 1]), Number(args[i + 2]), Number(args[i + 3]), Number(args[i + 4] ?? 120));
  } else {
    const names = args.filter((a, i) => !a.startsWith("--") && !(i > 0 && args[i - 1].startsWith("--")));
    const plates = config.plates.filter(plate => !names.length || names.includes(plate.name));
    if (!plates.length) throw new Error("No matching plates");
    for (const plate of plates) await capturePlate(browser, config, plate);
  }
} finally {
  await browser.close();
}
