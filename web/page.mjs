import { scene } from "./previews.mjs";
export const page = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>RikUI — A complete interface for WoW Forever</title>
<meta name="description" content="RikUI brings compact combat frames, action bars and quest guidance into one modular interface for WoW Forever.">
<meta name="theme-color" content="#111415"><link rel="canonical" href="https://rikwow.com/">
<link rel="stylesheet" href="/site.css"><script src="/site.js" defer></script></head>
<body><a class="skip" href="#main">Skip to content</a>
<header class="site-header wrap"><a class="brand" href="/" aria-label="RikUI home">Rik<span>UI</span><i></i></a>
<nav aria-label="Main navigation"><a href="#interface">Interface</a><a href="#details">Details</a><a href="#install">Get started <span>↗</span></a></nav>
<a class="github" href="https://github.com/rik-wow/RikUI">GitHub ↗</a></header>
<main id="main" tabindex="-1">
<section class="hero wrap" aria-labelledby="headline">
<div><p class="eyebrow"><span class="status-dot"></span> FOR WOW FOREVER <span class="muted">/</span> IN DEVELOPMENT</p>
<h1 id="headline">Rik<span>UI</span><b>.</b></h1></div>
<div class="hero-intro"><h2>Your interface.<br>Everything in its place.</h2><p>Compact combat frames. A clearer quest log.<br>An interface you can make your own.</p><a class="text-link" href="#interface">Take a closer look <span>↓</span></a></div>
</section>
<section id="interface" class="showcase wrap" aria-labelledby="preview-heading">
<div class="preview-header"><h2 id="preview-heading">THE INTERFACE</h2><span>PALADIN <i></i> LEVEL 10</span></div>
<div class="preview-controls" role="group" aria-label="Preview view">
<button type="button" data-view="combat" aria-pressed="true">01 <span>Combat detail</span></button>
<button type="button" data-view="layout" aria-pressed="false">02 <span>Full layout</span></button>
<button type="button" data-view="quests" aria-pressed="false">03 <span>Quest detail</span></button>
<span class="preview-hint">A closer look at RikUI</span></div>
<div class="preview-stage" data-view="combat">
<div class="scene-copy" id="copy-combat"><p class="eyebrow">01 / COMBAT</p><h3>Close to the action.<br>Clear of the world.</h3><p>Health and mana at a glance.<br>Your spells in reach. Room to see<br>what’s happening around you.</p><div class="color-key"><span><i class="health"></i> Paladin health</span><span><i class="mana"></i> Mana</span></div></div>
<div class="scene-copy" id="copy-layout" hidden><p class="eyebrow">02 / THE WHOLE PICTURE</p><h3>A little more<br>breathing room.</h3><p>Combat in the center.<br>Quests, chat and bags at the edges.</p></div>
<div class="scene-copy" id="copy-quests" hidden><p class="eyebrow">03 / QUESTING</p><h3>Your next stop.<br>Kept in view.</h3><p>A compact planner, clear objectives<br>and turn-in status, tucked beneath<br>the square minimap.</p><div class="color-key"><span><i class="quest-ready"></i> Ready for turn-in</span><span><i class="quest-active"></i> In progress</span></div></div>
${scene}</div>
<div class="preview-caption"><p>Reconstructed UI mockup · sample content</p><p>WoW icons © Blizzard Entertainment. <a href="#asset-notice">Asset notice ↗</a></p></div>
<noscript><p class="no-script">Combat detail is shown above. Explore the <a href="https://github.com/rik-wow/RikUI/blob/main/docs/questplanner.md">quest planner guide</a> for more.</p></noscript>
</section>
<section id="details" class="details wrap" aria-labelledby="details-heading"><div class="section-intro"><p class="eyebrow">SMALL DETAILS. EVERY SESSION.</p><h2 id="details-heading">One interface.<br>Your way through it.</h2><p>Pick your modules. Move your frames.<br>Keep the things that work for you.</p></div>
<div class="detail-list"><a href="https://github.com/rik-wow/RikUI/blob/main/docs/unitframes.md"><span class="detail-index">01</span><div><h3>Readable at a glance</h3><p>Class-colored health, distinct power bars and compact unit frames.</p></div><span>↗</span></a>
<a href="https://github.com/rik-wow/RikUI/blob/main/docs/questplanner.md"><span class="detail-index">02</span><div><h3>A little direction</h3><p>Quest objectives and guidance in one place, with missing data made explicit.</p></div><span>↗</span></a>
<a href="https://github.com/rik-wow/RikUI/blob/main/docs/bags.md"><span class="detail-index">03</span><div><h3>The everyday essentials</h3><p>Combined bags, searchable inventory and the details between pulls.</p></div><span>↗</span></a></div></section>
<section id="install" class="install wrap" aria-labelledby="install-heading"><div><p class="eyebrow">MAKE YOURSELF AT HOME</p><h2 id="install-heading">Settle into RikUI.</h2><p>Open source. Built for the WoW Forever beta.<br>Start with the source and local installation guide.</p><a class="button" href="https://github.com/rik-wow/RikUI/blob/main/installer/README.md">Open the installation guide <span>↗</span></a><p class="release-note">Public Windows installer in preparation.</p></div>
<ol class="setup-steps"><li><code>/rik setup</code><div><h3>Choose a starting point</h3><p>Review a preset and choose what to apply.</p></div></li><li><code>/rik move</code><div><h3>Find your arrangement</h3><p>Place your frames where they feel right.</p></div></li><li><code>/rik config</code><div><h3>Make it yours</h3><p>Choose modules and adjust the details.</p></div></li></ol></section>
<section class="faq wrap" aria-label="Common questions"><details><summary>Will it change my keybindings?<span>+</span></summary><p>Installing RikUI alone does not change your bindings. Setup lets you review and choose changes. Use <code>/rik undo</code> to undo the last setup.</p></details>
<details><summary>Which WoW client is supported?<span>+</span></summary><p>RikUI targets the WoW Forever beta. Compatibility with Retail, Classic Era and other clients is not advertised.</p></details>
<details><summary>Does quest guidance cover everything?<span>+</span></summary><p>Coverage depends on the installed quest and road data. Missing or unverified objectives and paths remain explicit. Read the <a href="https://github.com/rik-wow/RikUI/blob/main/docs/questplanner.md">quest planner guide</a>.</p></details></section>
</main><footer class="wrap"><div class="footer-top"><a class="brand" href="/" aria-label="RikUI home">Rik<span>UI</span><i></i></a><p>An interface for your next adventure.</p><nav aria-label="Project links"><a href="https://github.com/rik-wow/RikUI">Source ↗</a><a href="https://github.com/rik-wow/RikUI/issues">Feedback ↗</a><a href="https://github.com/rik-wow/RikUI/blob/main/LICENSE">Code license ↗</a></nav></div>
<p id="asset-notice" class="asset-notice"><strong>Blizzard asset notice.</strong> World of Warcraft spell and item icons shown in the interface mockup are © Blizzard Entertainment, Inc. All rights reserved. World of Warcraft and Blizzard Entertainment are trademarks or registered trademarks of Blizzard Entertainment, Inc. in the U.S. and/or other countries. RikUI is an independent fan project and is not affiliated with, endorsed by, or sponsored by Blizzard Entertainment. Blizzard artwork is not covered by RikUI’s code license. <a href="https://www.blizzard.com/en-us/legal/c1ae32ac-7ff9-4ac3-a03b-fc04b8697010/blizzard-legal-faq">Blizzard’s usage guidelines ↗</a></p></footer>
</body></html>`;
