# Auras

`src/modules/auras/auras.lua`, `src/modules/auras/auras-button.lua` and `src/modules/auras/auras-units.lua` show player buffs,
debuffs and weapon enchants at the top right, and target and pet auras above
their unit frames. The rows are Blizzard aura containers wearing RikUI's flat
skin: the client reads the auras and updates the icons in secure code, RikUI
only configures the containers once. Disable the `auras` module in
`/rik config` and reload to get the Blizzard buff frames back; disable
`unitauras` to drop the target and pet rows.

## Why a Blizzard container

On build 69913 every `C_UnitAuras` read throws for addon code while auras are
secret, which means during combat:

```
GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'RikUI'
```

A hand-rolled aura row therefore freezes or stays empty exactly when a
target's debuffs matter. Blizzard ships `Blizzard_AuraContainer` with
`CustomAuraContainerTemplate`, an aura container that addons may create
(`allowUntaintedCreation`), and `CustomAuraButtonTemplate`, an `AuraButton`
whose public API takes regions we supply and updates them through secret
aspects. The container registers `UNIT_AURA` for its unit itself, parses the
auras in the secure environment, assigns them to buttons, lays the buttons out
and sizes itself. RikUI never sees an aura value.

## What you see

Each aura is a 30 px icon with a 1 px border, the stack count in the bottom
right corner and a cooldown swipe with the client's own countdown number.
Buffs keep the neutral border; debuff borders take the client's dispel
colours (Magic blue, Curse purple, Disease brown, Poison green, anything else
red). Player icons fill from the right edge, eight per line: the buff row
holds four lines (32 auras), the debuff row two (16). Temporary weapon
enchants (main hand, off hand, ranged) take the first buff slots with the
weapon's icon and the remaining charges as the count.

Hovering an icon shows the client's aura tooltip. Right-clicking a player
buff or enchant cancels it; the button does that in secure code, so it works
in combat too.

Target auras sit directly above the target frame and fill left to right,
upward, one frame width (220 px) per line: your own debuffs first at full
size, other casters' debuffs after them at 22 px and half alpha, then a new
line with your own buffs on the target and, dimmed, everyone else's. The pet
frame carries the same two debuff groups at 22 px above it.

## How the pieces fit

- `auras.CreateContainer(name, parent, unit, flow)` creates the container,
  turns off its Edit Mode preview, sets the unit and the flow layout (anchor
  corner, growth directions from `AnchorUtil.FlowDirection`, maximum line
  size). It returns nil and prints one `Auras container` line when the client
  lacks the template, in which case nothing else is created and the Blizzard
  frames stay.
- `container:AddAuraGroup(key, filter, options)` adds one group per row with
  a filter string (`HELPFUL`, `HARMFUL`, and `|PLAYER` or `|!PLAYER` for own
  versus other casters), `maxFrameCount`, the flow layout options
  (`elementSpacing`, `lineSpacing`, `groupSpacing`, `elementWidth`,
  `elementHeight`, `forceNewLine`) and the decorator as `initializeFrame`.
  `AddItemEnchantment` adds the three weapon slots with the same decorator and
  `SetItemEnchantmentLayout` spaces them like a group.
- `auras.Decorator(spec)` returns the `initializeFrame` callback. The client
  creates buttons in batches of ten and calls it once per button, possibly in
  combat, before the button becomes inaccessible to addon code. The callback
  sizes the button, sets its alpha for dim groups, and creates the background,
  the icon (`SetIcon`), the four border lines (registered through
  `AddDispelTypeTexture` with the `PreserveAsset` style for debuffs, static
  neutral colour for buffs), a `Cooldown` child with countdown numbers
  (`SetDurationCooldown`) and the count FontString on an overlay above the
  swipe (`SetApplicationCount`). Player buffs and enchants get
  `SetCancelAuraButtons("RightButtonUp")`. Every region is a descendant of the
  button, which the client requires. Any failure prints one `Auras button`
  line.
- After `PLAYER_ENTERING_WORLD` the client denies tainted access to the
  buttons while auras are secret, so RikUI never touches a button after its
  decorator ran. It also never installs scripts on them: the `AuraButton`
  handles tooltip and click itself and forbids untrusted scripts.

## Layout

The player rows are plain proxy frames with the row's nominal footprint
(268x132 for buffs, 268x64 for debuffs) registered with the
[shared layout](layout.md) under `buffs` and `debuffs`, so `/rik move`,
`/rik move reset`, `/rik scale`, Apply and Undo include them and the mover
box has a stable size. The container is a child of the proxy anchored to its
top right corner and sizes itself to the visible auras. Defaults sit at the
top right of the screen, left of the minimap cluster (`x=-200, y=-13`) with
the debuff row directly under the four buff lines (`y=-149`).

The proxy exists because adding a group marks the container with the
`UntrustedLayoutScriptExecution` forbidden aspect and the layout module hooks
`OnSizeChanged` on every frame it registers.

Target and pet containers are children of the secure unit buttons anchored
`BOTTOMLEFT` to the frame's `TOPLEFT` four pixels up, so they hide with the
frame's visibility driver and follow it in `/rik move` and `/rik scale`. With
the `unitframes` module disabled there is nothing to attach to and the module
prints one `Unit auras attach` line.

The focus frame has a third container: own debuffs at 26 pixels, then other
casters' debuffs and buffs at 22, eight each, 160 wide. It starts 30 pixels
above the frame because the [focus cast bar](castbars.md) takes the space in
between. `PLAYER_FOCUS_CHANGED` refreshes it.

## Events

The containers register `UNIT_AURA` for their own unit. A unit token that now
names a different unit needs a full refresh, as Blizzard's target frame does,
so `PLAYER_TARGET_CHANGED` calls `UpdateAllAuras` on the target container and
`UNIT_PET` for the player (or a secret unit token) on the pet container. A
refused call prints one `Unit auras refresh` line. `PLAYER_ENTERING_WORLD`
rechecks the stock frames.

## Stock frames

Once both player containers exist and the module is enabled, `BuffFrame` and
`DebuffFrame` are parked through `RikUI.Hide.Frame(frame, false)`: their
events are unregistered until reload. Hiding happens only out of combat.
Missing globals are ignored.

## Diagnostics

`/rik debug` prints `Auras containers=<n> combat=<bool>`, the secrecy of
`ShouldAurasBeSecret()`, the `GetAuraDataByIndex(player,1,HELPFUL)` sample
(which reports the taint error in combat; that is expected and is the reason
for the container) and `Unit auras containers=<n>` with the target sample.

## Verification

The LuaJIT suites use a fake of the container and button
(`tests/aura_stub.lua`) that validates filter strings and options, creates
buttons through `initializeFrame` like the client and records every call.
`tests/auras.test.lua` proves: proxies registered at the top right with the
nominal footprint; containers from the template as proxy children with unit
player, preview off and a right-to-left, downward flow of 268 px lines; the
HELPFUL group of 32 after the three enchant slots and the HARMFUL group of
16 with 4 px spacing and 30 px elements; the decorator registering icon,
count (on an overlay above the cooldown), cooldown with countdown numbers,
four dispel-typed border lines for debuffs and a neutral border for buffs,
right-click cancel on buffs and enchants only, no scripts; zero `C_UnitAuras`
calls; stock frames parked; the missing-template fallback; combat-login
deferral; module disablement; missing stock globals.
`tests/auras-units.test.lua` proves the containers under the target and pet
frames, their anchoring and flow, the four target groups and two pet groups
with their filter strings, sizes, alphas and counts, no cancel buttons, the
refresh calls on target and pet changes, a refused refresh warning once,
coexistence with the player module, missing unit frames and the fallback.

The stub cannot show native rendering, the countdown numbers or combat
updates. Beta checklist on the Warrior:

1. Reload out of combat. The Blizzard buff and debuff frames should be gone,
   your buffs should appear top right with icons, borders and countdown
   numbers, and `/rik debug` should print `Auras containers=2` and
   `Unit auras containers=3` with no `Auras container` or `Auras button`
   line.
2. Cast Battle Shout and right-click it: it should be cancelled. Apply a
   sharpening stone: it should appear as the first buff with a countdown.
3. Target a mob and fight it. Rend and Sunder Armor should appear above the
   target frame at full size with countdown and stack count, the mob's own
   buffs smaller and dimmer on the line above, and your Battle Shout should
   keep updating top right during the fight. Swap targets and clear the
   target: the rows should follow. No red `RikUI:` line should print.
4. `/rik move`: drag both player rows, lock, reload and confirm positions.
   Disable `auras` in `/rik config`, reload, and confirm the Blizzard frames
   return; disable `unitauras` and confirm the target rows go.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [CustomAuraContainerTemplate: options, validation, flow layout, access restrictions](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua)
- [Container template marked for untainted creation](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraContainer.xml)
- [CustomAuraButton region API and secret aspects](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_AuraContainer/Blizzard_CustomAuraButton.lua)
- [AuraButton tooltip, cancel clicks and forbidden aspects](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraButton.lua)
- [Frame provider: batches, initializeFrame, deferred access restriction](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainerFrameProviders.lua)
- [Defaults, enums and the DenyTaintedAccessWhenAurasAreSecret restriction](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainerShared.lua)
- [Flow layout semantics](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SharedXMLBase/AnchorUtil.lua)
- [Aura filter strings and negation](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXMLUtil/AuraUtil.lua)
- [Secret predicates: SecretWhenUnitAuraRestricted](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/SecretPredicatesDocumentation.lua)
