// Retained Studio verification stays confined to an explicit loopback preview server.
process.env.STUDIO_PREVIEW = "true";
delete process.env.SITE_URL;
const { default: config } = await import("./playwright.config.mjs");
config.webServer.reuseExistingServer = false;
config.webServer.command += " --local-upstream 127.0.0.1";
export default config;
