# Western Dun Morogh terrain

Historical western/central delivery. [MAP.md](MAP.md) supersedes its installation
and unfinished full-map compiler/loading status; the source and replay notes below
remain useful regression evidence.

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

Unsupported WMO root 7801267 LOD layout still removes its whole MODF footprint.
Placement 350747 is now decoded: MODD high-byte flag 2 is InteriorLighting
([wowlib enum](https://skarndev.github.io/wowlib/python/wmo/root-chunks/)), not
collision behavior. The pinned TrinityCore extractor likewise retains the
instance transform and model collision independently of this flag. Other
unverified flag bits remain unsupported. Tests toggle this lighting flag across
real colliding doodads and require identical collision arrays.

The former flag gate erased outdoor ground above the cave, including the user's
42.9,47.2 screenshot location. Its removal restores 4,112 polygons without changing
radius, height, climb, slope or creating movement links. Six MH2O cells in 31_41 (x14/15,y11/12/13)
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
408 shards, 41,756 polygons, 81,476 directed portals, approximately 15.7 MB.
Lighting-corrected retained manifest SHA256:
8d03f166107abeeb9ba61d887edc2ea7274a5f1127d5a29bdd4548b7f5b9fa78.
The compiler's offline byte cap is 32 MiB; runtime polygon/portal/shard caps
remain unchanged. Original 16 MiB JSON cap rejected the restored 17.4 MB input.
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

## Grizzled Den replay

The rounded screenshot center 42.9,47.2 now has a 131-polygon modeled route to
the archived quest 313 POI vicinity. The final 4.8437-yard gap is not traversed or
drawn as walkable. Five of nine rounding samples route; four require prior
floor continuity or native altitude because outdoor and cave surfaces overlap.
No floor is guessed on a cold start. A simulated .12-yard/60fps traversal completes
4,394 steps with zero reversals. Adding .15-yard sideways perturbations initially
exposed eight aim reversals at the cave bend. Replacing behind-portal midpoint
bias with local corridor direction and rechecked aim continuity completes 4,411
steps with zero reversals and 312 distinct instructions.
The replay HTML/JSON and static PNG remain outside Git. This demonstrates
production Lua against real geometry, not actual native walking.

## Full-map acquisition (not yet installed)

`acquire_map.py` acquires the 70 WDT-mapped tiles 28–37 /39–45 covering the
exact-build Dun Morogh projection rectangle. It uses the same pinned TACTTool,
source identity and per-file hashes, with explicit 8,192-file /256 MiB ceilings.
The retained acquisition contains 1,590 files, 77,298,678 bytes; canonical profile
SHA256 is fc51a45b8de42ca240b59a8fc3faadc5329e881ec4bc93e15e83f3d514a84958.
The complete profile and client assets remain outside Git.

```text
python -B tools/terrain/acquire_map.py --existing "<verified old acquisition>" --game-root "<WoW root containing Data>" --tact-tool "<pinned TACTTool.exe>" --output "<new full-map acquisition>"
```

Missing parallel extraction outputs receive one serial retry, preserving both
logs and their actual encoding keys. No existing output is overwritten. WMO
7801267 and 7952336 have unsupported LOD layouts; 113881 has an unsupported
selected doodad-set index. Their roots remain acquired and must retain collision
exclusions until decoded. This acquisition is not a navigation-pack installation:
the compiler and runtime were unfinished at the time of this acquisition. They
are now implemented and verified as described in [MAP.md](MAP.md).

## Earlier western results and limits

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
