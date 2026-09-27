import { scene } from "./previews.mjs";
export const page = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>RikUI for WoW Forever</title>
<meta name="description" content="RikUI is a modular interface addon for WoW Forever: unit frames, action bars, quest guidance, bags and chat.">
<meta name="theme-color" content="#171918"><link rel="canonical" href="https://rikwow.com/">
<link rel="preload" as="image" href="/assets/world-20260927-120706.jpg">
<link rel="stylesheet" href="/site.css"><script src="/site.js" defer></script></head>
<body><a class="skip" href="#main">Skip to content</a>
<header class="site-header wrap"><a class="brand" href="/" aria-label="RikUI home">RikUI</a>
<nav aria-label="Main navigation"><a href="#install">Installation</a><a href="#modules">Documentation</a><a href="https://github.com/rik-wow/RikUI">GitHub</a></nav></header>
<main id="main" tabindex="-1">
<section class="intro wrap" aria-labelledby="headline"><div><h1 id="headline">RikUI for WoW Forever</h1>
<p>Unit frames, action bars, quest guidance, bags and chat in one addon.<br class="desktop-break"> Choose the modules you need and arrange them with <code>/rik move</code>.</p></div>
<a class="install-link" href="https://github.com/rik-wow/RikUI/blob/main/installer/README.md">Installation guide</a></section>
<section id="interface" class="showcase wrap" aria-label="RikUI interface preview">
<div class="preview-stage" data-view="layout">${scene}<img class="combat-capture" src="/assets/combat-20260927-122242.jpg" width="3840" height="2160" loading="lazy" alt="RikUI in game during a fight with a Mangy Wolf in Elwynn Forest, captured September 27 at 12:22:42."></div>
<div class="preview-toolbar"><div class="preview-controls" role="group" aria-label="Preview view">
<button type="button" data-view="layout" aria-pressed="true">Full interface</button>
<button type="button" data-view="combat" aria-pressed="false">Combat</button>
<button type="button" data-view="capture" aria-pressed="false">In game</button>
<button type="button" data-view="quests" aria-pressed="false">Quests</button></div>
<button class="overlay-control" type="button" aria-pressed="true">Show UI overlay</button></div>
<p class="view-description" id="view-description" aria-live="polite">Player frames and spells in the center; chat and quest tracking at the edges.</p>
<p class="preview-caption"><span id="capture-caption">UI mockup over a capture from the Cathedral of Light.</span> Game artwork © Blizzard Entertainment. <a href="#asset-notice">Asset notice</a></p>
<noscript><p class="no-script">The full interface preview is shown above.</p></noscript></section>
<div class="project-info wrap">
<section id="modules" aria-labelledby="modules-heading"><h2 id="modules-heading">What’s included</h2>
<p>Modules can be enabled individually in <code>/rik config</code>.</p>
<dl class="module-list">
<div><dt><a href="https://github.com/rik-wow/RikUI/blob/main/docs/unitframes.md">Unit frames</a></dt><dd>Player, target, party and raid frames with health, power and aura displays.</dd></div>
<div><dt><a href="https://github.com/rik-wow/RikUI/blob/main/docs/questplanner.md">Quest planner</a></dt><dd>Objectives, turn-in status and route guidance. Coverage depends on the installed quest and road data.</dd></div>
<div><dt><a href="https://github.com/rik-wow/RikUI/blob/main/docs/bags.md">Bags</a></dt><dd>Combined inventory with search.</dd></div>
<div><dt><a href="https://github.com/rik-wow/RikUI/blob/main/docs/chat.md">Chat</a></dt><dd>History, timestamps and channel controls.</dd></div>
</dl><a class="all-docs" href="https://github.com/rik-wow/RikUI/tree/main/docs">Browse all documentation</a></section>
<section id="install" aria-labelledby="install-heading"><h2 id="install-heading">Installing RikUI</h2>
<p>RikUI is in development for the WoW Forever beta. The source and local build instructions are available now; a public Windows installer is still being prepared.</p>
<p><a href="https://github.com/rik-wow/RikUI/blob/main/installer/README.md">Read the installation guide</a></p>
<h3>In game</h3><dl class="commands">
<div><dt><code>/rik setup</code></dt><dd>Review and apply a preset.</dd></div>
<div><dt><code>/rik move</code></dt><dd>Unlock and position frames.</dd></div>
<div><dt><code>/rik config</code></dt><dd>Choose modules and settings.</dd></div>
<div><dt><code>/rik undo</code></dt><dd>Undo the last setup.</dd></div></dl>
<p class="binding-note">Installing the addon alone does not change your keybindings. Setup lets you choose which changes to apply.</p>
<p>Found a problem? <a href="https://github.com/rik-wow/RikUI/issues">Report it on GitHub.</a></p></section></div>
</main><footer class="wrap"><div class="footer-links"><span>RikUI</span><a href="https://github.com/rik-wow/RikUI">Source code</a><a href="https://github.com/rik-wow/RikUI/blob/main/LICENSE">Code license</a></div>
<p id="asset-notice">World of Warcraft game imagery, spell icons and item icons are © Blizzard Entertainment, Inc. All rights reserved. World of Warcraft and Blizzard Entertainment are trademarks or registered trademarks of Blizzard Entertainment, Inc. in the U.S. and/or other countries. RikUI is an independent fan project and is not affiliated with, endorsed by, or sponsored by Blizzard Entertainment. Blizzard artwork is not covered by RikUI’s code license. <a href="https://www.blizzard.com/en-us/legal/c1ae32ac-7ff9-4ac3-a03b-fc04b8697010/blizzard-legal-faq">Blizzard’s usage guidelines</a>.</p></footer>
</body></html>`;
