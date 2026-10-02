import {studioControl} from "./studio-test-workflow.mjs";
import {test,expect} from "@playwright/test";
test("gallery and authentic editor keyboard/export/import/share journey",async({page})=>{
 const errors=[];page.on("pageerror",e=>errors.push(e.message));
 await page.goto("/setups/centered");await expect(page.locator("h1")).toHaveText("Centered");
 const original=await page.locator("#pack-code").inputValue();expect(original).toMatch(/^!RIKS1!/);
 await page.getByRole("link",{name:"Customize this setup"}).click();
 await expect(page.locator("#studio-app")).toBeVisible({timeout:30000});
 await expect(page.locator("#game-preview")).toHaveAttribute("width","1920");
 await studioControl(page,"frame-group");await page.locator("#frame-group").selectOption("main");
 const before=await page.locator("#geometry").innerText();
 await studioControl(page,"game-preview");await page.locator("#game-preview").focus();await page.keyboard.press("ArrowRight");
 await expect(page.locator("#geometry")).not.toHaveText(before);
 await page.getByRole("button",{name:"Undo",exact:true}).click();await expect(page.locator("#geometry")).toHaveText(before);
 await page.getByRole("button",{name:"Redo",exact:true}).click();
 await studioControl(page,"part-navigation");await page.locator("#part-navigation").uncheck();await studioControl(page,"part-inventory");await page.locator("#part-inventory").uncheck();
 await studioControl(page,"accessibility");await page.locator("#accessibility").selectOption("readable");
 await studioControl(page,"theme");await page.locator("#theme").selectOption("ocean");
 await studioControl(page,"export");await page.locator("#export").click();
 const edited=await page.locator("#result-code").inputValue();expect(edited).toMatch(/^!RIKS1!/);expect(edited).not.toBe(original);
 await studioControl(page,"import-code");await page.locator("#import-code").fill(edited);await studioControl(page,"import");await page.locator("#import").click();
 await expect(page.locator("#studio-status")).toContainText("Imported");
 await studioControl(page,"share");await page.locator("#share").click();const link=await page.locator("#share-link").inputValue();expect(link).toContain("/studio#");
 await page.goto(link);await expect(page.locator("#studio-app")).toBeVisible();await expect(page.locator("#part-navigation")).not.toBeChecked();
 expect(errors).toEqual([]);
});
test("malformed imports preserve the current editor and data failures retain fallback content",async({page})=>{
 await page.goto("/studio");await expect(page.locator("#studio-app")).toBeVisible({timeout:30000});
 const before=await page.locator("#pack-description").innerText();await studioControl(page,"import-code");await page.locator("#import-code").fill("return os.execute('unsafe')");
 await studioControl(page,"import");await page.locator("#import").click();await expect(page.locator("#pack-description")).toHaveText(before);
 await page.route("**/assets/studio/data-*.json",route=>route.fulfill({status:503,body:"Unavailable"}));
 await page.reload();await expect(page.locator("#studio-status")).toContainText("unavailable");
 await expect(page.getByRole("link",{name:"Browse setups",exact:true})).toBeVisible();
});
test("small-screen editor and gallery remain accessible without horizontal overflow",async({page})=>{
 await page.setViewportSize({width:390,height:844});await page.emulateMedia({reducedMotion:"reduce"});
 for(const path of ["/","/setups","/studio"]){
  await page.goto(path);if(path==="/studio")await expect(page.locator("#studio-app")).toBeVisible({timeout:30000});
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBeTruthy();
 }
 await studioControl(page,"device");await page.locator("#device").selectOption("handheld");await expect(page.locator("#game-preview")).toHaveAttribute("width","1280");
 await studioControl(page,"frame-group");await page.locator("#frame-group").selectOption("main");await page.getByRole("button",{name:"Move selected frame right"}).click();
 await expect(page.locator("#geometry")).toContainText("main:");
});