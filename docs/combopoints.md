# Combo points

Blizzard's `ComboFrame` hangs off the `TargetFrame` that the
[unit frames](unitframes.md) park, so rogues and druids had no combo points
under RikUI. `combopoints.lua` draws them as five flat pips. Other classes get
nothing. Disable the `combopoints` module in `/rik config` and reload to drop
the row.

## What you see

Five 10px squares with 2px between them, on the dark backing with the 1px edge
the nameplates use. Pips one to four fill gold, the fifth red. The row shows
while you have a target you can attack and hides otherwise. By default it sits
in the 60px gap between the player and target frames, level with their middle;
the space above the target frame belongs to its aura rows.

## Motion

The row fades in over 0.15s when it appears. A combo point change eases the
pips with the client's `ExponentialEaseOut` and flashes the row white for
0.2s. A new target's count lands with `Immediate`, so pips never sweep from
the last target's count.

## How it stays out of the secret system

Player power is secret in combat on this client and the combo count may be
too. Blizzard's frame compares the count against each pip index, which a
secret value forbids. Here pip `i` is a `StatusBar` with the range `i-1..i`,
and `GetComboPoints("player", "target")` goes through `core.Secret.Apply` into
every pip's `SetValue` unchanged. The widget clamps the value, so three points
fill pips one to three and leave four and five empty with no comparison in
Lua.

The price is that the module never knows which pip changed or whether the
count is zero. So the flash follows the `UNIT_POWER_FREQUENT` event for the
player with the `COMBO_POINTS` token rather than a value, and the row shows
with empty pips instead of hiding at zero. A secret unit token on that event
is ignored. `UnitExists` and `UnitCanAttack` run under `pcall`; a failed read
shows the row. A failing count read prints one `Combo points read` line.

A druid out of cat form sees five empty pips on a hostile target. Hiding them
would need a form or power type read that may be secret.

## Layout

The holder is `RikUIComboPoints`, registered with the [shared layout](layout.md)
under `combopoints`, so it moves with `/rik move` and works with the unit
frames module disabled. It is unprotected and shows and hides in combat. At a
combat login it is built on `PLAYER_REGEN_ENABLED` and filled for the current
target.

## Diagnostics

`/rik debug` prints `Combo points holder=<bool> shown=<bool>`.

## Verification

`tests/combopoints.test.lua` proves: the layout key, default and 58x10 holder;
five pips with their ranges, spacing, border and media; the finisher colour;
hidden without a target; shown with a fade and an immediate fill read from
`("player", "target")`; an eased fill and a flash on a combo point event;
other power types, other units and a secret unit ignored; a secret count
reaching every sink silently; a failing read reported once; a target swap
without easing or a second fade; an unattackable target, a lost target and the
next fade; showing in combat; a failing attack check; the debug line; a druid;
another class; a combat login; a client without `GetComboPoints`; a disabled
module.

The stub cannot show the look, confirm that the `StatusBar` clamps a secret
value the way it clamps a number, or that `UNIT_POWER_FREQUENT` names
`COMBO_POINTS` on this client. Beta checklist:

1. Fully restart the client (new TOC entry). On a rogue, target a mob: five
   empty pips appear between the player and target frames.
2. Build combo points in combat: pips fill left to right with a flash each
   time, the fifth in red. Spend them: all empty again.
3. Swap between two mobs with different counts and check each shows its own.
4. Target a friendly player: the row hides. Watch for errors in a fight.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Mainline/ComboFrame.lua: GetComboPoints, the events and the per-pip comparison](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UnitFrame/Mainline/ComboFrame.lua)
- [Camelot/ComboFrameOverrides.lua: the frame anchored to TargetFrame](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UnitFrame/Camelot/ComboFrameOverrides.lua)
