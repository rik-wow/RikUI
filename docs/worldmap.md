# World map navigation bar

`src/modules/worldmap/worldmap.lua` flattens the breadcrumb bar inside the world map (World >
Eastern Kingdoms > Elwynn Forest). The map's window chrome is covered by the
[panel skin](panels.md); this module covers what sits inside it. Disable the
`worldmap` module in `/rik config` and reload for the stock bar.

## What you see

The bar is a flat panel with a one-pixel edge in place of the stone strip.
Each breadcrumb is plain text in the RikUI typeface at Blizzard's size and
colour, with a thin vertical line after it in place of the chevron art and the
RikUI highlight on hover. Clicking a breadcrumb and its dropdown arrow work as
before.

## How it works

The map adds its bar with `AddOverlayFrame("WorldMapNavBarTemplate")` and keeps
it on `WorldMapFrame.NavBar`. On the map's first show the module hooks the
bar's own `Refresh`, the `WorldMapNavBarMixin` method that rebuilds the
breadcrumbs on every map change. The hook is on that one frame. The global
`NavBar_*` functions, which other windows share, are not hooked.

On the first show and after every `Refresh`:

- The bar's textures and the textures of its `overlay` child get alpha 0. The
  list of Blizzard's textures is taken once, on the first pass, before the
  module has created anything: `GetRegions` also returns regions an addon adds,
  and a later pass would otherwise fade the module's own fill and edge.
- The bar gets a fill and four edge lines, once.
- Every button in `navList` has `arrowUp`, `arrowDown`, `selected` and its
  normal, pushed and highlight textures faded, and the typeface written to
  `text`. Blizzard re-shows the chevron art when a breadcrumb changes state, so
  this is repeated. Once per button a highlight texture and a separator line
  on the right edge are added.

A skin that raises prints one `World map skin: <reason>` line and is never
tried again, not from `Refresh` either.

## Round canvas buttons

`WorldMapFrame.WorldMapTrackingOptionsButton` and `WorldMapTrackingPinButton`
lose their disc (`Background`) and ring (`Border`) on the map's first show and
get a flat backing four pixels in, a one-pixel edge and a hover highlight. The
icon stays. An earlier version left them stock because Blizzard refreshes
overlay frames with `secureexecuterange`; the navigation bar is an overlay
frame added by the same `AddOverlayFrame` call and has been skinned since the
first version, so the buttons add no new class of risk. They are handled more
carefully than the bar: nothing is stored on a button, the record lives in a
weak table (`RikUI.WorldMap.Overlays`). A button that refuses is reported once
as `World map overlay`. The floor dropdown inherits `WowStyle1DropdownTemplate`, so the
[window controls](controls.md) walk the panel skin runs on the map should catch
it; that is unchecked and belongs on the beta list.

If quest tracking from the map gets blocked or pins stop responding, disable
the `worldmap` module first.

## Left stock on purpose

The canvas, the pins, the coordinates panel, the side panel toggle and the
content overlays (bounty board, action button, zone timer, threat frame,
activity tracker) are not written at all. The map is the part of the UI where
addon taint has historically done the most damage. The dropdowns the buttons
open are flat through the [menus](menus.md) module.

Nothing is moved, resized, reparented, shown, hidden or rescripted. Only
alpha, fonts and new child regions are written, none of which is protected, so
a map change in combat is safe.

## Diagnostics

`/rik debug` prints `World map bar=<true|false> crumbs=<n> failed=<true|false>`.

## Verification

`tests/worldmap.test.lua` builds a fake map with the bar's art, an overlay
child, chevron buttons and a `Refresh`, and a `GetRegions` that returns
addon-made regions as the client does. It proves: nothing skinned before the
map opens; bar and overlay art faded with a fill and edge; the home breadcrumb
flat with typeface, highlight and separator; canvas and tracking button
unwritten and the map unmoved; Blizzard's `Refresh` still running and a new
breadcrumb skinned; one decoration per breadcrumb and bar with restored art
faded again; the module's own fill and edge never faded by a later pass (this
check failed against the first implementation); a map change in combat; the
debug line; a refused write reported once and never retried; a bar without a
list or overlay; a map without a bar; a client without the map; the disabled
module.

The stub cannot settle these: whether these writes taint the map, whether
faded button textures leave the breadcrumb's click area intact, and how the
dropdown arrow on a breadcrumb looks without the chevron behind it. Beta
checklist:

1. Fully restart the client (new TOC entry). Open the map: flat bar, text
   breadcrumbs with separators.
2. Click through continent and zone and back via the breadcrumbs; open a
   breadcrumb's dropdown.
3. With the map open, track and untrack a quest and click a pin. Then enter
   combat with the map open and change zone on it. Any "action blocked"
   message or dead pin means this module is the first suspect: disable it and
   retry.
4. `/rik debug` should print `World map bar=true` with `failed=false`.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_WorldMap.lua: AddOverlayFrame calls, self.NavBar and the secureexecuterange refresh](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_WorldMap/Blizzard_WorldMap.lua)
- [Camelot/Blizzard_WorldMap.lua: the tracking button anchored beside the bar](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_WorldMap/Camelot/Blizzard_WorldMap.lua)
- [Blizzard_WorldMapTemplates.lua: WorldMapNavBarMixin:Refresh](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_WorldMap/Blizzard_WorldMapTemplates.lua)
- [Mainline/NavigationBar.xml: NavBarTemplate and NavButtonTemplate keys](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_FrameXML/Mainline/NavigationBar.xml)
