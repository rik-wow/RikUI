# Auction house

RikUI gives the auction house a custom layout with the game's existing search,
pricing, bidding, buying, posting and cancellation behavior.

## Layout

- Top navigation for buying, selling and managing auctions.
- A wide search field, category sidebar and larger result tables.
- Separate item summaries, comparison lists and purchase controls.
- A dedicated selling form beside current listings.
- Auctions and bids with their own navigation, summaries and action areas.
- Dark cards, readable headings, larger rows, blue selection rails and clear
  loading, empty and waiting messages.
- A window that scales down to fit smaller screens.

Use the auctioneer normally. After updating RikUI, use `/reload`.
The Panels module's commerce setting controls this presentation; changes to
native window styling take effect after reloading.

## Individual item enchantments

Select an item in search results to open its individual auctions. The purchase
table's **Item / enchantment** column shows each auction's full linked item
name, including any random suffix supplied by the client (for example,
“of the Bear”). Names retain item-quality colors and wrap over two lines.
Hover the row for the native tooltip with that listing's details.

Grouped search results describe an item group; compare variants in the
individual purchase table. A missing or unnamed link reads **Item details
unavailable** until native results supply it. RikUI does not infer an
enchantment from a base item ID or another listing. Additional server-specific
enchantments absent from the supplied link/name cannot be identified here.

## Native behavior

The layout uses the actual Blizzard controls and data providers. It retains
native search filters, sorting, favorites, tooltips, quantities, prices, bid
amounts, durations, validation and confirmation dialogs. It does not issue
search or transaction requests of its own.

The adapter handles the auction addon's delayed loading, native tab changes,
recycled result rows and display-size changes. Repeated refreshes preserve
unchanged control anchors and leave subsequent form layout to the native
controllers, so showing a pooled row does not restart the whole layout.
Visual updates defer during combat. Protected and forbidden frames are skipped.
Native tooltips appear immediately: the auction controller periodically hides
and rebuilds them while hovered, so a repeated entry fade would cause flicker.

## Implementation and evidence

The four files in `src/modules/auctionhouse/` split the shell and refresh
lifecycle, layout, control styling, and individual item variants. They register
a dedicated auction adapter after the shared interiors and use their pooled-row callbacks.
The purchase list wraps the native layout callback to add one unsortable
column with an isolated frame pool. Native table builders size and populate
all columns; price, quantity, socket and time cells remain native. Exact
row data is never changed, and the added cells pass mouse interaction to the
native row. Stable refreshes do not rebuild the table or its tooltips.

Source reviewed on 2026-09-27: the then-current
[Forever branch](https://github.com/Gethe/wow-ui-source/tree/forever/Interface/AddOns/Blizzard_AuctionHouseUI),
version `1.60.1.70009`, commit
`bd2470aed543f72697a044e989285b6c83e63f73`. The installed WowB.exe version
matched. This records the reviewed source, not a pinned client requirement.
The auction frame, Mainline item-list/table templates, selling layouts,
category setup and
[shared scroll implementation](https://github.com/Gethe/wow-ui-source/tree/forever/Interface/AddOns/Blizzard_SharedXML/Shared/Scroll)
establish the native frame structure and lifecycle used here.

The tooltip refresh fix follows the current
[auction tooltip builder](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Mainline/Blizzard_AuctionHouseUtil.lua)
and [GameTooltip update handler](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_GameTooltip/Mainline/GameTooltip.lua):
periodic owner updates hide and rebuild the tooltip. The regression replays
this cycle and checks opacity, updated contents, ownership and actual hiding.

The variant column follows the current
[ItemSearchResultInfo API](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua),
[item purchase controller](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseItemBuyFrame.lua),
[TableBuilder lifecycle](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXML/TableBuilder.lua)
and [frame pool API](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXMLBase/Pools.lua).
Tests cover distinct variants of the same item, localized and late names,
missing links, virtual entries, recycled cells, native layout replacement,
unchanged purchase data and hover handlers, combat deferral and panel opt-out.

The automated fixture checks anchor separation, small-screen scaling,
preserved values and handlers, disabled controls, confirmation state, result
providers, pooled selection/alpha, repeated refreshes, delayed loading,
combat deferral and commerce opt-out. The full regression suite and manifest
check also cover integration and Lua compilation.

Native acceptance is supplied by the user's standing project policy.
No agent-observed game-client interaction or screenshot is claimed.
