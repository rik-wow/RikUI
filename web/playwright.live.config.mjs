// Verify the public deployment without starting or reusing a local server.
process.env.SITE_URL = "https://rikwow.com";
delete process.env.STUDIO_PREVIEW;
const { default: config } = await import("./playwright.config.mjs");
export default config;
