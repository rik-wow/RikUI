import {test,expect} from "@playwright/test";
import {documentation} from "./docs-generated.mjs";
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
  await expect(page.getByText(/Guides in other languages are not currently supported/)).toBeVisible();
  const releases=await (await page.request.get("/api/v1/releases")).json();
  if(releases.installer){
   const download=page.getByRole("link",{name:"Download RikUI setup for Windows"});
   await expect(download).toHaveAttribute("href",releases.installer.url);
   await download.focus();await expect(download).toBeFocused();
  }
  const measured=page.getByText("Why does preparation take time?",{exact:true});
  await measured.focus();await page.keyboard.press("Enter");
  const cost=page.locator("details").filter({has:page.getByText("Why does preparation take time?",{exact:true})}).locator("p");
  await expect(cost).toBeVisible();
  await expect(cost).toContainText(/completed/);
  await page.keyboard.press("Enter");
  await expect(cost).not.toBeVisible();
  await expect(page.getByText(/Allow 16 GiB free for first preparation/)).toBeVisible();
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
test("every public page uses player-facing copy",async({page})=>{
 test.setTimeout(180000);
 const paths=["/","/install",...Object.keys(documentation).filter(path=>path!=="/docs/setup-studio")];
 const internal=/\b(?:fixture(?:s)?|renderer|baseline(?:s)?|provenance|workbench|magistr|ship_check|think_record_step|source audit(?:ing)?|public contract|contract version|schema inputs|provider semantics|source checkout|native acceptance|developer(?:s)?|development workflow|maintainer(?:s)?|pull request|source viewport|test harness|quality gate|roadmap|developer[- ]only|placeholder|TODO|agent[- ]observed|standing acceptance|view or improve this guide|code contributions|source & support|rendered by the actual addon|representative exploration state)\b|[A-Z]:[\\/](?:Code|RikUI-local|Users)\b/i;
 for(const path of paths){
  const response=await page.goto(path);expect(response.status(),path).toBe(200);
  const text=await page.locator("body").evaluate(body=>{
   const clone=body.cloneNode(true);
   for(const node of clone.querySelectorAll("script,style"))node.remove();
   return [clone.textContent,...Array.from(clone.querySelectorAll("[alt],[aria-label],[title]"),node=>[node.getAttribute("alt"),node.getAttribute("aria-label"),node.getAttribute("title")].filter(Boolean).join(" "))].join(" ").replace(/\s+/g," ");
  });
  expect(text,path).not.toMatch(internal);
  await expect(page.locator('a[href^="/studio"],a[href^="/setups"],a[href="/docs/setup-studio"]'),path).toHaveCount(0);
 }
});
test("old Studio URLs return users to regular settings",async({page})=>{
 for(const path of ["/studio?pack=healer","/setups","/setups/centered","/setups/submit","/docs/setup-studio"]){
  await page.goto(path);
  await expect(page).toHaveURL(/\/docs\/options$/);
  await expect(page.locator("#studio-app")).toHaveCount(0);
 }
});
