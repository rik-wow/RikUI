import { test, expect } from "@playwright/test";
import { fileURLToPath } from "node:url";
const screenshotPath = name => fileURLToPath(new URL("../dist/" + name, import.meta.url));

for (const width of [1440, 1024, 768, 390, 320]) {
  test("interface previews, keyboard and layout at " + width + "px", async ({ page }) => {
    await page.setViewportSize({ width, height: 1000 });
    await page.emulateMedia({ reducedMotion: "reduce" });
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    page.on("console", message => { if (message.type() === "error") errors.push(message.text()); });
    await page.goto("/");
    await expect(page.getByRole("heading", { level: 1 })).toContainText("Rebuilt for Forever");
    await page.keyboard.press("Tab");
    await expect(page.getByRole("link", { name: "Skip to content" })).toBeFocused();
    await page.keyboard.press("Enter");
    await expect(page.locator("#main")).toBeFocused();
    const combat = page.getByRole("tab", { name: "Combat HUD" });
    await combat.focus();
    await page.keyboard.press("ArrowRight");
    await expect(page.getByRole("tab", { name: "Quest planner" })).toBeFocused();
    await expect(page.locator("#panel-quests")).toBeVisible();
    await expect(page.locator("#panel-combat")).toBeHidden();
    await page.getByRole("button", { name: "Warlock accent" }).click();
    await expect(page.locator(".preview-area")).toHaveAttribute("data-theme", "warlock");
    await expect(page.getByRole("button", { name: "Mage accent" })).toHaveAttribute("aria-pressed", "false");
    await page.getByRole("tab", { name: "Setup", exact: true }).click();
    await expect(page.locator("#panel-setup")).toBeVisible();
    await page.keyboard.press("Home");
    await expect(combat).toBeFocused();
    await expect(page.locator("#panel-combat")).toBeVisible();
    await page.getByRole("button", { name: "Mage accent" }).click();
    const fullSize = await page.locator(".cooldown").first().boundingBox();
    await page.getByRole("button", { name: "Enlarge combat HUD" }).click();
    await expect(page.locator(".combat-scene")).toHaveClass(/focused/);
    const enlarged = await page.locator(".cooldown").first().boundingBox();
    expect(enlarged.width).toBeGreaterThan(fullSize.width);
    if (width === 1440 || width === 390)
      await page.locator(".showcase").screenshot({ path: screenshotPath("rikwow-redesign-" + width + "-closeup.png") });
    await page.getByRole("button", { name: "Show full layout" }).click();
    await expect(page.locator(".combat-scene")).not.toHaveClass(/focused/);
    await page.getByText("Will it change my keybindings?", { exact: false }).click();
    await expect(page.getByText("Installing RikUI alone does not change", { exact: false })).toBeVisible();
    await page.getByText("Will it change my keybindings?", { exact: false }).click();
    for (const view of ["combat", "quests", "setup"]) {
      await page.locator("#tab-" + view).click();
      const horizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
      expect(horizontalOverflow, view + " must fit the viewport").toBe(false);
      if (width === 1440 || width === 390) {
        await page.locator(".showcase").screenshot({ path: screenshotPath("rikwow-redesign-" + width + "-" + view + ".png") });
      }
    }
    await combat.click();
    await page.evaluate(() => window.scrollTo(0, 0));
    if (width === 1440 || width === 390)
      await page.screenshot({ path: screenshotPath("rikwow-redesign-" + width + "-full.png"), fullPage: true });
    expect(errors).toEqual([]);
  });
}

test("content remains useful without browser JavaScript", async ({ browser }) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto(process.env.SITE_URL || "http://127.0.0.1:8787");
  await expect(page.locator("#panel-combat")).toBeVisible();
  await expect(page.getByRole("link", { name: "setup guide", exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: "Open the installation guide" })).toBeVisible();
  await context.close();
});
