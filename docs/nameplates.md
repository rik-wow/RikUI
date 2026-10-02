# Nameplates

Three files lay a RikUI design over Blizzard's nameplates without replacing
them. The client still creates, positions, stacks and drives every plate.
`src/modules/nameplates/nameplates.lua` owns the events, the pooled parts and the debuff row,
`src/modules/nameplates/nameplates-skin.lua` the layout and the health bar, `src/modules/nameplates/nameplates-target.lua`
the target and threat indicators. Disable the `nameplates` module in
`/rik config` and reload to get the stock plates back.

## Readable names

**Adaptive name width** is on by default under Settings > Nameplates. Long
names and surnames get a wider label above the health bar; short names stay
compact. The health bar, level badge and clickable area keep their original size.

**Minimum name width** and **Maximum name width** set the label's bounds,
defaulting to 160 and 280 UI units. Both sliders range from 120 to 400. A label
never becomes narrower than its health bar and level badge. If you put the
maximum below the minimum, the minimum wins. Text beyond the maximum still
truncates. Turn adaptive width off to use the original fixed row.

Changes apply to visible plates, and a reused plate shrinks for its new name.
Native name-only plates keep their existing placement. If the client hides
the text measurement, RikUI keeps the fixed row. These preferences travel
with shared profiles.

![Adaptive and fixed name labels](preview:plates-adaptive-names)

![Maximum label width](preview:plates-name-width-limit)

![A reused plate with a short name](render:plates-pooled-short-name)

![Nameplate readability settings](render:plates-name-options)

Community research reviewed 2026-10-01: a [September 27 Forever player
request](https://eu.forums.blizzard.com/en/wow/t/few-suggestions-quality-of-life-and-proposals/631992)
asks for dynamic minimum/maximum nameplate lengths because full names
truncate. This addition addresses that request. Current addon descriptions
reviewed did not document the exact adaptive-label behavior; global
uniqueness is unknown.

## Row sizes

Nameplates settings offer health bar and name row heights from 12 to 24, defaulting to 14 and 13. The preferences apply to active and reused plates and survive native layout resets. They change the existing cosmetic row layout, not the client's hit area or stacking rules. Profile sharing validates integer bounds.

Research reviewed 2026-09-24: [Forever UI feedback](https://us.forums.blizzard.com/en/wow/t/classic-forever-needs-its-ui-fixed/2352794) requests adjustable plate size and readability. This is community demand. The implementation extends the existing build-specific layout surface without assuming additional CVars. User native acceptance applies; automated fixtures cover refresh, layout resets and invalid values.

## What you see

A 14px flat bar on a dark backing with a one-pixel edge, with the health
percent centred inside it. The unit's name sits in its own plaque on top of the
bar: a flat dark box with the same one-pixel edge. It spans the bar and level
box and can grow symmetrically to fit a long name, up to your maximum width.
The name is centred and truncates only beyond that limit. Both texts use the RikUI font. The bar is coloured by reaction, or by class for players, and goes grey for tapped
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
`nameplateShowFriendlyPlayers` / `nameplateShowFriendlyNpcs` settings the
[setup engine](setup.md) writes.

## Threat text

**Show threat text** on the Nameplates options page adds white `Threat 75%` text to the right of the level badge, outside the target arrow. It is enabled by default and included in profile sharing. The number is the client's scaled percentage from `UnitDetailedThreatSituation("player", unit)`; RikUI does not compute a ratio or infer thresholds. Zero is displayed when explicitly reported. If numeric data is unavailable, the label shows `AGGRO` only while Blizzard's existing aggro highlight is shown; otherwise it stays empty.

Threat list/situation events refresh matching plates. Player/alias or protected event tokens refresh known public active tokens without comparing protected tokens. Target changes refresh active plates. No timer polling is added. Removal clears text and unit identity; reused frames read the new unit. Name-only plates hide the label. Disabling the setting clears labels and stops threat reads.

Research reviewed 2026-09-24: a [Forever player requested numeric threat because they are colorblind](https://www.reddit.com/r/classicwow/comments/1wn4jbq/top_addons_for_forever/). This is community demand, not a claim that every build exposes readable numbers. The exact-build [Unit API](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua) may return nothing or protected threat values; [FontString.SetFormattedText](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleFontStringAPIDocumentation.lua) permits protected arguments from addon code. Protected percentages go directly to that sink, without arithmetic, comparisons or saved-variable storage. Read or sink failures clear stale percentages.

Automated fixtures cover plain/zero/protected values, malformed results, reader/sink failure, event filtering, fallback warning, name-only visibility, disabled reads and pooled-unit cleanup. Native/game-client acceptance is supplied by the user; these fixtures are not native rendering observations.

## Animations

- Health eases to its new value (`ExponentialEaseOut`). A pooled plate's first
  fill is immediate so it does not sweep from the previous unit's health.
- In that same health update, the lost portion flashes red (0.18s) and the
  gained portion glows green (0.4s). Native clipping between previous/current
  fill boundaries selects the visible region, including for secret values.
  Unchanged health has no visible region. This matches all custom unit frames
  and includes passive regeneration. Combat events cannot trigger a late cue.
  Removal/reuse stops both fades and clears the baseline.
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
  frames use. Blizzard's fill texture is faded to alpha zero. Two transparent
  native StatusBars receive previous/current opaque values. Red is clipped to
  the old fill outside the new fill, and green to the new fill outside the old.
  Both fades start in the same sink call as the visible bar; native clipping
  selects direction without Lua arithmetic, comparisons or geometry readback.
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
  through the shared factory in `src/modules/auras/auras.lua`.

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
Adaptive sizing changes the name decoration. Health bar width, click geometry
and native stacking stay under the client's control. Tank-style threat
colouring would need threat values addon code cannot read.

## Diagnostics

`/rik debug` prints `Nameplates skinned=<n> active=<n> containers=<n>`.

## Verification

`tests/nameplates.test.lua` builds fake plates with the reviewed region names, an
`UpdateAnchors` that restores the stock look, recorders for animation groups
and a fake `C_CVar`. It proves: the three client settings written with the
originals saved; the own bar, faded fill, 14px height and pixel backing;
secret health reaching the bar with an immediate first fill; bar colour; the
name centred in a plaque as wide as the bar and level box that follows the
name's shown state; the centred percent texts; the elite marker, a classification change and
a secret classification; the fade-in; the level box; eased health without an ambiguous flash;
simultaneous clipped green gain/red loss cues, cancellation and pooled cleanup; other and secret tokens
ignored; arrows, accent line and pulse following `selectedBorder` without
restarting on a repeat; their anchors; the blanked flare and the threat line
following `aggroHighlight`; the flat cast bar with its fill untouched; the
layout surviving a layout pass; the name-only case; the debuff container, its
fade of the stock list, removal and pooled reuse without new hooks; a
forbidden plate; a plate missing every optional region; the debug line; a
combat login deferring the settings and the container; a client without the
container template; a disabled module restoring the saved settings. Adaptive
label regressions also cover padded expansion, bounds, shrinking, unavailable
or protected measurements, and live setters. Profile-sharing regressions
validate and round-trip the mode and both bounds.

Native gameplay is accepted under the user's standing policy. Stub tests and
Lua renders provide automated and visual evidence, without claiming an
agent-observed native playtest. Readable geometry and classification coverage
may vary with the client's protected values; guarded fallbacks preserve the
fixed row and omit unavailable classification markers.

## Source evidence

Adaptive label work reviewed 2026-10-01 against the latest Forever head,
[1.60.1 (70170)](https://github.com/Gethe/wow-ui-source/commit/9a789c074b8e73c5d604ef2d6af3bb5b3aefb348),
matching the installed executable. The current `CompactUnitFrame_UpdateName`
still sets the native FontString, and the current nameplate anchors, health
bar, badge and native hit-area layout remain the owning surfaces. This is
review provenance, not a client target; resolve current source before future work.

Original implementation evidence, retained as historical review: Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_NamePlates.toc: the shared files plus the Camelot level frame, constants and option overrides](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlates.toc)
- [Blizzard_NamePlates.xml: BaseNamePlateUnitFrameTemplate's region names](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlates.xml)
- [Blizzard_NamePlateUnitFrame.lua: UpdateAnchors, UpdateIsTarget and UpdateAggroHighlight](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlateUnitFrame.lua)
- [Blizzard_NamePlateHealthBar.lua: UpdateSelectionBorder and the info display bitfield](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlateHealthBar.lua)
- [Blizzard_NamePlateCastingBar.lua: ApplyStyleAndAnchoring and the cast bar regions](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlateCastingBar.lua)
- [Camelot/Blizzard_NamePlateFrameOptionsOverrides.lua: the classification indicator switched off](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Camelot/Blizzard_NamePlateFrameOptionsOverrides.lua)
- [Camelot/Blizzard_NamePlateConstants.lua: the nameplate CVar names](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Camelot/Blizzard_NamePlateConstants.lua)
- [Camelot/Blizzard_NamePlateLevelFrame.xml: playerLevelDiffText and the badge art](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_NamePlates/Camelot/Blizzard_NamePlateLevelFrame.xml)
