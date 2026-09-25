# Tooltips

**Show vendor unit and stack values** adds an item's vendor price and the value of a full stack at its maximum stack size. It defaults off, works without the bags module, and does not report auction prices or the currently hovered stack quantity. Missing, secret and zero prices are omitted; repeated tooltip processing updates one line.

Source reviewed 2026-09-24: [69913 item information return fields](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua).

**Show item IDs**, **Show spell IDs** and **Show item levels** independently control metadata on the next tooltip display. Item IDs default off; spell IDs and item levels preserve their existing on defaults. Shared profiles include these choices. Protected, missing, fractional or invalid IDs are omitted. Repeated processing updates an existing metadata row.

Research reviewed 2026-09-24: [Forever addon discussion](https://www.reddit.com/r/WowUI/comments/1wkfntp/wow_forever_working_addons_addon/) lists TooltipID for item/spell lookup. This is community usage, not proof of API coverage. RikUI reuses its existing TooltipDataProcessor data and does not infer unknown IDs.

**Tooltip size** scales styled tooltips from 75% to 150% of their original size,
independently of HUD scale. Changes apply immediately, including comparison
tooltips; newly loaded tooltips inherit the preference. Repeated shows do not
compound the scale. Shared text size also affects their fonts.


**Tooltips follow the cursor** uses Blizzard's cursor anchor. Turn it off to
return to the movable fixed tooltip position; the default is fixed.

**Show item ownership counts** adds carried/equipped and client-reported bank
quantities for the current character. It does not track alts or an account bank.
Unavailable or secret counts are omitted, and the option can be turned off.

Tooltips fade in over 180ms and cancel the entrance immediately when hidden. Existing native fade-out, ownership, data processing and GUID health watches remain intact. Motion is regression-tested; native acceptance is supplied by the user's standing policy.

`src/modules/tooltip/tooltip.lua` and `src/modules/tooltip/tooltip-data.lua` restyle the Blizzard tooltips instead of
replacing them: the client keeps building every line, RikUI moves the tooltip,
flattens the backdrop, swaps the font, colours the unit name and adds the two
numbers people always want, item level and spell ID. Disable the `tooltip`
module in `/rik config` and reload to get the stock tooltips back.

## What you see

Tooltips that ask for the default anchor appear bottom right, in a flat dark
box with a one-pixel border in the shared media, in the RikUI font. Unit
tooltips colour the name line by class for players and by reaction for NPCs
(the same colours as the unit frames; tapped units grey-blue, disconnected
units grey) and tint the guild line light blue. The health bar under a unit
tooltip uses the shared statusbar texture and the same colour as the name.
Item tooltips end with `Item level N`; spell tooltips end with `Spell ID N`.
Both lines are muted grey.

`Hide unit tooltips in combat` on the Tooltips options page (off by default,
saved as `Profile.tooltip.hideInCombat`) hides unit tooltips while you are in
combat. Item and spell tooltips are never hidden.

## Layout

The anchor is a plain 250x150 frame registered with the
[shared layout](layout.md) under `tooltip`, so `/rik move`, `/rik move reset`
and `/rik scale` apply to it. The default is `BOTTOMRIGHT` of the screen at
`x=-16, y=180`, above the space the micro menu and bag strip will take.
`GameTooltip_SetDefaultAnchor` is post-hooked: after Blizzard sets the owner
and its own corner anchor, the tooltip is re-pointed `BOTTOMRIGHT` to the
RikUI anchor. Tooltips anchored to the cursor or to a specific frame are not
touched.

## Secret rules

Nothing in the tooltip module reads a unit's health. On this beta
`UnitHealth` is secret for the player and the target at all times, so the
health bar under a unit tooltip is Blizzard's own `GameTooltip.StatusBar`
(`GameTooltipUnitHealthBarMixin`): `SetWatch(guid)` stores the GUID in an
attribute and the bar's secure mixin feeds `SetValue` from
`UnitPercentHealthFromGUID` on every update. The Blizzard source notes that
`SetWatch` and `ClearWatch` were written to be called from tainted code, and
no Blizzard Lua calls `SetWatch` itself, so the unit post-call does: once,
when the bar is hidden, with the GUID from the tooltip data. RikUI sets
`lockColor` so `HealthBar_OnValueChanged` stops recolouring the bar green and
tints it with the unit frame colour. The module never calls `SetValue` or
`SetMinMaxValues` on the bar.

Every other value is guarded before it is compared or formatted:

- The unit token comes from `UnitTokenFromGUID(tooltipData.guid)`, which the
  API documentation marks `SecretWhenUnitIdentityRestricted`. A secret token
  skips the name and guild colouring; the bar is still watched by GUID with a
  neutral colour.
- Name colouring reuses `RikUI.UnitFrames.HealthColor`, whose class, reaction,
  tapped and disconnected reads are each `pcall`ed and checked with
  `issecretvalue`; anything unreadable falls back to neutral grey.
- The guild line is tinted only when `GetGuildInfo` returns a readable string
  that appears in the second line's text.
- The item level comes from `C_Item.GetDetailedItemLevelInfo` on the tooltip
  data's hyperlink (or item ID); a secret, nil or zero level adds no line.
- The spell ID is `tooltipData.id`; a secret or missing ID adds no line.

All post-calls run under `pcall`; a failure prints one `Tooltip ...` line per
operation and never reaches the client's delegate. None of the writes are
protected, so everything above also runs in combat.

## Skin

`GameTooltip`, `ItemRefTooltip`, `ShoppingTooltip1` and `ShoppingTooltip2`,
plus the secondary instances found in the 69913 source
(`ItemRefShoppingTooltip1`/`2`, `EmbeddedItemTooltip`, `GameNoHeaderTooltip`,
`GameSmallHeaderTooltip`, `BuffFrameTooltip`, `AuraButtonTooltip`,
`PrivateAurasTooltip`, `LootHistoryExtraTooltip`, `QuickKeybindTooltip`,
`SettingsTooltip`), each skipped when the client lacks it. The pass runs again
on every `ADDON_LOADED`, so a tooltip from a load-on-demand add-on is covered.
`ItemSocketingDescription` is a description area pinned inside the socketing
window and is left alone. They
get a background texture and four edge lines (`RikUI.UnitFrames.Edges`) and
their `NineSlice` backdrop is hidden. `GameTooltip_OnHide` re-applies the
default style through `SharedTooltip_SetBackdropStyle`, which shows the
NineSlice again, so that function is post-hooked to hide it once more on the
skinned tooltips. The font objects `GameTooltipHeaderText`, `GameTooltipText`
and `GameTooltipTextSmall` receive the media font through `Media.Font`
(label and small sizes); every tooltip line inherits from them. Lines keep the
colours the client gives them.

Missing pieces degrade one at a time: no `GameTooltip_SetDefaultAnchor` or
`SharedTooltip_SetBackdropStyle` prints one line and skips that hook; no
`TooltipDataProcessor` or `Enum.TooltipDataType` prints one
`Tooltip data processor` line and leaves the colours and extra lines off while
the anchor and skin still work.

## Diagnostics

`/rik debug` prints `Tooltip anchor=<bool> skinned=<n> processor=<bool>` and
the secrecy of `UnitTokenFromGUID(UnitGUID("player"))` and
`C_Item.GetDetailedItemLevelInfo(6948)` (the Hearthstone).

## Verification

`tests/tooltip.test.lua` runs against `tests/tooltip_stub.lua`, a fake of the
69913 tooltip surface (NineSlice, the GUID-watched status bar, lines, the
anchor and backdrop functions, the font objects and a recording
`TooltipDataProcessor`). It proves: the anchor proxy and its layout defaults;
default-anchored tooltips re-pointed to it; the background, edges and hidden
NineSlice, kept hidden after the style is re-applied, on all four tooltips;
the font objects; reaction and class colours on line 1 and the guild tint;
the bar watched by GUID with our texture, `lockColor` and colour, no
`UnitHealth` read and no value write, no re-watch while shown, cleared on
hide; a secret token skipping colours silently; a unit without a GUID leaving
the bar alone; item level from hyperlink or ID, secret and missing levels;
spell ID and a secret ID; a failing item read reported once; the debug
output; combat login; `hideInCombat` on, off and its option row; a missing
processor and a missing anchor function; a disabled module leaving fonts,
backdrops, hooks and post-calls untouched.

The stub cannot show native rendering, whether the client also calls
`SetWatch` itself, or how `UnitTokenFromGUID` behaves for hostile units in
combat. Beta checklist on the Warrior:

1. Reload and hover a bag item: the tooltip should appear bottom right in a
   flat box with the RikUI font and end with `Item level N`. Hover a
   spellbook spell: last line `Spell ID N`. Run `/rik debug` and confirm the
   `Tooltip anchor=true skinned=4 processor=true` line and no `Tooltip ...`
   error line.
2. Hover a player: name in class colour, guild line light blue, a health bar
   under the tooltip in the same colour that fills. Hover an NPC: reaction
   colour. Hover a mob in combat: the bar should still fill and no red
   `RikUI:` line should print.
3. Turn on `Hide unit tooltips in combat`, fight a mob and hover it: no
   tooltip. Item tooltips should still show.
4. `/rik move`: drag the Tooltip box, lock, reload and hover something.
   Disable the module in `/rik config`, reload, and confirm the stock tooltip
   returns at its Edit Mode position.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [GameTooltip_SetDefaultAnchor and SharedTooltip_SetBackdropStyle](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SharedXML/SharedTooltipTemplates.lua)
- [GameTooltipUnitHealthBarMixin, its secure mixin and the taint note; GameTooltip_OnHide](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_GameTooltip/Mainline/GameTooltip.lua)
- [GameTooltipTemplate: the StatusBar child and font key values](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_GameTooltip/Mainline/GameTooltip.xml)
- [HealthBar_OnValueChanged and lockColor](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_GameTooltip/HealthBar.lua)
- [TooltipDataProcessor post-calls and the insecure delegate](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua)
- [TooltipUtil: guid, hyperlink and id fields of tooltip data](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua)
- [UnitPercentHealthFromGUID and UnitTokenFromGUID secret rules](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua)
- [C_Item.GetDetailedItemLevelInfo](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua)
