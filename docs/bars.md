# Overlay action bars

`RikUI.Bars` owns five 12-button bars and hides the corresponding stock action
bars, bag/menu buttons and XP/reputation bars once their overlays are ready.
The next chunk supplies stance overlays; the main row currently
mirrors slots 1–12 even while the native Warrior ACTIONBUTTON bindings resolve
to a stance page.

| Bar | Fixed slots | Native binding prefix | Default anchor (x, y) |
|---|---|---|---|
| main | 1–12 | ACTIONBUTTON (base page only) | BOTTOM (0, 40) |
| bar2 | 61–72 | MULTIACTIONBAR1BUTTON | BOTTOM (0, 82) |
| bar3 | 49–60 | MULTIACTIONBAR2BUTTON | BOTTOM (0, 124) |
| bar4 | 25–36 | MULTIACTIONBAR3BUTTON | RIGHT (-40, 0) |
| bar5 | 37–48 | MULTIACTIONBAR4BUTTON | RIGHT (-82, 0) |

The mapping comes from `Setup.SlotToAction`, the same source used by Apply.
Defaults come from `Setup.DefaultPositions`. Three horizontal rows use
36-pixel buttons with 6-pixel gaps; the two side columns run top to bottom.
Each bar reads `Profile.positions[name]` and `Profile.scale`. Apply and Undo
refresh existing bars after changing saved positions. All creation, attributes,
position and scale writes run through the core combat queue. Invalid saved
position fields or scale fall back to defaults without rewriting saved data.

## Module API

- `Bars.Create(name, firstAction, layoutOpts)` creates or returns a bar.
  Options: `size` (positive number, default 36), `spacing` (nonnegative,
  default 6), `vertical` and `fade` (booleans, default false).
  The same name/range is idempotent; a conflicting range is rejected.
  Returns the frame on immediate success, `nil, "queued"` when deferred,
  or `nil, reason` for invalid input or immediate creation failure.
- `Bars.Frames[name].buttons[i]` exposes the corresponding button. Its
  `action` field and secure `action` attribute are fixed to
  `firstAction + i - 1`. Frame names are `RikUIBar_<name>` and
  `RikUIBar_<name>Button<i>`.
- `Bars.ApplyLayout()` refreshes all existing frames from the current profile,
  coalescing requests during combat.
- `Bars.Refresh(slot)` refreshes matching slots; nil or zero refreshes all.
- `Profile.modules.bars = false` disables creation on the next reload.

## Clicks, dragging and visuals

Buttons inherit only `SecureActionButtonTemplate`. Their frame IDs stay zero:
positive IDs would make the secure mixin calculate paged actions instead.
Both AnyDown and AnyUp are registered; the inherited secure click handler selects
one edge using `ActionButtonUseKeyDown`. RikUI neither replaces OnClick nor
changes that CVar. Two PostClick notifications alone do not establish two casts.

The bare template has no drag scripts. Explicit handlers call PickupAction
and PlaceAction out of combat. Locked bars require the configured PICKUPACTION
modifier to pick up a button (normally Shift). A drop requires a nonempty cursor;
displaced actions stay on the cursor. Combat drags are rejected, never queued.

Icons, counts and empty-slot textures refresh on slot changes, world entry,
binding changes, spell icon/charge updates and inventory changes. Modern
C_ActionBar APIs are preferred, with legacy globals retained for beta
compatibility. Display-ready counts go directly to SetText; secret numeric
counts go directly to SetFormattedText without comparison or conversion.

Bar3 remains mouse-interactive at zero alpha. Hovering its frame or a button
reveals the row; a short delayed leave check prevents flicker between buttons.
An alpha animation fades it out in 0.2 seconds. Combat reveals it immediately
and combat exit reevaluates hover. No OnUpdate or restricted secure snippets
are installed.

## Stock action bars

`bars-stock.lua` parks MainActionBar and the four replaced MultiBar roots under
a hidden parent. MainActionBar includes its gryphons and page controls; the
legacy MainMenuBarArtFrame is parked if present. MainMenuBar itself, stance,
pet, override and extra-action controls are not suppressed. A missing
MainActionBar global falls back to ActionButton1.bar, the owner assigned by
Blizzard's action-bar constructor.

With the main overlay ready, the same cleanup also parks MicroMenu, BagsBar and
StatusTrackingBarManager. Their child artwork and both XP/reputation containers
are hidden with them. The menu is targeted directly so its sibling matchmaking
status button remains available; MicroMenuContainer and the MicroButtonAndBagsBar
anchor stay intact. Inventory windows are separate from the bag buttons and remain
available through their normal keys. Restoring the menu to MicroMenuContainer
refreshes its native layout; a temporary native override parent is restored as-is.
These stock modules load during game startup; world entry also rechecks targets.

Native events, attributes and click handlers stay intact. Reparenting runs only
through the combat queue; a posthook remembers native parent changes and
reapplies suppression, deferring if combat is active. Stock bars could briefly
reappear if Blizzard reparents them during combat, until the queue can run.

`/rik stockbars show` restores their saved parents; `/rik stockbars hide`
suppresses them again. The choice persists as `Profile.showStockBars`.
Disabling the bars module leaves the stock UI available after reload. Stock
bars without a complete matching overlay remain available.

## Verification

The LuaJIT suite covers fixed attributes and IDs, inherited click preservation,
profile positions and scale, Apply/Undo, queued creation/layout, rejected combat
drags, lock/modifier pickup, cursor drops, event refreshes, modern and legacy
APIs, secret count sinks, module disablement and hover/combat fade transitions.
Stock-bar tests cover parent restoration, native reattachment, combat deferral,
module disablement, furniture hide/restore, native menu relocation/layout refresh,
and preservation of native events, status-child hierarchy and unrelated controls. The recording
renderer does not execute Blizzard's protected action handler.

Native beta acceptance passed on 2026-09-18. The user confirmed the expanded
stock UI cleanup, both right-side columns, one expected action per click,
Shift-drag out of combat, and third-row hover/combat reveal followed by fade,
with no Lua errors. This confirms the current client configuration; alternate
click-edge settings and temporary override modes were not separately reported.

Repeatable Warrior beta regression checks:

1. Reload with RikUI enabled and inspect the bottom stack and right columns.
   Stock main/extra bars, gryphons, bag/menu buttons, and XP/reputation bars
   should be absent. Verify native keys still cast, bag/menu keys still open
   their panels, and /rik stockbars show|hide restores/hides the stock UI.
2. With the Warrior preset placed, click a known non-toggle spell/action on an
   overlay and confirm the expected action fires once. Compare bar2 with its
   Shift binding. Check with ActionButtonUseKeyDown both 1 and 0, restoring
   the original setting afterward. Do not use Attack's toggle state as proof.
3. Out of combat, Shift-drag an action to an empty overlay slot and back;
   verify icons move and the action casts from its new slot.
4. Check bar3 at rest, over a button, in the gaps, during combat, and after
   combat. Confirm no Lua/protected-action errors.
5. Check saved position/scale persistence across reload. Apply/Undo should
   update positions immediately.

## Source evidence

Reviewed 2026-09-18. The 12.1.5 ptr2 source reports build 69848; it supports
implementation choices but does not replace a check on beta 1.60.1.69913.

- [Secure template XML](https://github.com/Gethe/wow-ui-source/blob/ptr2/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.xml)
- [Fixed action and click edge handling](https://github.com/Gethe/wow-ui-source/blob/ptr2/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua)
- [Native multi-bar pages](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ActionBar/Shared/MultiActionBars.lua)
- [Action button drag and refresh events](https://github.com/Gethe/wow-ui-source/blob/ptr2/Interface/AddOns/Blizzard_ActionBar/Shared/ActionButton.lua)
- [Action-bar API documentation](https://github.com/Gethe/wow-ui-source/blob/ptr2/Interface/AddOns/Blizzard_APIDocumentationGenerated/ActionBarFrameDocumentation.lua)
- [Menu roots](https://github.com/Gethe/wow-ui-source/blob/ptr2/Interface/AddOns/Blizzard_MicroMenu/Mainline/MicroMenuContainer.xml) and [native relocation/layout](https://github.com/Gethe/wow-ui-source/blob/ptr2/Interface/AddOns/Blizzard_MicroMenu/Shared/MicroMenuContainer.lua)
- [Bag bar hierarchy](https://github.com/Gethe/wow-ui-source/blob/ptr2/Interface/AddOns/Blizzard_MainMenuBarBagButtons/Mainline/MainMenuBarBagButtons.xml)
- [Status bar manager hierarchy](https://github.com/Gethe/wow-ui-source/blob/ptr2/Interface/AddOns/Blizzard_ActionBar/Mainline/StatusTrackingBar.xml)
