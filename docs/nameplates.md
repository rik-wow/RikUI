# Nameplates

Three files lay a RikUI design over Blizzard's nameplates without replacing
them. The client still creates, positions, stacks and drives every plate.
`nameplates.lua` owns the events, the pooled parts and the debuff row,
`nameplates-skin.lua` the layout and the health bar, `nameplates-target.lua`
the target and threat indicators. Disable the `nameplates` module in
`/rik config` and reload to get the stock plates back.

## What you see

A 14px flat bar on a dark backing with a one-pixel edge, with the health
percent centred inside it. The unit's name sits in its own plaque on top of the
bar: a flat dark box with the same one-pixel edge, exactly as wide as the bar
and level box together and sharing their top line, so the two rows stack as one
block on every mob. The name is centred in it and a name too long for the row
truncates. Both texts use the RikUI font. The bar is coloured by reaction, or by class for players, and goes grey for tapped
and disconnected units. The level is a flat dark box flush with the bar's right
end, exactly as tall as the bar, with the number in Blizzard's difficulty
colour and the skull kept for high-level units. Left of the bar, outside the target arrow, a small glyph
marks special units: gold `+` elite, red `B` boss, silver `R` rare and `R+`
rare elite. Your own debuffs sit in a centred row of up to six 18px icons
above the name plaque, with countdown numbers and dispel-coloured borders like the
[target aura row](auras.md).

Your target and focus get a `>` and `<` arrow either side of the plate and a
pulsing accent-blue line under the bar. The target plate also grows to 115%
and the others dim to 60%, both animated by the client. A red line over the
bar marks a unit that is on you.

The cast bar keeps Blizzard's fill, which changes colour for casts you cannot
interrupt, and gets the flat backing, a one-pixel edge, a cropped icon and the
RikUI font in place of the border art and the shield.

Friendly plates that show only a name keep Blizzard's name placement. Which
plates exist is still up to the `nameplateShowEnemies` and
`nameplateShowFriends` settings the [setup engine](setup.md) writes.

## Animations

- Health eases to its new value (`ExponentialEaseOut`). A pooled plate's first
  fill is immediate so it does not sweep from the previous unit's health.
- A health change flashes the bar white for a quarter of a second.
- A plate fades in over 0.15s when it appears.
- The arrows fade in when you select a plate and the accent line pulses while
  it stays selected. The plate's growth and the dimming of the others are
  tweened by the client.

## How it stays out of the secret system

Addon code on this client cannot read unit health, and comparing units in
combat is not dependable. Nothing here reads or compares either.

- Health. Blizzard calls `SetValue` without an interpolation argument, and a
  second call cannot add easing afterwards. So every plate gets an own
  `StatusBar` on top of Blizzard's, filled through `core.Secret.Apply`:
  `UnitHealth` and `UnitHealthMax` go straight into `SetMinMaxValues` and
  `SetValue(value, easing)`, the same reader-to-sink route the RikUI unit
  frames use. Blizzard's fill texture is faded to alpha zero. The flash is
  triggered by the `UNIT_HEALTH` event, never by a value.
- Percent text. It is Blizzard's own health text, which already works with
  secret values. The module switches it on with the `CurrentHealthPercent`
  bit of `nameplateInfoDisplay` and moves the font strings onto the own bar.
  `TextStatusBar` uses `Text`, `LeftText` or `RightText` depending on the
  display mode, so all three are centred in the bar; only one is filled at a
  time.
- Target and focus. `NamePlateHealthBarMixin:UpdateSelectionBorder` decides
  them in secure code and shows `healthBar.selectedBorder`. That art is faded
  and its `SetShown` and `Hide` are post-hooked; arrows and accent line copy
  `selectedBorder:IsShown()`.
- Threat. Blizzard shows the unit frame's `aggroHighlight` region from secure
  code. `UpdateAggroHighlight` is post-hooked and the red line copies
  `aggroHighlight:IsShown()`. The threat colour is not read, and the animated
  flare art is blanked rather than faded because Blizzard animates its alpha.
  Whether the client raises that state at all depends on its
  `nameplateThreatDisplay` setting.
- Scale and dimming. Plate scale and alpha belong to the engine. The module
  writes `nameplateSelectedScale = 1.15` and `nameplateNotSelectedAlpha = 0.6`
  when `C_CVar.GetCVarInfo` knows them.
- Classification. Camelot switches Blizzard's classification art off, so
  `UnitClassification` is read through `core.Secret.Read`; only a readable
  string picks a glyph and anything else shows none.
- Colour. `UnitFrames.HealthColor`, shared with the unit frames, which reads
  flags and reaction through the same guarded readers.
- Debuffs. Blizzard's `CustomAuraContainerTemplate` with `HARMFUL|PLAYER`
  through the shared factory in `auras.lua`.

## Layout pass

`NamePlateUnitFrameMixin:UpdateAnchors` resets the bar height, the background
atlas, the name's font height and every anchor on each layout pass. Each unit
frame's `UpdateAnchors` is post-hooked once, and `Skin.Apply` then sets the
14px height, the backing, the fonts, the name, plaque and percent anchors, the level
box, the cast bar frame and the pixel sizes again. Lines are sized with
`PixelUtil.GetNearestPixelSize` against the own bar's effective scale and have
pixel snapping off, because plates move in fractions of a pixel.

A child frame draws above its parent's regions, so the own bar would cover
Blizzard's health text. Those font strings are re-parented to the own bar, and
the bar's RikUI regions are created on it.

The name stays Blizzard's font string on the unit frame. The plaque is a 13px
texture anchored from the backing's top-left corner to the level box's
top-right corner, one pixel down so both rows share an edge line, plus the
shared outline. The name is anchored left and right inside it with 4px of
padding, centred, with word wrap off. Blizzard hides the name on some plates;
the name's `SetShown`, `Show` and `Hide` are post-hooked and the plaque follows.
A name-only plate keeps Blizzard's name placement and gets no plaque.

## Plates, pooling and combat

On `NAME_PLATE_UNIT_ADDED` the module asks `C_NamePlate.GetNamePlateForUnit`
for the plate and skips it when it is missing or `IsForbidden()`. Blizzard
pools unit frames, so parts, hooks and the aura container are made once per
frame and kept in weak tables; a reused frame is refilled, recoloured,
re-marked, faded in, and its container gets `SetUnit`, `Show` and
`UpdateAllAuras`. `NAME_PLATE_UNIT_REMOVED` hides the container.
`UNIT_HEALTH`, `UNIT_MAXHEALTH`, `UNIT_FACTION`, `UNIT_NAME_UPDATE` and
`UNIT_CLASSIFICATION_CHANGED` are routed to the plate that holds the token.

Layout is plain region work and runs in combat. Aura containers are created
out of combat only; a plate that first appears mid-fight gets its row on
`PLAYER_REGEN_ENABLED`. Blizzard's `AurasFrame.DebuffListFrame` is hidden only
where the RikUI container exists, so a client that refuses the container keeps
the stock debuffs with one `Auras container` line. Blizzard shows that list
with `SetShown` on every aura display update, so `SetShown` is post-hooked and
the list is hidden again; fading it was not enough and left two rows.

## Client settings

The three CVars are written through the combat queue, because several
nameplate CVars refuse writes in combat. The value each had before goes to
`profile.nameplateCVars`. CVars outlive the module toggle, so when the module
is disabled the saved values are written back at the next login and the table
is cleared.

## Not covered

Raid target icon, quest and widget art and the dimming overlay Blizzard draws
on non-targets are left stock. The cast bar's fill texture stays Blizzard's.
There is no plate resizing beyond the bar height and no tank-style threat
colouring, which would need threat values addon code cannot read.

## Diagnostics

`/rik debug` prints `Nameplates skinned=<n> active=<n> containers=<n>`.

## Verification

`tests/nameplates.test.lua` builds fake plates with the 69913 region names, an
`UpdateAnchors` that restores the stock look, recorders for animation groups
and a fake `C_CVar`. It proves: the three client settings written with the
originals saved; the own bar, faded fill, 14px height and pixel backing;
secret health reaching the bar with an immediate first fill; bar colour; the
name centred in a plaque as wide as the bar and level box that follows the
name's shown state; the centred percent texts; the elite marker, a classification change and
a secret classification; the fade-in; the level box; eased health with a flash
on `UNIT_HEALTH` and none on `UNIT_MAXHEALTH`; other and secret tokens
ignored; arrows, accent line and pulse following `selectedBorder` without
restarting on a repeat; their anchors; the blanked flare and the threat line
following `aggroHighlight`; the flat cast bar with its fill untouched; the
layout surviving a layout pass; the name-only case; the debuff container, its
fade of the stock list, removal and pooled reuse without new hooks; a
forbidden plate; a plate missing every optional region; the debug line; a
combat login deferring the settings and the container; a client without the
container template; a disabled module restoring the saved settings.

The stub cannot show how any of this looks, or settle these client questions:
whether re-parenting Blizzard's name and health text is tolerated, whether
`SetHeight` on `HealthBarsContainer` disturbs plate stacking or click areas,
whether the two target CVars exist on 69913, whether `SetValue` accepts the
easing argument here, whether `UnitClassification` is readable for nameplate
units in combat, and whether the hooks taint plate layout. Beta checklist:

1. Fully restart the client (two new TOC entries). Target a mob: chunky bar
   with the percent centred, the name in its plaque on top, level box flush right, arrows and a pulsing line,
   the plate a little larger and the others dimmer.
2. Hit the mob: the bar should ease down and flash. Let it hit you: a red line
   should appear over its bar.
3. Find an elite or a rare and check the marker. Watch a caster: the cast bar
   should be flat with the spell name in the RikUI font.
4. Fight two or three mobs with a debuff on each and watch for errors, plates
   that stop following their mobs, or names that vanish. `/rik debug` should
   print the three counts with no `Nameplates ...` error line.
5. Disable the module, reload, and confirm the stock plates and the stock
   target scale return.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_NamePlates.toc: the shared files plus the Camelot level frame, constants and option overrides](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlates.toc)
- [Blizzard_NamePlates.xml: BaseNamePlateUnitFrameTemplate's region names](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlates.xml)
- [Blizzard_NamePlateUnitFrame.lua: UpdateAnchors, UpdateIsTarget and UpdateAggroHighlight](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlateUnitFrame.lua)
- [Blizzard_NamePlateHealthBar.lua: UpdateSelectionBorder and the info display bitfield](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlateHealthBar.lua)
- [Blizzard_NamePlateCastingBar.lua: ApplyStyleAndAnchoring and the cast bar regions](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlateCastingBar.lua)
- [Camelot/Blizzard_NamePlateFrameOptionsOverrides.lua: the classification indicator switched off](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Camelot/Blizzard_NamePlateFrameOptionsOverrides.lua)
- [Camelot/Blizzard_NamePlateConstants.lua: the nameplate CVar names](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Camelot/Blizzard_NamePlateConstants.lua)
- [Camelot/Blizzard_NamePlateLevelFrame.xml: playerLevelDiffText and the badge art](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Camelot/Blizzard_NamePlateLevelFrame.xml)
