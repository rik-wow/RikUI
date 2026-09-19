# Nameplates

`nameplates.lua` puts the flat skin on Blizzard's nameplates without replacing
them. The client still creates, positions, stacks and drives every plate; the
module only writes textures, fonts and alpha, and adds an own-debuff row.
Disable the `nameplates` module in `/rik config` and reload to get the stock
look back.

## What you see

The health bar uses the RikUI statusbar texture on a flat dark backing that
shows as a one-pixel border. The bar's fill and colour are Blizzard's: reaction
colour for mobs and class colour for players when the client's class-colour
setting is on. The name and the level number use the RikUI font. The level
badge loses its gold frame for a flat dark box with the same border; the number
keeps Blizzard's difficulty colour and the skull for high-level units stays.
Your target and focus get a white border in place of Blizzard's glow. Borders
are sized with `PixelUtil.GetNearestPixelSize` against the plate's effective
scale on every layout pass, so they stay one screen pixel. Your own
debuffs sit in a centred row of up to six 18px icons above the name, with the
same countdown numbers and dispel-coloured borders as the
[target aura row](auras.md).

Which plates exist is still up to the `nameplateShowEnemies` and
`nameplateShowFriends` settings the [setup engine](setup.md) writes.

## How it stays out of the secret system

Addon code on this client cannot safely read unit health, and comparing units
in combat is not dependable either. The module reads no unit value at all:

- The bar's value and colour are never written. Only
  `healthBar.barTexture:SetTexture` and the `bgTexture` behind it change.
- Blizzard's `NamePlateHealthBarMixin:UpdateSelectionBorder` decides target and
  focus in secure code and shows or hides `healthBar.selectedBorder`. That art
  is faded to alpha zero and its `SetShown` and `Hide` are post-hooked; the
  flat border copies `selectedBorder:IsShown()`.
- Debuffs come from Blizzard's `CustomAuraContainerTemplate` through the shared
  factory in `auras.lua` with the filter `HARMFUL|PLAYER`. The container reads
  and draws in secure code.

`NamePlateUnitFrameMixin:UpdateAnchors` puts the stock bar atlas, background
atlas and name font height back on every layout pass, so each unit frame's
`UpdateAnchors` is post-hooked once and the skin is applied again after it.

## Plates, pooling and combat

On `NAME_PLATE_UNIT_ADDED` the module asks `C_NamePlate.GetNamePlateForUnit`
for the plate, skips it when it is missing or `IsForbidden()` (friendly plates
in instances), and skins `plate.UnitFrame`. Blizzard pools unit frames, so
hooks and the aura container are made once per frame and kept in weak tables;
when a frame comes back for another token its container gets `SetUnit`,
`Show` and `UpdateAllAuras`. `NAME_PLATE_UNIT_REMOVED` hides the container.

Skinning is plain region work and runs in combat. Aura containers are only
created out of combat, like every other container in RikUI; a plate that first
appears mid-fight gets its row on `PLAYER_REGEN_ENABLED`, and frames created
earlier already have one. Blizzard's own `AurasFrame.DebuffListFrame` is faded
only on frames where the RikUI container exists, so if the client refuses the
container you keep the stock debuff icons. A refusal prints one
`Auras container` line and is not retried.

## Not covered

The cast bar, classification icon, raid target icon, aggro flare and the
dimming overlay on non-targets are left stock. There is no plate resizing and no threat colouring.

## Diagnostics

`/rik debug` prints `Nameplates skinned=<n> active=<n> containers=<n>`.

## Verification

`tests/nameplates.test.lua` builds fake plates with the 69913 region names and
an `UpdateAnchors` that restores the stock textures. It proves: bar texture,
backing, its two anchors and both fonts; the faded selection art and the
highlight following `SetShown` and `Hide`; the skin surviving a layout pass;
the container's unit, filter, parent and anchor above the name, and the stock debuff list
fading with it; removal hiding the container; a pooled frame reused without
new hooks and retargeted; a forbidden plate untouched; unknown and secret
tokens ignored; a plate without level or aura frames; the debug line; a combat
add skinned without a container until regen; a client without the container
template keeping stock debuffs with one warning; a disabled module installing
no hooks.

The stub cannot show whether the client accepts an aura container on a
nameplate token, whether `SetUnit` is allowed in combat, or whether the
`UpdateAnchors` post-hook taints plate layout. Beta checklist:

1. Reload and target a mob: flat bar, RikUI font on the name and level, white
   border on the target only. Tab through several mobs and watch the border
   move.
2. Fight two mobs with a debuff on each: your debuff icons should sit above
   each plate's name with countdowns. Watch for a secret-value or blocked-action
   error and for plates that stop following their mobs.
3. Pull a mob whose plate was not on screen before combat: it should be
   skinned straight away and get its debuff row after the fight.
4. `/rik debug` should print the three counts with no `Auras nameplate` line.
   Disable the module, reload, and confirm the stock plates return.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_NamePlates.toc: the shared files plus the Camelot level frame and option overrides](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlates.toc)
- [Blizzard_NamePlates.xml: BaseNamePlateUnitFrameTemplate's region names](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlates.xml)
- [Blizzard_NamePlateUnitFrame.lua: UpdateAnchors resetting the bar, background and name font](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlateUnitFrame.lua)
- [Blizzard_NamePlateHealthBar.lua: UpdateSelectionBorder](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlateHealthBar.lua)
- [Camelot/Blizzard_NamePlateLevelFrame.xml: playerLevelDiffText](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Camelot/Blizzard_NamePlateLevelFrame.xml)
