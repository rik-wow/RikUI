import { test, expect } from "@playwright/test";
import { documentation } from "./docs-generated.mjs";
import { catalogue } from "./docs-catalogue.mjs";

test("every documentation route and internal guide link resolves",async({request,page})=>{
 test.setTimeout(120000);
 const pages={};
 for(const route of Object.keys(documentation)){
  const response=await request.get(route);
  expect(response.status(),route).toBe(200);
  expect(response.headers()["content-type"]).toContain("text/html");
  pages[route]=await response.text();
 }
 await page.goto("/docs");
 const failures=await page.evaluate(pages=>{
  const result=[];
  const parsed=Object.fromEntries(Object.entries(pages).map(([route,html])=>[route,new DOMParser().parseFromString(html,"text/html")]));
  for(const [route,doc] of Object.entries(parsed)){
   for(const link of doc.querySelectorAll('a[href^="/docs"],a[href^="#"]')){
    const url=new URL(link.getAttribute("href"),location.origin+route);
    if(!parsed[url.pathname]){result.push(route+" -> "+url.pathname);continue;}
    if(url.hash&&!parsed[url.pathname].getElementById(decodeURIComponent(url.hash.slice(1)))) result.push(route+" -> "+url.pathname+url.hash);
   }
  }
  return [...new Set(result)];
 },pages);
 expect(failures).toEqual([]);
 expect((await request.get("/docs/not-a-guide")).status()).toBe(404);
 expect((await request.get("/docs/bags/",{maxRedirects:0})).status()).toBe(308);
 for(const guide of catalogue){
  expect(pages["/docs/"+guide.slug]).toContain('class="ui-example"');
  expect(pages["/docs/"+guide.slug].match(/<figure /g)?.length).toBe(guide.surfaces.length);
 }
});

for(const width of [1440,768,390,320]){
 test("documentation navigation and layout at "+width+"px",async({page})=>{
  await page.setViewportSize({width,height:1000});
  const errors=[];page.on("pageerror",error=>errors.push(error.message));
  await page.goto("/docs/unitframes");
  await expect(page.locator("h1")).toHaveText("Unit frames");
  expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  await page.screenshot({path:"../dist/rikwow-docs-units-"+width+".png",fullPage:false});
  if(width<=780)await page.getByText("Browse documentation",{exact:true}).click();
  await page.getByLabel("Find a guide").fill("bags");
  await expect(page.locator('[data-doc-link]:visible').filter({hasText:"Inventory"})).toBeVisible();
  await page.getByLabel("Find a guide").fill("zzzzzzzzz");
  await expect(page.locator("#search-empty")).toBeVisible();
  await page.getByLabel("Find a guide").fill("inventory");
  await page.locator('[data-doc-link]:visible').click();
  await expect(page.locator("h1")).toHaveText("Inventory");
  await page.getByText("Show all 9 examples",{exact:true}).click();
  await expect(page.locator("figure").last()).toBeVisible();
  expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  expect(errors).toEqual([]);
 });
}

test("spell and item examples load the correct named images",async({page})=>{
 await page.goto("/docs/castbars");
 await expect(page.locator('[data-action="Holy Light"] image').first()).toHaveAttribute("href",/spell_holy_holybolt.png$/);
 await page.goto("/docs/loot");
 await expect(page.locator('[data-action="Minor Healing Potion"] image').first()).toHaveAttribute("href",/inv_potion_49.png$/);
 await page.goto("/docs/micromenu");
 await expect(page.locator("figure").first().locator("image")).toHaveCount(0);
 await page.goto("/docs/totems");
 const paths=await page.locator("image").evaluateAll(images=>[...new Set(images.map(image=>image.getAttribute("href")))]);
 expect(paths).toHaveLength(4);
 for(const path of paths){expect((await page.request.get(path)).status()).toBe(200);}
});

test("documentation works without JavaScript",async({browser})=>{
 const context=await browser.newContext({javaScriptEnabled:false});
 const page=await context.newPage();
 await page.goto((process.env.SITE_URL||"http://127.0.0.1:8787")+"/docs/castbars");
 await expect(page.getByRole("heading",{name:"Cast bars",exact:true})).toBeVisible();
 await expect(page.getByRole("navigation",{name:"Documentation",exact:true})).toBeVisible();
 await context.close();
});
