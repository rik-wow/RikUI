# Castbars

`castbars.lua` and `castbars-status.lua` replace the Blizzard player casting
bar with a flat bar under the player frame and add a second one under the
target frame. Disable the `castbars` module in `/rik config` and reload to get
the Blizzard casting bar back.

## What you see

Each bar is a spell icon on the left, a fill with the spell name on the left
and the remaining time on the right. Casts fill up in gold, channels drain in
blue. An interrupted or failed cast turns red, says `Interrupted` or `Failed`
and disappears after a short hold. The target bar also carries a shield
overlay on the icon while the cast cannot be interrupted.

The bars are 220x22, sized to the large unit frames, and use the shared font
and statusbar media.

## Layout

Both bars register with the [shared layout](layout.md) under `castplayer` and
`casttarget`, so `/rik move`, `/rik move reset`, `/rik scale`, Apply and Undo
include them. Defaults sit directly under the player frame (`x=-140, y=272`)
and the target frame (`x=140, y=272`). To make room, the pet frame default now
sits to the left of the player frame (`x=-313, y=300`), mirroring the
target-of-target frame on the right.

Two smaller bars follow the same rules. `castpet` (110 wide) sits under the pet
frame at `x=-313, y=272`. `castfocus` (160 wide, with the shield) sits above the
focus frame at `x=-340, y=380`: under the focus frame the pet frame is in the
way. The focus aura row starts above that bar, which leaves a 26 pixel band
empty while the focus is not casting. `PLAYER_FOCUS_CHANGED` re-reads the focus
cast and `UNIT_PET` for the player re-reads the pet cast.

## Secret rules

On this beta the client documents `UnitCastingInfo` and `UnitChannelInfo` as
secret whenever the unit is not the player or their pet, so every value about
the target's cast (name, icon, start and end time, cast ID, interruptibility)
may be a secret value. The module never subtracts, compares or formats those
values in Lua:

- The fill comes from `UnitCastingDuration(unit)` or
  `UnitChannelDuration(unit)`, the client's duration object, fed into
  `StatusBar:SetTimerDuration` with `ElapsedTime` for casts and
  `RemainingTime` for channels. The remaining-time text is a
  `C_DurationUtil.CreateDurationTextBinding` driven by a
  `C_StringUtil.CreateSecondsFormatter` formatter. Neither path reads a
  number back.
- If the duration API is missing or returns nothing, readable start and end
  times drive a plain `OnUpdate` fill and a `%.1f` remaining text. If the
  times are secret and there is no duration object, the bar shows full with
  the name and icon and prints one `Castbars fill` warning.
- The display name goes straight into `SetText`, the icon into `SetTexture`,
  and `notInterruptible` into the shield's `SetAlphaFromBoolean`, the three
  sinks the pinned API documentation marks as accepting secret arguments from
  addon code. `UNIT_SPELLCAST_INTERRUPTIBLE` and `NOT_INTERRUPTIBLE`, which
  carry only the unit, update the shield afterwards.
- `UNIT_SPELLCAST_STOP` and `FAILED` compare the event's cast ID with the
  bar's only when both are readable strings; otherwise the event applies to
  the current cast. A channel stop reports `Interrupted` only when
  `interruptedBy` is a readable non-empty string.
- Every event handler filters by the event's unit token; a secret token makes
  both bars re-read their own cast instead of comparing.

Frame creation, anchoring and stock-frame parking run through the combat
queue. Bar fills, text, colours and visibility are not protected and update
during combat.

## Stock frames

Once both RikUI bars exist and the module is enabled, `PlayerCastingBarFrame`
(and `CastingBarFrame` when a build defines it) is parked through
`RikUI.Hide.Frame(frame, false)`: its events are unregistered until reload.
Hiding happens only out of combat and after `PLAYER_ENTERING_WORLD` rechecks.
Missing globals are ignored. The Blizzard target spell bar is a child of the
already parked `TargetFrame`, and the focus spell bar of the parked
`FocusFrame`. `PetCastingBarFrame` hangs off `UIParent` on 69913, so parking
`PetFrame` left it on screen; it is parked here with the player bar.

## Diagnostics

`/rik debug` reports the secrecy of `UnitCastingInfo(player)`,
`UnitCastingInfo(target)` and `UnitCastingDuration(target)`. Reader failures
print one `Castbars ...` line per operation.

## Verification

The LuaJIT suite (`tests/castbars.test.lua`) uses a recording renderer to
prove: layout keys and defaults under the unit frames with the pet frame moved
beside the player; icon, name and cast colour on start; the duration object
and direction handed to `SetTimerDuration` for casts, channels, delays and
channel updates; the text binding configured, fed and disabled; cast-ID
matching on stop and failure; the red interrupted and failed hold and its
cancellation by a new cast; channel interruption versus completion; secret
target values reaching the sinks unchanged without a printed error; shield
events; target-change resync for casts and channels; the secret event unit
fallback; zero protected writes during combat events; one contained reader
failure; the debug report; the readable-time fallback fill, its clamp and the
secret-time full bar with one warning; a secret duration value treated as
unavailable; combat-login deferral; module disablement; stock parking and
missing stock globals.

The stub cannot show native timer rendering, the text binding output or
secret-value errors inside the real VM. Beta checklist on the Warrior:

1. Reload out of combat. The Blizzard casting bar should be gone. Cast a
   spell with a cast time (Hearthstone works): a gold bar with the icon, name
   and a counting-down time should appear under the player frame and fill to
   the end, then vanish. Run `/rik debug` and confirm the three `castbars.*`
   lines print with no Lua error.
2. Move during the cast: the bar should turn red, say `Interrupted` and hide.
   Channel a spell (bandage) and confirm the blue bar drains.
3. Target a casting NPC in combat. The bar under the target frame should show
   its icon and name and fill; when the NPC's cast cannot be interrupted the
   icon should carry the shield overlay. No secret-value or comparison error
   should print. If the bar shows full with a `Castbars fill` warning, the
   duration API returned nothing for that unit; report the debug output.
4. `/rik move`: drag both bars, lock, reload and confirm positions. Disable
   the module in `/rik config`, reload, and confirm the Blizzard casting bar
   returns.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Cast API, duration objects and cast events](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua)
- [Secret predicate definitions](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicatesDocumentation.lua)
- [StatusBar timer duration sink](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleStatusBarAPIDocumentation.lua)
- [Duration text binding](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/DurationTextBindingObjectAPIDocumentation.lua)
- [Blizzard aura button using the same sinks](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraButton.lua)
- [Blizzard casting bar](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Shared/CastingBarFrame.lua)
