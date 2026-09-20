# World map

The map uses one quest interface: Blizzard's existing right-hand quest log,
including search, objectives, tracking and quest details. Native map markers,
breadcrumbs, filters, coordinate readout and the quest-panel toggle stay in place.

RikUI uses continuous charcoal surfaces across the header and full quest panel,
including the scrollbar gutter. Breadcrumbs and category headers use subtle
bottom dividers instead of outlined boxes. Map actions are text controls with
hover feedback; the quest count is unboxed. Search keeps a field boundary.
Neutral navigation and category text distinguish structure from native quest
status colors. The native quest frame's filigree and parchment are removed. Quest titles and objectives
use the RikUI typeface while retaining native status colors and icons.

Two small controls share the title row, leaving the terrain and coordinates clear:

- **Fog: on/off** shows the current state. On preserves normal exploration;
  off reveals terrain in blue without changing exploration progress.
- **My location** returns to the player's current zone.

The duplicate quest drawer, Pins and Up buttons, second coordinate readout and
permanent navigation instructions have been removed. Navigation tips live in the
My location tooltip. Old quest-drawer preferences are ignored and no longer
appear in settings. Fog is saved per profile and remains available in /rik config.

Creating controls and returning to the player wait for or are guarded during
combat. Disable the worldmap module and reload to restore native presentation.

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

- worldmap.lua: header, native quest-panel chrome, breadcrumbs and round buttons.
- worldmap-navigation.lua: guarded return-to-player action and safe API reads.
- worldmap-terrain.lua: reversible unexplored-art rendering.
- worldmap-tools.lua: compact header controls, profile controls and coalesced refresh.

Client API failures and secret values never become invented coordinates.
No quest snapshot is persisted. Only user preferences enter the profile.
The existing breadcrumb skin keeps one decoration per button and does not fade
its own regions on repeated refreshes.

/rik debug includes bar, crumbs, failed, tools and reveal state, plus current map
ID, frame alpha, canvas dimensions, detail loading, and exploration pin dimensions,
alpha and waiting state. Capture it with the map open if rendering fails.

## Verification

Automated checks cover reveal/restore, reused textures, newly explored regions,
unknown art, dataset tile geometry and allocation bounds, single-list presentation,
legacy preferences, return-to-player navigation, secret and
failing reads, combat-first-open and disabled-module behavior. Existing skin,
manifest, global-ownership and layout checks remain enabled.

Native acceptance still requires the Forever client:

1. Restart after installing the new TOC entries. Open a partially explored zone;
   turn fog off, zoom and pan, explore an area, then turn fog on.
2. Cross zone/continent/dungeon boundaries and change floors. Check for stale
   tiles, incorrect crops, protected-action errors and map clipping.
3. Use the native quest list: search, select, track and collapse it. Confirm no
   second list or coordinate readout appears, including with old saved profiles.
4. Check header controls in minimized and maximized maps, with the
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
