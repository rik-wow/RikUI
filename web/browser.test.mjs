import { test, expect } from "@playwright/test";
import { fileURLToPath } from "node:url";
const screenshotPath = name => fileURLToPath(new URL("../dist/" + name, import.meta.url));

for (const width of [1440, 1024, 768, 390, 320]) {
  test("reference mock, artwork, keyboard and layout at " + width + "px", async ({ page }) => {
    await page.setViewportSize({ width, height: 1000 });
    await page.emulateMedia({ reducedMotion: "reduce" });
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    page.on("console", message => { if (message.type() === "error") errors.push(message.text()); });
    await page.goto("/");
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("RikUI.");
    const loaded = await page.evaluate(async () => {
      const urls = [...new Set([...document.querySelectorAll(".game-scene image")]
        .map(image => image.getAttribute("href")))];
      return Promise.all(urls.map(url => new Promise(resolve => {
        const image = new Image();
        image.onload = () => resolve({ url, loaded: image.naturalWidth > 0 });
        image.onerror = () => resolve({ url, loaded: false });
        image.src = url;
      })));
    });
    expect(loaded.length).toBeGreaterThan(20);
    expect(loaded.filter(image => !image.loaded)).toEqual([]);
    expect(loaded.every(image => image.url.startsWith("https://render.worldofwarcraft.com/icons/56/"))).toBe(true);
    await page.keyboard.press("Tab");
    await expect(page.getByRole("link", { name: "Skip to content" })).toBeFocused();
    await page.keyboard.press("Enter");
    await expect(page.locator("#main")).toBeFocused();
    const combat = page.getByRole("button", { name: "01 Combat detail" });
    await combat.focus();
    await page.keyboard.press("ArrowRight");
    await expect(page.getByRole("button", { name: "02 Full layout" })).toBeFocused();
    await expect(page.locator(".game-scene")).toHaveAttribute("viewBox", "0 0 2048 1152");
    await expect(combat).toHaveAttribute("aria-pressed", "false");
    await page.keyboard.press("End");
    await expect(page.locator("#copy-quests")).toBeVisible();
    await expect(page.locator("#copy-combat")).toBeHidden();
    await page.keyboard.press("Home");
    await expect(combat).toBeFocused();
    await expect(page.locator(".game-scene")).toHaveAttribute("viewBox", "700 650 590 500");
    await page.getByText("Will it change my keybindings?", { exact: false }).click();
    await expect(page.getByText("Installing RikUI alone does not change", { exact: false })).toBeVisible();
    await page.getByText("Will it change my keybindings?", { exact: false }).click();
    await expect(page.locator("#asset-notice")).toContainText("not affiliated with, endorsed by, or sponsored by Blizzard");
    for (const view of ["combat", "layout", "quests"]) {
      await page.locator('button[data-view="' + view + '"]').click();
      expect(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth),
        view + " must fit viewport").toBe(false);
      if (width === 1440 || width === 390)
        await page.locator(".showcase").screenshot({ path: screenshotPath("rikwow-reference-" + width + "-" + view + ".png") });
    }
    await combat.click();
    await page.evaluate(() => window.scrollTo(0, 0));
    if (width === 1440 || width === 390)
      await page.screenshot({ path: screenshotPath("rikwow-reference-" + width + "-full.png"), fullPage: true });
    expect(errors).toEqual([]);
  });
}
test("content remains useful without browser JavaScript", async ({ browser }) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto(process.env.SITE_URL || "http://127.0.0.1:8787");
  await expect(page.locator(".game-scene")).toBeVisible();
  await expect(page.locator(".preview-controls")).toBeHidden();
  await expect(page.getByRole("link", { name: "Open the installation guide", exact: false })).toBeVisible();
  await expect(page.locator("#asset-notice")).toBeVisible();
  await context.close();
});
