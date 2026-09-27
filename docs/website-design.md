# RikUI website design

Research and implementation: 2026-09-27.
User direction: addon first, large interface previews, crisp dark panels and
class-color accents. The previous general project landing page was rejected.

## Research and decisions

- [ToxiUI](https://toxiui.com/): reviewed the live page and a rendered desktop
  capture. Its UI imagery and feature-specific views make the product tangible;
  installation and documentation have direct navigation. RikUI uses its own
  compositions, copy, palette and code. No competitor screenshots or assets
  are embedded.
- [Dialogue UI](https://www.curseforge.com/wow/addons/dialogueui): the author's
  page presents theme and quest-window images beside specific functions.
  This supports separate combat, planner and setup views rather than one
  image expected to explain every feature.
- [NN/g: Photos as Web Content](https://www.nngroup.com/articles/photos-as-web-content/):
  the eyetracking research distinguishes useful product imagery from decoration.
  The interface explorer carries information about layout and feature behavior.
- [NN/g: Homepage Usability](https://www.nngroup.com/articles/113-design-guidelines-homepage-usability/):
  make product identity, purpose and important navigation evident.
  RikUI and WoW Forever appear in the first screen; installation has its own
  section and accurate release status.
- [W3C tabs pattern](https://www.w3.org/WAI/ARIA/apg/patterns/tabs/):
  implemented selection state, panel associations, roving tab focus, arrow keys,
  Home/End and keyboard activation. Content is already loaded, so switching is
  immediate.

These are design references and our interpretation, not evidence that the new
website has been usability tested with players.

## RikUI's own visual foundation

Reviewed `src/ui/skin.lua`, `src/ui/media.lua`, `src/ui/unit-colors.lua`,
`src/ui/shell.lua`, `data/layouts.lua`, and the combat/setup/planner guides.

- Dark backing around RGB (0.06, 0.07, 0.09); slate header bands.
- One-pixel edges, inset tracks and restrained gold labels.
- Class colors on unit displays, with independent power coloring.
- Existing spellbook, quest and settings glyph shapes from `media/icons/`.
- A centered cooldown/resource/cast stack, edge furniture and movable frames.
- Four documented layout presets and selective setup with undo.

The site adds an original R monogram, web typography and responsive composition.
The class swatches change the website illustration's accent; they do not change
an installed addon or claim to configure a game profile.

## Interface illustrations

No game screenshot was available in the repository. The previews are authored
HTML/CSS/SVG illustrations, explicitly labeled as such. They use sample content,
simplified glyphs and responsive arrangements; they are not captures of the
client or pixel-exact representations of every addon screen.

The combat view explains placement and offers a larger HUD view. The quest
view uses a schematic example route and keeps partial coverage visible. The
setup view explains selective changes and undo. None consumes or republishes
the quest corpus or Blizzard game imagery.

Replace or supplement these with current user-approved game captures when
available. Keep the illustrations useful for explaining layout rather than
presenting them as gameplay evidence.

## Implementation and verification

No frontend framework, analytics, remote font service or image dependency.
A small same-origin script handles tabs, class accents and combat enlargement.
The Worker permits only same-origin scripts; no inline-script exception.
Without JavaScript, the combat illustration, guides, FAQ and installation
content remain available, while inactive preview controls are hidden.
Reduced-motion preference disables smooth scrolling and transitions.

Node tests cover Worker responses and download boundaries. Playwright checks
1440, 1024, 768, 390 and 320 pixel widths, keyboard tabs, accent selection,
enlargement, FAQ operation, page overflow and browser/CSP errors. An additional
test disables JavaScript. Desktop and mobile renders of all three panels,
combat enlargement and the full page were visually reviewed. Fixed mobile
panel crowding and inconsistent quest-view height during that review.

Run from `web/`:
```
npm ci
npx playwright install chromium
npm test
npm run test:browser
npm run check
```

The Playwright configuration starts the local Worker when needed. Set
`SITE_URL=https://rikwow.com` to run the same browser checks against production.
Screenshot outputs go under ignored `dist/`; test reports stay ignored.
