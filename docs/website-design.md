# RikUI website design

Reviewed and updated 2026-09-27.

## Current page

The page opens with the addon name, supported client and actual modules, followed
by the full interface preview. Module documentation and installation instructions
follow directly. Public installer availability is stated plainly.

The preview combines a real game capture with an SVG mock. It remains labeled
as a mock and uses sample chat rather than private messages. Full interface,
combat and quest views use the same 16:9 frame. The UI-visible capture is a
reference for the reconstructed overlay. The overlay can be hidden to
inspect the game backdrop. Without JavaScript, the full preview remains visible.

## Research and complete page audit

The sources below are design commentary and usability guidance, not a reliable
test of whether a human or AI authored a site.

- [Designpixil: AI design patterns](https://designpixil.com/blog/ai-slop-design),
  updated September 2026: recurring decorative treatments, generic feature
  structures and interchangeable writing. Applied as a visual checklist.
- [InterfaceKit: what makes a website look AI-generated](https://blog.interfacekit.io/what-makes-a-website-look-ai-generated),
  updated September 7, 2026: judge product specificity, meaningful decoration,
  consistent rules and behavior beyond the happy path. A particular font or
  color alone does not establish authorship.
- [NN/g: concise, scannable, objective web writing](https://www.nngroup.com/articles/concise-scannable-and-objective-how-to-write-for-the-web/):
  use factual text that readers can scan.
- [ToxiUI](https://toxiui.com/): a real addon reference for showing the interface
  and linking directly to installation and feature documentation. Its branding
  and marketing language are not reused.

| Audited area | Decision |
| --- | --- |
| Oversized two-tone wordmark and decorative terminal dot | Replaced with a compact, single-color RikUI name. |
| Hero slogans and interchangeable promises | Removed; the opening names the client and modules. |
| Tiny tracked capitals, section eyebrows and decorative status dot | Removed. Development status is readable body text. |
| Numbered view controls and feature rows | Removed numbering; controls say Full interface, Combat and Quests. |
| Forced three-part feature composition | Replaced with a documentation list of actual modules, with descriptions of different lengths. |
| Framed marketing CTA panel and repeated arrows | Removed; installation links name their destination. |
| Slogan-like section titles and repeated short fragments | Replaced with What’s included, Installing RikUI and In game. |
| FAQ accordion used to extend the page | Removed; client, keybinding and coverage constraints appear with the relevant information. |
| Every item inside a card | No decorative cards; dividers group documentation where useful. |
| Excess blank space and disconnected UI islands | Compact opening; common centerline, edges and spacing in the mock. |
| Tiny, low-contrast website text | Body text is 14–16px, captions 11–12px; controls have visible focus states. Game text scales with the mock. |
| Artificial glows, gradient words, glass panels, stock line icons | Absent; game artwork supplies the visual identity. |
| Fabricated metrics, testimonials, partner marks and download counts | Absent. |
| Fake or unavailable actions | No download button until a release exists. Guide/source links are real; view and overlay controls work. |
| Mobile treated as a shrunken desktop page | Text reflows, documentation stacks, controls wrap, and detail views remain available. |
| Motion and accessibility | No decorative motion. Keyboard arrows/Home/End, skip link, no-JS fallback and reduced-motion support remain. |

This is a documented design review, not a claim that aesthetic judgment can be
exhaustively automated.

## Overlay alignment

All positions use a 2048 × 1152 scene.

- Player frame starts at x=822, target at x=1048; each is 178 units wide.
- Cooldowns and action rows are centered at x=1024. Seven 30-unit cooldown
  icons use 3-unit gaps. Twelve action slots span 404 units.
- Minimap and quest tracker share x=1788 and width=228.
- Chat, XP bar, utility bars and micromenu end at y=1120.
- Outer screen inset is 32 units. The bottom chat and meter begin at y=936.
- The minimap room diagram remains a schematic. Spell icons are visual examples,
  not evidence about current spell behavior.

Geometry assertions accompany visual review so these alignments cannot drift
silently.

## Game backdrop and ownership

The user explicitly requested the newest screenshot from the Classic Beta
Screenshots folder. At selection, this was
`WoWScrnShot_092726_120706.jpg`, modified 2026-09-27 19:07:06 UTC.
It shows the Cathedral of Light with the UI hidden.

The original JPEG is copied unchanged to
`web/public/assets/world-20260927-120706.jpg` (4,144,668 bytes).
SHA-256:
`212b21a4c6745595bbb84f1bb2e84845c851bfcf4ff39221f71bd6ec687edd7d`.
The browser applies a separate translucent shade beneath the SVG UI; no raster
editing, inpainting or generated scenery is used.

The latest two screenshots were then requested for combat:
`WoWScrnShot_092726_122246.jpg` (UI hidden, 19:22:46 UTC) provides the combat
mock's backdrop; `WoWScrnShot_092726_122242.jpg` (19:22:42 UTC) supplies the
layout reference. Its baked-in UI is not pasted into a preview. Both originals
are preserved byte for byte.
Every tab uses the same 16:9 preview frame, including Combat and Quests.
The combat view includes the whole scene, reconstructed player/target frames,
nameplate, weapon timer, cooldowns and action rows. Browser checks assert identical frame
height across tab changes at all five viewport widths.

Spell/item icons and Elwynn map tiles come from the installed Forever client.
[TACTTool](https://github.com/wowdev/TACTSharp) loaded the installation's local
CASC indices and selected `wow_classic_beta` from `.build.info`; it reported
`WOW-70009patch1.60.1_ForeverBeta`. `WowB.exe` independently reports
1.60.1.70009. BLP textures were decoded to 64 × 64 PNGs without resizing or
recoloring. [The asset receipt](../web/client-assets.json) records source IDs,
build configuration and both BLP and PNG hashes. These are dated evidence,
not a target build for future work. The website has no external icon requests. Notices below the preview,
in the footer and in [the asset notice](../web/ASSET-NOTICE.md) identify Blizzard
ownership and exclude artwork from the project's MIT code license.
The [Blizzard Legal FAQ](https://www.blizzard.com/en-sg/legal/c1ae32ac-7ff9-4ac3-a03b-fc04b8697010/blizzard-legal-faq)
describes limited fansite use and its conditions. Attribution is not a blanket
license, and this work does not resolve quest-corpus redistribution rights.

## Hosting and checks

Cloudflare Workers Static Assets hosts the captures and icons through an ASSETS binding.
Only their exact public paths are routed by the Worker. Existing private R2 and
release allowlists remain intact. The image receives immutable caching;
HTML retains no-transform and the same-origin script policy.

Playwright checks five widths (320–1440px), real image loading, keyboard controls,
overlay toggle, geometry, no-JS fallback and the captures' and icons' exact SHA-256 hashes.
Node tests cover asset security/conditional responses and download boundaries.
Screenshots are resolved relative to the test module into repository `dist/`.

Run in `web/`: `npm test`, `npm run test:browser`, `npm run check`.
Use `SITE_URL=https://rikwow.com` for production browser checks.

## Website documentation

The build renders Markdown from docs, installer, tools and the root project
guides into /docs pages. The navigation has keyword filtering, local guide
links, heading anchors and a small-screen disclosure. Technical source links
remain available. The draft licensing request is labeled as an unsent draft.

A source registration check maps every named module to a visual guide. The
catalogue currently includes 274 illustrative surface/state examples covering
46 registered modules. Examples can be opened as standalone SVGs; sample values
and conditional native surfaces are not evidence of a live client capture.
The page inventory and module mapping are generated in web/docs-inventory.json.

Named spell and item identities replace random icon selection. Spell identifiers
come from RikUI catalogues; action placement also uses the selected preset and
saved action snapshot. Glyphs come from media/icons. File IDs and texture hashes
are retained in web/client-assets.json. Documentation map illustrations use
Elwynn tiles extracted from the same installed client.

Run npm run build:docs before direct Wrangler commands. npm test, check, dev and
deploy build the documentation automatically. Generated HTML and SVG outputs
stay under web/public; browser verification images stay under repository dist.
