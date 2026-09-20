# Totem row

`src/modules/totems/totems.lua` shows your active totems as a row of flat icons. Blizzard's
`TotemFrame` is a child of `PlayerFrame`, which the [unit frames](unitframes.md)
park, so without this module a shaman sees no totems at all. Disable the
`totems` module in `/rik config` and reload to remove the row; the stock frame
stays hidden with the player frame either way.

## What you see

Up to four 28px icons under the player cast bar, packed from the left in slot
order (fire, earth, water, air). Each icon sits in a flat dark box with a
one-pixel edge, is cropped like the action buttons, and carries a dark sweep
that fills as the totem runs out plus the client's countdown number. A new
totem fades in over 0.15s; a refreshed one does not. Hover shows the totem's
tooltip. With no totems down nothing is drawn.

Move it with `/rik move` under the key `totems`.

## Display only

You cannot dismiss a totem from the row. Blizzard's button calls
`DestroyTotem` from its own secure click handler; for addon code that call is
most likely protected, a blocked call raises the forbidden-action popup that
`pcall` cannot catch, and a secure button cannot be shown or hidden in combat,
which is when totems drop. Recasting or the stock keybinds still work.

## How it stays out of the secret system

`PLAYER_TOTEM_UPDATE` and `PLAYER_ENTERING_WORLD` refresh every slot.
`GetTotemInfo(slot)` is read through `core.Secret.Apply`:

- Readable values decide presence the way Blizzard does: `haveTotem` is true
  and `duration > 0`. Anything else hides the slot and clears its sweep.
- Secret `haveTotem` or `duration` cannot be compared. The slot shows and the
  start, duration and icon go straight to `Cooldown:SetCooldown` and
  `Texture:SetTexture`, which accept secrets. An empty slot then shows as an
  empty box, which beats hiding real totems in a fight.
- A read that raises hides every slot and prints one `Totems read: <reason>`
  line.

The cooldown widget draws the sweep and the number, so no remaining time is
worked out in Lua. The slots are plain frames, so showing, hiding and
repacking run in combat. The row itself is built through the combat queue; a
combat login builds it when the fight ends.

## Diagnostics

`/rik debug` prints `Totems holder=<true|false> shown=<n>`.

## Verification

`tests/totems.test.lua` proves: the layout key and default; four flat slots
hidden at rest; a placed totem's cropped icon, start and duration; the fade-in
and no second fade on an update; packing in slot order and repacking on
removal; a cleared sweep; a zero duration treated as gone; the hover tooltip;
no click script; secret values passed through without a print; a failing read
hiding the row with one line; a totem appearing in combat; the debug line; a
combat login deferring the build; a client without `GetTotemInfo`; the disabled
module.

The stub cannot settle these: whether `GetTotemInfo` returns secrets in combat
on 69913, whether `SetCooldown` accepts them here, whether the countdown font
name exists, and whether the default position clears the player aura row.
Beta checklist (needs a shaman):

1. Fully restart the client (new TOC entry). Drop one totem of each element
   out of combat: four icons in slot order, sweeps and numbers running.
2. Drop totems during a fight and let one expire: icons appear and vanish with
   no error and no empty boxes. Empty boxes in combat mean the values are
   secret there; report it.
3. Hover an icon for the tooltip. `/rik move` and drag the row.
4. `/rik debug` should print the `Totems` line.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_UnitFrame.toc: TotemFrame loads for mainline-type games, which camelot satisfies](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UnitFrame/Blizzard_UnitFrame.toc)
- [Mainline/TotemFrame.lua: the GetTotemInfo reads, the duration test and DestroyTotem in OnClick](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UnitFrame/Mainline/TotemFrame.lua)
