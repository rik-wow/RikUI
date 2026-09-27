# RikUI website design

Updated 2026-09-27 after direct user review.

## Direction and reference

The user rejected the previous illustrations and supplied a current RikUI
screenshot as a visual reference. They explicitly requested a reconstructed
mock, not an embedded screenshot, and then requested real WoW assets.

The site now uses a single SVG scene with a 2048 × 1152 coordinate system.
Combat detail, full layout and quest detail select different views of that
same scene. The player frame, seven-icon resource strip, partly empty 12-column
action rows, right-side bars, quest cards, chat and damage meter follow the
reference's placement and proportions. The mock preserves paladin pink,
royal-blue mana, green turn-in status and yellow active objectives.

The screenshot is not copied, cropped or deployed. Chat contains sample addon
messages, not private conversations. The minimap's room shapes are an original
schematic rather than a reproduced game texture. Spell/item selections are
visual examples; this is a labeled mock, not a live game client or proof of
current spell behavior. No invented setup screen, target frame, reticle or
class-color switcher remains.

## Asset ownership and delivery

Real WoW spell and item icons load unchanged from Blizzard's official
`https://render.worldofwarcraft.com/icons/56/` CDN. The explicit mapping lives
in `web/previews.mjs`; artwork is not vendored into this public repository.
The CSP allows images from that exact host, keeping scripts same-origin.

A copyright notice is immediately below the mock. A fuller footer notice
identifies Blizzard's artwork and trademarks, states that RikUI is independent
and not endorsed, affiliated or sponsored, and excludes Blizzard artwork from
the project's code license.

Reviewed [Blizzard's Legal FAQ](https://www.blizzard.com/en-sg/legal/c1ae32ac-7ff9-4ac3-a03b-fc04b8697010/blizzard-legal-faq)
on 2026-09-27. It describes limited noncommercial fansite display, retained
ownership/notices, restrictions on modification and transfer, and revocation.
This is not a blanket permission or a determination that every use qualifies;
the project does not claim Blizzard approval. A notice alone does not grant
rights. This asset-display decision does not resolve quest-corpus licensing.

## Design research carried forward

- [ToxiUI](https://toxiui.com/): addon imagery and specific feature views.
- [Dialogue UI](https://www.curseforge.com/wow/addons/dialogueui): interface
  details beside descriptions of the actual features.
- [NN/g product imagery](https://www.nngroup.com/articles/photos-as-web-content/):
  use visuals that help visitors understand the product.
- [NN/g homepage guidance](https://www.nngroup.com/articles/113-design-guidelines-homepage-usability/):
  make identity, purpose and navigation evident.

The new website takes its geometry and color cues from the user's reference.
A compact wordmark, restrained typography and square edges leave the interface
as the main visual. At narrow sizes, explanations move below the mock.

## Architecture and verification

No frontend framework or remote font service. A same-origin script switches
views with click, arrow keys, Home and End. Without JavaScript, combat detail,
installation guidance, FAQ and attribution remain available. Reduced-motion
preferences disable smooth scrolling.

Cloudflare Worker routes, private source storage and approved-download
boundaries remain intact. HTML retains `Cache-Control: no-transform` to
prevent Cloudflare from injecting a beacon blocked by the existing CSP.

Node tests cover responses and download boundaries. Playwright checks real
icon loading, keyboard control, notices, FAQ, overflow and browser errors at
1440, 1024, 768, 390 and 320 pixels, plus a JavaScript-disabled session.
Full-page and all-view renders are saved only beneath the repository's
ignored `dist/`, resolved from the test module rather than shell cwd.

Run in `web/`: `npm test`, `npm run test:browser`, `npm run check`.
Set `SITE_URL=https://rikwow.com` to check production.
