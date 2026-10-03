// Actual browser screenshots complement the full-size native capture review.
import {chromium} from "@playwright/test";
import {mkdir} from "node:fs/promises";
const root=new URL("../dist/studio-browser-review/",import.meta.url);await mkdir(root,{recursive:true});
const browser=await chromium.launch(),page=await browser.newPage({viewport:{width:1440,height:1000},reducedMotion:"reduce"});
const site=process.env.SITE_URL||"http://127.0.0.1:8790";
const capture=async name=>{
 await page.waitForFunction(()=>document.querySelector("#game-preview").dataset.previewReady==="true");
 await page.screenshot({path:new URL(name+".png",root).pathname.replace(/^\/(\w:)/,"$1"),fullPage:true});
};
await page.goto(site+"/studio");await page.locator("#studio-app").waitFor();await capture("choose");
await page.getByRole("button",{name:"Make this setup mine"}).click();await capture("parts");
await page.locator("#module-search").fill("chat");await page.getByRole("button",{name:"Show Chat in preview",exact:true}).click();await capture("module-chat");
await page.locator("#module-chat").uncheck();await capture("module-chat-off");await page.locator("#module-chat").check();
await page.locator("#module-search").fill("");await page.locator("#module-area").selectOption("inventory");await capture("module-inventory");await page.locator("#module-area").selectOption("");
await page.locator("#tab-style").click();await page.locator("#theme").selectOption("ocean");await page.locator("#activity").selectOption("party");await capture("appearance");
await page.locator("#tab-layout").click();await page.locator("#frame-group").selectOption("casttarget");await capture("layout");
await page.locator("#device").selectOption("handheld");await capture("handheld");
await page.locator("#review-fit").click();await page.locator("#export").click();await capture("review-export");
await page.setViewportSize({width:390,height:1000});await page.locator('.studio-steps [data-step="choose"]').click();await capture("mobile-choose");
await page.getByRole("button",{name:"Make this setup mine"}).click();await page.locator("#tab-layout").click();await capture("mobile-layout");
await browser.close();console.log("Captured actual guided Studio choose, parts, appearance, layout, handheld, review/export and two mobile states.");
