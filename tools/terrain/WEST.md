# Western Dun Morogh terrain

This local exact-build delivery addresses the reported 35.5,46.6 position and
archived Frostmane Hold marker 25.95,40.57. It is a static walking estimate, not
verified native traversal or a quest action corpus.

## Source and profile

Eight source ADTs 30–33 /41–42 are acquired from Forever 1.60.1.69913/enUS with
the existing pinned TACTTool. West/central output bounds are nav X
[-1066.6673177083333,1066.666015625], Z[-5866.667317708333,-5150].
Root/obj/WDT hashes and geographic IDs are in west_profile.py. The complete
481-file acquisition profile (15,923,600 bytes) stays outside Git and is pinned
by canonical SHA256 150ee6e381a9a0cda778f51d88c5a0e9c2f51d643e1f0c5f0f7430dcd722b640.
The old profile remains unchanged.

The .25-yard raster keeps radius .5yd, height 1.8yd, climb .3yd, slope 40° and a 64 yd
tile core. Its generator border is 1.25 yd versus 2 yd at the old .5-yard raster.
MCNK source selection retains 2 yd padding; all relevant WMO/M2 collision is
still included. No movement links are guessed. Recast portal heights and
all exported polygons/exclusions receive independent compiler/runtime checks.

The root-aware legacy liquid sentinel follows the independently checked
[TrinityCore extractor semantics](https://github.com/TrinityCore/TrinityCore/blob/1f70838eff729a099c32b2e50f8c122bf385c970/src/tools/vmap4_extractor/wmo.cpp).
A liquid chunk or has-liquid flag still prevents admission.
Empty MODD can omit MODI; all populated references retain strict bounds.
The exact 203171 M2 v274 GnomereganVent collision arrays match the unmodified
pinned wow.export loader; its hash-specific evidence is recorded in
m2-274-collision-profiles.json. No general v274 compatibility is inferred.

Unsupported WMO root 7801267 LOD layout and placement 350747 doodad flags each
remove their whole MODF footprint. Six MH2O cells in 31_41 (x14/15,y11/12/13)
remove their entire horizontal MCNK footprints, on all floors, with radius
padding. Their layout is checked against the pinned source and
[ADT loader framing](https://github.com/Kruithne/wow.export/blob/c2fd7bde36a712be78a5da896c995b84fbfa2545/src/js/3D/loaders/ADTLoader.js).
There are no swim links or inferred safe building interiors.

## Reproduction

From the repository, supply actual local paths and new external output folders:

```text
python -B tools/terrain/acquire_west.py --existing "<verified old acquisition>" --game-root "<WoW root>" --tact-tool "<pinned TACTTool.exe>" --output "<new acquisition>"
python -B tools/terrain/portable_west.py --source "<new acquisition>" --output "<new bake>"
```

The first command reuses verified old files and extracts new exact-build
dependencies read-only. It rejects any final profile that differs from the
pinned complete inventory. The second verifies every source file, copies
authored tools, installs lockfile-pinned Recast with scripts disabled, decodes
collision, bakes twice and compares every output byte, then compiles the local
RikUIQuestTerrain companion. Output paths are disjoint and new. No assets enter Git.

The delivery reproduced 410 files identically and compiled 414 companion files:
408 shards, 37,644 polygons, 73,648 directed portals, approximately 14.3 MB.
Final retained manifest SHA256:
88043ddd25a5608fd6c3554578000a37721d3e911039e684867ed8d6c7550dc5.
Path-specific parser/source provenance means another directory can change the
manifest hash even with identical shard geometry. Use that run's printed hash.

Tests:
```text
python -B tools/terrain/test_west.py --source "<acquisition>" --geometry "<bake>/geometry-west.json" --manifest "<bake>/region/manifest.json" --reference "<independent M2 reference JSON>"
python -B -m unittest discover -s tools/terrain -p test_compile_quest_terrain.py
luajit tests/quest-terrain-data.lua "<bake>/RikUIQuestTerrain"
luajit tests/quest-nav-visual.lua "<bake>/RikUIQuestTerrain" "<packet>" .355 .466 "<new visual prefix>" require-complete 1.4 412
```

The independent M2 reference JSON is produced by the pinned unmodified M2Loader
over exact 203171 bytes and includes all converted collision positions/indices.
The test compares every value, not only counts. Original-region parser/topology
reproduction remains available through portable_region.py.

## Actual results and limits

The old installed region did not cover either current screenshot position or
Frostmane marker. Merely expanding at the old raster covered 4/9 rounding samples;
finer sampling covers 8/9, including the center. That center produces an 85-polygon
route in production Lua, with 7,140 search work. Simulated movement at .35yd and 1.4yd
steps completes without reversals or near-waypoint hides. Four independent
Dijkstra comparisons also pass.

One rounding-corner sample remains uncovered; older recorded indoor starts remain
unresolved. Screenshot coordinates do not establish exact current player altitude
or position. Shared edges resolve only via actual matching-height portals.
Native physics, dynamic obstacles, real walking and interactions remain unverified.

Copy the compiled companion into the client's Interface/AddOns after preserving
the previous copy. Verify hashes against compile-receipt.json. A full WoW restart
is necessary because the companion TOC adds terrain files. No completion,
combat, travel or export testing is required to install it.
