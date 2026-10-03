import {test,expect} from "@playwright/test";
const ready=page=>expect(page.locator("#game-preview")).toHaveAttribute("data-preview-ready","true");
test("presentation interactions retain feature nodes and settled pixels",async({page})=>{
 await page.goto("/studio");await ready(page);
 await page.locator('.studio-steps [data-step="customize"]').click();await ready(page);
 await page.evaluate(()=>{
  window.originalChat=document.getElementById("module-chat");
  window.bitmapDraws=0;const original=CanvasRenderingContext2D.prototype.drawImage;
  CanvasRenderingContext2D.prototype.drawImage=function(...args){if(this.canvas.id==="game-preview")window.bitmapDraws++;return original.apply(this,args);};
 });
 await page.locator("#show-movers").check();await ready(page);
 await page.locator("#frame-group").evaluate(el=>{el.value="chat";el.dispatchEvent(new Event("change"));});await ready(page);
 await page.locator('#mover-layer [data-group="minimap"]').hover();
 const hoverColor=await page.locator('#mover-layer [data-group="minimap"]').evaluate(el=>getComputedStyle(el).backgroundColor);
 expect(Number(hoverColor.match(/,\s*([.\d]+)\)$/)?.[1])).toBeLessThan(0.2);
 await page.locator("#tab-style").click();await ready(page);
 expect(await page.evaluate(()=>window.originalChat===document.getElementById("module-chat"))).toBe(true);
 expect(await page.evaluate(()=>window.bitmapDraws)).toBe(0);
 await page.locator("#theme").selectOption("ocean");
 await expect.poll(()=>page.evaluate(()=>window.bitmapDraws)).toBeGreaterThan(0);
});
test("fullscreen keeps controls, fits the stage, zooms and restores focus with Escape",async({page})=>{
 await page.goto("/studio");await ready(page);
 await page.locator("#fullscreen").click();
 await expect(page.locator("#studio-app")).toHaveClass(/precision-workspace/);
 await expect(page.locator("#exit-fullscreen")).toBeFocused();
 await expect.poll(()=>page.evaluate(()=>document.fullscreenElement?.id)).toBe("studio-app");
 await page.locator("#viewport").selectOption("3840x2160");await ready(page);
 await page.locator("#workspace-controls").click();
 await expect(page.locator("#studio-controls")).toBeHidden();
 await expect.poll(()=>page.locator("#game-preview").evaluate(c=>{const s=c.closest(".preview-shell"),r=c.getBoundingClientRect();return r.width<=s.clientWidth+2&&r.height<=s.clientHeight+2;})).toBe(true);
 await page.locator("#preview-zoom").selectOption("4");
 await expect.poll(()=>page.locator(".preview-shell").evaluate(s=>s.scrollWidth>s.clientWidth||s.scrollHeight>s.clientHeight)).toBe(true);
 await page.keyboard.press("Escape");
 await expect(page.locator("#studio-app")).not.toHaveClass(/precision-workspace/);
 await expect(page.locator("#fullscreen")).toBeFocused();
 await expect(page.locator("#studio-controls")).toBeVisible();
 expect(await page.evaluate(()=>document.querySelector(".site-header").inert)).toBe(false);
});
test("denied fullscreen has an accessible expanded workspace on mobile",async({page})=>{
 await page.setViewportSize({width:390,height:844});
 await page.addInitScript(()=>{Element.prototype.requestFullscreen=()=>Promise.reject(new Error("denied"));});
 await page.goto("/studio");await ready(page);await page.locator("#fullscreen").click();
 await expect(page.locator("#workspace-status")).toContainText("Expanded workspace");
 await page.locator("#workspace-controls").click();
 await expect(page.locator("#studio-controls")).toBeHidden();
 await page.locator("#exit-fullscreen").focus();await page.keyboard.press("Escape");
 await expect(page.locator("#fullscreen")).toBeFocused();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
test("world background fits all device aspects, stays out of export and degrades cleanly",async({page})=>{
 await page.goto("/studio");await ready(page);
 await expect(page.locator("#game-preview")).toHaveAttribute("data-background","ready");
 const source=await page.evaluate(async()=>{const d=await (await fetch(document.getElementById("studio-app").dataset.source)).json();return d.background;});
 expect(source.width).toBe(3840);expect(source.height).toBe(2160);
 expect(source.sha256).toBe("212b21a4c6745595bbb84f1bb2e84845c851bfcf4ff39221f71bd6ec687edd7d");
 await expect(page.locator("#background-status")).toContainText("Supplied game screenshot");
 const image=await page.evaluate(async url=>{const im=new Image();im.src=url;await im.decode();return [im.naturalWidth,im.naturalHeight];},source.url);
 expect(image).toEqual([3840,2160]);
 await page.locator('.studio-steps [data-step="review"]').click();await page.locator("#export").click();const original=await page.locator("#result-code").inputValue();
 for(const value of ["dim","plain","world"]){await page.locator("#world-background").selectOption(value);await ready(page);await page.locator("#export").click();expect(await page.locator("#result-code").inputValue()).toBe(original);}
 for(const viewport of ["3440x1440","1280x800","3840x2160"]){await page.locator("#viewport").selectOption(viewport);await expect(page.locator("#game-preview")).toHaveAttribute("width",viewport.split("x")[0]);await ready(page);await expect(page.locator("#game-preview")).toHaveAttribute("data-background","ready");}
});
test("one supplied screenshot is reused by every bundled setup and activity",async({page})=>{
 const requests=[];page.on("request",r=>{if(/\/assets\/studio\/background-[a-f0-9]+\.jpg$/.test(new URL(r.url()).pathname))requests.push(r.url());});
 await page.goto("/studio");await ready(page);
 const packs=await page.locator("#pack-picker option").evaluateAll(options=>options.map(o=>o.value));
 expect(packs.length).toBeGreaterThanOrEqual(4);
 for(const pack of packs){await page.locator("#pack-picker").selectOption(pack);await ready(page);await expect(page.locator("#game-preview")).toHaveAttribute("data-background","ready");}
 const activities=await page.locator("#activity option").evaluateAll(options=>options.map(o=>o.value));
 expect(activities.length).toBeGreaterThanOrEqual(4);
 for(const activity of activities){await page.locator("#activity").selectOption(activity);await ready(page);await expect(page.locator("#game-preview")).toHaveAttribute("data-background","ready");}
 expect(requests).toHaveLength(1);
});
test("failed world image keeps native preview, controls and export usable",async({page})=>{
 await page.route("**/assets/studio/background-*.jpg",route=>route.abort());
 await page.goto("/studio");await ready(page);
 await expect(page.locator("#background-status")).toContainText("unavailable");
 const keys=JSON.parse(await page.locator("#game-preview").getAttribute("data-painted-groups"));expect(keys).toContain("chat");expect(keys).toContain("main");
 await page.locator('.studio-steps [data-step="review"]').click();await expect(page.locator("#export")).toBeEnabled();await page.locator("#export").click();await expect(page.locator("#result-code")).toHaveValue(/^!RIKS1!/);
});
test("drag feedback performs no canvas pixel readback and commits a snapped edit",async({page})=>{
 await page.goto("/studio");await ready(page);await page.locator("#edit-positions").click();await ready(page);
 await page.evaluate(()=>{window.readbacks=0;const original=CanvasRenderingContext2D.prototype.getImageData;CanvasRenderingContext2D.prototype.getImageData=function(...args){window.readbacks++;return original.apply(this,args);};});
 await page.locator("#viewport").selectOption("3840x2160");await expect(page.locator("#game-preview")).toHaveAttribute("width","3840");await ready(page);
 await page.locator("#frame-group").selectOption("chat");await ready(page);
 const mover=page.locator('#mover-layer [data-group="chat"]'),r=await mover.boundingBox();
 await page.mouse.move(r.x+20,r.y+20);await page.mouse.down();await page.mouse.move(r.x+45,r.y+10,{steps:4});
 await expect(page.locator("#drag-outline")).toBeVisible();
 expect(await page.evaluate(()=>window.readbacks)).toBe(0);
 await page.mouse.up();await ready(page);
 await expect(page.locator("#drag-outline")).toBeHidden();await expect(page.locator("#undo")).toBeEnabled();
});
test("canvas bar editor is wide, visual, independent and restores collapsed controls",async({page})=>{
 await page.setViewportSize({width:1600,height:1100});await page.goto("/studio");await ready(page);
 await page.locator("#edit-positions").click();await ready(page);
 await expect(page.locator("#studio-app")).toHaveClass(/layout-workspace/);
 await expect(page.locator("#studio-controls")).toBeHidden();
 await expect(page.locator("#show-movers")).not.toBeChecked();
 expect((await page.locator(".canvas-workspace").boundingBox()).width).toBeGreaterThan(1500);
 await expect.poll(()=>page.locator("#game-preview").evaluate(c=>c.getBoundingClientRect().bottom<=innerHeight)).toBe(true);
 await expect(page.locator('#bar-picker [data-bar="main"]')).toHaveAttribute("aria-pressed","true");
 await page.locator('#bar-arrangements [data-columns="4"]').click();await ready(page);
 await expect(page.locator("#bar-columns")).toHaveValue("4");await expect(page.locator("#shape-summary")).toContainText("3 rows");
 await page.locator('#bar-gaps [data-gap="4"]').click();await ready(page);
 await expect(page.locator("#bar-spacing")).toHaveValue("4");
 for(const id of ["bar-columns","bar-spacing"])expect((await page.locator("#"+id).boundingBox()).width).toBeGreaterThanOrEqual(72);
 await page.locator('#bar-picker [data-bar="bar2"]').click();await ready(page);
 await expect(page.locator("#bar-columns")).toHaveValue("12");
 await page.locator('#bar-arrangements [data-columns="6"]').click();await ready(page);
 await page.locator('#bar-picker [data-bar="main"]').click();await ready(page);
 await expect(page.locator("#bar-columns")).toHaveValue("4");await expect(page.locator("#bar-spacing")).toHaveValue("4");
 const geometry=await page.locator("#geometry").textContent();
 await page.locator("#close-inspector").click();await expect(page.locator("#layout-inspector")).toBeHidden();
 await expect(page.locator("#show-inspector")).toBeFocused();
 await page.locator('#mover-layer [data-group="main"]').click({position:{x:5,y:5}});await ready(page);
 await expect(page.locator("#layout-inspector")).toBeVisible();await expect(page.locator("#geometry")).toHaveText(geometry);
 await page.locator('#bar-picker [data-bar="pet"]').focus();await page.keyboard.press("Enter");await ready(page);
 await expect(page.locator("#inspector-title")).toHaveText("Pet action bar");
 await expect(page.locator("#bar-arrangements")).toContainText("5 × 2");
 await page.locator('#bar-picker [data-bar="main"]').click();await ready(page);
 await page.screenshot({path:"../dist/studio-canvas-bars-desktop.png",fullPage:false});
 await page.locator("#tab-parts").click();await ready(page);await expect(page.locator("#studio-controls")).toBeVisible();
 await page.locator("#tab-layout").click();await ready(page);
 await expect(page.locator("#studio-app")).toHaveClass(/layout-workspace/);
});
test("canvas bar controls remain usable on phones and in precise fullscreen",async({page})=>{
 await page.setViewportSize({width:390,height:844});await page.goto("/studio");await ready(page);
 await page.locator("#edit-positions").click();await ready(page);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 const c=await page.locator("#game-preview").boundingBox(),i=await page.locator("#layout-inspector").boundingBox();
 expect(i.y).toBeGreaterThanOrEqual(c.y+c.height);
 await page.locator('#bar-arrangements [data-columns="6"]').click();await ready(page);await expect(page.locator("#bar-columns")).toHaveValue("6");
 await page.locator("#layout-inspector").scrollIntoViewIfNeeded();
 await page.screenshot({path:"../dist/studio-canvas-bars-mobile.png",fullPage:false});
 await page.setViewportSize({width:1600,height:1100});
 await page.locator("#fullscreen").click();
 await expect(page.locator("#studio-app")).toHaveClass(/precision-workspace/);
 await expect(page.locator("#studio-controls")).toBeHidden();
 await expect(page.locator("#bar-size")).toBeVisible();
 await page.locator("#bar-size").selectOption("42");await ready(page);
 await expect.poll(()=>page.locator("#game-preview").evaluate(c=>{const s=c.closest(".preview-shell"),r=c.getBoundingClientRect();return r.width<=s.clientWidth+2&&r.height<=s.clientHeight+2;})).toBe(true);
 await page.screenshot({path:"../dist/studio-canvas-bars-fullscreen.png",fullPage:false});
 await page.locator("#exit-fullscreen").focus();await page.keyboard.press("Escape");
 await expect(page.locator("#studio-app")).not.toHaveClass(/precision-workspace/);
 await expect(page.locator("#fullscreen")).toBeFocused();
 await expect(page.locator("#bar-size")).toHaveValue("42");
});
test("movement controls give unsnapped fine nudges and exact independent coordinates",async({page})=>{
 await page.goto("/studio");await ready(page);await page.locator("#edit-positions").click();await ready(page);
 await page.getByText("Position & alignment",{exact:true}).click();
 const x=Number(await page.locator("#frame-x").inputValue()),y=Number(await page.locator("#frame-y").inputValue());
 await page.locator("#game-preview").focus();await page.keyboard.press("ArrowRight");
 await expect.poll(async()=>Number(await page.locator("#frame-x").inputValue())).toBeCloseTo(x+1,2);
 await expect.poll(async()=>Number(await page.locator("#frame-y").inputValue())).toBeCloseTo(y,2);
 await page.keyboard.press("Shift+ArrowRight");
 await expect.poll(async()=>Number(await page.locator("#frame-x").inputValue())).toBeCloseTo(x+11,2);
 await page.locator("#move-step").selectOption("2");await page.locator("#game-preview").focus();await page.keyboard.press("ArrowUp");
 await expect.poll(async()=>Number(await page.locator("#frame-y").inputValue())).toBeCloseTo(y+2,2);
 await page.locator("#frame-x").fill(String(x+12.25));await page.keyboard.press("Tab");
 await expect.poll(async()=>Number(await page.locator("#frame-x").inputValue())).toBeCloseTo(x+12.25,2);
 await expect.poll(async()=>Number(await page.locator("#frame-y").inputValue())).toBeCloseTo(y+2,2);
 await page.locator("#undo").click();await expect.poll(async()=>Number(await page.locator("#frame-x").inputValue())).toBeCloseTo(x+11,2);
 await page.locator("#snap-align").uncheck();await page.locator("#snap-grid").uncheck();await page.locator("#grid-size").selectOption("4");await page.locator("#show-grid").check();
 await expect(page.locator("#grid-layer")).toBeVisible();
 await expect.poll(()=>page.locator("#game-preview").evaluate(c=>{const s=c.closest(".preview-shell"),r=c.getBoundingClientRect(),b=s.getBoundingClientRect();return r.top>=b.top-1&&r.bottom<=b.bottom+1&&s.scrollTop===0;})).toBe(true);
 await page.screenshot({path:"../dist/studio-precision-grid.png",fullPage:false});
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
test("snapping preferences avoid bitmap repaint and never enter exported packs",async({page})=>{
 await page.goto("/studio");await ready(page);
 await page.locator('.studio-steps [data-step="review"]').click();await page.locator("#export").click();const code=await page.locator("#result-code").inputValue();
 await page.locator("#edit-positions").click();await ready(page);
 await page.evaluate(()=>{window.preferenceDraws=0;const original=CanvasRenderingContext2D.prototype.drawImage;CanvasRenderingContext2D.prototype.drawImage=function(...args){if(this.canvas.id==="game-preview")window.preferenceDraws++;return original.apply(this,args);};});
 await page.locator("#show-grid").check();await page.locator("#grid-size").selectOption("2");await page.locator("#move-step").selectOption("4");await page.locator("#snap-align").uncheck();await page.locator("#snap-grid").uncheck();
 expect(await page.evaluate(()=>window.preferenceDraws)).toBe(0);await expect(page.locator("#undo")).toBeDisabled();
 await page.locator("#review-fit").click();await page.locator("#export").click();expect(await page.locator("#result-code").inputValue()).toBe(code);
});
test("live grid drag feedback matches settled bounds and Alt bypasses snaps",async({page})=>{
 await page.goto("/studio");await ready(page);await page.locator("#edit-positions").click();await ready(page);
 await page.locator("#close-inspector").click();await page.locator("#snap-align").uncheck();await page.locator("#grid-size").selectOption("16");
 const mover=page.locator('#mover-layer [data-group="main"]');
 for(const free of [false,true]){
  const r=await mover.boundingBox(),canvas=await page.locator("#game-preview").boundingBox();
  if(free)await page.keyboard.down("Alt");
  const start={x:r.x+r.width/2,y:r.y+r.height/2};
  expect(await page.evaluate(p=>document.elementFromPoint(p.x,p.y)?.closest("[data-group]")?.dataset.group,start)).toBe("main");
  await page.mouse.move(start.x,start.y);await page.mouse.down();await page.mouse.move(start.x+37.25*canvas.width/1920,start.y-33.25*canvas.height/1080,{steps:5});
  await expect(page.locator("#drag-outline")).toBeVisible();
  const ghost=await page.locator("#drag-outline").boundingBox();
  await page.mouse.up();if(free)await page.keyboard.up("Alt");
  await ready(page);const settled=await mover.boundingBox();
  expect(Math.abs(settled.x-ghost.x)).toBeLessThan(.01);expect(Math.abs(settled.y-ghost.y)).toBeLessThan(.01);
  // Exact source coordinates avoid CSS subpixel rounding in bounding boxes.
  const units=Number(await page.locator("#frame-x").inputValue());
  if(!free)expect(Math.abs(units/16-Math.round(units/16))).toBeLessThan(.001);
  else expect(Math.abs(units/16-Math.round(units/16))).toBeGreaterThan(.02);
  await page.locator("#close-inspector").click();
 }
});
