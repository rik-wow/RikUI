# XP and reputation bar

`src/modules/xpbar/xpbar.lua` replaces the stock status tracking bars with up to two thin flat
rows: experience while the character is levelling, and the watched faction's
reputation whenever a faction is watched. `StatusTrackingBarManager` is parked
through the [shared hide helper](../SDD.md) once the bar exists. Disable the
`xpbar` module in `/rik config` and reload to get the stock bars back.

## What you see

Each row is 498px wide, the width of the main action bar, and 8px tall, on the
same dark backing and 1px edge as the nameplates. The experience row is purple
with a blue rested segment behind it that reaches to current plus rested
experience. The reputation row takes its colour from the standing: red for
hated and hostile, orange for unfriendly, yellow for neutral, green from
friendly to revered and teal for exalted. A capped standing draws a full bar.

With both rows showing, reputation sits 2px under experience. At the level cap,
or with experience gain switched off, only the reputation row remains. With no
row to show the whole holder hides.

## Motion

Fills use the client's `ExponentialEaseOut` StatusBar interpolation. A row that
was hidden gets its first value with `Immediate`, so it never sweeps in from a
stale number. An experience gain (`PLAYER_XP_UPDATE`) plays a 0.25s white flash
over the row; rested changes do not. A row that appears fades in over 0.15s.
The tween and easing helpers live in `src/ui/motion.lua` and are shared with the other
furniture modules.

## Hover

Hovering the experience row shows `Experience`, `current / max (percent)` and
the rested amount. Hovering the reputation row shows the faction name, the
standing label and progress inside the standing.

## Layout

The holder is `RikUIXPBar`, registered with the [shared layout](layout.md)
under `xpbar`, so `/rik move`, `/rik move reset` and `/rik scale` apply. The
default hangs from `y=36` above the bottom of the screen, centred, which puts
it under the main action bar where the Classic bar sat. The roadmap text said
above the bar stack; the stance and pet rows already sit there.

## Stock frames

`src/modules/bars/bars-stock.lua` used to park `StatusTrackingBarManager` with the main action
bar. This module owns it now and parks it only after its own bar is built, with
events kept and the child containers untouched. `/rik stockbars show` returns
it (the module follows `bars.UpdateStockVisibility` through a post-hook) and
`hide` parks it again. The holder is created and the stock frame reparented
inside one `Combat.Queue` closure; at a combat login nothing is touched until
`PLAYER_REGEN_ENABLED`. The rows themselves are unprotected, so they show,
hide and resize in combat.

## Secret rules

Whether `UnitXP`, `UnitXPMax`, `GetXPExhaustion` and the watched faction data
are secret for addon code on 69913 is not verified. The module assumes they can
be:

- Experience goes through `core.Secret.Apply` straight into
  `SetMinMaxValues`/`SetValue`. A failing read prints one `XP bar experience`
  line.
- The rested sum runs under `pcall`. A secret makes the sum throw, and the
  rested segment is hidden without a message.
- Reputation thresholds and standing go to the sinks uncompared. The capped
  check runs under `pcall`, and a secret reaction falls back to the neutral
  colour.
- Tooltip numbers are built under `pcall`; unreadable values leave the title
  alone.

## Diagnostics

`/rik debug` prints `XP bar holder=<bool> xp=<bool> reputation=<bool>`.

## Verification

`tests/xpbar.test.lua` fakes the experience, rested, level-cap and watched
faction reads. It proves: the layout key and defaults; one 8px experience row
for a levelling character; the first fill without easing; the rested segment
value; media, border and colours; an eased fill with a flash on a gain; rested
loss hiding the segment without a flash; both tooltips; a secret experience
value reaching the sink silently with no rested segment and no tooltip numbers;
a failing read reported once; the reputation row, its fade, colour, capped and
secret cases; the level cap, no watched faction and switched-off experience
hiding rows or the holder; the bar returning in combat; the stock bars parked,
returned and parked again; the debug line; a combat login building nothing
until regen; a client without the reputation and level-cap helpers; a disabled
module leaving everything untouched.

The stub cannot show how the bar looks or whether the values are secret. Beta
checklist:

1. Reload on a levelling character: a purple row sits under the main bar, the
   stock experience bar is gone, and `/rik debug` prints `xp=true`.
2. Kill something: the fill eases up and the row flashes once.
3. Rest in an inn, then leave: the blue segment appears behind the fill.
4. Watch a faction in the reputation panel: a second row appears under the
   first in the standing colour. Unwatch it and the row goes.
5. Hover both rows and check the numbers. Fight something and confirm no error
   appears and the fill still moves.
6. `/rik move`, drag the bar, lock, reload. `/rik stockbars show` should bring
   the stock bars back.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Shared/ExpBar.lua: UnitXP, UnitXPMax, GetXPExhaustion, the level-cap and disabled checks and the events](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_StatusTrackingBar/Shared/ExpBar.lua)
- [Shared/ReputationBar.lua: C_Reputation.GetWatchedFactionData and its fields](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_StatusTrackingBar/Shared/ReputationBar.lua)
- [Mainline/StatusTrackingBar.xml: StatusTrackingBarManager and its two containers](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_StatusTrackingBar/Mainline/StatusTrackingBar.xml)
