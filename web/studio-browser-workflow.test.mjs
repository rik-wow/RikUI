import {test,expect} from "@playwright/test";
import {readFileSync} from "node:fs";
import {createEngine} from "./pack-engine.mjs";
import {sourcePaths} from "./pack-sources.mjs";
const scaleEngine=()=>createEngine(sourcePaths.map(p=>readFileSync(new URL("../"+p,import.meta.url),"utf8")));
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
 await page.goto("/studio");await expect(page.locator("#studio-app")).toBeVisible(); for(const step of ["choose","customize","review"]){
  await page.locator('.studio-steps [data-step="'+step+'"]').click();
  const positions=await page.evaluate(()=>({controls:document.querySelector(".studio-controls").getBoundingClientRect().top,preview:document.querySelector(".studio-workspace").getBoundingClientRect().top,overflow:document.documentElement.scrollWidth>innerWidth}));
  expect(positions.preview).toBeGreaterThan(positions.controls);expect(positions.overflow).toBe(false);
 }
 await page.locator("#edit-positions").click();await expect(page.locator("#custom-layout")).toBeVisible();
 await expect(page.locator("#frame-group")).toBeVisible();
});
test("UI scale is visible, keyboard editable, portable and independent of preview zoom",async({page})=>{
 await page.goto("/studio");await expect(page.locator("#game-preview")).toHaveAttribute("data-preview-ready","true");
 const scale=page.getByRole("slider",{name:"UI scale",exact:true}),percent=page.getByRole("spinbutton",{name:"UI scale percentage"});
 await expect(scale).toBeVisible();await expect(percent).toHaveValue("100");
 await page.locator("#show-movers").check();await expect(page.locator("#game-preview")).toHaveAttribute("data-preview-ready","true");
 const main=page.locator("#mover-layer [data-group=main]"),before=await main.evaluate(el=>el.getBoundingClientRect().width);
 const capture=await page.locator("#game-preview").screenshot();
 await scale.focus();await page.keyboard.press("ArrowRight");await expect(percent).toHaveValue("105");
 await expect(page.locator("#ui-scale-summary")).toContainText("Effective UI scale: 105%");
 await expect(page.locator("#game-preview")).toHaveAttribute("data-preview-ready","true");
 expect(await main.evaluate(el=>el.getBoundingClientRect().width)).toBeCloseTo(before*1.05,0);
 expect((await page.locator("#game-preview").screenshot()).equals(capture)).toBe(false);
 await page.locator("#undo").click();await expect(percent).toHaveValue("100");
 await page.locator("#redo").click();await expect(percent).toHaveValue("105");
 await page.locator("#review-fit").click();await page.locator("#export").click();
 const code=await page.locator("#result-code").inputValue(),e=scaleEngine(),pack=e.call("Decode",code);
 expect(pack.adjustments.scale).toBe(1.05);
 await page.locator("#preview-zoom").selectOption("1.5");await page.locator("#export").click();
 expect(await page.locator("#result-code").inputValue()).toBe(code);
 await page.getByRole("button",{name:"Use setup UI scale"}).click();await expect(percent).toHaveValue("100");
 await page.locator("#export").click();expect(e.call("Resolve",e.call("Decode",await page.locator("#result-code").inputValue())).profile.scale).toBe(1);
});
test("UI scale explains accessibility and theme minimums and refuses invalid values",async({page})=>{
 await page.goto("/studio");await expect(page.locator("#studio-app")).toBeVisible();
 const percent=page.getByRole("spinbutton",{name:"UI scale percentage"});
 await percent.fill("90");await percent.press("Tab");await expect(page.locator("#ui-scale-summary")).toContainText("90%");
 await page.getByRole("button",{name:"Make this setup mine"}).click();await page.locator("#tab-style").click();
 await page.locator("#accessibility").selectOption("readable");await expect(percent).toHaveValue("90");
 await expect(page.locator("#ui-scale-summary")).toContainText("Effective UI scale: 115%");
 await expect(page.locator("#ui-scale-summary")).toContainText("your 90% choice is preserved");
 await page.locator("#accessibility").selectOption("standard");await page.locator("#theme").selectOption("ink");
 await expect(page.locator("#ui-scale-summary")).toContainText("Effective UI scale: 110%");
 await percent.fill("400");await percent.press("Tab");await expect(page.locator("#studio-status")).toContainText("25% to 300%");
 await expect(percent).toHaveValue("90");await page.locator("#theme").selectOption("classic");
 for(const value of ["25","300"]){
  await percent.fill(value);await percent.press("Tab");await expect(percent).toHaveValue(value);
  await expect(page.locator("#fit-badge")).toContainText("fit issues");
 }
 await page.locator("#review-fit").click();await expect(page.locator("#export")).toBeDisabled();
});
test("imported custom UI scale survives selective adoption on a narrow screen",async({page})=>{
 const e=scaleEngine(),source=e.call("Bundled","centered");source.adjustments={scale:1.073};const original=e.call("Encode",source);
 await page.setViewportSize({width:320,height:900});await page.goto("/studio");await expect(page.locator("#studio-app")).toBeVisible();
 await page.locator("#import-section").evaluate(el=>el.open=true);await page.locator("#import-code").fill(original);await page.locator("#import").click();
 const percent=page.getByRole("spinbutton",{name:"UI scale percentage"});
 await expect(percent).toHaveValue("107.3");await page.locator("#part-appearance").uncheck();
 await expect(percent).toBeDisabled();await expect(page.locator("#ui-scale-summary")).toContainText("Select Appearance & chat");
 await page.locator("#part-appearance").check();await expect(percent).toHaveValue("107.3");
 await percent.fill("105");await percent.press("Tab");await page.locator("#undo").click();await expect(percent).toHaveValue("107.3");
 expect(e.call("Decode",original).adjustments.scale).toBe(1.073);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
});
