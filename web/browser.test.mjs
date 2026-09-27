import { test, expect } from "@playwright/test";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
const screenshotPath = name => fileURLToPath(new URL("../dist/" + name, import.meta.url));

for (const width of [1440, 1024, 768, 390, 320]) {
  test("aligned mock, images and keyboard at " + width + "px", async ({ page }) => {
    await page.setViewportSize({ width, height: 1000 });
    await page.emulateMedia({ reducedMotion: "reduce" });
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    page.on("console", message => { if (message.type() === "error") errors.push(message.text()); });
    await page.goto("/");
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("RikUI for WoW Forever");
    const loaded = await page.evaluate(async () => {
      const urls = [...new Set([...document.querySelectorAll(".game-scene image")]
        .map(image => image.getAttribute("href")))];
      return Promise.all(urls.map(url => new Promise(resolve => {
        const image = new Image();
        image.onload = () => resolve({ url, width: image.naturalWidth });
        image.onerror = () => resolve({ url, width: 0 });
        image.src = url;
      })));
    });
    expect(loaded.length).toBeGreaterThan(10);
    await expect(page.locator('[data-action="Holy Strike"] image').first()).toHaveAttribute("href", "/assets/forever-20260927/classicon_paladin.png");
    await expect(page.locator('[data-action="Holy Light"] image').first()).toHaveAttribute("href", "/assets/forever-20260927/spell_holy_holybolt.png");
    await expect(page.locator(".combat-capture")).toHaveCount(0);
    expect(loaded.every(image => image.url.startsWith("/assets/"))).toBe(true);
    expect(loaded.filter(image => !image.width)).toEqual([]);
    expect(loaded.find(image => image.url.startsWith("/assets/")).width).toBeGreaterThanOrEqual(2048);
    await page.keyboard.press("Tab");
    await expect(page.getByRole("link", { name: "Skip to content" })).toBeFocused();
    await page.keyboard.press("Enter");
    await expect(page.locator("#main")).toBeFocused();
    const layout = page.getByRole("button", { name: "Full interface", exact: true });
    await layout.focus();
    await page.keyboard.press("ArrowRight");
    await expect(page.getByRole("button", { name: "Combat", exact: true })).toBeFocused();
    await expect(page.locator(".game-scene")).toHaveAttribute("viewBox", "0 0 2048 1152");
    await expect(layout).toHaveAttribute("aria-pressed", "false");
    await page.keyboard.press("End");
    await expect(page.locator("#view-description")).toContainText("share one column");
    await page.keyboard.press("Home");
    await expect(layout).toBeFocused();
    await expect(page.locator(".game-scene")).toHaveAttribute("viewBox", "0 0 2048 1152");
    const overlay = page.getByRole("button", { name: "Show UI overlay" });
    await overlay.click();
    await expect(page.locator(".ui-overlay")).toBeHidden();
    await expect(page.locator(".world-backdrop")).toBeVisible();
    await overlay.click();
    await expect(page.locator(".ui-overlay")).toBeVisible();
    await expect(page.locator("#asset-notice")).toContainText("not affiliated with, endorsed by, or sponsored by Blizzard");
    const frame = await page.locator(".preview-stage").boundingBox();
    for (const view of ["layout", "combat", "quests"]) {
      await page.locator('button[data-view="' + view + '"]').click();
      if (view === "combat") {
        await expect(page.locator(".target-frame")).toBeVisible();
        const target = await page.locator(".target-frame > rect").first().evaluate(el => ({ x: el.x.baseVal.value, y: el.y.baseVal.value }));
        expect(target).toEqual({ x: 1048, y: 690 });
        await expect(page.locator(".world-backdrop")).toHaveAttribute("href", "/assets/combat-20260927-122246.jpg");
        await page.locator(".world-backdrop").evaluate(async element => {
          const image = new Image(); image.src = element.getAttribute("href"); await image.decode();
        });
      }

      const box = await page.locator(".preview-stage").boundingBox();
      expect(box.width / box.height, view + " uses 16:9").toBeCloseTo(16 / 9, 2);
      expect(box.height, view + " preserves frame height").toBeCloseTo(frame.height, 1);
      expect(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth),
        view + " must fit viewport").toBe(false);
      if (width === 1440 || width === 390)
        await page.locator(".showcase").screenshot({ path: screenshotPath("rikwow-aligned-" + width + "-" + view + ".png") });
    }
    await layout.click();
    await page.evaluate(() => window.scrollTo(0, 0));
    if (width === 1440 || width === 390)
      await page.screenshot({ path: screenshotPath("rikwow-aligned-" + width + "-full.png"), fullPage: true });
    expect(errors).toEqual([]);
  });
}
test("UI groups share centerlines, column edges and bottom baseline", async ({ page }) => {
  await page.goto("/");
  const boxes = await page.evaluate(() => Object.fromEntries(
    ["player-frame", "cooldowns", "action-bars", "minimap", "quest-tracker",
      "chat-panel", "utility-bars", "damage-meter"].map(name => {
      const { x,y,width,height } = document.querySelector("." + name).getBBox();
      return [name, {x,y,width,height}];
    })));
  const center = box => box.x + box.width/2;
  const bottom = box => box.y + box.height;
  expect(boxes["player-frame"].x).toBe(822);
  expect(boxes["player-frame"].y).toBe(690);
  expect(center(boxes["player-frame"])).toBeLessThan(1024);
  expect(center(boxes.cooldowns)).toBeCloseTo(1024, 0);
  expect(center(boxes["action-bars"])).toBeCloseTo(1024, 0);
  expect(boxes.minimap.x).toBe(boxes["quest-tracker"].x);
  expect(boxes.minimap.width).toBe(boxes["quest-tracker"].width);
  for (const group of ["action-bars", "chat-panel", "utility-bars", "damage-meter"])
    expect(bottom(boxes[group]), group + " bottom").toBeCloseTo(1120, 0);
});
test("world asset matches the selected original screenshot", async ({ request }) => {
  const response = await request.get("/assets/world-20260927-120706.jpg");
  expect(response.status()).toBe(200);
  expect(response.headers()["content-type"]).toContain("image/jpeg");
  expect(response.headers()["cache-control"]).toContain("immutable");
  expect(createHash("sha256").update(await response.body()).digest("hex"))
    .toBe("212b21a4c6745595bbb84f1bb2e84845c851bfcf4ff39221f71bd6ec687edd7d");
});
test("content remains useful without browser JavaScript", async ({ browser }) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto(process.env.SITE_URL || "http://127.0.0.1:8787");
  await expect(page.locator(".game-scene")).toBeVisible();
  await expect(page.locator(".preview-toolbar")).toBeHidden();
  await expect(page.getByRole("link", { name: "Read the installation guide", exact: true })).toBeVisible();
  await expect(page.locator("#asset-notice")).toBeVisible();
  await context.close();
});

test("client icons and both combat captures match their recorded bytes", async ({ request }) => {
  const { readFile } = await import("node:fs/promises");
  const manifest = JSON.parse(await readFile(new URL("./client-assets.json", import.meta.url), "utf8"));
  for (const item of [...manifest.icons, ...manifest.maps, ...manifest.screenshots]) {
    const response = await request.get(item.path);
    expect(response.status(), item.path).toBe(200);
    expect(response.headers()["content-type"]).toContain(item.path.endsWith(".png") ? "image/png" : "image/jpeg");
    expect(createHash("sha256").update(await response.body()).digest("hex"), item.path).toBe(item.sha256);
  }
});
