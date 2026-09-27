import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: ".",
  testMatch: "browser.test.mjs",
  fullyParallel: false,
  workers: 1,
  use: { baseURL: process.env.SITE_URL || "http://127.0.0.1:8787", browserName: "chromium" },
  webServer: process.env.SITE_URL ? undefined : {
    command: "node node_modules/wrangler/bin/wrangler.js dev --local --port 8787",
    url: "http://127.0.0.1:8787/healthz",
    reuseExistingServer: !process.env.CI,
    timeout: 60000
  }
});
