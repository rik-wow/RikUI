import {test,expect} from "@playwright/test";
test("focused steps, keyboard tabs, selected cards, preview zoom and fit review",async({page})=>{
 const errors=[];page.on("pageerror",e=>errors.push(e.message));
 await page.goto("/studio");await expect(page.locator("#game-preview")).toHaveAttribute("data-preview-ready","true");
 await expect(page.locator("[data-panel=choose]")).toBeVisible();
 await expect(page.locator("#export")).not.toBeVisible();
 await expect(page.locator("#theme")).not.toBeVisible();
 await page.locator("[data-pack=hud]").click();await expect(page.locator("[data-pack=hud]")).toHaveAttribute("aria-pressed","true");
 await page.getByRole("button",{name:"Make this setup mine"}).click();
 await expect(page.locator("#custom-parts")).toBeVisible();
 await page.locator("#tab-parts").focus();await page.keyboard.press("ArrowRight");
 await expect(page.locator("#tab-style")).toBeFocused();await expect(page.locator("#custom-style")).toBeVisible();
 await page.locator("#theme").selectOption("ocean");await expect(page.locator("#theme-description")).toContainText("Blue accent");
 await page.locator("#tab-style").focus();await page.keyboard.press("End");
 await expect(page.locator("#tab-layout")).toBeFocused();await expect(page.locator("#show-movers")).toBeChecked();
 await expect(page.locator("#mover-layer [data-group=questtimers]")).toBeVisible();
 await page.locator("#frame-group").selectOption("main");
 const before=await page.locator("#geometry").innerText();await page.locator("#game-preview").focus();await page.keyboard.press("ArrowRight");
 await expect(page.locator("#geometry")).not.toHaveText(before);await page.locator("#undo").click();await expect(page.locator("#geometry")).toHaveText(before);
 const width=await page.locator("#game-preview").evaluate(el=>el.getBoundingClientRect().width);
 await page.locator("#preview-zoom").selectOption("1.5");expect(await page.locator("#game-preview").evaluate(el=>el.getBoundingClientRect().width)).toBeGreaterThan(width*1.4);
 await page.locator("#review-fit").click();await expect(page.locator("[data-panel=review]")).toBeVisible();
 await expect(page.locator("#export")).toBeEnabled();await page.locator("#export").click();await expect(page.locator("#result-code")).toHaveValue(/^!RIKS1!/);
 expect(errors).toEqual([]);
});
test("mobile workflow follows controls then preview, without horizontal page overflow",async({page})=>{
 await page.setViewportSize({width:390,height:844});await page.emulateMedia({reducedMotion:"reduce"});
 await page.goto("/studio");await expect(page.locator("#studio-app")).toBeVisible();
 for(const step of ["choose","customize","review"]){
  await page.locator('.studio-steps [data-step="'+step+'"]').click();
  const positions=await page.evaluate(()=>({controls:document.querySelector(".studio-controls").getBoundingClientRect().top,preview:document.querySelector(".studio-workspace").getBoundingClientRect().top,overflow:document.documentElement.scrollWidth>innerWidth}));
  expect(positions.preview).toBeGreaterThan(positions.controls);expect(positions.overflow).toBe(false);
 }
 await page.locator("#edit-positions").click();await expect(page.locator("#custom-layout")).toBeVisible();
 await expect(page.locator("#frame-group")).toBeVisible();
});
