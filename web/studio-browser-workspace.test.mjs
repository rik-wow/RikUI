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
test("drag feedback performs no canvas pixel readback and commits a snapped edit",async({page})=>{
 await page.goto("/studio");await ready(page);await page.locator("#edit-positions").click();await ready(page);
 await page.evaluate(()=>{window.readbacks=0;const original=CanvasRenderingContext2D.prototype.getImageData;CanvasRenderingContext2D.prototype.getImageData=function(...args){window.readbacks++;return original.apply(this,args);};});
 const mover=page.locator('#mover-layer [data-group="chat"]'),r=await mover.boundingBox();
 await page.mouse.move(r.x+20,r.y+20);await page.mouse.down();await page.mouse.move(r.x+45,r.y+10,{steps:4});
 await expect(page.locator("#drag-outline")).toBeVisible();
 expect(await page.evaluate(()=>window.readbacks)).toBe(0);
 await page.mouse.up();await ready(page);
 await expect(page.locator("#drag-outline")).toBeHidden();await expect(page.locator("#undo")).toBeEnabled();
});
