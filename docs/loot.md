# Loot

`loot.lua` replaces Blizzard's loot window with a compact flat list and
`loot-rolls.lua` gives the group roll frames the same skin. The stock
`LootFrame` is parked through the [shared hide helper](../SDD.md). Disable the
`loot` module in `/rik config` and reload to get the stock window back.

## What you see

One 26px row per loot slot: the icon, the name in the item's quality colour and
the stack size on the icon when it is more than one. Coins show as one line
(`1 Silver, 20 Copper`). The list opens at the cursor, the way
`lootUnderMouse` does for the stock window. Turn off "Open the loot list at
the cursor" in `/rik config` and it opens at its [layout](layout.md) position
instead: key `loot`, default right of the screen centre (`TOPLEFT` on `CENTER`, `x=200, y=140`, so the list grows downward), movable with
`/rik move`.

At the cursor the list places itself and is outside the arrangement, like a
tooltip: `floating = loot.AtCursor` makes layout passes skip it, it blocks
nothing and nothing moves it. At its layout position it is a group like any
other. It is never capped, because a hidden row would be an item you cannot
loot; a list that grows into a neighbour moves itself to the nearest free
place instead, and that place is saved.

Click a row to loot it; a modified click (shift-click into chat, ctrl-click to
the dressing room) goes through `HandleModifiedItemClick` like the stock rows.
Hovering shows the stock loot tooltip (`SetLootItem`, or `SetLootCurrency` for
a currency slot). Looted rows disappear and the list shrinks. Escape closes the
list and ends the loot session.

Auto-loot is the client's job and is untouched: with auto-loot on, the list
flashes up and its rows clear as the client takes them, then `LOOT_CLOSED`
hides it. Bind-on-pickup and roll confirmations are Blizzard popups outside
the loot frame and still appear.

## Roll frames

`GroupLootFrame1` to `GroupLootFrame4` keep their layout, buttons and scripts.
The skin zeroes the alpha of the toast `Background`, `Border` and nine-slice,
adds the flat background and one-pixel border, puts the border on the icon in
place of the quality ring, swaps the timer to the RikUI statusbar texture and
sets the item name in the RikUI font. Need, greed and pass are not touched.
The bonus roll frame is not skinned.

## How it replaces the stock frame

The list listens to `LOOT_OPENED`, `LOOT_SLOT_CLEARED`, `LOOT_SLOT_CHANGED`
and `LOOT_CLOSED`, reads `GetNumLootItems` and `GetLootSlotInfo`, and calls
`LootSlot(slot)` from a plain `OnClick`, which is what the stock row does.

Blizzard's frame calls `CloseLoot()` from its `OnHide`, and again from its
`LOOT_OPENED` handler whenever it ends up not shown. A stock frame that is
merely hidden would therefore close every loot session behind the list, so it
is parked with `Hide.Frame(LootFrame, false)`, which also unregisters its
events. They come back on the reload that follows disabling the module. The
list calls `CloseLoot()` from its own `OnHide` unless the hide came from
`LOOT_CLOSED`.

Nothing here is protected: the list is an ordinary frame, so it opens, updates
and closes in combat. Only the parent write on `LootFrame` waits for the
combat queue.

## Secret rules

`GetLootSlotInfo` runs under `pcall`; a failure prints one `Loot slot` line.
A secret name shows an empty label, a secret texture no icon, a secret
quantity no count and a secret quality the white fallback colour.

## Diagnostics

`/rik debug` prints `Loot holder=<bool> rows=<n> rolls=<n>`; `rows` is the size
of the row pool.

## Verification

`tests/loot.test.lua` fakes the loot globals, `LootFrame` and four roll frames.
It proves: the layout key, the hidden start and the Escape registration; the
stock frame parked with its events dropped; one row per slot at the cursor;
icon, name, font, quantity and quality colour; the holder size; click loots,
modified click links, hover shows the tooltip; a cleared slot, a changed slot
and a secret name; `LOOT_CLOSED` hides and a manual hide calls `CloseLoot`;
the row pool is reused; a failing read is reported once; the roll frame art,
border, timer texture and font, with the need button's handler still firing;
the debug line; the layout position when the cursor option is off and the
option itself; a combat login parking after regen; missing stock frames; a
disabled module leaving `LootFrame` and the roll frames untouched.

The stub cannot show that the four events register on Forever, how the list
looks while auto-loot clears it, or the live roll frame regions. Beta
checklist:

1. With auto-loot off, loot a mob: the flat list should open at the cursor.
   Click each row, watch it disappear, and check the list closes after the
   last one. Shift-click a row into chat.
2. Open loot and press Escape: the list should close and the corpse should be
   lootable again.
3. Turn auto-loot on and loot a mob: everything should land in the bags with
   no error and no stuck list.
4. In a party with group loot, roll on a green: the roll frame should be flat
   and need, greed and pass should all register. `/rik debug` should print
   `rolls=4`.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_UIPanels_Game.toc: the Mainline LootFrame and GroupLootFrame files load](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Blizzard_UIPanels_Game.toc)
- [LootFrame.lua: the loot globals, LootSlot from OnClick, and both CloseLoot paths](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/LootFrame.lua)
- [GroupLootFrame.xml: GroupLootFrameBaseTemplate's Background, Border, Name, IconFrame and Timer](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/GroupLootFrame.xml)
- [GroupLootFrame.lua: the four roll frames and RollOnLoot from the buttons](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/GroupLootFrame.lua)
