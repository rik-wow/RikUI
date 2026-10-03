import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: ".",
  testMatch: process.env.STUDIO_PREVIEW ? ["studio-browser-workspace.test.mjs","studio-browser.test.mjs","studio-browser-advanced.test.mjs","studio-browser-fidelity.test.mjs","studio-browser-live-import.test.mjs","studio-browser-workflow.test.mjs"] : ["public-browser.test.mjs","docs-browser.test.mjs"],
  fullyParallel: false,
  workers: 1,
  use: { baseURL: process.env.SITE_URL || "http://127.0.0.1:8787", browserName: "chromium" },
  webServer: process.env.SITE_URL ? undefined : {
    command: "node node_modules/wrangler/bin/wrangler.js dev --local --port 8787"+(process.env.STUDIO_PREVIEW ? " --var STUDIO_PREVIEW:true" : ""),
    url: "http://127.0.0.1:8787/healthz",
    reuseExistingServer: !process.env.CI,
    timeout: 60000
  }
});
