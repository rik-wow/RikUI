# World map

The world map keeps Blizzard's canvas, zoom, quest pins and interactions, with a
RikUI breadcrumb skin, compact toolbar and optional quest drawer. Disable the
worldmap module in /rik config and reload to return to the native presentation.

## Controls

- **Fog: on / Reveal all:** normal exploration fog is the default. Reveal all
  draws unexplored terrain in a subtle blue tint; clicking again restores normal
  fog immediately. This never changes exploration progress or achievements.
- **Pins:** switches the native questPOI setting. Blizzard continues to own
  quest markers, objective areas, tooltips and route behavior. This setting is
  client-owned, so changes made elsewhere are reflected in the toolbar.
- **Quest list:** opens a six-row, paged list. This map shows quests with supplied
  objective coordinates on the displayed map; All quests also shows log entries
  without coordinates. Completed quests sort first, followed by tracked quests.
  Click a quest to select its native route and open details; Shift-click toggles
  tracking. The list refreshes on quest and map events.
- **Player / Up:** return to your current zone or navigate to the parent map.
- Player coordinates refresh five times per second while the map is visible.
  Missing or restricted positions display --.

Fog, list visibility and the map-only filter are stored per RikUI profile. These
settings also appear on the World map page in /rik config. The list starts
collapsed to keep the map clear. Quest actions and navigation are guarded during
combat; creating the toolbar waits until combat ends. Native map interactions
continue to work independently.

Quest locations come from C_QuestLog.GetQuestsOnMap. This is not an external
quest database: when the client supplies no location, the UI says so rather than
inventing a pin. Native quest-offer providers remain responsible for available
quest markers.

## Reveal-all architecture and data

data/map-terrain.lua contains numeric asset metadata from the exact target
Forever build, 1.60.1.69913: 1,073 unconditional base-layer overlays across 84 map
art IDs. It contains no copied addon implementation or bundled Blizzard artwork.

Sources:
- [WorldMapOverlay CSV](https://wago.tools/db2/WorldMapOverlay/csv?build=1.60.1.69913)
- [WorldMapOverlayTile CSV](https://wago.tools/db2/WorldMapOverlayTile/csv?build=1.60.1.69913)

Rows are grouped by UiMapArtID, excluding PlayerConditionID != 0. Both Flags 0
and Flags 4 records are retained; filtering out nonzero flags removed valid terrain.
Records without base-layer tiles are omitted.
Each entry stores texture width, height, X/Y offsets, and tiles joined through
WorldMapOverlayID. Tile entries store RowIndex, ColIndex and FileDataID; only
LayerIndex 0 is included. Preserve this build provenance when regenerating data.

worldmap-terrain.lua owns a reusable texture layer on the native exploration pin.
It uses the current art ID and tile dimensions, excludes already explored
rectangles, crops partial tiles to the file's power-of-two dimensions, and
registers textures with the canvas mask. Reveal textures use the exploration
provider's artwork layer below native explored textures. Addon textures do not
join the native load group: an unavailable reveal asset must never hold the
entire native exploration pin at alpha zero. Its native sizing method runs
before drawing, and native alpha is restored only when it is not awaiting assets. It post-hooks instance RefreshOverlays
so map, exploration and art-layer changes clear stale textures. It does not
replace a data provider, write global mixins, alter native texture pools, or
change native fog-of-war gameplay overlays.

Only the base art layer is supplied. Unsupported map art keeps normal artwork;
the map toggle is unavailable there, and switching maps clears previous reveal
textures. Conditional/phased terrain is intentionally not guessed. Normal mode
allocates no terrain textures. A pin reuses at most 256 textures.

Map opening defers addon construction to the next frame and refreshes native
canvas geometry and explicitly rebuilds detail layers before refreshing providers.
RefreshAll alone skips cached detail layers and does not initialize pin dimensions.
The panels module leaves world-map alpha animation to Blizzard's movement fader.
This applies to the first opening after login as well. Closing the
map before the deferred callback cancels that work; combat defers it safely.

## Code boundaries

- worldmap.lua: breadcrumb and round-button skin; supports late map loading.
- worldmap-navigation.lua: readable quest snapshots and guarded native actions.
- worldmap-terrain.lua: reversible unexplored-art rendering.
- worldmap-tools.lua: toolbar, quest drawer, profile controls and coalesced refresh.

Client API failures and secret values never become invented coordinates.
No quest snapshot is persisted. Only user preferences enter the profile.
The existing breadcrumb skin keeps one decoration per button and does not fade
its own regions on repeated refreshes.

/rik debug includes bar, crumbs, failed, tools and reveal state, plus current map
ID, frame alpha, canvas dimensions, detail loading, and exploration pin dimensions,
alpha and waiting state. Capture it with the map open if rendering fails.

## Verification

Automated checks cover reveal/restore, reused textures, newly explored regions,
unknown art, dataset tile geometry and allocation bounds, quest filtering,
native selection/tracking, marker controls, player/parent navigation, secret and
failing reads, combat-first-open and disabled-module behavior. Existing skin,
manifest, global-ownership and layout checks remain enabled.

Native acceptance still requires the Forever client:

1. Restart after installing the new TOC entries. Open a partially explored zone;
   toggle Reveal all, zoom and pan, explore an area, then return to Fog: on.
2. Cross zone/continent/dungeon boundaries and change floors. Check for stale
   tiles, incorrect crops, protected-action errors and map clipping.
3. Open the quest list; switch filters and pages, click a quest, Shift-click to
   track/untrack, and toggle Pins. Test missing-location quests and an empty log.
4. Check toolbar/drawer placement in minimized and maximized maps, with the
   native quest panel open, at small UI scales and with gamepad controls.
5. Repeat during combat; verify only the intended guarded actions are deferred
   or refused, then switch profiles and restart to check persistence.

Stub tests establish behavior, not in-game visual quality or secure execution.

## Client source evidence

Reviewed against the [Forever 69913 source snapshot](https://github.com/Gethe/wow-ui-source/tree/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):
Blizzard_WorldMap, MapExplorationDataProvider, QuestDataProvider, and generated
QuestLog / MapExploration API documentation. The native exploration renderer
provides the tile sizing and canvas-layer contract; quest providers establish
the questPOI and location contracts.
