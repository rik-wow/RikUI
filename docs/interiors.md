# Window interiors

## Social, calendar and achievements

Friend/guild/community/group/raid/PvP/inspect rows use flat backgrounds and
hover fades while presence, rank, class and selection indicators remain native.
Calendar day cells keep event art, invites and date selection but flatten the
decorative backing and restyle date text. Achievement cards retain progress,
rewards and completion state. Forbidden CommunitiesAddDialog/CreateDialog
surfaces report a client limit once instead of being traversed.

Source: pinned FriendsFrame, CommunitiesMemberList, CalendarTemplates,
AchievementUI and CommunitiesSecure XML. The social fixture checks lowercase
friend labels, calendar global date regions, achievement progress preservation
and forbidden subtree exclusion. Optional game-variant roots remain conditional.


## Auction, training, professions, guild bank and stable

Service lists use the same flat rows and cropped item treatment. Recipe labels,
trainer costs, prices and pet names keep their native status colours. Scroll-box
initialization restyles recycled rows without adding duplicate hooks; hover
animations stop when the row is released/hidden. Native selection art remains.

Reviewed against pinned AuctionHouseItemList, ProfessionsRecipeList and
GuildBankUI XML. Optional trainer/stable variants are detected by existing
region keys; unsupported or absent variants are not invented. Service fixtures
exercise late-row creation, recycling, selection preservation and hover cleanup.


## Merchant, bank, mail and trade

Item slots and content rows share the character icon/quality treatment and gold
hover wash. Classic global Name/Sender/Subject region suffixes are recognized
alongside modern parent keys. Money text uses the UI font without changing
amounts; bank locks, trade warnings, quest-item markers and selection stay native.
Merchant/mail/trade global updates and events refresh recycled content.

Source: pinned Camelot BankFrame.xml, Mainline MerchantFrame.xml/TradeFrame.xml
and [MailFrame.xml](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_MailFrame/MailFrame.xml).
The commerce fixture discovers each root, exercises click preservation and
repeat refresh, and checks money and disabled overlays.


## Quest and map content

Quest, gossip and detail parchment is replaced with dark surfaces; dark neutral
prose becomes pale text while requirement/status colours remain native. Refresh
events are deferred and coalesced; QuestInfo_Display and quest-list global
post-hooks cover text rebuilt while the window stays open. Reward icons reuse
the quality-strip decorator.

The map pass targets the side toggle and recognized coordinate, bounty, action
and threat overlays in the native overlay registry. The large threat holder is
never backed: only its small eye is decorated. Map canvas, pins, positions,
tracking, zoom and native click handlers are unchanged.

Source: [WorldMap overlay registry](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_WorldMap/Blizzard_WorldMap.lua)
and Mainline QuestInfo.lua/GossipFrame.xml at the same pinned revision.
The quest fixture checks prose refresh, semantic colours and canvas exclusion.


## Spellbook and talents

The spellbook page textures and talent backdrop become dark surfaces. Nested
spell buttons use cropped icons and flat outlines; cooldowns, disabled overlays,
rank text, search markers and native casting/dragging remain intact. Talent
outlines copy the native rank text colour every 0.1 seconds while visible, so
uncommitted, locked and refund/error states follow Blizzard. Dependency lines
keep native endpoints/visibility and become thin flat strokes.

Source: [Forever talent art](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SharedTalentUI/Blizzard_TalentButtonArt.lua)
and the SpellBookItem/SpellBookFrame XML at that revision. The spells fixture
checks native handler preservation in combat, semantic overlays, colour refresh
and connection geometry. Native acceptance remains user-supplied.


The panels module now decorates the character window's equipment icons, stat
categories, reputation, skills and currency rows. Icons use the action bars'
crop and flat edge. The native quality border becomes a thin strip, retaining
Blizzard's colour and visibility updates. Rows have a dark backing and a gold
hover wash that fades in and out, cancelling when hidden.

The interior service keeps state in weak tables, never writes fields or secure
attributes on buttons, and preserves click, drag, tooltip, cooldown, disabled and
selection behavior. Only named window roots are walked, to a bounded depth.
OnShow and scroll-box acquisition/initialization cover late and recycled rows.
Forbidden frames and refused operations are reported once as an Interiors client
limit. Disabling panels and reloading leaves the interior stock.

Source: Forever [CharacterFrame](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/CharacterFrame.xml),
[PaperDollFrame](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/PaperDollFrame.xml)
and ReputationFrame at the same revision. Absent window names are optional:
source presence across game variants is not a promise of runtime availability.

Automated coverage: `tests/interiors.test.lua` checks cropped protected items,
quality-strip geometry, handler preservation, hover cancellation, idempotence,
late rows, forbidden reporting and disabled-panel behavior. Native/game-client
acceptance is supplied by the user; these are simulated checks, not client
observations. New TOC files require a full client restart.

