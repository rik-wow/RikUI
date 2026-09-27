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

The three files in `src/modules/auctionhouse/` split the shell and refresh
lifecycle, layout, and control styling. They register a dedicated auction
adapter after the shared interiors and use their pooled-row callbacks.
Native table builders still size and populate their own columns.

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

The automated fixture checks anchor separation, small-screen scaling,
preserved values and handlers, disabled controls, confirmation state, result
providers, pooled selection/alpha, repeated refreshes, delayed loading,
combat deferral and commerce opt-out. The full regression suite and manifest
check also cover integration and Lua compilation.

Native acceptance is supplied by the user's standing project policy.
No agent-observed game-client interaction or screenshot is claimed.
