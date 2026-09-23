# UI oracle

Every GUI surface a Forever player can see, how RikUI handles it today, how far
it is from the target, what it depends on and which roadmap chunk moves it
forward. The rule this file serves: nothing stays stock, and every surface ends
at the nameplate standard. Update it in the same commit as any UI chunk.

The roadmap (`roadmap_*` tools) stays the source of truth for chunk status.
This file is the map from screen to chunk. Last audited 2026-09-20 against
Blizzard source 1.60.1.69913. None of the fourth-run work and little of the
second and third runs has been seen in the client; tiers describe the code,
not a verified look.

## Tiers

| Tier | Meaning |
| --- | --- |
| 3 | Nameplate standard: a designed RikUI layout (not only stripped art), eased values where there are values, a change flash or state pulse, fade-in, hover tweens |
| 2 | Flat RikUI look with some motion (a fade-in or a hover tween), layout still Blizzard's or motion incomplete |
| 1 | Flat RikUI look, no motion of its own |
| 0 | Stock Blizzard art on screen |

How: `own` = RikUI builds the frame and parks Blizzard's; `overlay` = RikUI
regions on Blizzard's living frame; `skin` = art faded or emptied, fonts set,
flat regions added; `font` = font objects only.

## Foundation (no surface of its own)

| Node | Files | Used by |
| --- | --- | --- |
| core | `src/core/core.lua`, `src/platform/hide.lua`, `src/ui/media.lua` | everything |
| layout | `src/layout/layout.lua`, `src/layout/layout-geometry.lua`, `src/layout/layout-rects.lua`, `src/layout/layout-unlock.lua`, `src/layout/layout-drag.lua`, `Bindings.xml` | every `own` frame; no two groups may overlap |
| motion | `src/ui/motion.lua` | every tier 2 and 3 surface |
| skin | `src/ui/skin.lua` | every `skin` surface |
| controls | `src/modules/controls/controls.lua` | panels, dialogs, toasts, damage meter, popups |
| setup | `setup*.lua`, `data/*`, `presets/*` | bars content, bindings, settings |

## Combat HUD

| Surface | Files | How | Tier | Depends on | Next chunk |
| --- | --- | --- | --- | --- | --- |
| Nameplates | `nameplates*.lua` | overlay | 3 | auras, motion | `nameplates-beta-acceptance` |
| Action bars 1-5 | `bars*.lua` | own | 2 | layout, setup | `bars-motion` (empty-slot preset previews implemented) |
| Stance and pet rows | `src/modules/bars/bars-controls.lua` | own | 1 | bars | `bars-motion` |
| Extra, zone, flyout, possess buttons | `src/modules/extrabuttons/extrabuttons.lua` | skin | 2 | skin, bars colour | `bars-motion` |
| Vehicle bar frame | `src/modules/extrabuttons/extrabuttons.lua` (buttons only) | skin | 0 | extrabuttons | `vehicle-bar` |
| Proc overlay around the character | none | none | 0 | bars | `spell-activation-overlay` |
| Cooldown viewer (4 viewers) | `src/modules/cooldownviewer/cooldownviewer*.lua` | skin with owned panels, mouse controls, saved group holders and fades | 2 | skin, motion, layout, editmode, bars colour | delivered (`cooldownviewer-controls`) |
| Player, target, ToT, pet, focus frames | `src/modules/unitframes/unitframes.lua`, `src/modules/unitframes/unitframes-status.lua` | own | 1 | layout | `unitframes-motion` |
| Party frames | `src/modules/unitframes/unitframes-party.lua` | own | 1 | unit frames | `party-raid-motion` |
| Raid grid | `src/modules/unitframes/unitframes-raid.lua` | own | 1 | unit frames | `party-raid-motion` |
| Personal resource display | none | none | 0 | nameplates | `personal-resource` |
| Cast bars (player, target, focus, pet) | `castbars*.lua` | own | 2 | unit frames | `castbars-motion` |
| Aura rows (player, target, pet, focus) | `auras*.lua` | Blizzard container, own buttons | 1 | unit frames | `auras-motion` |
| Combo points | `src/modules/combopoints/combopoints.lua` | own | 3 | unit frames | `hud-extras-beta-acceptance` |
| Swing timer | `src/modules/swingtimer/swingtimer.lua` | own | 3 | layout | `hud-extras-beta-acceptance` |
| Mirror timers (breath, fatigue) | `src/modules/mirrortimers/mirrortimers.lua` | own | 3 | layout | `hud-extras-beta-acceptance` |
| Totem row | `src/modules/totems/totems.lua` | own | 2 | unit frames | `interiors-misc` (dismissal) |
| Loss of control | `src/modules/lossofcontrol/lossofcontrol.lua` | skin with own animated regions | 3 | skin, motion | `ui-final-beta-acceptance` |
| Damage meter | `src/modules/damagemeter/damagemeter.lua` | skin with own track, glyph buttons, row fade and hover; hung on a RikUI holder for `/rik move` | 2 | skin, motion, layout, controls | `ui-last-beta-acceptance` (bar easing is a client limit) |
| Floating combat text | `src/modules/combattext/combattext.lua` | font | 1 | media | `screentext-own` (engine limit: font only) |

## Screen text and toasts

| Surface | Files | How | Tier | Depends on | Next chunk |
| --- | --- | --- | --- | --- | --- |
| Zone text, error line, raid warning | `src/modules/screentext/screentext.lua` | font | 1 | media | `screentext-own` |
| Level-up and event toasts, boss banner, tracker top banner | `src/modules/banners/banners.lua` | skin (Blizzard animates) | 1 | skin | `alerts-own` |
| Event toast side display | none | none | 0 | banners | `alerts-own` |
| Alert toasts (loot, money, recipes) | `src/modules/alerts/alerts.lua` | skin (Blizzard animates) | 1 | skin | `alerts-own` |
| Social toasts (Battle.net, play time, voice) | `src/modules/toasts/toasts.lua` | skin (Blizzard animates) | 1 | skin, controls | `alerts-own` |
| Chat bubbles | `src/modules/chatbubbles/chatbubbles.lua` | skin | 2 | skin, motion | `ui-sweep-beta-acceptance` |
| UI widgets: status, double status, capture bars | `src/modules/widgets/widgets.lua` | skin | 1 | skin | `widgets-rest` |
| UI widgets: every other type | none | none | 0 | widgets | `widgets-rest` |
| Quest navigation marker | `src/modules/hudframes/hudframes.lua` | font | 1 | skin | `screentext-own` |

## Furniture

| Surface | Files | How | Tier | Depends on | Next chunk |
| --- | --- | --- | --- | --- | --- |
| Minimap | `src/modules/minimap/minimap.lua` | own shape and buttons | 1 | layout | `hud-polish` |
| Micro menu and bag strip | `src/modules/micromenu/micromenu.lua` | own | 1 | layout | `hud-polish` |
| Bags (one-bag) | `bags*.lua` | own | 1 | layout | `hud-polish` |
| Loot list and roll frames | `src/modules/loot/loot.lua`, `src/modules/loot/loot-rolls.lua` | own, skin | 1 | layout | `hud-polish` |
| Tooltips (all 15 named) | `tooltip*.lua` | skin | 1 | unit frame colours | `hud-polish` |
| Chat frames, tabs, edit box, copy window | `chat*.lua` | skin and own parts | 2 | layout | `chat-polish` |
| XP and reputation bars | `src/modules/xpbar/xpbar.lua` | own | 3 | layout | `xpbar-beta-acceptance` |
| Quest tracker | `questtracker*.lua` | own | 3 | layout | `questtracker-beta-acceptance` |
| Quest timers | `src/modules/questtimers/questtimers.lua` | own | 3 | quest tracker | `ui-sweep-beta-acceptance` |
| Durability pill | `src/modules/durability/durability.lua` | own | 3 | layout | `hud-extras-beta-acceptance` |
| Queue status tooltip, framerate label | `src/modules/hudframes/hudframes.lua` | skin, font | 2 | skin | `ui-sweep-beta-acceptance` |

## Windows, dialogs and menus

| Surface | Files | How | Tier | Depends on | Next chunk |
| --- | --- | --- | --- | --- | --- |
| Window chrome, tabs, insets, close buttons (55 windows) | `panels*.lua` | skin | 2 | skin, motion, controls | `windows-motion` |
| Controls in windows (buttons, checks, edits, sliders, scrollbars, dropdowns, late rows) | `src/modules/controls/controls.lua` | skin | 2 | skin, motion | `windows-motion` |
| Small dialogs (42) | `src/modules/dialogs/dialogs.lua` | skin | 2 | panels, controls | `windows-motion` |
| Static popups | `popups*.lua` | skin | 2 | skin | `windows-motion` |
| Menu backing | `src/modules/menus/menus.lua` | own child frame | 2 | skin, motion | `menus-rows` |
| Menu rows, check marks, arrows | none (compositor forbids) | none | 0 | menus | `menus-rows` |
| Character window interior | none | none | 0 | panels, controls | `interiors-character` |
| Spellbook and talents interior | none | none | 0 | extrabuttons rules | `interiors-spells-talents` |
| Quest log, quest and gossip interiors | none | none | 0 | panels | `interiors-quests-map` |
| World map navigation bar and round buttons | `src/modules/worldmap/worldmap.lua` | skin | 1 | panels | `interiors-quests-map` |
| World map side toggle, coordinates, content overlays | none | none | 0 | worldmap | `interiors-quests-map` |
| Merchant, bank, mail, trade, auction, trainer, profession, guild bank, stable interiors | none | none | 0 | interiors-character | `interiors-commerce` |
| Friends, guild, communities, group finder, raid, PvP, inspect interiors | none | none | 0 | interiors-commerce | `interiors-social` |
| Calendar day buttons, achievement rows | none (chrome only) | none | 0 | panels-last | `interiors-social` |
| CommunitiesSecure dialogs, secure transfer dialog | none | none | 0 | dialogs | `interiors-social` (may be forbidden) |
| Player choice, splash, trait frame, collections and transmog interiors, stopwatch close button | none | none | 0 | panels | `interiors-misc` |
| `/rik config` panel | `options*.lua` | own | 1 | controls design | `options-polish` |
| First-login wizard | `wizard*.lua` | own | 2 | setup, layouts | `wizard-beta-acceptance` (pages fade, controls fade on hover; no eased values to show) |

## Counts

Tier 3: 9 surfaces. Tier 2: 14. Tier 1: 18. Tier 0: 16. The tier 0 rows are
the ones the user's rule forbids; the tier 1 rows are full replacements that
lack motion.

## Order of work

The dependency edges above give this order; each step is one roadmap chunk.

1. `cooldownviewer`, `personal-resource`: the last two whole systems still stock.
2. `unitframes-motion` then `party-raid-motion`, `castbars-motion`,
   `auras-motion`, `bars-motion`: the pieces on screen every second of play.
3. `spell-activation-overlay`, `vehicle-bar`: only if Forever shows them.
4. `alerts-own`, `screentext-own`, `widgets-rest`.
5. `hud-polish`, `chat-polish`. (`damagemeter-motion` is done.)
6. `interiors-character` first (it builds the shared item-button and row pass),
   then `interiors-spells-talents`, `interiors-quests-map`,
   `interiors-commerce`, `interiors-social`, `interiors-misc`.
7. `windows-motion`, `menus-rows`, `options-polish`.
8. The beta acceptance chunks, which need the client and the user.

## Limits that are the client's, not RikUI's

- Floating combat text is drawn by the engine; only its font can change.
- The Menu compositor forbids `SetFont` and new regions on menu frames
  (`menus-rows` tries three routes around it).
- Frames in secure add-ons may be forbidden to addon code.
- Where Blizzard animates a frame's alpha or drives it from a setting, RikUI
  animates only its own regions.
