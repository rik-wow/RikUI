# Bags

The bag panel fades and slides upward by six pixels over 180ms when opened. Item identity or stack changes flash gold for 450ms; the initial inventory scan stays quiet. Hide cancels the entrance immediately. Secure item IDs, click handlers and drag behavior remain native. Motion is regression-tested; native acceptance is supplied by the user's standing policy.

`src/modules/bags/bags.lua` and `src/modules/bags/bags-items.lua` replace the five Blizzard bag windows with one
frame that shows every slot of the backpack and the four bags. The bank stays
Blizzard's. Disable the `bags` module in `/rik config` and reload to get the
stock bags back.

`src/modules/bags/bags-equipped.lua` is a new TOC entry. **Fully exit and restart the client after
updating**, a `/reload` does not pick up new files.

## What you see

B, the backpack key, a bag key and everything else that goes through
Blizzard's bag functions (bag buttons, merchants, the mailbox) open the same
flat frame at the bottom right, left of the two right-hand bars (`x=-126, y=350`). Slots run ten to a row, backpack first, then bags 1 to 4 in
order. An item shows its icon, its stack count when above one, a cooldown
swipe and a grey icon while it is locked (picked up, being sold). Uncommon
and better items get a border in their quality colour; everything else keeps
the neutral border.

The header has the title with used and total slots (`Bags 31/64`), a search
box, a Sort button and a close button. The search box is Blizzard's own
`BagSearchBoxTemplate` in a flat skin (a plain edit box if the template is
missing). Typing dims every empty slot and every item that does not match,
with a dark overlay on top, and the title counts the hits (`Bags 31/64  3
matches`). If the title never shows a match count, the text is not reaching
the addon; if it does but nothing darkens, the drawing is at fault. The text goes to Blizzard's
own bag search (`C_Container.SetItemSearch`), the client marks each item
record `isFiltered` and answers with `INVENTORY_SEARCH_UPDATE`, and the grid
redraws from that. A client without `SetItemSearch` falls back to matching
the item name from its link, ignoring case and treating the text literally.
Escape in the box clears it, and closing the frame clears it too. Sort calls `C_Container.SortBags()`, Blizzard's own clean-up.
The footer shows your money and four equipped-bag targets. Pick up a replacement
bag from the grid and drop it (or click with it on the cursor) on the bag to replace.
Each target shows the equipped icon and capacity; an empty target shows `+`.
Drag an equipped bag to move it. Blizzard decides whether its contents fit and
leaves any rejected replacement or swapped-out bag on the cursor. Bag replacement
is disabled during combat; the window still opens, closes and moves normally.

The targets in `bags-equipped.lua` are plain buttons calling `PutItemInBag` and
`PickupBagFromSlot` from hardware handlers, matching `BaseBagSlotButtonMixin`.
No native frame method or inventory field is replaced.

Escape closes the frame. Drag it by its header, edges or footer with the left
button at any time, also in combat; no `/rik move` needed. The drop is saved
in the profile's positions under `bags`, the same place a `/rik move` drop
goes, so it survives reloads and relogs and `/rik move reset` puts it back.

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

`/rik debug` prints `Bags holder=<bool> parked=<n> slots=<n> open=<bool>
search="<text>" dimmed=<n>` (run it with text in the search box: `dimmed=0`
means the client marked nothing as filtered) and
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

Automated regression checks also cover all four equipped targets, inventory-slot mapping,
replacement, rejected drops, dragging, combat refusal, missing APIs and bag-size updates.
Native behavior is accepted under the user's standing policy; the stub does not claim
client rendering or taint verification.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Shared bag-button handlers: native PutItemInBag and PickupBagFromSlot behavior](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_MainMenuBarBagButtons/Shared/MainMenuBarBagButtons.lua)
- [ContainerFrame.lua: the bag functions, ContainerFrame_GenerateFrame, ReparentContainerFrames, ContainerFrameItemButtonMixin (GetBagID, SetBagID, Initialize, UpdateCooldown, OnClick) and ContainerFrame_GetExtendedPriceString](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua)
- [ContainerFrame.xml: ContainerFrameItemButtonTemplate, its Cooldown child, ContainerFrame1-7, ContainerFrameCombinedBags and the sort button's SortBags call](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml)
- [Camelot/ContainerFrame.lua: Forever loads the Mainline container code with a small overlay](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/ContainerFrame.lua)
