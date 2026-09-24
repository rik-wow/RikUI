# Window interiors

The panels module now decorates the character window's equipment icons, stat
categories, reputation, skills and currency rows. Icons use the action bars'
crop and flat edge. The native quality border becomes a thin strip, retaining
Blizzard's colour and visibility updates. Rows have a dark backing and a gold
hover wash that fades in and out, cancelling when hidden.

The interior service keeps state in weak tables, never writes fields or secure
attributes on buttons, and preserves click, drag, tooltip, cooldown, disabled and
selection behavior. Only named window roots are walked, to a bounded depth.
OnShow and scroll-box acquisition/initialization cover late and recycled rows.
Forbidden frames and refused operations are reported once as an Interiors client
limit. Disabling panels and reloading leaves the interior stock.

Source: Forever [CharacterFrame](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/CharacterFrame.xml),
[PaperDollFrame](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/PaperDollFrame.xml)
and ReputationFrame at the same revision. Absent window names are optional:
source presence across game variants is not a promise of runtime availability.

Automated coverage: `tests/interiors.test.lua` checks cropped protected items,
quality-strip geometry, handler preservation, hover cancellation, idempotence,
late rows, forbidden reporting and disabled-panel behavior. Native/game-client
acceptance is supplied by the user; these are simulated checks, not client
observations. New TOC files require a full client restart.

