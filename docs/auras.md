# Player auras

`auras.lua` and `auras-status.lua` replace the Blizzard buff and debuff
frames with two flat rows of icons at the top right: buffs (and temporary
weapon enchants) first, debuffs beneath. Disable the `auras` module in
`/rik config` and reload to get the Blizzard frames back.

## What you see

Each aura is a 30 px icon with a 1 px border, the stack count in the bottom
right corner and a cooldown swipe with the client's own countdown number.
Buffs keep the neutral border; debuffs are bordered in the Blizzard dispel
colours (Magic blue, Curse purple, Disease brown, Poison green, anything else
red). Icons fill from the right edge, eight per line: the buff row has four
lines (32 slots), the debuff row two (16 slots). Temporary weapon enchants
(main hand, off hand, ranged) take the first buff slots with the weapon's
icon and the remaining charges as the count.

Hovering an icon shows the aura tooltip (`GameTooltip:SetUnitAura`) or the
item tooltip for an enchant. Right-clicking a buff out of combat cancels it.

## Layout

Both rows register with the [shared layout](layout.md) under `buffs` and
`debuffs`, so `/rik move`, `/rik move reset`, `/rik scale`, Apply and Undo
include them. Defaults sit at the top right of the screen, left of the
minimap cluster (`x=-200, y=-13`) with the debuff row directly under the
four buff lines (`y=-149`).

## Secret rules

The client documents every `C_UnitAuras` read as secret while unit auras are
restricted, and the addon kit reports player auras unreadable in combat on an
earlier beta build. The module never subtracts, compares or formats an aura
value unless `issecretvalue` says it is readable:

- Every row refresh reads `C_UnitAuras.GetAuraDataByIndex("player", i, filter)`
  inside one `pcall`. If a read throws or returns a secret record, the row
  keeps its last display, sets a blocked flag and prints one `Auras read`
  line. `PLAYER_REGEN_ENABLED` re-reads a blocked row; `/rik debug` reports
  the flag.
- The icon goes straight into `SetTexture`. The count comes from
  `C_UnitAuras.GetAuraApplicationDisplayCount`, which formats the number and
  applies the minimum of two in the client, so a secret count still displays
  through `SetText`. Without that API a readable `applications` of two or
  more is formatted; a secret one shows nothing.
- The timer is the aura's duration object from `C_UnitAuras.GetAuraDuration`
  fed into `Cooldown:SetCooldownFromDurationObject`, the same sink the action
  bars use. When no object is available, readable `duration` and
  `expirationTime` drive `Cooldown:SetCooldown(expirationTime - duration,
  duration)`; otherwise the swipe is cleared. A secret `auraInstanceID` never
  reaches `GetAuraDuration` or `GetAuraApplicationDisplayCount`, because both
  refuse secret arguments from addon code.
- The border colour uses `dispelName` only when it is a readable string.
- Weapon enchants come from `C_PaperDollInfo.GetTemporaryEnchantmentInfo`.
  The client reports only the remaining time, so the duration is the
  remaining time seen when an enchant first appears or is refreshed, as
  Blizzard's own aura container does; a permanent enchant shows no swipe.
- `UNIT_AURA` handlers filter by the event's unit token; a secret token
  refreshes both rows instead of comparing.

## Cancel layer

Cancelling a buff needs secure code. `C_UnitAuras.CancelAuraByInstanceID`
and `CancelUnitBuff` are restricted, so each buff slot carries a
`SecureActionButtonTemplate` button with `type2 = cancelaura` over its
display button. After every refresh the module copies the slot's aura index
and filter (or the inventory slot for an enchant) into the button's
attributes and shows or hides it, always through the combat queue.

Protected frames cannot be shown, hidden or moved by addon code during
combat, so the cancel layer's parent has a `[combat] hide; show` visibility
driver: in combat the layer disappears, the plain display buttons underneath
keep redrawing and answer the tooltip, and the pending attribute sync runs
when combat ends. Out of combat the cancel buttons sit on top and take the
right click.

The build's `cancelaura` action only cancels a weapon enchant when the
client's `CANCELABLE_ITEMS` table accepts the slot, and that table is
referenced but not defined in the 69913 interface source. The module sets
`target-slot` anyway; if right-click does nothing on an enchant, that is the
client, and the Blizzard character pane remains the way to remove it.

## Stock frames

Once both rows exist and the module is enabled, `BuffFrame` and
`DebuffFrame` are parked through `RikUI.Hide.Frame(frame, false)`: their
events are unregistered until reload. Hiding happens only out of combat and
after `PLAYER_ENTERING_WORLD` rechecks. Missing globals are ignored.

## Diagnostics

`/rik debug` prints `Auras blocked=<bool> combat=<bool>` and the secrecy of
`GetAuraDataByIndex(player,1,HELPFUL)`, `ShouldAurasBeSecret()` and, when the
first buff's instance ID is readable, `GetAuraDuration(player, first buff)`.
Reader failures print one `Auras ...` line per operation.

## Verification

The LuaJIT suite (`tests/auras.test.lua`) uses a recording renderer to
prove: plain rows with 32 and 16 display buttons and top-right layout
defaults; the cancel layer as a child of the buff row with the combat driver
and secure `cancelaura` buttons anchored over their display buttons; stock
frames parked with events dropped; icons, duration-object timers, client
display counts and the readable fallbacks for both; neutral buff borders and
dispel-coloured debuff borders; secret icon, count, instance ID, dispel type
and times reaching the sinks with no printed error and no secret argument
passed to the duration or count APIs; one contained duration failure;
per-unit event filtering with the secret fallback; combat redraws without a
protected write; a throwing or secret read keeping the display and warning
once; the re-read and cancel sync after combat; weapon enchants with the
item icon, charges, snapshot duration, refresh and removal, and the
`target-slot` attribute; tooltips; the debug report; missing duration and
count APIs; combat-login deferral; module disablement; missing stock globals.

The stub cannot show native rendering, the countdown numbers, secure clicks
or secret-value errors inside the real VM. Beta checklist on the Warrior:

1. Reload out of combat. The Blizzard buff and debuff frames should be gone
   and your buffs should appear top right with icons, borders and countdown
   numbers. Run `/rik debug` and confirm the `Auras blocked=false` line and
   the three `auras.*` lines print with no Lua error.
2. Cast Battle Shout: the icon should appear with a swipe and countdown.
   Right-click it: the buff should be cancelled. Apply a sharpening stone or
   weightstone to your weapon: it should appear as the first buff icon with
   the weapon's icon and a countdown.
3. Fight a mob. Debuffs on you (a mob's Sunder, poison or disease) should
   appear in the lower row with a coloured border, buffs should keep
   updating, and no secret-value or protected-action error should print.
   If the rows freeze during combat and `/rik debug` shows
   `Auras blocked=true`, aura reads throw in combat on this build; report
   the debug output. The rows should refresh once combat ends.
4. `/rik move`: drag both rows, lock, reload and confirm positions. Disable
   the module in `/rik config`, reload, and confirm the Blizzard frames
   return.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Unit aura API and UNIT_AURA event with secret annotations](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua)
- [Cooldown duration-object sink](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameAPICooldownDocumentation.lua)
- [Temporary enchant info and cancel](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/PaperDollInfoDocumentation.lua)
- [cancelaura secure action](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/SecureTemplates.lua)
- [Blizzard aura button cancel path](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraButton.lua)
- [Blizzard enchant duration snapshot](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraContainerEnchantments.lua)
- [Blizzard buff frame events](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_BuffFrame/BuffFrame.lua)
