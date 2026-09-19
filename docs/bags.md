# Bags

`bags.lua` and `bags-items.lua` replace the five Blizzard bag windows with one
frame that shows every slot of the backpack and the four bags. The bank stays
Blizzard's. Disable the `bags` module in `/rik config` and reload to get the
stock bags back.

`bags-items.lua` is a new TOC entry. **Fully exit and restart the client after
updating**, a `/reload` does not pick up new files.

## What you see

B, the backpack key, a bag key and everything else that goes through
Blizzard's bag functions (bag buttons, merchants, the mailbox) open the same
flat frame, bottom right above the tooltip anchor. Slots run ten to a row, backpack first, then bags 1 to 4 in
order. An item shows its icon, its stack count when above one, a cooldown
swipe and a grey icon while it is locked (picked up, being sold). Uncommon
and better items get a border in their quality colour; everything else keeps
the neutral border.

The header has the title with used and total slots (`Bags 31/64`), a search
box, a Sort button and a close button. Typing in the search box dims every
slot whose item name does not contain the text; matching ignores case and
treats the text literally. Escape in the box clears it, and closing the frame
clears it too. Sort calls `C_Container.SortBags()`, Blizzard's own clean-up.
The footer shows your money.

Escape closes the frame. `/rik move` drags it under the label `bags`.

Left-click picks an item up, dragging works, right-click uses, equips or
sells, shift-click splits a stack or links into chat, and the item tooltip
with its comparison opens on hover. None of that is RikUI code: the buttons
are Blizzard's `ContainerFrameItemButtonTemplate` and run Blizzard's handlers.

## Why the buttons are built this way

Using an item is protected, so the click has to reach
`C_Container.UseContainerItem` without passing through addon-written data.
Blizzard's item button finds its slot with `self:GetID()` and its bag with
`self:GetBagID()`, which is `self.bagID or self:GetParent():GetID()`. Frame
IDs live in the client, not in Lua fields, so RikUI:

- creates one plain parent frame per bag and gives it the bag number with
  `SetID`
- creates each button from the template under that parent and gives it the
  slot number with `SetID`
- never calls the mixin's `Initialize`, `SetBagID` or `UpdateCooldown`, which
  would write `bagID` or `hasItem` from addon code for the secure handlers to
  read later
- draws on its own regions (`rikIcon`, `rikCount`, `rikBorder`,
  `rikBackground`) and drives the template's `Cooldown` frame directly

One known gap follows from that rule: Blizzard's refund confirmation reads
`button.count`, which RikUI does not write, so the popup for a refundable
vendor item names a count of 1.

## How open and close work

RikUI does not replace `ToggleAllBags` or any other bag function, because a
replaced global taints the bag key binding. It post-hooks `OpenAllBags`,
`CloseAllBags`, `ToggleAllBags`, `OpenBackpack`, `CloseBackpack`,
`ToggleBackpack`, `OpenBag`, `CloseBag` and `ToggleBag`. After each call the
frame shows if any stock container frame is shown and hides otherwise.
Closing the RikUI frame (Escape, the close button) calls `CloseAllBags()` so
Blizzard's state follows.

The stock frames (`ContainerFrame1` onwards and `ContainerFrameCombinedBags`)
are parked with `RikUI.Hide.Frame(frame)`, one by one, keeping their events.
A parked frame keeps its shown flag but never draws. Fullscreen panels
reparent each container frame on their own; the hide helper sees that and
parks the frame again. Parent writes are protected, so at a combat login the
parking waits for `PLAYER_REGEN_ENABLED`; the RikUI frame itself is not
protected and opens in combat.

Opening a single bag (`ToggleBag(2)`) shows the whole frame. What B does
next is Blizzard's decision: if its `ToggleAllBags` opens the remaining bags
when only some are open, closing takes a second press.

If the client shows a keyring, it uses a stock container frame and is
therefore not visible while the module is enabled.

## Updates

`BAG_UPDATE_DELAYED`, `BAG_UPDATE_COOLDOWN` and `ITEM_LOCK_CHANGED` redraw the
grid while the frame is open; a closed frame reads nothing. Opening redraws
everything. `PLAYER_MONEY` rewrites the money line. Buttons are created the
first time a slot is shown and hidden, not destroyed, when a bag shrinks.

## Secret rules

Every `C_Container` read runs under `pcall`. A failing item read prints one
`Bags items` line. A secret item record draws an empty slot, a secret count
or quality falls back to no count and the neutral border, and a secret
cooldown leaves the swipe as it was. Nothing secret is compared or printed.

## Diagnostics

`/rik debug` prints `Bags holder=<bool> parked=<n> slots=<n> open=<bool>` and
the secrecy of `C_Container.GetContainerNumSlots(0)`. A client without the
item template prints one `Bags buttons` line, one without `SortBags` one
`Bags sort` line, and one without container frames one `Bags frames` line.

## Verification

`tests/bags.test.lua` runs against `tests/bags_stub.lua`, a fake of the 69913
bag surface: six stock container frames under `ContainerFrameContainer`, the
combined frame, the nine bag functions flipping their shown flags,
`C_Container` slot counts, item records, cooldowns and a sort counter,
`GetMoney` and quality colours. It proves: the layout registration and
defaults; the seven parked frames; post-hooks instead of replaced globals;
no bag read before the first open; all 22 slots on the bag key; template and
frame type; slot in the button ID and bag in the parent ID; no `bagID`,
`hasItem`, `count`, `readable` or `bagid` attribute written; icons, counts,
quality and neutral borders; the ten-column flow across bags; holder size and
title; the money text; search dimming, clearing and literal matching; the
sort call; redraws on the three bag events; lock desaturation; cooldown set
and cleared; a shrinking bag; a secret record; a failing read reported once;
the debug line; closing by key, by hiding and by the close button with
Blizzard's frames following; single-bag and backpack opens; a closed frame
ignoring events; a combat login; a missing template, `SortBags` or combined
frame; a disabled module touching nothing.

The stub cannot show taint, rendering or sound. Beta checklist on the
Warrior, after a full client restart:

1. Press B: one flat frame, no Blizzard bag windows. `/rik debug` should
   print `Bags holder=true parked=<n> slots=<n> open=true` with no `Bags ...`
   error line. Note the parked count.
2. Right-click a food item, equip a weapon from the bag, drag an item to
   another slot, shift-click a stack to split it. No "action blocked" error.
3. Repeat the right-click use while in combat.
4. Open a merchant: the frame should open by itself; right-click sells, and
   the grey-item sell cursor shows. Close the merchant: the frame closes.
5. Type part of an item name in the search box: other slots dim. Escape
   clears it.
6. Click Sort: items regroup and the grid follows.
7. Hover an item: tooltip with comparison, in the RikUI tooltip skin.
8. Press Escape with the frame open: it closes, and B opens it again with one
   press.
9. Open the world map fullscreen and press B: no stock bag window appears.
10. If the character has a keyring button, note whether anything opens.
11. `/rik move`: a `bags` overlay; drag, lock, reload, position kept.
12. Disable the module, reload: the Blizzard bags return.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [ContainerFrame.lua: the bag functions, ContainerFrame_GenerateFrame, ReparentContainerFrames, ContainerFrameItemButtonMixin (GetBagID, SetBagID, Initialize, UpdateCooldown, OnClick) and ContainerFrame_GetExtendedPriceString](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua)
- [ContainerFrame.xml: ContainerFrameItemButtonTemplate, its Cooldown child, ContainerFrame1-7, ContainerFrameCombinedBags and the sort button's SortBags call](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml)
- [Camelot/ContainerFrame.lua: Forever loads the Mainline container code with a small overlay](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/ContainerFrame.lua)
