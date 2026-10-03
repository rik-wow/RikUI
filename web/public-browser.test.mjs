import {test,expect} from "@playwright/test";
for(const width of [390,1440]){
 test("regular site is usable without Studio at "+width,async({page})=>{
  await page.setViewportSize({width,height:1000});
  const errors=[];page.on("pageerror",e=>errors.push(e.message));
  await page.goto("/");
  await expect(page.getByRole("heading",{level:1})).toHaveText("RikUI for WoW Forever");
  await expect(page.locator('a[href^="/studio"],a[href^="/setups"]')).toHaveCount(0);
  await expect(page.getByRole("link",{name:"Install RikUI · beta →"})).toHaveAttribute("href",/github.com\/rik-wow\/RikUI\/releases\/tag\/v/);
  await expect(page.locator(".hero img")).toHaveJSProperty("complete",true);
  expect(await page.locator(".hero img").evaluate(n=>n.naturalWidth)).toBeGreaterThan(0);
  await page.getByRole("link",{name:"Customize in game",exact:true}).click();
  await expect(page).toHaveURL(/\/docs\/options$/);
  await expect(page.getByRole("heading",{level:1})).toHaveText("Settings and profiles");
  await expect(page.locator('a[href^="/studio"],a[href^="/setups"],a[href="/docs/setup-studio"]')).toHaveCount(0);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  await page.keyboard.press("Tab");
  expect(await page.evaluate(()=>document.activeElement.tagName)).toBeTruthy();
  expect(errors).toEqual([]);
 });
}
test("old Studio URLs return users to regular settings",async({page})=>{
 for(const path of ["/studio?pack=healer","/setups","/setups/centered","/setups/submit","/docs/setup-studio"]){
  await page.goto(path);
  await expect(page).toHaveURL(/\/docs\/options$/);
  await expect(page.locator("#studio-app")).toHaveCount(0);
 }
});
