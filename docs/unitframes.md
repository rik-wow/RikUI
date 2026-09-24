# Unit frames

`src/modules/unitframes/unitframes.lua` and `src/modules/unitframes/unitframes-status.lua` replace the Blizzard player,
target, target-of-target, pet and focus frames with flat frames that never branch on
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

## Motion

Solo, party and raid frames use `src/modules/unitframes/unitframes-motion.lua` and
the shared `RikUI.Motion` helpers. Their first health and power fill is
immediate; subsequent updates use the client's `ExponentialEaseOut`
interpolation. Show and target, focus, pet or target-of-target replacement
events reset first-fill state. Failed reads clear the bar and feedback, and
the first successful recovery establishes a fresh baseline.

A visible frame fades in over 0.15 seconds. Health feedback starts in the
same sink call as the health bar's `SetValue`, including target-of-target
polling. The lost portion flashes red (0.18 seconds, 0.5 starting opacity);
the gained portion glows green (0.4 seconds, 0.28 starting opacity). The
main bar continues easing while the overlay fades. There is no combat-event
handler, delayed pairing, or snap-to-completion step.

Two transparent native StatusBars hold the previous and current targets.
The red overlay is clipped to the previous filled area and starts at the
current fill's right edge. Green reverses those bounds. Thus native clipping
shows only the lost or gained interval, with no visible interval for an
unchanged value. Lua starts both fades synchronously and never needs to
classify or compare the protected health values. Passive regeneration uses
the same green gain feedback. Rapid changes replace both regions with the
latest transition.

Initial fills, maximum-health refreshes, hidden frames and recycled units
establish a baseline without feedback. The previous opaque values are retained
only to feed native StatusBar sinks on the next update; resets clear them.
All helper frames are mouse-disabled and their anchors are built once.

The readable threat border pulses between full and 0.35 opacity every 0.6
seconds. Repeated threat refreshes keep the running pulse. Secret, absent or
zero threat stops it; hiding stops all effects. An appearance fade survives
a unit-change event arriving just after the show callback.

All values still travel directly from readers to sinks. Only local
presentation flags select interpolation; no health/power arithmetic,
comparison, GUID tracking or status-bar readback is added. Missing animation
groups or interpolation enums leave working static frames. Secure visibility,
attributes and positioning retain their existing owners.

Party and raid frames also fade out over 0.15 seconds when their secure
button hides. Their bars, text and borders live on a noninteractive sibling
under the group holder. The button disappears immediately, so departed
members cannot be clicked while their last presentation fades. Hidden member
events cannot overwrite that presentation. Rejoining cancels the departure,
refreshes values immediately and starts a new appearance fade. Roster refreshes
reset first-fill state for occupied slots without comparing GUIDs; readable
absent units retain their last bars until the secure driver hides the button.
Missing animation groups use immediate show/hide instead.

Presence and range use separate visual parents, so fading in does not erase
the out-of-range dim. Readable range changes tween over 0.15 seconds; unchanged
polls leave the running tween alone. The initial range and the first readable
range after a secret result apply immediately. Secret results cancel the range
tween and go directly to the presentation frame's boolean alpha sink; no alpha
is read back or used in arithmetic.

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

## Focus frame

Added 2026-09-20. A fifth frame shows your focus: 160 by 36, between the large
player and target frames and the small pet and target-of-target ones, with the
same health bar, power bar, name, level, colours, threat edge and tooltip,
because it is built by the same factory. It sits above the pet frame by
default on layout key `focus` and moves with `/rik move`.

It shows only while a focus exists (`[@focus,exists] show; hide`) and refreshes
on `PLAYER_FOCUS_CHANGED` plus the shared unit events. Left click targets the
focus, right click opens the unit menu, which holds Clear Focus. To set a
focus use the unit menu's Set Focus on any RikUI frame or a `/focus` macro;
both are Blizzard's. The stock `FocusFrame` is parked with the others.

A client that does not know `PLAYER_FOCUS_CHANGED` prints one
`Could not register event` line and everything else keeps working. The focus
cast bar is in [castbars](castbars.md) and the focus aura row in
[auras](auras.md).

Beta checklist: `/focus` a mob, check the frame appears above the pet frame
with name and health; hit the mob and watch the bar move; `/clearfocus` and
check it hides; confirm the stock focus frame is gone; try Set Focus from the
target frame's right-click menu and watch for "action blocked".

## Party frames

`src/modules/unitframes/unitframes-party.lua` builds four fixed frames for `party1` to `party4`
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
the visual `Frame:SetAlphaFromBoolean(inRange, 1, 0.45)`, which accepts secrets from
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

## Raid frames

`src/modules/unitframes/unitframes-raid.lua` builds forty fixed frames for `raid1` to `raid40` through
the same factory, so they get the same clicks, tooltips, class colours, threat
border and secret-safe sinks. There is no `SecureGroupHeaderTemplate`, for the
same reason as the party frames. That also fixes the order: slots follow the
raid index, five to a column and eight columns, not the subgroups. Sorting by
subgroup would mean re-pointing units when the roster changes in combat, and
only a secure header can do that.

Each slot is 72x30 with a 22px health bar, a 5px power bar and the name; level
and health text are hidden at this size. The slots sit in one `RikUIRaid`
holder registered with the layout under the key `raid`. Its default is the
party holder's position, which is free because the party frames hide in a
raid. Each slot's visibility driver is `[@raidN,exists] show; hide`, so the
grid shows only filled slots and empties itself when the raid ends, at which
point the party drivers show again.

Members out of range fade to `Raid.FadeAlpha` on the same 0.5 second poll.
The fade is `UnitFrames.FadeByRange`, shared with the party frames.
`GROUP_ROSTER_UPDATE` and `PLAYER_ENTERING_WORLD` refresh every slot.
`CompactRaidFrameContainer` is parked through `RikUI.Hide.Frame(frame, false)`
once the grid exists. `CompactRaidFrameManager` is left alone: it holds the
ready check, world markers and raid settings.

`tests/unitframes-raid.test.lua` covers the build, drivers, the layout key and
default, the grid geometry, sinks in readable and secret form, the range
cases and poll interval, unit and roster events, threat, zero protected writes
in combat, parking of the container only, combat login, the disabled module
and missing stock globals. None of this has been seen in a real raid yet.
Beta checklist: convert a party to a raid and confirm the party frames give
way to the grid, one slot per member, class colours, clicks, the fade, no
Blizzard raid frames, the raid manager still opens, and leaving the raid
brings back the party or solo state.

Run `/rik raid test` out of combat to show all 40 raid slots using your player unit, then use `/rik move` to arrange the grid. The final slot previews range fading. Run the command again to restore every raid token and visibility driver; reload also leaves preview. The toggle is refused during combat or before the grid exists. Preview displays player data and is not a simulation of raid membership.

Research reviewed 2026-09-24: [Forever players discussing frame previews and dragging](https://www.reddit.com/r/classicwow/comments/1wl16sa/classic_ui_now_configurable_through_edit_mode/). This is evidence of setup demand; the implementation follows the existing fixed-frame party preview and the pinned secure-button source below. Automated tests exercise all 40 retarget/restoration pairs, player events, range preview and zero protected writes on combat refusal. Native behavior is accepted by the user.

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

Once all five RikUI frames exist and the module is enabled, `PlayerFrame`,
`TargetFrame`, `PetFrame`, `FocusFrame` and `TargetFrameToT` (falling back to
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

`tests/unitframes.test.lua` and its `unitframes_motion_checks.lua` fixture
exercise immediate first fills, eased updates, unchanged secret-value sinks,
synchronous clipped healing/damage cues, hide/show cleanup, replacement/show event ordering,
reader failures and recovery, threat pulse transitions and missing APIs.
Existing secure click, tooltip, layout, event filtering, combat-update,
combat-login, disabled-module and stock-parking checks remain in place.
Party/raid fixtures share `group_motion_checks.lua` and a deterministic animation
double. They cover immediate/eased fills, separate heal/damage cues, range tween reuse and secret
fallback, departure/rejoin races, roster removal before secure hide, combat
callbacks and missing-animation fallbacks. Architecture checks enforce the
helper's manifest dependencies. `tests/health_feedback_geometry.lua` evaluates the
recorded native anchors and clipping intersections for loss, gain, unchanged
health, death, full healing, maximum changes and opaque-value forwarding.

Native/game-client behavior is accepted under the user's standing policy.
Automated results cover the Lua fixture and source contracts; they are not
agent-observed native rendering or gameplay evidence. Historical beta
checklists elsewhere in this document are reference scenarios, not delivery
requirements.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [SecureUnitButtonTemplate and click handling](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua)
- [Unit API and event documentation, secret annotations](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua)
- [StatusBar sinks accept secret values](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleStatusBarAPIDocumentation.lua)
- [Threat colour API](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/ThreatDocumentation.lua)
- [Blizzard target and ToT frames](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UnitFrame/Mainline/TargetFrame.lua)
