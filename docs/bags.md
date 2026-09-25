# Bags

**Protect favorites from bulk junk sales** is on by default. RikUI skips the whole manual or automatic bulk sale when it finds favorite junk or cannot verify inventory. The merchant button explains the block. You can sell individual items normally, or disable protection explicitly. The guard reads current slots again at click time.

Use **/rik favorite <item link or ID>** to add or remove a favorite item. Paste a link by shift-clicking it into the command. The **Favorites** quick filter, `type:favorites` search selector and small gold **F** badge follow the item ID across bag moves. Favorites are saved per UI profile (up to 50 item IDs), work with text search, and are included in shared profiles. They organize items and can guard RikUI bulk junk sales; native individual use, sorting and selling remain available. Hover Favorites for command help.

**Show item levels on bag gear** adds a level in the top-right of weapon and armor icons, leaving the new-item badge and stack count in their own corners. It is off by default and applies immediately. Unreadable or uncached levels stay blank and refresh on existing item-data events. Native item click and drag behavior is unchanged.

Bag search accepts combined selectors: `type:gear q:uncommon blade`, `id:123`, or `q:common !hearth`. Terms in a structured query must all match; `!` excludes a literal term or selector. Quality names are poor/common/uncommon/rare/epic/legendary (or 0–5), and types are all/junk/quest/gear/use/materials/new. Unknown selector data never matches, including exclusions. Quick filters still apply. Ordinary searches retain native behavior. Hover the search field for help; queries are limited to 256 characters and 16 terms.

**Prefer guild funds for repairs** uses guild money when the client reports permission, sufficient balance and allowance. Otherwise it uses affordable personal funds. It applies to both automatic and manual repairs; the button says **Guild repair** when selected. It defaults off and never retries spending after a failed repair call. Missing guild APIs leave personal repair available.

**Automatically sell junk** is off by default in Bags and vendors. When enabled it runs the client's Sell junk action once on opening a merchant, respecting native exclusions. Hold Shift to skip both automatic selling and repair; manual buttons remain available. Combat or unavailable modifier/item data skips selling without scheduling a later sale.

API reviewed 2026-09-24: [69913 native merchant batch selling](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/MerchantFrameDocumentation.lua).

Lock changes now read and shade only the affected visible inventory slot, instead of rebuilding all bags. Equipment-only events, unsupported slots and closed inventory do no work. Unreadable lock state clears stale shading. Full inventory changes still refresh the grid. This reduces measured API calls in automated tests; it is not a measured FPS claim. The event's optional slot payload is verified in the [69913 Container API](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua).

Items with readable IDs refresh when their delayed item data arrives: icons, names and filter counts update in the open bag window. Only matching visible slots are reread; hidden bags and failed/unrelated completion events do no work. No item is moved or used. Event payloads and container IDs were checked against the [69913 item API](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua) on 2026-09-24. Slots with unavailable IDs still refresh on ordinary bag updates.

Cooldown-only events refresh the visible cooldown widgets without rereading item information, reclassifying items or rebuilding the grid. Hidden inventory performs no cooldown queries. Inventory changes still use the complete refresh path. Automated API-call counts verify the reduced work; no native FPS improvement is claimed.

Hover the money line for session income, spending and net balance changes. Click it to reset. Transfers, trades, repairs and purchases all count; this is observed cash flow, not farming profit. Missing balance reads mark the totals partial and do not invent changes across the gap. Counters reset on reload and are never saved.

If a bag-size read fails or is invalid, the inventory keeps its last complete grid until a valid refresh arrives. A readable zero still removes an unequipped bag. This is a guarded display snapshot; item actions remain owned by the client.

**Sort** disables during combat and while an item is held on the cursor. Hover for the current reason. It never clears the cursor or queues an automatic sort for later; click again when ready. Unavailable or unreadable cursor state also blocks sorting. The refresh event is verified in the [69913 Cursor API](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/CursorDocumentation.lua).

The capacity HUD can show **only when space is low**, using a configurable 0–20 free-slot threshold (default 4). It counts general space; specialized slots do not hide a shortage. Unknown capacity stays visible. The existing Show capacity switch still hides the HUD completely, and bag-window capacity remains available.

**Bags and vendors** exposes native sorting direction, loot insertion direction, and backpack exclusions for sorting and Sell junk. These are client preferences shared across RikUI profiles; loading RikUI never writes them. Unavailable or unreadable settings are disabled, changes wait for you to leave combat, and each write checks the client's readback. Verified against [69913 Container APIs](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua) on 2026-09-24.

At merchants, **Repair all** sits beside **Sell junk**. It uses personal funds only when repairs are needed and affordable, and disables itself during combat or when the client cannot provide readable repair information. Auto repair remains opt-in; Shift skips only the automatic action.

Research reviewed 2026-09-24: [September 23 vendor-action requests](https://us.forums.blizzard.com/en/wow/t/wow-forever-controller-feedback-bug-tracking/2358921), [exact-build merchant repair availability and cost](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua). Native controller focus/bindings are not changed.

The bag panel fades and slides upward by six pixels over 180ms when opened. Item identity or stack changes flash gold for 450ms; the initial inventory scan stays quiet. Hide cancels the entrance immediately. Secure item IDs, click handlers and drag behavior remain native. Motion is regression-tested; native acceptance is supplied by the user's standing policy.

`src/modules/bags/bags.lua` and `src/modules/bags/bags-items.lua` replace the five Blizzard bag windows with one
frame that shows every slot of the backpack and the four bags. The bank stays
Blizzard's. Disable the `bags` module in `/rik config` and reload to get the
stock bags back.

`src/modules/bags/bags-equipped.lua` is a new TOC entry. **Fully exit and restart the client after
updating**, a `/reload` does not pick up new files.

The **Materials** quick filter highlights trade goods and reagents, including cloth, ore and herbs when the client classifies them that way. It combines with text search; unreadable categories do not match. All restores the grid without moving any items.

The **New** quick filter highlights items still marked new by the client. Hovering an item acknowledges it and immediately updates the filter count. Missing or unreadable new-item data produces no matches; the native new-item flag is the source of truth.

**Bag columns** in Settings > Bags and vendors adjusts the grid from 10 to 16 columns. Wider windows need fewer rows. The preference follows your profile; changes requested during combat apply after combat. Buttons keep their original native bag and slot IDs.

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
redraws from that. A missing, failing or refused `SetItemSearch` call, or an unreadable per-item filter flag, falls back to matching
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
cooldown clears the swipe until readable data returns. Empty slots, failed reads, disabled cooldowns and invalid timing also clear stale swipes. Nothing secret is compared or printed.

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

Newly acquired items carry a small gold **N**. Hovering acknowledges the item
through Blizzard's new-item API. Empty slots and unavailable or secret new-item
data never show a marker. Native item clicks and tooltips remain unchanged.

## Sell junk

At a merchant, **Sell junk (count)** appears beside Sort. A click requests one
native bulk sale; Blizzard decides which items qualify and respects its own
bag exclusions. No items are sold automatically. The action is unavailable in
combat or when the client cannot confirm a supported junk sale.

## Vendor repairs

Enable **Automatically repair gear** under Bags and vendors to repair when
opening a vendor. It uses personal funds, skips unaffordable repairs, and never
uses guild money. Hold Shift when opening the vendor to bypass it. The option
is off by default; missing or failed repair APIs produce a one-time diagnostic.

## Available space

The footer shows general free slots separately from specialized bag space.
Four or fewer general slots turn amber; no general room turns red. A completely
full inventory reads "Bags full". Missing or unreadable capacity reads "Space
unavailable". Counts refresh with bag changes and when the window opens.

## Quick filters

All, Junk, Quest, Gear and Use buttons narrow the inventory without moving slots.
Filters combine with the search text; the title counts the matches. Junk means
poor quality, Gear means weapons or armor, and Use means consumables. Quest
items use native quest metadata or the quest-item class. Unavailable metadata
does not guess a category. All restores every slot; closing bags resets filters.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Shared bag-button handlers: native PutItemInBag and PickupBagFromSlot behavior](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_MainMenuBarBagButtons/Shared/MainMenuBarBagButtons.lua)
- [ContainerFrame.lua: the bag functions, ContainerFrame_GenerateFrame, ReparentContainerFrames, ContainerFrameItemButtonMixin (GetBagID, SetBagID, Initialize, UpdateCooldown, OnClick) and ContainerFrame_GetExtendedPriceString](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua)
- [ContainerFrame.xml: ContainerFrameItemButtonTemplate, its Cooldown child, ContainerFrame1-7, ContainerFrameCombinedBags and the sort button's SortBags call](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.xml)
- [Camelot/ContainerFrame.lua: Forever loads the Mainline container code with a small overlay](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/ContainerFrame.lua)
