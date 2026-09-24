# Panel skin and motion

Blizzard windows, small dialogs and popups share flat dark chrome, thin edges,
gold headings and close glyphs. Panel titles have a muted gold accent rule.
Selected tabs fade their blue accent over 0.12 seconds; rapid selection changes
cancel the previous transition. Rows use the shared hover wash.

Entrances combine a 0.18-second fade with a six-pixel cosmetic rise. Translation
animations change the rendered image, never frame anchors, parenting or layout.
Hide stops the animation. The world map retains its native animation and its
canvas has no competing fill.

Native close handlers and hide timing remain immediate, including protected
popups. The addon-owned utility panel supports a 0.12-second close fade;
reopening cancels pending closure. Escape/external hides still work immediately.

Window discovery runs at login and ADDON_LOADED. Missing variant globals are
skipped; failed skin operations print once and leave the other windows usable.
Disabling panels and reloading restores native styling. Interior adapters cover
character, spellbook, talents, quest/map content, commerce, social and special
windows; see [interiors](interiors.md) for supported surfaces and limits.

Tab selection follows global PanelTemplates hooks or supported tab scripts.
No native frame method is replaced or post-hooked. Controls preserve native
click, drag, tooltip and secure action handlers.

Automated panel/dialog/popup/shell tests exercise discovery, styling, combat
anchor safety, native clicks, tab changes, close cancellation and repeated
open/hide. Native behavior is accepted by the user; no client run is claimed.
`/rik debug` reports hooked, skinned and failed panel counts.

Source: pinned Forever [CharacterFrame XML](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/CharacterFrame.xml)
and PlayerSpellsFrame/TabSystem templates, plus the existing shared cosmetic
animation implementation in `src/ui/motion.lua`.
