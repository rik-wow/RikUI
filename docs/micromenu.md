# Micro menu and bags

Micro and bag-strip buttons gain a 100ms gold hover transition on addon-owned textures. Secure click attributes and native tooltip behavior remain intact. Motion is regression-tested; native acceptance is supplied by the user's standing policy.

`src/modules/micromenu/micromenu.lua` replaces the bottom-right cluster with one flat row of 22px
buttons: a button for every micro button the client shows, then the backpack,
the four bag slots and the keyring. The Blizzard `MicroMenu` and `BagsBar` are
parked through the [shared hide helper](../SDD.md) once the row exists. Disable
the `micromenu` module in `/rik config` and reload to get the stock cluster back.

## What you see

Each micro button is a dark square with the RikUI border and one letter:
`C` character, `P` professions, `S` spells and talents, `B` spellbook,
`T` talents, `A` achievements, `L` legacy, `Q` quest log, `H` housing,
`G` guild, `F` group finder, `O` collections, `J` journal, `?` help, `$` shop,
`=` game menu. Only the ones the client has and shows at login get a button, so
the row matches whatever Forever ships. Hovering a button shows the stock
button's own tooltip text, which carries the key binding.

After a gap come the bag buttons. The backpack and every equipped bag show
their icon and the number of free slots in the corner; an empty bag slot is a
blank square. The keyring button appears when
`C_ActionBar.ShouldShowKeyring()` says the client has one. Counts refresh on
`BAG_UPDATE_DELAYED`.

## Clicks

A micro button is a `SecureActionButtonTemplate` with `type = "click"` and
`clickbutton` set to the stock button. The click runs the stock button's own
handler from the secure click path, so the panel that opens, the level locks
and the combat behaviour are Blizzard's, and RikUI never calls a panel toggle
itself. This is why the stock buttons are parked with their events kept.

Bag buttons are plain buttons: the backpack calls `ToggleBackpack()`, a bag
slot `ToggleBag(id)` and the keyring `ToggleBag(KEYRING_CONTAINER)`. Those are
the same globals the stock bag bar calls and the [one-bag view](bags.md) hooks.
Dragging an item onto a strip bag slot to equip or stash it is not supported;
use the one-bag view or `/rik stockbars show`.

## Layout

The holder is `RikUIMicroMenu`, registered with the [shared layout](layout.md)
under `micromenu`, so `/rik move`, `/rik move reset` and `/rik scale` apply.
The default is `BOTTOMRIGHT` of the screen at `x=-16, y=16`. Buttons are 22px
with a 2px gap and an 8px gap between the two groups.

## Stock frames

`src/modules/bars/bars-stock.lua` used to park `MicroMenu` and `BagsBar` with the main action
bar. This module owns them now and parks them only after its row is built, so
there is never a moment without a menu. `/rik stockbars show` returns both
(the module follows `bars.UpdateStockVisibility` through a post-hook and
re-runs the menu container's `Layout`), and `hide` parks them again.
`MicroMenuContainer`, the queue status button and the `MicroButtonAndBagsBar`
anchor are left alone. Frame creation, attributes and parent writes run inside
one `Combat.Queue` closure; at a combat login nothing is touched until
`PLAYER_REGEN_ENABLED`.

## Secret rules

The free-slot read runs under `pcall`; a failure prints one `Micro menu bags`
line. A secret or non-numeric count shows nothing and a secret icon shows a
blank square.

## Diagnostics

`/rik debug` prints `Micro menu holder=<bool> buttons=<n> bags=<n>`.

## Verification

`tests/micromenu.test.lua` fakes the stock menu, seven micro buttons (one
hidden), the bag bar and the container reads. It proves: the layout key and
bottom-right defaults; one secure click delegate per shown stock button and
none for the hidden one; label, font and border; the six bag buttons in order;
holder size; icon and free count, an empty slot, a bag update, a secret count
and a failing read reported once; bag clicks reaching the toggles in combat;
the tooltip; both stock frames parked with the container left alone, returned
with a layout refresh on show and parked again on hide; the debug line; a
combat login building nothing until regen; no keyring; missing stock frames;
a show-stock profile; a disabled module leaving everything untouched.

The stub cannot show whether a secure click delegate reaches a stock button
whose parent is hidden, or which buttons Forever shows. Beta checklist:

1. Reload: the row sits at the bottom right and the stock menu and bag bar are
   gone. `/rik debug` should print the button and bag counts.
2. Click every letter out of combat and check the matching panel opens and
   closes. Repeat `C`, `Q` and `=` in combat and watch for a blocked-action
   message.
3. Click the backpack and a bag slot in and out of combat. Loot something and
   check the free count drops.
4. `/rik move`, drag the row, lock, reload. `/rik stockbars show` should bring
   the stock menu and bag bar back beside the row.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_MicroMenu.toc: camelot loads the Mainline button files plus its own overrides and menu frame](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_MicroMenu/Blizzard_MicroMenu.toc)
- [MainMenuBarMicroButtons.xml: the sixteen button names](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_MicroMenu/Mainline/MainMenuBarMicroButtons.xml)
- [MainMenuBarMicroButtons.lua: the OnClick handlers and their panel toggles](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_MicroMenu/Mainline/MainMenuBarMicroButtons.lua)
- [Camelot/MainMenuBarBagButtons.xml: BagsBar, the backpack and KeyRingButton](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_MainMenuBarBagButtons/Camelot/MainMenuBarBagButtons.xml)
- [Camelot/MainMenuBarBagButtons.lua: KeyRingMixin, ShouldShowKeyring and the ToggleBag click](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_MainMenuBarBagButtons/Camelot/MainMenuBarBagButtons.lua)
