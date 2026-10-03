import {studioControl} from "./studio-test-workflow.mjs";
import {test,expect} from "@playwright/test";
import {readFileSync} from "node:fs";
import {createHash} from "node:crypto";
import {createEngine} from "./pack-engine.mjs";
import {sourcePaths} from "./pack-sources.mjs";
const engine=()=>createEngine(sourcePaths.map(p=>readFileSync(new URL("../"+p,import.meta.url),"utf8")));
test("dragging native groups settles, snaps and resets without source drift",async({page})=>{
 await page.goto("/studio");await expect(page.locator("#studio-app")).toBeVisible();
 await studioControl(page,"frame-group");await page.locator("#frame-group").selectOption("main");
 await expect(page.locator("#geometry")).toHaveText(/main: ([0-9]+), ([0-9]+) · ([0-9]+) × ([0-9]+)/);
 const before=await page.locator("#geometry").innerText();
 const values=before.match(/main: (\d+), (\d+) · (\d+) × (\d+)/).slice(1).map(Number);
 await page.locator("#game-preview").scrollIntoViewIfNeeded();
 const box=await page.locator("#game-preview").boundingBox(),[x,y,w,h]=values;
 const cx=box.x+(x+w/2)/1920*box.width,cy=box.y+box.height-(y+h/2)/1080*box.height;
 await page.mouse.move(cx,cy);await page.mouse.down();await page.mouse.move(cx+24/1920*box.width,cy,{steps:4});await page.mouse.up();
 await expect(page.locator("#geometry")).not.toHaveText(before);
 await studioControl(page,"export");await page.locator("#export").click();const pack=engine().call("Decode",await page.locator("#result-code").inputValue());
 expect(pack.ancestry.id).toBe("rikui-centered");expect(pack.adjustments.positions.main.point).toBe("BOTTOMLEFT");
 await studioControl(page,"reset-frame");await page.locator("#reset-frame").click();await expect(page.locator("#geometry")).toHaveText(before);
 await studioControl(page,"game-preview");await page.locator("#game-preview").focus();await page.keyboard.press("ArrowLeft");await page.keyboard.press("Control+z");
 await expect(page.locator("#geometry")).toHaveText(before);
});
test("creator revisions keep personal edits, allow selective changes and clear obsolete choices",async({page})=>{
 const e=engine(),incoming=e.call("Bundled","centered");incoming.revision++;
 incoming.profile=e.call("Merge",incoming.profile,e.call("Theme","ink"));
 await page.goto("/studio");await expect(page.locator("#studio-app")).toBeVisible();
 await studioControl(page,"theme");await page.locator("#theme").selectOption("ocean");await studioControl(page,"import-code");await page.locator("#import-code").fill(e.call("Encode",incoming));
 await studioControl(page,"creator-update");await page.locator("#creator-update").click();await expect(page.locator("#update-conflicts")).toContainText("theme.accent");
 await expect(page.locator("#theme")).toHaveValue("ocean");
 await page.getByLabel("Accept creator change: theme.accent",{exact:true}).check();
 await expect(page.locator("#theme")).toHaveValue("ink");
 await studioControl(page,"device");await page.locator("#device").selectOption("handheld");await expect(page.locator("#update-conflicts input")).toHaveCount(0);
 await expect(page.locator("#fit-status")).not.toHaveClass("issue");
});
test("maintained metadata, theme-only sharing and explicit character content round-trip",async({page})=>{
 await page.goto("/studio");await expect(page.locator("#studio-app")).toBeVisible();
 await page.locator('.studio-steps [data-step="review"]').click();await page.getByText("Creator attribution and revision",{exact:true}).click();
 await studioControl(page,"maintain-identity");await page.locator("#maintain-identity").check();await studioControl(page,"pack-title");await page.locator("#pack-title").fill("My maintained setup");
 await studioControl(page,"pack-creator");await page.locator("#pack-creator").fill("Test creator");await studioControl(page,"pack-revision");await page.locator("#pack-revision").fill("3");await studioControl(page,"metadata-apply");await page.locator("#metadata-apply").click();
 await studioControl(page,"export");await page.locator("#export").click();const p=engine().call("Decode",await page.locator("#result-code").inputValue());
 expect(p.id).toBe("rikui-centered");expect(p.revision).toBe(3);expect(p.creator).toBe("Test creator");expect(p.character).toBeUndefined();
 await studioControl(page,"theme-export");await page.locator("#theme-export").click();const theme=engine().call("Decode",await page.locator("#result-code").inputValue());
 expect(theme.components).toEqual({appearance:true});expect(theme.character).toBeUndefined();expect(Object.keys(theme.groups)).toHaveLength(0);
 const optional=engine().call("Bundled","centered");optional.character={bindings:{"CTRL-1":"ACTIONBUTTON1"}};
 await studioControl(page,"import-code");await page.locator("#import-code").fill(engine().call("Encode",optional));await studioControl(page,"import");await page.locator("#import").click();
 await expect(page.locator("#part-character")).not.toBeChecked();
 await studioControl(page,"part-character");await page.locator("#part-character").check();await studioControl(page,"export");await page.locator("#export").click();
 const adopted=engine().call("Decode",await page.locator("#result-code").inputValue());
 expect(adopted.character.bindings).toEqual({"CTRL-1":"ACTIONBUTTON1"});
});
test("optional integration absent or present preserves honest ownership and appearance limits",async({page})=>{
 const e=engine(),p=e.call("Bundled","centered");p.integration="questtogether";p.ownership.nameplates="specialist";p.profile.modules.nameplates=false;
 await page.goto("/studio");await expect(page.locator("#studio-app")).toBeVisible();
 await studioControl(page,"import-code");await page.locator("#import-code").fill(e.call("Encode",p));await studioControl(page,"import");await page.locator("#import").click();
 await expect(page.locator("#ownership")).toContainText("Nameplates (rikui)");
 await studioControl(page,"questtogether");await page.locator("#questtogether").check();await expect(page.locator("#ownership")).toContainText("Nameplates (specialist)");
 p.profile.textScale=1.05;await studioControl(page,"import-code");await page.locator("#import-code").fill(e.call("Encode",p));await studioControl(page,"import");await page.locator("#import").click();
 await expect(page.locator("#preview-limit")).toContainText("Geometry-only");
});
test("public native component bytes match reviewed hashes and private client inputs stay unavailable",async({request,page})=>{
 test.setTimeout(120000);
 await page.goto("/studio");const response=await request.get(await page.locator("#studio-app").getAttribute("data-source")),data=await response.json();
 expect(data.reviewOnly).toBe(false);expect(Object.keys(data.atlases)).toHaveLength(6);
 for(const atlas of Object.values(data.atlases))for(const component of Object.values(atlas.components)){
  const image=await request.get(component.url);expect(image.status()).toBe(200);
  // Public lossless crops have their own byte hash; source capture SHA remains unchanged provenance.
  expect(createHash("sha256").update(await image.body()).digest("hex")).toBe(component.bitmap?.sha256??component.sha256);
 }
 for(const path of ["/assets/forever-20260927/spells/holy_light.png","/assets/studio/WowB.exe","/assets/studio/forever-source.lua"])expect((await request.get(path)).status()).toBe(404);
});