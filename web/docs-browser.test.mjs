import { test, expect } from "@playwright/test";
import { documentation } from "./docs-generated.mjs";
import { catalogue } from "./docs-catalogue.mjs";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
const publicCatalogue=catalogue.filter(guide=>guide.slug!=="setup-studio");
const docPages=new Set(publicCatalogue.map(guide=>guide.slug));
const renders=JSON.parse(readFileSync(new URL("./ui-renders/manifest.json",import.meta.url),"utf8")).renders.filter(render=>docPages.has(render.page));
const sequences=renders.filter(render=>render.frames);
const WIZARD_WIDTH=860, WIZARD_HEIGHT=624;
// Each Lua render belongs beside the instruction it illustrates, identified by the nearest preceding heading.
const placements={
 wizard:{"wizard-1":"ref-1-welcome","wizard-2":"ref-2-your-role","wizard-3":"ref-3-keybinds","wizard-4":"ref-4-screen-layout","wizard-5":"ref-5-modules-and-settings","wizard-6":"ref-6-review-and-apply"},
 options:{"options-castbars":"ref-open-settings","options-search":"ref-open-settings","options-pending":"ref-open-settings","options-confirm":"ref-profiles","options-general":"ref-appearance","options-appearance":"ref-appearance","options-bar-configuration":"ref-appearance","options-class":"ref-your-class-area","options-modules":"ref-choose-your-modules","options-profiles":"ref-profiles","options-setup":"ref-help-and-recovery"},
 sharing:{"sharing-export":"ref-export-a-ui-profile","sharing-import":"ref-import-a-ui-profile","sharing-library":"ref-remove-an-imported-preset","sharing-remove":"ref-remove-an-imported-preset"},
 unitframes:{"units-player":"ref-player-and-target","units-target":"ref-player-and-target","units-tot":"ref-player-and-target","units-pet":"ref-player-and-target","units-focus":"ref-player-and-target","units-low-health":"ref-health-and-power-text","units-party":"ref-party-and-raid","units-raid":"ref-party-and-raid"},
 castbars:{"cast-interrupted":"ref-reading-a-cast-bar","cast-channel":"ref-reading-a-cast-bar","cast-target":"ref-player-target-focus-and-pet","cast-focus":"ref-player-target-focus-and-pet","cast-pet":"ref-player-target-focus-and-pet","cast-player":"ref-change-the-size"},
 bags:{"bags-inventory":"ref-open-your-inventory","bags-search":"ref-search-and-filters","bags-empty-search":"ref-search-and-filters","bags-filters":"ref-search-and-filters","bags-markers":"ref-favourites-and-item-markers","bags-merchant":"ref-vendors-and-repairs","bags-capacity":"ref-capacity-and-money"},
 chat:{"chat-history":"ref-read-and-send-messages","chat-input":"ref-read-and-send-messages","chat-scroll":"ref-read-and-send-messages","chat-copy":"ref-copy-chat-text","chat-search":"ref-search-the-history","chat-resize":"ref-font-timestamps-and-size"},
 loot:{"loot-list":"ref-loot-an-item","loot-coins":"ref-loot-an-item","loot-roll":"ref-group-rolls","loot-confirm":"ref-group-rolls"},
 shell:{"shell-menu":"ref-the-rikui-button","shell-launcher":"ref-the-rikui-button","shell-interface":"ref-the-rikui-button","shell-support":"ref-the-rikui-button","shell-tools":"ref-tracked-spells"},
 layout:{"layout-mover":"ref-move-a-frame","layout-tags":"ref-move-a-frame","layout-resize":"ref-resize-a-frame","layout-nudges":"ref-fine-positioning","layout-grid-settings":"ref-snapping-and-grid","layout-grid":"ref-snapping-and-grid","layout-presets":"ref-scale-and-presets","layout-short-presets":"ref-scale-and-presets","layout-healer-groups":"ref-scale-and-presets","layout-undo":"ref-reset-or-undo"},
 overview:{"overview-layouts":"ref-choose-a-layout","overview-small-screen":"ref-choose-a-layout"},
 "combat-hud":{"hud-arrangement":"ref-what-the-hud-shows","hud-column":"ref-the-column","hud-rogue":"ref-your-class-in-the-column","hud-shaman":"ref-your-class-in-the-column","hud-druid":"ref-your-class-in-the-column","hud-scale":"ref-scale-the-hud"},
 cooldowns:{"cooldowns-strip":"ref-your-cooldown-strip","cooldowns-viewer":"ref-your-cooldown-strip","cooldowns-class":"ref-your-cooldown-strip","cooldowns-rows":"ref-your-cooldown-strip","cooldowns-counter":"ref-your-cooldown-strip","cooldowns-tracked":"ref-choose-tracked-spells"},
 swingtimer:{"swing-main-hand":"ref-weapon-swings","swing-off-hand":"ref-weapon-swings","swing-ranged":"ref-weapon-swings","swing-move":"ref-ranged-movement-cues","swing-stop":"ref-ranged-movement-cues","swing-unknown":"ref-ranged-movement-cues"},
 bars:{"bars-independent-grids":"ref-change-each-bar-39-s-shape","bars-main":"ref-arrange-your-bars","bars-secondary":"ref-arrange-your-bars","bars-third":"ref-arrange-your-bars","bars-right":"ref-arrange-your-bars","bars-left":"ref-arrange-your-bars","bars-ghost":"ref-labels-and-empty-slots","bars-page":"ref-pages-stances-and-pets","bars-stance-page":"ref-pages-stances-and-pets","bars-stance":"ref-pages-stances-and-pets","bars-pet":"ref-pages-stances-and-pets"},
 auras:{"auras-buffs":"ref-player-buffs-and-debuffs","auras-debuffs":"ref-player-buffs-and-debuffs","auras-target":"ref-target-pet-and-focus","auras-pet":"ref-target-pet-and-focus","auras-focus":"ref-target-pet-and-focus"},
 "class-effects":{"effects-player":"ref-follow-your-class-effects","effects-target":"ref-follow-your-class-effects"},
 personalresource:{"prd-health":"ref-personal-resource-display","prd-power":"ref-personal-resource-display"},
 nameplates:{"plates-enemy":"ref-enemy-nameplates","plates-debuffs":"ref-enemy-nameplates","plates-cast":"ref-enemy-nameplates","plates-target-focus":"ref-enemy-nameplates","plates-markers":"ref-enemy-nameplates","plates-threat":"ref-threat","plates-friendly":"ref-size-and-visibility","plates-adaptive-names":"ref-readable-names","plates-name-width-limit":"ref-readable-names","plates-pooled-short-name":"ref-readable-names","plates-name-options":"ref-readable-names"},
 combopoints:{"combo-empty":"ref-combo-points","combo-three":"ref-combo-points","combo-full":"ref-combo-points"}, combattimer:{"timer-elapsed":"ref-combat-timer","timer-final":"ref-combat-timer","timer-stopwatch":"ref-stopwatch"},
 mirrortimers:{"mirror-breath":"ref-breath-fatigue-and-feign-death","mirror-fatigue":"ref-breath-fatigue-and-feign-death","mirror-feign":"ref-breath-fatigue-and-feign-death"},
 totems:{"totems-slots":"ref-active-totems","totems-duration":"ref-active-totems"},
 lossofcontrol:{"loc-effect":"ref-control-effects","loc-remaining":"ref-control-effects"},
 "proc-overlay":{"proc-sides":"ref-ability-cues","proc-vertical":"ref-ability-cues","proc-center":"ref-ability-cues"},
 damagemeter:{"meter-rows":"ref-read-the-meter"},
 extrabuttons:{"extra-zone":"ref-special-actions"},
 combattext:{"combattext-settings":"ref-damage-and-healing-numbers"},
 worldmap:{"worldmap-settings":"ref-map-tools"},
 minimap:{"minimap-square":"ref-the-minimap","minimap-indicators":"ref-the-minimap","minimap-performance":"ref-rikui-menu"},
 xpbar:{"xp-experience":"ref-experience","xp-rested":"ref-experience","xp-gain":"ref-experience","xp-reputation":"ref-reputation"},
 durability:{"dur-worn":"ref-worn-and-broken-gear","dur-broken":"ref-worn-and-broken-gear","dur-tooltip":"ref-worn-and-broken-gear","dur-lowest":"ref-keep-durability-visible"},
 tooltip:{"tip-item":"ref-unit-item-and-spell-information","tip-aura":"ref-unit-item-and-spell-information","tip-unit":"ref-size-and-position"},
 micromenu:{"micro-menu":"ref-game-menus","micro-bags":"ref-bag-strip"},
 chatbubbles:{"bubble-player":"ref-speech-bubbles","bubble-npc":"ref-speech-bubbles"},
 hudframes:{"hud-framerate":"ref-small-on-screen-labels","hud-navigation":"ref-small-on-screen-labels","hud-queue":"ref-small-on-screen-labels"},
 screentext:{"text-zone":"ref-zone-names-and-warnings","text-subzone":"ref-zone-names-and-warnings","text-error":"ref-zone-names-and-warnings","text-raid":"ref-zone-names-and-warnings"},
 alerts:{"alert-loot":"ref-loot-and-reward-alerts","alert-money":"ref-loot-and-reward-alerts","alert-achievement":"ref-loot-and-reward-alerts"},
 banners:{"banner-objective":"ref-level-ups-and-events","banner-objective-long":"ref-level-ups-and-events","banner-objective-reused":"ref-level-ups-and-events"},
 toasts:{"toast-friend":"ref-social-notices","toast-time":"ref-social-notices","toast-voice":"ref-social-notices"},
 questtracker:{"tracker-active":"ref-your-watched-quests","tracker-complete":"ref-your-watched-quests","tracker-failed":"ref-your-watched-quests","tracker-header":"ref-your-watched-quests","tracker-overflow":"ref-your-watched-quests"},
 questtimers:{"timers-timed":"ref-timed-quests","timers-warning":"ref-timed-quests","timers-final":"ref-timed-quests"},
 questplanner:{"planner-browser":"ref-start-quest-guidance","planner-pins":"ref-start-quest-guidance","planner-guidance":"ref-guide-controls","planner-objective":"ref-guide-controls","planner-details":"ref-guide-controls","planner-arrow":"ref-map-and-direction-arrow","planner-partial":"ref-missing-locations","planner-preferences":"ref-preferences"},
 panels:{"panels-window":"ref-game-windows","panels-close":"ref-game-windows","panels-tabs":"ref-game-windows","panels-inset":"ref-game-windows"},
 interiors:{"int-character":"ref-character-and-abilities","int-stats":"ref-character-and-abilities","int-reputation":"ref-character-and-abilities","int-spellbook":"ref-character-and-abilities","int-quest":"ref-quests-and-conversations","int-gossip":"ref-quests-and-conversations","int-merchant":"ref-buying-crafting-and-storage","int-trade":"ref-buying-crafting-and-storage","int-inbox":"ref-buying-crafting-and-storage","int-friends":"ref-social-and-group-panels","int-communities":"ref-social-and-group-panels","int-raidinfo":"ref-social-and-group-panels","int-inspect":"ref-social-and-group-panels","int-calendar":"ref-other-game-panels","int-achievements":"ref-other-game-panels","int-collections":"ref-other-game-panels"},
 "auction-house":{"ah-browse":"ref-find-an-item","ah-item":"ref-find-an-item","ah-sell":"ref-sell-an-item","ah-owned":"ref-sell-an-item"},
 dialogs:{"dlg-readycheck":"ref-small-windows","dlg-rolepoll":"ref-small-windows","dlg-stacksplit":"ref-small-windows","dlg-queueready":"ref-small-windows","dlg-colorpicker":"ref-small-windows","dlg-addfriend":"ref-small-windows","dlg-report":"ref-small-windows","dlg-autocomplete":"ref-small-windows"},
 popups:{"popup-confirm":"ref-confirmations","popup-invite":"ref-confirmations","popup-text":"ref-confirmations","popup-item":"ref-confirmations"},
 menus:{"menu-context":"ref-context-menus"},
 widgets:{"widget-status":"ref-objectives-and-activity-displays","widget-double":"ref-objectives-and-activity-displays","widget-icon":"ref-objectives-and-activity-displays"},
 controls:{"ctl-button":"ref-buttons-and-fields","ctl-checkbox":"ref-buttons-and-fields","ctl-dropdown":"ref-buttons-and-fields","ctl-disabled":"ref-buttons-and-fields","ctl-textfield":"ref-buttons-and-fields","ctl-slider":"ref-buttons-and-fields","ctl-scrollbar":"ref-buttons-and-fields","ctl-colour":"ref-buttons-and-fields"}
};const figureSections=()=>{
 const article=document.querySelector("article.doc-prose");
 let heading=null;const result=[];
 for(const node of article.querySelectorAll("h2,h3,figure")){
  if(node.tagName==="FIGURE")result.push({render:node.dataset.render||null,caption:node.querySelector("figcaption strong").textContent,heading,inParagraph:!!node.closest("p")});
  else heading=node.id;
 }
 return result;
};

test("every documentation route and internal guide link resolves",async({request,page})=>{
 test.setTimeout(120000);
 const pages={};
 for(const route of Object.keys(documentation).filter(route=>route!=="/docs/setup-studio")){
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
   if(doc.querySelector(".visual-guide,#visual-guide,.more-examples")||/Visual guide/.test(doc.body.textContent))result.push(route+" still has a detached gallery");
   const figures=doc.querySelectorAll("figure");
   if(doc.querySelectorAll("article.doc-prose figure").length!==figures.length)result.push(route+" has figures outside the article");   for(const figure of figures){
    if(figure.closest("p"))result.push(route+" places a figure inside a paragraph");
    if(!figure.closest(".example-grid"))result.push(route+" has an ungrouped figure");
   }
  }
  return [...new Set(result)];
 },pages);
 expect(failures).toEqual([]);
 expect((await request.get("/docs/not-a-guide")).status()).toBe(404);
 expect((await request.get("/docs/bags/",{maxRedirects:0})).status()).toBe(308);
 for(const guide of publicCatalogue){
  expect(pages["/docs/"+guide.slug]).toContain('class="ui-example"');
  expect(pages["/docs/"+guide.slug].match(/<figure /g)?.length,guide.slug).toBe(renders.filter(render=>render.page===guide.slug).length);
  expect(pages["/docs/"+guide.slug],guide.slug+" still places a drawing").not.toMatch(/<svg|data-mockup/);
  const images=[...pages["/docs/"+guide.slug].matchAll(/<figure [\s\S]*?<\/figure>/g)].map(([figure])=>figure.match(/<img [^>]*src="([^"]+)"/)[1]);
  expect(new Set(images).size,guide.slug+" repeats an image").toBe(images.length);
 }
});

test("examples sit beside the instructions they illustrate",async({page})=>{
 for(const [slug,expected] of Object.entries(placements)){
  await page.goto("/docs/"+slug);
  const figures=await page.evaluate(figureSections);
  const actual=Object.fromEntries(figures.map(figure=>[figure.render,figure.heading]));
  expect(actual,slug).toEqual(expected);
  const captions=figures.map(figure=>figure.caption);
  expect(new Set(captions).size,slug+" repeats an example").toBe(captions.length);
  for(const render of renders.filter(render=>render.page===slug))await expect(page.locator('figure[data-render="'+render.id+'"] img').first()).toHaveAttribute("src",/\/assets\/docs\//);
 }
});

for(const width of [1440,768,390,320]){ test("documentation navigation and layout at "+width+"px",async({page})=>{
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
  await page.locator("#ref-search-and-filters").scrollIntoViewIfNeeded();
  await expect(page.locator('figure[data-render="bags-search"] img')).toBeVisible();
  await expect(page.locator("figure").last()).toBeVisible();
  await page.keyboard.press("Tab");
  expect(await page.evaluate(()=>document.activeElement?.tagName)).toBeTruthy();
  expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  expect(errors).toEqual([]);
 });
}

test("spell and item examples load the correct named images",async({page})=>{
 await page.goto("/docs/micromenu");
 await expect(page.locator("figure").first().locator("image")).toHaveCount(0);
 for(const slug of ["worldmap","combattext"]){
  await page.goto("/docs/"+slug);
  const sources=await page.locator("figure img.ui-example").evaluateAll(images=>images.map(image=>image.getAttribute("src")));
  expect(sources.length,slug).toBeGreaterThan(0);  for(const source of sources)expect((await page.request.get(source)).status(),source).toBe(200);
 }
});

test("documentation works without JavaScript",async({browser})=>{
 const context=await browser.newContext({javaScriptEnabled:false});
 const page=await context.newPage();
 const site=process.env.SITE_URL||"http://127.0.0.1:8787";
 await page.goto(site+"/docs/castbars");
 await expect(page.getByRole("heading",{name:"Cast bars",exact:true})).toBeVisible();
 await expect(page.getByRole("navigation",{name:"Documentation",exact:true})).toBeVisible();
 await expect(page.locator('figure[data-render="cast-interrupted"] img')).toBeVisible();
 // A setting preview degrades to its default frame with the control hidden.
 await page.goto(site+"/docs/combat-hud");
 const preview=page.locator('figure[data-sequence="slider"]').first();
 await expect(preview.locator("[data-frame]:visible")).toHaveCount(1);
 await expect(preview.locator(".preview-control")).toBeHidden();
 await context.close();
});

test("setting previews swap frames in place",async({page})=>{
 await page.goto("/docs/combat-hud");
 const preview=page.locator('figure[data-render="hud-scale"]');
 await expect(preview).toHaveAttribute("data-sequence","slider");
 const frames=preview.locator("[data-frame]");
 expect(await frames.count()).toBe(sequences.find(render=>render.id==="hud-scale").frames.length);
 const control=preview.locator(".preview-control input[type=range]");
 await expect(control).toBeVisible();
 await expect(preview.locator("[data-frame]:visible")).toHaveCount(1);
 await expect(preview.locator(".preview-control output")).toHaveText("100%");
 const before=await preview.locator("[data-frame]:visible img").getAttribute("src");
 await control.fill("0"); await expect(preview.locator(".preview-control output")).toHaveText("85%");
 await expect(preview.locator('[data-frame="0"]')).toBeVisible();
 await expect(preview.locator('[data-frame="1"]')).toBeHidden();
 const after=await preview.locator("[data-frame]:visible img").getAttribute("src");
 expect(after).not.toBe(before);
 expect(await preview.locator("[data-frame] img").evaluateAll(images=>images.map(image=>image.complete&&image.naturalWidth>0))).not.toContain(false);
 await control.fill("2");
 await expect(preview.locator(".preview-control output")).toHaveText("115%");
 await expect(preview.locator('[data-frame="2"]')).toBeVisible();
});
test("nameplate previews respond to keyboard controls on a narrow screen",async({page})=>{
 await page.setViewportSize({width:390,height:1000});
 await page.goto("/docs/nameplates");
 const adaptive=page.locator('figure[data-render="plates-adaptive-names"]');
 const toggle=adaptive.getByRole("switch");
 await expect(toggle).toBeChecked();
 await toggle.focus();
 const before=await adaptive.locator("[data-frame]:visible img").getAttribute("src");
 await page.keyboard.press("Space");
 await expect(adaptive.locator("[data-frame]:visible")).toHaveCount(1);
 expect(await adaptive.locator("[data-frame]:visible img").getAttribute("src")).not.toBe(before);
 const width=page.locator('figure[data-render="plates-name-width-limit"]');
 const slider=width.getByRole("slider");
 await slider.focus();
 await page.keyboard.press("End");
 await expect(width.locator('[data-frame="2"]')).toBeVisible();
 await expect(width.locator(".preview-control output")).toHaveText("400");
 expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
});
test("layout previews select both presets and group types by keyboard",async({page})=>{
 await page.setViewportSize({width:390,height:1000});
 await page.goto("/docs/layout"); for(const id of ["layout-short-presets","layout-healer-groups"]){
  const preview=page.locator('figure[data-render="'+id+'"]');
  const control=preview.getByRole("combobox");
  await control.focus();
  await page.keyboard.press("Home");
  await expect(preview.locator('[data-frame="0"]')).toBeVisible();
  const first=await preview.locator("[data-frame]:visible img").getAttribute("src");
  await page.keyboard.press("End");
  await expect(preview.locator('[data-frame="1"]')).toBeVisible();
  await expect(preview.locator("[data-frame]:visible")).toHaveCount(1);
  expect(await preview.locator("[data-frame]:visible img").getAttribute("src")).not.toBe(first);
 }
 expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
});
test("Lua examples serve the reviewed images with their original proportions",async({request,page})=>{
 for(const render of renders)for(const frame of render.frames||[render]){
  const asset="/assets/docs/"+render.id+(render.frames?"-"+String(frame.value).replace(/[^a-z0-9]+/gi,"-"):"")+"-"+frame.sha256.slice(0,12)+".webp";
  const response=await request.get(asset);
  expect(response.status(),asset).toBe(200);
  expect(createHash("sha256").update(await response.body()).digest("hex"),asset).toBe(frame.reviewedSha256);
 }
 await page.goto("/docs/wizard");
 const images=page.locator("figure img.ui-example");
 await expect(images).toHaveCount(6);
 for(const img of await images.all()){
  await img.scrollIntoViewIfNeeded();
  await expect(img).toHaveJSProperty("naturalWidth",WIZARD_WIDTH);
  const geometry=await img.evaluate(node=>({w:node.getBoundingClientRect().width,h:node.getBoundingClientRect().height,filter:getComputedStyle(node).filter}));
  expect(geometry.w/geometry.h).toBeCloseTo(WIZARD_WIDTH/WIZARD_HEIGHT,2);
  expect(geometry.filter).toBe("none");
  expect(geometry.w).toBeLessThanOrEqual(WIZARD_WIDTH);
 } for(const slug of ["bags","unitframes"]){
  await page.goto("/docs/"+slug);
  for(const img of await page.locator("figure img.ui-example").all()){
   await img.scrollIntoViewIfNeeded();
   const size=await img.evaluate(node=>({display:node.getBoundingClientRect().width,natural:node.naturalWidth}));
   expect(size.display).toBeLessThanOrEqual(size.natural);
  }
 }
});

test("desktop guide groups and page contents are vertical and independently bounded",async({page})=>{
 await page.setViewportSize({width:1440,height:900});await page.goto("/docs/setup-studio");
 const nav=page.getByRole("navigation",{name:"Documentation",exact:true});
 const geometry=await nav.evaluate(node=>({w:node.clientWidth,sw:node.scrollWidth,h:node.clientHeight,sh:node.scrollHeight,
  groups:[...node.querySelectorAll(".nav-group")].map(g=>{const r=g.getBoundingClientRect();return {x:r.x,y:r.y};})}));
 expect(geometry.sw).toBeLessThanOrEqual(geometry.w);expect(geometry.sh).toBeGreaterThan(geometry.h);
 for(let i=1;i<geometry.groups.length;i++){expect(Math.abs(geometry.groups[i].x-geometry.groups[0].x)).toBeLessThan(1);expect(geometry.groups[i].y).toBeGreaterThan(geometry.groups[i-1].y);}
 const before=await page.evaluate(()=>scrollY);await nav.evaluate(node=>{node.scrollTop=node.scrollHeight;});
 expect(await page.evaluate(()=>scrollY)).toBe(before);await expect(page.getByLabel("Find a guide")).toBeInViewport();
 const toc=page.getByRole("navigation",{name:"On this page",exact:true});
 expect(await toc.evaluate(n=>n.scrollWidth<=n.clientWidth)).toBe(true);
 await page.goto("/docs/controls");await expect(nav.locator('[aria-current="page"]')).toBeInViewport();
 expect(await page.evaluate(()=>scrollY)).toBe(0);
});
for(const width of [320,390,768])test("mobile documentation keyboard disclosure at "+width,async({page})=>{
 await page.setViewportSize({width,height:900});await page.goto("/docs/setup-studio");
 const details=page.locator(".docs-nav-toggle"),summary=details.locator("summary");
 await expect(details).not.toHaveAttribute("open","");await summary.focus();await page.keyboard.press("Enter");
 await expect(details).toHaveAttribute("open","");await page.getByLabel("Find a guide").fill("inventory");
 await expect(page.locator("[data-doc-link]:visible")).toHaveCount(1);
 await page.keyboard.press("Escape");await expect(details).not.toHaveAttribute("open","");await expect(summary).toBeFocused();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
});
test("mobile documentation retains native navigation without JavaScript",async({browser})=>{
 const context=await browser.newContext({javaScriptEnabled:false,viewport:{width:390,height:900}});
 const page=await context.newPage();await page.goto((process.env.SITE_URL||"http://127.0.0.1:8787")+"/docs/setup-studio");
 await expect(page.getByRole("navigation",{name:"Documentation",exact:true})).toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);await context.close();
});
