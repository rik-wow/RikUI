# Menus

`src/modules/menus/menus.lua` puts the flat RikUI backing under every menu Blizzard's Menu system
opens: right-click menus on units, chat names and bags, dropdown lists in the
options and in Blizzard's windows, and their submenus. The menus stay
Blizzard's; their rows, checks, arrows and clicks are untouched. Disable the
`menus` module in `/rik config` and reload for the stock look.

## What you see

A flat dark panel with a one-pixel edge, the same as the [popups](popups.md)
and [panel skin](panels.md), in place of the rounded grey dropdown art. The
panel fades in over 0.15s each time a menu or submenu opens. Row text keeps
Blizzard's font and colours, which is how a title, a disabled row and a
coloured name stay readable as such.

## How it works

`MenuProxyMixin:OnShow` and `OnHide` trigger `MenuProxy.OnShow` and
`MenuProxy.OnHide` on `EventRegistry` with the menu frame. The module registers
for both.

While a menu is open, its compositor swaps the frame's metatable for one that
asserts on `CreateTexture`, `CreateFontString`, `CreateAnimationGroup` and
`CreateLine`, and the pooled font strings assert on `SetFont`. So nothing is
created on the menu and no font is written. The backing is an own frame from a
pool, parented to `UIParent`, anchored to the menu's corners, put in the menu's
strata and one frame level under it so the rows draw on top. It is never
reparented, which keeps opening a menu in combat free of protected calls.

Blizzard's background is a texture from the compositor's pool with the atlas
`common-dropdown-bg`. The module finds it among `menu:GetRegions()` by that
atlas name and writes alpha 0. The pool calls `SetToDefaults` on release, so
the write does not follow the texture to its next user and is repeated on every
show.

`MenuStyle1Mixin` insets the rows by 8px and by 15px at the bottom for the
art's drop shadow. The backing's bottom edge is lifted 7px so the padding is
8px on every side.

On hide the backing is hidden, unanchored and returned to the pool. A submenu
open at the same time has a backing of its own.

## Not covered

Row fonts, the check and radio marks, the submenu arrow, the row highlight and
the scroll bar of a long list stay stock. The closed dropdown button (the box
with the arrow that opens a list) is part of the window that holds it, not of
the menu.

## Diagnostics

`/rik debug` prints `Menus shown=<n> active=<n> pooled=<n>`. A skin that fails
prints one `Menus skin: <reason>` line and later menus are still tried.

## Verification

`tests/menus.test.lua` builds fake menus whose `CreateTexture`,
`CreateAnimationGroup` and font string `SetFont` raise, with a background
texture that answers the 69913 atlas name. It proves: the background faded and
other art left alone; the flat backing with its edge; strata, level and anchors;
the fade-in; nothing created on, moved or reparented on the menu; a second
backing for a submenu; release to the pool on hide and reuse with a new
fade-in; level never under zero; a repeated show ignored; a hide for an unknown
menu ignored; open and close in combat; the debug line; a menu without regions,
level or strata; a refused alpha write reported once with later menus working;
a client without `EventRegistry`; the disabled module.

The stub cannot settle these: whether the background is attached before
`MenuProxy.OnShow` fires, whether a frame one level under the menu in the same
strata draws under every row, whether the 7px lift matches the visible art, and
whether an alpha write on the pooled texture taints protected menu actions such
as Set Focus. Beta checklist:

1. Fully restart the client (two new TOC entries). Right-click your own unit
   frame, a chat name and a bag item: flat panel, even padding, rows readable.
2. Open a submenu (for example loot options): second flat panel, no grey art
   behind either.
3. In combat, right-click the target and use a protected entry such as Set
   Focus. An "action blocked" message means this module is the first suspect:
   disable it and retry.
4. Open a long dropdown in the options window and scroll it.
5. `/rik debug` should print the `Menus` line with `active=0` once all menus
   are closed.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_Menu.toc: Camelot/Menu.xml replaces Menu.xml, the Mainline variants load](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_Menu/Blizzard_Menu.toc)
- [Menu.lua: MenuProxyMixin:OnShow and OnHide trigger the registry events](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_Menu/Menu.lua)
- [Compositor.lua: the disallowed functions and SetToDefaults on release](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_Menu/Compositor.lua)
- [Mainline/MenuTemplates.lua: MenuStyle1Mixin's background atlas and insets](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_Menu/Mainline/MenuTemplates.lua)
