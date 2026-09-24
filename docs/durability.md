# Durability

Settings > Durability offers **Show lowest gear durability**. It keeps the lowest readable percentage visible before warning thresholds; worn/broken alerts still take precedence. Hover lists readable gear. Missing, secret and invalid readings are omitted, and unavailable early slots no longer hide later alerts. The existing eleven-slot coverage and repair-disabled game rule still apply.

Research reviewed 2026-09-24: [Forever UI wishlist](https://www.reddit.com/r/wowforever/comments/1wnnqtf/what_does_your_wow_forever_wishlist_look_like/). This is an inferred HUD improvement, not a specific player request. Existing API coverage is reused; online retrieval of the pinned source failed during this run.

`src/modules/durability/durability.lua` replaces the armoured figure that appears under the minimap
when gear wears out. A small flat pill says how many pieces are worn or broken
and `DurabilityFrame` is parked through the shared hide helper once the pill
exists. Disable the `durability` module in `/rik config` and reload to get the
figure back.

## What you see

Nothing while your gear is fine. When the client flags a piece, a 132x18 pill
appears at the top centre on the dark backing with the 1px edge the nameplates
use: `2 worn` in yellow, or `1 broken, 2 worn` in red. The colours are
Blizzard's own alert yellow and red. Hovering lists each flagged slot with its
durability percent and state.

## Motion

The pill fades in over 0.15s when it appears. While anything is broken a red
overlay pulses behind the text until it is repaired; a repeated alert does not
restart the pulse. Worn gear does not pulse.

## How it works

`UPDATE_INVENTORY_ALERTS` and `PLAYER_ENTERING_WORLD` trigger a refresh that
reads `GetInventoryAlertStatus(1..11)`, the same eleven slots in the same order
as Blizzard's `INVENTORY_ALERT_STATUS_SLOTS`: 1 is worn, 2 is broken. That is
inventory state and not a unit value, so the module counts it; the read still
runs under `pcall`, and a failure prints one `Durability status` line and
hides the pill. Under the `RepairArmorDisabled` game rule the pill stays
hidden, as Blizzard's figure does.

The tooltip percent comes from `GetInventoryItemDurability` on the inventory
slot behind each entry, worked out under `pcall`. A missing or secret value
leaves the percent out and keeps the slot name and state.

## Layout

The frame is `RikUIDurability`, registered with the [shared layout](layout.md)
under `durability`. The default is centred 94px under the top of the screen,
just over the [mirror timers](mirrortimers.md). Blizzard's figure sat under
the minimap, where the RikUI quest tracker is now.

## Stock frames and combat

The pill is built and `DurabilityFrame` parked, with its events dropped,
inside one `Combat.Queue` closure. At a combat login nothing is touched until
`PLAYER_REGEN_ENABLED`, when the pill is built with the current damage. The
pill is unprotected and shows and hides in combat.

## Diagnostics

`/rik debug` prints `Durability pill=<bool> worn=<n> broken=<n>`.

## Verification

`tests/durability.test.lua` proves: the layout key and default; nothing shown
for sound gear; border and font; the worn count in yellow with a fade; the
tooltip slots and percents; the broken count first, in red, with one pulse; a
slot without a durability read and a secret one; repair hiding the pill and
stopping the pulse; the next fade; the game rule; a failing read reported
once; the stock figure parked; the debug line; damage picked up on entering
the world; a combat login; a client without the alert read and one without
game rules; a disabled module.

The stub cannot show the look or confirm that parking Blizzard's right-managed
frame leaves the managed container quiet. Beta checklist:

1. Fully restart the client (new TOC entry). Die a few times or fight until a
   piece goes yellow: the pill appears top centre and the armoured figure does
   not.
2. Hover it and compare the slots with the character sheet.
3. Let a piece break: red text and a pulse. Repair: the pill goes.
4. `/rik move`, drag it, lock, reload.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [DurabilityFrame.lua: the slot list, alert colours, events, GetInventoryAlertStatus and the game rule](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_DurabilityFrame/DurabilityFrame.lua)
