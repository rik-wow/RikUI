# Extra buttons

`extrabuttons.lua` gives the action buttons outside RikUI's bars the bar look:
the extra action button (quest and encounter abilities), the zone ability
buttons and the spell flyout. Disable the `extrabuttons` module in
`/rik config` and reload for the stock buttons.

## What you see

The large ornament behind the extra action button and the zone ability frame
is gone. Each button shows a cropped square icon, without Blizzard's round
mask, inside a one-pixel edge. The edge uses the bars' border colour setting,
so these buttons match your bars. Hotkey and count use the RikUI font. The
edge fades in over 0.15s each time the holder appears. The flyout loses its
background strip.

Cooldown sweeps, the ready flash, range colouring, clicks, key bindings and
the extra bar's own intro and outro animations are Blizzard's.

## Holders

| Holder | Buttons | When they are skinned |
| --- | --- | --- |
| `ExtraActionBarFrame` | `.button` (`ExtraActionButton1`) | the holder's `OnShow` |
| `ZoneAbilityFrame` | pooled children of `SpellButtonContainer` | `OnShow` and after every `UpdateDisplayedZoneAbilities`, hooked on the frame instance |
| `SpellFlyout` | its child buttons | `OnShow` |
| `PossessActionBar` | the buttons in its `actionButtons` list (mind control, cancel) | `OnShow` |
| `OverrideActionBar` | `SpellButton1` to `SpellButton6` | `OnShow` |

The override (vehicle) bar keeps its hand-drawn frame: that art changes with a
texture kit per vehicle, and Forever is unlikely to have vehicles at all. Only
its six spell buttons get the bar look. Beta check for the possess bar: mind
control a mob as a priest, or use any possess effect, and look at the two
buttons above the bars.

A button is recognised by its `icon` or `Icon` key. A holder the client lacks
is skipped.

## How it stays safe

These are secure buttons, and the extra action button can appear in combat.

- Only regions are written: alpha on `style`, `Style` and the normal texture,
  `RemoveMaskTexture` and a crop on the icon, fonts on `HotKey` and `Count`,
  and four new line textures. None of that is protected.
- No attribute, parent, point, size or script is written, and scripts on the
  holders are hooked with `HookScript`.
- Nothing is stored on a button. Skinned buttons, their edges and their fades
  live in weak tables inside the module, so no RikUI key sits on a table that
  Blizzard's action button code reads. The suite checks the button's own keys
  before and after.

A button that refuses the skin is reported once as `ExtraButtons skin` and not
tried again.

## Diagnostics

`/rik debug` prints `ExtraButtons hooked=<n> skinned=<n> failed=<n>`.

## Verification

`tests/extrabuttons.test.lua` fakes the three holders with their 69913 keys. It
proves: nothing before the first show; ornament, normal texture and mask
removed; the crop and the edge one pixel outside the icon; the fallback and the
bars' border colour; fonts; no new key, attribute, point, parent or script on
the button; the fade on every show with one edge; pooled zone buttons after
Blizzard's update; flyout background and buttons; a button first seen in
combat; the debug line; a client without the holders; one failure report; the
disabled module. The suite's only red run was a syntax slip in the suite
itself; its first clean run came after the module existed.

The stub cannot show how it looks or whether Blizzard re-adds the icon mask on
an update. Classic-era content rarely uses these buttons, so they may be hard
to reach on the beta. Beta checklist:

1. Fully restart the client (new TOC entry). Find a quest or event that grants
   an extra action button or a zone ability.
2. The button should be a square cropped icon in a thin edge with no ornament,
   and its key binding should still fire it, in and out of combat.
3. Change the bar border colour in `/rik config`, reload, and check the edge
   follows.
4. Watch for "action blocked" when the button appears during combat.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [ExtraActionBar.xml: ExtraActionButtonTemplate's icon, IconMask, HotKey, Count, style and the holder's button key](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ActionBar/Shared/ExtraActionBar.xml)
- [ZoneAbility.xml: Style, SpellButtonContainer and the spell button's Icon, Count and NormalTexture](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ZoneAbility/ZoneAbility.xml)
- [ZoneAbility.lua: UpdateDisplayedZoneAbilities](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ZoneAbility/ZoneAbility.lua)
- [SpellFlyout.xml: the flyout frame and its button template](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ActionBar/Shared/SpellFlyout.xml)
