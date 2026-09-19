# Unit frames

`unitframes.lua` and `unitframes-status.lua` replace the Blizzard player,
target, target-of-target and pet frames with flat frames that never branch on
a unit value. Disable the `unitframes` module in `/rik config` and reload to
get the Blizzard frames back.

## What you see

Each frame is a health bar over a power bar. The health bar carries the unit
name on the left and `current / max` on the right; the power bar carries the
level on the left and, on the two large frames, `current / max` on the right.
No frame shows a percent: on this beta the player's own health and the
target's health are secret values, and a percent cannot be computed from them.

Health bars are class-coloured for players and reaction-coloured for NPCs.
Tapped units are grey-blue, disconnected units grey. Power bars use the
Blizzard colour for the unit's power token. When any of those reads is secret
or fails, the bar falls back to a neutral grey rather than guessing.

A 2-pixel threat border surrounds a frame when the client reports a readable
threat status above zero, coloured by `GetThreatStatusColor`. The player and
pet frames ask for that unit's own status; the target and ToT frames ask for
the player's status against that unit. When threat data
is secret, nil or zero the border stays hidden; nothing else changes.

Left click targets the unit and right click opens the unit menu. The frames
are `SecureUnitButtonTemplate` buttons with `*type1 = target`,
`*type2 = togglemenu` and the `unit` attribute, so the client handles both
clicks securely. Target, ToT and pet frames show and hide through
`RegisterStateDriver` visibility conditions (`[@target,exists]`,
`[@targettarget,exists]`, `[@pet,exists]`), the same mechanism the pet bar
uses and which was verified in combat on build 69913.

Hovering a frame shows the unit's tooltip the way the stock frames did:
`OnEnter` asks for the default anchor (so the [tooltip module](tooltip.md)
places and skins it) and calls `GameTooltip:SetUnit`, the frame's
`UpdateTooltip` method lets `GameTooltip_OnUpdate` refresh it while hovered,
and `OnLeave` hides it. A failing `SetUnit` prints one `Unit frames tooltip`
line. Neither script is protected, so hover works in combat.

## Layout

The frames register with the [shared layout](layout.md) under the keys
`player`, `target`, `tot` and `petframe` (`pet` belongs to the pet action
row), so `/rik move`, `/rik move reset`,
`/rik scale`, Apply and Undo include them. Defaults sit centre-bottom above
the bar stack and the stance/pet rows: player left (`x=-140, y=300`), target
right (`x=140, y=300`), ToT to the right of the target (`x=313`), pet to the
left of the player (`x=-313`). The large frames are 220x44 and the small ones
110x30. The [castbars](castbars.md) sit directly under the player and target
frames.

## Party frames

`unitframes-party.lua` builds four fixed frames for `party1` to `party4`
through the same factory (`UnitFrames.Build`), so clicks, tooltips, colours,
threat and the secret rules match the player frame. There is no
`SecureGroupHeaderTemplate`: its `initialConfigFunction` is a secure snippet,
and snippets cannot run on build 69913. They are part of the `unitframes`
module and turn off with it.

The frames are 150x36 and sit in one `RikUIParty` holder registered with the
layout under the key `party`, default `LEFT` of the screen at `x=20, y=0`, so
one mover carries the stack. Each frame's visibility driver is
`[group:raid] hide; [@partyN,exists] show; hide`: one frame per member, none
solo, none in a raid. The health bar has no `current / max` text at this size.

A leader icon sits at the right of the health bar and a role letter (`T`,
`H`, `D`) at the right of the power bar. `UnitIsGroupLeader` and
`UnitGroupRolesAssigned` are `pcall`-read; a secret leader flag goes
uncompared into `Texture:SetAlphaFromBoolean(flag, 1, 0)`, and a secret or
unassigned role shows no letter.

Range is polled every 0.5 seconds with `UnitInRange` inside `pcall`
(`UNIT_IN_RANGE_UPDATE` carries secret payloads, so it is not used). A
readable result fades the frame to 0.45 alpha only when the range was checked
and the member is out of range. The pinned documentation marks the returns as
secret-capable; a secret result goes into
`Frame:SetAlphaFromBoolean(inRange, 1, 0.45)`, which accepts secrets from
addon code. In that case the `checkedRange` flag cannot be honoured. A failing
read leaves the frame opaque and prints one `Unit frames range` line.

`GROUP_ROSTER_UPDATE` refreshes every member, `PARTY_LEADER_CHANGED` the
icons. `PartyFrame` and `CompactPartyFrame` (the raid-style party option) are
parked through `RikUI.Hide.Frame(frame, false)` once the RikUI frames exist,
and rechecked on roster updates and `PLAYER_ENTERING_WORLD`.

To look at the frames solo, run `/rik party test` out of combat. All four
frames take the `player` unit and a forced-show driver, so the bars, name,
clicks, tooltip and `/rik move` work with real data. The first frame shows
the leader icon and the last one the 0.45 fade as previews, since you are
never your own leader or out of your own range. Run it again to restore the
`partyN` units and the real drivers; a reload also leaves test mode. It
cannot exercise the raid condition, roster events or real range results.

`tests/unitframes-party.test.lua` covers the test mode toggle and the build, attributes, drivers,
layout default, stacking, sinks, leader and role in readable and secret form,
the four range cases, the poll interval, roster and leader events, threat,
zero protected writes in combat, parking, combat login, the disabled module
and missing stock globals. Beta checklist: join a party and confirm one frame
per member on the left edge, left and right click, the leader icon, the fade
when a member runs off, no frames after converting to a raid, no Blizzard
party frame, and no `Could not register event` line at login.

## Secret rules

- `UnitHealth`, `UnitHealthMax`, `UnitPower` and `UnitPowerMax` are read
  through `RikUI.Secret.Apply` and land only in `StatusBar:SetMinMaxValues`,
  `StatusBar:SetValue` and `FontString:SetFormattedText("%d / %d", ...)`. The
  pinned API documentation marks those sinks as accepting secret arguments.
- `UnitName` goes straight into `SetText`; `UnitLevel` into
  `SetFormattedText("%d")` unless it is a readable non-positive number, which
  shows `??`.
- `UnitIsPlayer`, `UnitClass` (the class token), `UnitReaction`,
  `UnitIsConnected`, `UnitIsTapDenied`, `UnitPowerType` (the power token) and
  `UnitThreatSituation` are the only values the module compares. Each read is
  `pcall`-wrapped and checked with `issecretvalue` first; a secret or failed
  read uses the neutral colour or hides the threat border.
- Every event handler filters by the event's unit token; a secret token
  refreshes every frame instead of comparing.
- The target-of-target frame also polls every 0.5 seconds while shown, as
  Blizzard's does, because its unit events are not reliable.

Frame creation, attribute writes and stock-frame parking run through the
combat queue. Bar fills, text and colours are not protected and update during
combat.

## Stock frames

Once all four RikUI frames exist and the module is enabled, `PlayerFrame`,
`TargetFrame`, `PetFrame` and `TargetFrameToT` (falling back to
`TargetFrame.totFrame`) are parked through `RikUI.Hide.Frame(frame, false)`:
no native handler needs to keep running for these units, so their events are
unregistered until reload. Hiding happens only out of combat and after
`PLAYER_ENTERING_WORLD` rechecks. Missing globals are ignored.

## Diagnostics

`/rik debug` reports the secrecy of `UnitHealth(player)`, `UnitPower(player)`,
`UnitHealth(target)`, `UnitClass(target)`, `UnitReaction(target)` and
`UnitThreatSituation(player)`. Reader failures print one `Unit frames ...`
line per operation.

## Verification

The LuaJIT suite (`tests/unitframes.test.lua`) uses a recording renderer to
prove that secret sentinel values reach the bar and text sinks unchanged, that
no percent format exists, class/reaction/tapped/disconnected/power colours and
their neutral fallbacks, threat border colour for readable status and hidden
for secret/zero/nil, the secure attributes and click registration, layout keys
and default anchors, visibility drivers, per-unit event filtering, ToT polling,
pet and target-change refreshes, zero protected writes during combat events,
combat-login deferral, module disablement, stock-frame parking with events
dropped, missing stock globals and the debug report.

The stub cannot show native rendering, the popup menu or secret-value errors
inside the real VM. Beta checklist on the Warrior:

1. Reload out of combat. The Blizzard player, target and pet frames should be
   gone and the RikUI player frame visible above the bars with name, level and
   `current / max` text and a class-coloured health bar. Run `/rik debug` and
   confirm the six `unitframes.*` lines print with no Lua error.
2. Target a hostile NPC, a friendly NPC and another player. The target frame
   should appear with reaction or class colour and the ToT frame with the
   target's target. Left click each frame to target, right click for the menu.
3. Fight a mob. Health and power bars should fill and empty for player and
   target during combat, the target's threat border should appear when you
   hold aggro, and no secret-value or protected-action error should print.
4. `/rik move`: drag all four frames, lock, reload and confirm positions.
   `/rik move reset` restores the defaults. Disable the module in
   `/rik config`, reload, and confirm the Blizzard frames return.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [SecureUnitButtonTemplate and click handling](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua)
- [Unit API and event documentation, secret annotations](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua)
- [StatusBar sinks accept secret values](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleStatusBarAPIDocumentation.lua)
- [Threat colour API](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/ThreatDocumentation.lua)
- [Blizzard target and ToT frames](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UnitFrame/Mainline/TargetFrame.lua)
