import {test,expect} from "@playwright/test";
for(const width of [390,1440]){
 test("regular site is usable without Studio at "+width,async({page})=>{
  await page.setViewportSize({width,height:1000});
  const errors=[];page.on("pageerror",e=>errors.push(e.message));
  await page.goto("/");
  await expect(page.getByRole("heading",{level:1})).toHaveText("RikUI for WoW Forever");
  await expect(page.locator('a[href^="/studio"],a[href^="/setups"]')).toHaveCount(0);
  await expect(page.getByRole("link",{name:"Install RikUI · beta →"})).toHaveAttribute("href","/install");
  await expect(page.locator(".hero img")).toHaveJSProperty("complete",true);
  expect(await page.locator(".hero img").evaluate(n=>n.naturalWidth)).toBeGreaterThan(0);
  await page.getByRole("link",{name:"Customize in game",exact:true}).click();
  await expect(page).toHaveURL(/\/docs\/options$/);
  await expect(page.getByRole("heading",{level:1})).toHaveText("Settings and profiles");
  await expect(page.locator('a[href^="/studio"],a[href^="/setups"],a[href="/docs/setup-studio"]')).toHaveCount(0);
  await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  await page.keyboard.press("Tab");
  expect(await page.evaluate(()=>document.activeElement.tagName)).toBeTruthy();
  expect(errors).toEqual([]);
 });
}
for(const width of [390,1440]){
 test("installer instructions are readable and keyboard accessible at "+width,async({page})=>{
  await page.setViewportSize({width,height:1000});
  await page.goto("/install");
  await expect(page.getByRole("heading",{level:1})).toHaveText("Your quest guide and routes");
  await expect(page.getByRole("heading",{name:"Four simple steps"})).toBeVisible();
  await expect(page.locator("main ol li")).toHaveCount(4);
  await expect(page.getByText(/Requires an installed current Forever client with English game text \(enUS\)/)).toBeVisible();
  await expect(page.getByText(/All nine provider translation sets are retained locally for source auditing; translated runtime guides are not currently supported/)).toBeVisible();
  const releases=await (await page.request.get("/api/v1/releases")).json();
  if(releases.installer){
   const download=page.getByRole("link",{name:"Download RikUI setup for Windows"});
   await expect(download).toHaveAttribute("href",releases.installer.url);
   await download.focus();await expect(download).toBeFocused();
  }
  const measured=page.getByText("Measured preparation example",{exact:true});
  await measured.focus();await page.keyboard.press("Enter");
  await expect(page.getByText(/about 74 minutes/)).toBeVisible();
  await page.keyboard.press("Enter");
  await expect(page.getByText(/about 74 minutes/)).not.toBeVisible();
  await page.goto("/install");
  await expect(page.getByRole("heading",{name:"What coverage means"})).toBeVisible();
  await expect.poll(()=>page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  await page.keyboard.press("Tab");
  await expect(page.getByRole("link",{name:"Skip to content"})).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page.locator("#main")).toBeFocused();
  await page.getByRole("link",{name:"QuestieDB",exact:true}).focus();
  await expect(page.getByRole("link",{name:"QuestieDB",exact:true})).toBeFocused();
 });
}
test("old Studio URLs return users to regular settings",async({page})=>{
 for(const path of ["/studio?pack=healer","/setups","/setups/centered","/setups/submit","/docs/setup-studio"]){
  await page.goto(path);
  await expect(page).toHaveURL(/\/docs\/options$/);
  await expect(page.locator("#studio-app")).toHaveCount(0);
 }
});
