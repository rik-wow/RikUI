# Road network and quest patches

This replaces the Dun Morogh regional mesh and the compact gateway packs as
the way walking routes are made. Long travel uses a small walk network that
prefers roads. Detailed mesh only ships in patches around corpus quest spots,
so the last stretch to an NPC, cave or building still follows real geometry.

## Pipeline

1. **Bake the world.** `world_bake.py` as before, with placement index v4.
   Placements whose physics extent can't be decoded (PFDC, unproven PCOL,
   WMO doodad flag 0x20) are no longer fatal for their world. Their static
   footprint grown by 8 yards is carved out of the walkable mesh instead.
   `world_bake_parallel.py` runs one batch per process so a continent takes
   minutes instead of hours; it doesn't change the hashed bake tools.
2. **Classify roads.** `acquire_tex0.py` pulls the tex0 ADTs with the pinned
   TACTTool. `road_textures.py` decodes MDID/MCLY/MCAL, blends layers the way
   the client does, and writes a 256x256 road raster per tile. Textures count
   as road when their name matches road/cobble/street/pave, plus reviewed
   extras such as Dun Morogh's `ironforgerock09browncracks`. Texture names
   come from the community listfile, pinned by SHA-256.
3. **Compile the network and patches.** `road_network.py --capture` collects
   bake runs, then a compile run (all cores by default, `--workers 1` for the
   single-process path) builds, per world:
   - one node per connected piece of each 128-yard cell, preferring road
     polygons;
   - edges to neighbouring cells, found by Dijkstra over the real polygon
     graph, string-pulled through the portals and simplified to 1.5 yards;
     road terrain costs 0.6x, so routes follow roads;
   - redundant edges and node groups under 16 nodes are dropped;
   - quest patches: polygons within 48 yards of a corpus spawn, or objective
     bounds plus 24 yards, grouped by 128-yard cell, plus the in-cell path to
     that cell's network node.
4. **Install.** `install_roads.py install` swaps the addons in with an
   ownership receipt; `retire` moves the legacy `RikUIQuestTerrain*`,
   `RikUIQuestPaths*` and `RikUIQuestSeams*` folders out of AddOns into a
   backup directory. Nothing is deleted.

## Runtime

`RikUIQuestRoads` (always loaded) maps each UI map to its world's network
addon. `quest-roads.lua` loads a world's network on demand. When the player's
map has a network, `quest-road-guidance.lua` owns walking guidance:
`quest-road-navigate.lua` loads the patch cells around start and goal, walks
mesh legs to the nearest gateway nodes where a patch covers an end, and runs
A* (`quest-road-route.lua`) over the network between them. Outside patches
the end legs are straight open-ground legs to a node in the same cell,
labelled as such. `quest-road-follow.lua` follows the resulting polyline and
publishes the same display table as the corridor follower, so the arrow,
tracker and map dots are unchanged.

Floor choices, learned hunting anchors and journey arrival receipts still
come from the old regional mesh. Where that isn't installed they are simply
unavailable; road mode doesn't fake them.

## Measured results (build 69913)

| World | Baked polygons | Network nodes | Network data | Patch polygons | Addons |
| --- | ---: | ---: | ---: | ---: | ---: |
| Eastern Kingdoms (0) | 1,614,372 | 7,603 | 1.6 MB | 895,449 | 58.8 MiB |
| Kalimdor (1) | 2,222,225 | 10,500 | 2.2 MB | 1,241,450 | 81.6 MiB |
| Alterac Valley (30) | 100,965 | 813 | 0.1 MB | 0 | 0.1 MiB |

A full compile of all worlds takes about 1 minute 50 seconds on 32 cores
(`road_parallel.py`): 52 seconds to validate and cache every batch, then about
13 seconds of network search and 7 seconds of patches per continent. The
cache in `road-network-cache/` beside the output is keyed by the input hash,
so a rerun with different patch radii skips the load.

With 20-yard spawn radius, 10-yard margin and 80-yard cap the patches drop to
569k polygons (40.2 MB) and 709k (50.4 MB). Quest areas cover more than half
of each continent's walkable mesh, so patch size doesn't shrink much with the
radius.

The continent mesh is split into many pieces by water and structure
exclusions: Eastern Kingdoms has 163,710 connected pieces and only 16,680
edges between bake batches. Dun Morogh's Kharanos, Grizzled Den, Brewnall and
Coldridge are one piece; many zone-to-zone crossings are not. The network
reports no route rather than inventing a connection.

## Tests

```text
python -B tools/terrain/test_world_bake.py
python -B tools/terrain/test_road_textures.py
python -B tools/terrain/test_quest_pockets.py
python -B tools/terrain/test_install_roads.py
luajit tests/run_tests.lua                                  # includes quest-roads
luajit tests/quest-roads-real.lua <network dir> <world> [pairs]
luajit tests/quest-roads-navigate-real.lua <network dir> <uiMapID> sx sy gx gy ...
```

Everything here is modeled geometry. Native walking, doors, swimming and
transports are not verified.
