# Panel skin

`src/modules/panels/panels.lua` and `src/modules/panels/panels-skin.lua` put the flat RikUI look on Blizzard's
windows without replacing anything inside them. Disable the `panels` module in
`/rik config` and reload to get the stock look back; nothing is saved or
changed permanently.

## Windows

| Window | Frame on 69913 |
|---|---|
| Character | `CharacterFrame` (camelot's own file) |
| Spellbook and talents | `PlayerSpellsFrame`, load on demand in `Blizzard_PlayerSpells` |
| Quest log | `QuestMapFrame` inside `WorldMapFrame`; the chrome is on `WorldMapFrame.BorderFrame` |
| Merchant | `MerchantFrame` |
| Bank | `BankFrame` (camelot's own file) |
| Mail | `MailFrame`, `OpenMailFrame` |
| Trade | `TradeFrame` |
| Quest giver and gossip | `QuestFrame`, `GossipFrame` |

The Classic `SpellBookFrame` and `QuestLogFrame` files are excluded from the
camelot game type, so they are not targets.

### The rest of the windows

Added on 2026-09-20 so every Blizzard window opens in the same look. The skin
touches only the chrome keys a window has and a global that does not exist is
skipped, so a name the client lacks costs nothing. `/rik debug` prints how many
were found.

Frame names found in the 69913 source tree: `ClassTrainerFrame`,
`AuctionHouseFrame`, `FriendsFrame`, `CommunitiesFrame`, `MacroFrame`,
`ProfessionsFrame`, `ProfessionsBookFrame`, `InspectFrame`, `DressUpFrame`,
`ItemTextFrame`. Source files exist for `GuildRegistrarFrame`, `PetitionFrame`,
`TabardFrame`, `HelpFrame` and `AddonList`.

Names taken from long-standing convention and not read in source:
`StableFrame`, `GuildBankFrame`, `TimeManagerFrame`, `GroupLootHistoryFrame`,
`SettingsPanel`. Their addon folders exist in the tree.

The tree holds every game type, so a name being in it does not mean Forever
loads that addon. Which of these windows exist is only known in game. A window
whose template differs from the shared chrome keeps whatever pieces it does
not share; the auction house, communities and settings windows have the most
content of their own and are the likeliest to look half-done.

### The last windows

A third list, read from the 69913 source on 2026-09-20: `PVEFrame`,
`LFGParentFrame`, `ChannelFrame`, `ItemSocketingFrame`, `ChatConfigFrame`,
`RaidInfoFrame`, `TaxiFrame`, `CollectionsJournal`, `GuildControlUI`,
`DeathRecapFrame`, `PVPMatchScoreboard`, `PVPMatchResults` and
`CooldownViewerSettings`. They needed three chrome kinds the earlier windows
did not have:

- Dialog border. `ChatConfigFrame` and `RaidInfoFrame` keep their art in a
  `Border` child frame and a `Header` with `LeftBG`, `RightBG`, `CenterBG` and
  `Text`. The border frame is faded, the header art too, and the header text
  becomes a gold RikUI heading.
- Corner pieces. `BasicFrameTemplate` (`TaxiFrame`) and
  `TranslucentFrameTemplate` (`GuildControlUI`) name their art
  `TopLeftCorner`, `BotLeftCorner` or `BottomLeftCorner`, `TopBorder` and so
  on. Those keys are in the strip list.
- Hand-drawn art. `LFGParentFrame` and `RaidInfoFrame` draw unnamed textures
  straight on the frame. Targets marked `regions` have every `Texture` region
  of the frame faded. The regions are listed before the fill and edge exist,
  because `GetRegions` also returns regions an addon made.

The close button is looked up as `CloseButton`, then `CloseXButton`
(`DeathRecapFrame`), then the global `<window>CloseButton`
(`LFGParentFrame`).

The last audit of the 69913 source added twelve more:

- Hand-drawn (`regions`): `AchievementFrame`, `CalendarFrame`,
  `StopwatchFrame`, `SideDressUpFrame`. Only the window chrome goes flat.
  Calendar day buttons and achievement rows keep their own art, which needs a
  look in game: if the mix reads worse than stock, drop the two targets.
- `BattlefieldMapFrame` (the zone map, Shift-M) is a map canvas. Its border
  pieces are unnamed textures on `BorderFrame`, so that frame is the chrome,
  it is marked `regions`, and it gets no fill, like the world map.
- Template windows: `TransmogFrame`, `PetStableFrame`,
  `QuestLogPopupDetailFrame`, `InspectRecipeFrame`, `ItemUpgradeFrame`,
  `ClickBindingFrame`, `ArchaeologyFrame`. The Camelot stable is
  `PetStableFrame`; the `StableFrame` target never matched on this build.

Still stock: `PlayerChoiceFrame`, `SplashFrame` and `GenericTraitFrame` are
full-art layouts with no chrome to flatten. The stopwatch's close button is
`StopwatchCloseButton` on its tab frame, which the lookup does not find.

The controls inside every window are done by [window controls](controls.md).

## What changes

On a window's first show:

- the `NineSlice` frame art, `Bg`, `TopTileStreaks`, `TitleBg` and the portrait
  (`PortraitContainer`, `PortraitFrame`, `portrait`) are faded to alpha 0;
- a dark flat fill goes under everything (`BACKGROUND`, sublevel -8) with the
  1px RikUI border around it;
- the title takes the RikUI font in gold;
- the close button loses its textures and gets a flat box with an `x` and the
  hover highlight;
- the `Inset` loses its art and gets a darker flat fill and border;
- bottom tabs (`frame.Tabs` or `frame.TabSystem.tabs`) lose their nine art
  pieces and get a flat backing, border, the RikUI font and a 2px blue accent
  on the selected tab.

Every show fades the window in over 0.15s.

The map window gets no fill: its chrome frame sits above the map canvas, and a
fill there would cover the map. The camelot character window's side mode tabs
use their own template and stay stock, as does everything inside the windows:
item slots, spell buttons, the talent tree, merchant items, mail rows.

## How it stays safe

A window is never reparented, moved, resized, shown, hidden or given a new
script. The module calls `HookScript("OnShow")`, sets alpha on regions, sets
fonts and creates child regions. None of those is a protected operation, so a
window first opened in combat is skinned on the spot. Art is faded, not hidden,
so Blizzard's own `Show` calls on it change nothing.

Each chrome key is touched only when it holds a region; a window that lacks one
keeps that piece stock. Each window is skinned under `pcall`. A failure prints
one `Panels skin <name>` line, the window is not retried, and the other windows
are unaffected.

Tab selection is followed with post-hooks: `PanelTemplates_SelectTab` and
`PanelTemplates_DeselectTab` for classic panel tabs and a tab's own
`SetTabSelected` for `TabSystem` tabs. The close button keeps Blizzard's click
handler.

## Discovery

Windows are looked up by global name at login and again on every
`ADDON_LOADED`, which is how `PlayerSpellsFrame` is found when the player first
opens the spellbook. A window already visible when it is found is skinned
immediately.

## Diagnostics

`/rik debug` prints `Panels hooked=<n> skinned=<n> failed=<n>`.

## Verification

`tests/panels.test.lua` fakes windows with the shared chrome keys. It proves: a
window never opened is untouched; the strip, fill, border, title font and inset
on first show; the fade on every show without a second skin; the close button's
look and that Blizzard's click handler still runs; tab art, backing, font, the
initial accent and the accent following selection; the map window's chrome on
`BorderFrame` with no fill; a load-on-demand window found on `ADDON_LOADED`; a
first open in combat with no protected write; `TabSystem` tabs following
`SetTabSelected`; a failing window reported once while the rest work; the debug
line; missing windows skipped; a client without the tab functions; a disabled
module leaving every window stock.

The stub cannot show the real windows. The chrome keys on camelot's own
`CharacterFrame` and `BankFrame`, whether Blizzard resets any faded alpha and
how the fade behaves in combat are unverified. Beta checklist:

1. Reload and open each window in the table. Each should be dark and flat with
   a gold title and an `x`. Note any window that still shows parchment, a
   portrait ring or a stock tab.
2. Use every control you normally use: equip an item, drag a spell to a bar,
   spend a talent point, buy and sell, send mail, trade.
3. Open the character window and the map in combat and watch for a
   blocked-action message or a Lua error.
4. Switch tabs in the merchant and spellbook windows; the blue accent should
   follow.
5. Disable `panels` in `/rik config`, reload, and check the stock look is back.

### Beta checklist for the added windows

1. Visit a class trainer, the auction house and a stable master; open the
   friends list, macros, professions, the addon list and the options window.
2. Each should open flat with a working close button and tabs. Note any that
   keep stock art or look half-skinned.
3. `/rik debug`: `Panels hooked=<n>` rises as load-on-demand windows arrive.

### Beta checklist for the last windows

1. Open the group finder, the chat settings (right-click a chat tab), the
   raid info from the raid tab, a flight master and the socketing window if
   you have a socketed item. Each should be flat with a working close button.
2. In the chat settings the heading should be gold and the ornate border gone.
3. Die once and open the death recap if the client offers it.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_UIPanels_Game.toc: which character, bank, merchant, trade, quest map and spellbook files camelot loads and excludes](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Blizzard_UIPanels_Game.toc)
- [Camelot/CharacterFrame.xml: the side mode tabs](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/CharacterFrame.xml)
- [Camelot/Blizzard_PlayerSpellsFrame.xml: PortraitFrameTemplate, TabSystem, the spellbook and talents children](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_PlayerSpells/Camelot/Blizzard_PlayerSpellsFrame.xml)
