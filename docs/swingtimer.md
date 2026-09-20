# Swing timer

Forever ships its own swing timer: three stock bars fed by a `PLAYER_SWING`
event. `swingtimer.lua` replaces them with flat bars for main hand, off hand
and ranged, and parks `SwingTimerMainHandFrame`, `SwingTimerOffHandFrame` and
`SwingTimerRangedFrame` once its own bars exist. Disable the `swingtimer`
module in `/rik config` and reload to get the stock bars back.

## What you see

Each bar is 200px wide and 14px tall on the dark backing with the 1px edge the
nameplates use: the weapon label left, the time to the next swing right, a 2px
white spark on the fill edge. Main hand is light steel, off hand darker steel,
ranged green. A bar shows only while that weapon is swinging. With two weapons
the off hand bar stacks 3px over the main hand, because the stance and pet
rows sit just under the default position; when one stops the other moves
down.

Out of range, the fill, spark and texts dim to 40% and the time turns red.

## Motion

- A bar fades in over 0.15s with its first swing.
- Every swing flashes the bar white for 0.2s and restarts the fill from empty.
- A finished swing stays full for 0.6s before the bar goes. The next
  `PLAYER_SWING` normally lands inside that window, so a bar does not blink
  between swings; when you stop attacking it goes after the last swing.

## How it works

`PLAYER_SWING(duration, swingType)` sets the bar's end time from `GetTime()`
and an `OnUpdate` fills it from the clock, as Blizzard's bar does. Nothing is
read from a unit, so there is nothing the secret system can hide. A duration
that is missing, not a number or not positive is ignored, as is a swing type
the client's `Enum.PlayerSwingType` does not list.

Blizzard creates its off hand and ranged bars from `UnitAttackSpeed` and hides
all three behind the `showSwingTimer` setting and an Edit Mode visibility
choice. This module uses none of them: a weapon that never swings never gets a
bar.

`PLAYER_SWING_RANGE_UPDATE(swingType, inRange, checksRange)` drives the
dimming, and `PLAYER_TARGET_CHANGED` asks
`C_SwingTimer.IsTargetWithinSwingRange` for every bar under `pcall`. The stock
frames request those range updates with `C_SwingTimer.EnableRangeCheck`; they
drop their events when parked, so the module makes the same request itself. A
refusal prints one `Swing timer range check` line and the bars work without
dimming.

## Layout

The holder is `RikUISwingTimer`, registered with the [shared layout](layout.md)
under `swingtimer`. The default is centred 236px above the bottom of the
screen, between the two cast bars.

## Stock frames and combat

The holder is built and the stock frames parked inside one `Combat.Queue`
closure. At a combat login nothing is touched until `PLAYER_REGEN_ENABLED` and
swings before that are ignored. The bars are unprotected and show, hide and
restack in combat. On a client without `Enum.PlayerSwingType` or
`C_SwingTimer` the module registers nothing and prints nothing.

## Diagnostics

`/rik debug` prints `Swing timer holder=<bool> active=<n>`.

## Verification

`tests/swingtimer.test.lua` drives `GetTime` by hand. It proves: the layout key
and default; three hidden labelled bars; media, border, 0..1 range and the
spark anchored to the fill; the range check requested per type; a swing showing
the bar empty with time, fade and flash; the fill following the clock; the
linger; a restart without a second fade; stacking and restacking; the bar
clearing after the linger with its `OnUpdate` removed; bad durations and swing
types ignored silently; range dimming, restore, the non-checking case and the
target change query; the stock frames parked; the debug line; a refused range
check reported once; a combat login; a client without the API; a disabled
module.

The stub cannot show the look, or settle whether `PLAYER_SWING` still fires
with the `showSwingTimer` setting off, or whether parking Blizzard's
bottom-managed frames disturbs the managed container. Beta checklist:

1. Fully restart the client (new TOC entry). Attack a mob: a `Main hand` bar
   appears between the cast bars, fills, flashes and restarts on every swing,
   and the stock swing bar is gone.
2. Dual wield or shoot: a second bar stacks over the first.
3. Step out of melee range while attacking: the bar dims and the time turns
   red. Step back in: it returns.
4. Stop attacking: the bar goes about half a second after the last swing.
5. Turn the swing timer off in the game options and attack again. If the bar
   stops appearing, the event is gated by that setting; report it.
6. Watch for errors about managed frames or Edit Mode.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_SwingTimer.lua: PLAYER_SWING, the range events, C_SwingTimer and the OnUpdate fill](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SwingTimer/Blizzard_SwingTimer.lua)
- [Blizzard_SwingTimer.xml: the three frames, their swing types and label globals](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SwingTimer/Blizzard_SwingTimer.xml)
