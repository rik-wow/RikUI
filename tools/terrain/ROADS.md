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
   - quest patches: select polygons within 48 yards of a corpus spawn or
     objective bounds plus 24 yards, then retain their complete connected
     pieces inside each 128-yard cell and one ring of pieces connected by
     existing portals. This keeps open crossings and nearby approaches available
     instead of leaving thin routes to network nodes.
4. **Install.** `install_roads.py install` swaps the addons in with an
   ownership receipt; `retire` moves the legacy `RikUIQuestTerrain*`,
   `RikUIQuestPaths*` and `RikUIQuestSeams*` folders out of AddOns into a
   backup directory. Nothing is deleted.

## Water and open crossings

Swimming costs apply only within occupied liquid subcells and their local
surface-height range, allowing 0.6 yards for bake rounding. Dry terrain above
water keeps walking cost; empty liquid-mask cells do not remove lake-floor
polygons or add swim penalties. Actual submerged surfaces remain excluded.

Quest patches retain existing connected geometry throughout each selected
cell. They preserve obstacle boundaries and directed portals while allowing
short routes across open ground, including solid frozen lakes.

## Travel links

`travel_links.py` compiles client DB2 exports (TaxiNodes, TaxiPath,
TaxiPathNode, AreaTrigger from wago.tools for the pinned build) into stops and
links:

- flight points with their faction (TaxiNodes flags: 1 Alliance, 2 Horde);
- flights between two points of a shared faction, timed from the path length;
- boats and zeppelins: TaxiPaths with waiting nodes that do not run between two
  flight points. Each waiting node is a dock or zeppelin tower, named after the
  nearest flight point; a ride goes to the next stop around the loop and costs
  its sailing time plus half the modelled cycle as the wait;
- the Deeprun Tram between AreaTriggers 2173 (Stormwind) and 2175 (Ironforge).

`road_network.py --travel` attaches every stop to its world's nearest network
node (flight masters within 80 yd, docks within 160) and stores walking costs
between the stops of each world in the catalog. The index carries all stops
and links. Speeds are estimates (flight 32 yd/s, transports 30 yd/s): client
data has the paths but not the speeds or schedules.

At runtime `quest-road-travel.lua` runs a sliced Dijkstra from the player and
from the destination to every stop, then a small search over start, stops and
goal. Flights count only when both points are discovered
(`C_TaxiMap.GetTaxiNodesForMap`) and the faction matches. Unknown or conflicting
discovery observations cannot unlock flights. Taxi status events refresh the
cache immediately; remaining flight legs are rechecked while approaching a
flight master and discarded if either endpoint becomes unavailable. Guidance walks one
leg at a time, says which link to take at each stop, and replans after a
flight, a ride or a map change.

Lifts and portals come from AzerothCore's world database
(`azerothcore_travel.py`: gameobject spawns, gameobject_template, areatrigger_teleport),
because the client has each lift's animation (TransportAnimation) but not
where it stands. Each lift spawn gets a bottom and a top stop at the spawn
height plus the animation's lowest and highest offset: Undercity (3),
Thunder Bluff (4 cars), the Great Lift, Gnomeregan and the Searing Gorge
scaffold. Lift and portal stops attach by a height-weighted distance so a
landing never joins the floor above or below it. Named portals only: the
Rut'theran and Darnassus pair and the Stormwind Wizard Sanctum (whose tower
interior has no network nodes, so it stays unattached). The same data gives
boat and zeppelin speeds (30 yd/s). Guidance treats walking 25 yd away from a
lift or portal stop as having taken it and replans from the link's far stop.

## Client patches

`verify_build.py` extracts every file of the world acquisition profile from a
new client build with the pinned TACTTool and compares SHA-256s. For
1.60.1.69977 all 15,697 terrain sources and every DB2 table the pipeline
reads were identical to 1.60.1.69913, so `quest-builds.lua` maps 69977 to the
69913 data build instead of rebuilding. A patch that changes sources needs a
rebake of what they feed.

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

Loading never does more than one synchronous addon load per frame: the
continent network (about 2 MB) loads alone, then one patch addon (at most
1 MB) per frame, then patch cells decode 64 polygons at a time and the NavMesh
validates in slices. Recently decoded cells are cached for the next plan.

Floor choices, learned hunting anchors and journey arrival receipts still
come from the old regional mesh. With the legacy packs retired they are
unavailable; road mode doesn't fake them. The compact gateway runtime
(`quest-paths`, `quest-path-graph/search/route/navigate/compose`) was removed.
A single regional pack can still be installed and routes on its own mesh.

## Measured results (data build 69913, v11)

| World | Baked polygons | Network nodes | Network data | Patch polygons | Addons |
| --- | ---: | ---: | ---: | ---: | ---: |
| Eastern Kingdoms (0) | 3,048,191 | 21,141 | 4.5 MB | 1,448,399 | 97.5 MiB |
| Kalimdor (1) | 3,703,985 | 26,350 | 5.1 MB | 1,831,803 | 122.7 MiB |
| Alterac Valley (30) | 113,426 | 920 | 0.2 MB | 0 | 0.2 MiB |

A full compile of all worlds takes about 1 minute 50 seconds on 32 cores
(`road_parallel.py`): 52 seconds to validate and cache every batch, then about
13 seconds of network search and 7 seconds of patches per continent. The
cache in `road-network-cache/` beside the output is keyed by the input hash,
bake-tool hashes, routing compiler hashes and raster directory. Cost-model
changes cannot reuse stale swimming classifications. A rerun with different
patch radii can still skip the load.

With 20-yard spawn radius, 10-yard margin and 80-yard cap the patches drop to
569k polygons (40.2 MB) and 709k (50.4 MB). Quest areas cover more than half
of each continent's walkable mesh, so patch size doesn't shrink much with the
radius.

Keeping approximable geometry (unknown ADT chunks, WMOs with unfamiliar chunks,
water as a swim surface, lava only below its surface) joined the continents:
the Eastern Kingdoms network is one piece of 18,445 nodes from Silverpine to
Booty Bay, Kalimdor one of 22,108 from Orgrimmar to Thousand Needles. What
stays apart is joined by travel links (lifts, the Darnassus portal, boats) or
is an interior with no way in on foot.

## Installed rebuild (2026-09-23)

All 2,290 batches across worlds 0, 1, 30, 489, 529, 2991 and 2997 were rebaked
with occupied-subcell liquid bounds. The resulting pack contains 278 addons
and 12,428 files (271,420,081 bytes). Eastern Kingdoms retains 1,704,013 patch
polygons; Kalimdor retains 2,192,933. Compiler and runtime bounds remain in place.
The external output is `D:/RikUI-local/road-network-liquid-fix-20260923-v2`,
receipt SHA-256 `9d75d2baf27473b84d8ed98195625b057bdf141775569784f92c74f7d7d80beb`.
The installer verified all 12,428 installed files and retained the old packs at
`Interface/.rikui-road-stage-j5wpkysq/previous`. A full client restart is needed
to discover the changed LoadOnDemand addon set.

A host replay from Dun Morogh 54.1,44.8 to 56.6,44.2 now uses a 125-yard
mesh-only crossing instead of the previous 180-yard network detour. This
probes the screenshot location, not a captured exact quest-giver coordinate.
The nearby 53.1,44.8 approach also has a direct route. Points 53.0,44.8 and
53.5,44.8 have no polygon in the source bake itself; their coverage limits
remain explicit. No unrestricted straight-line shortcut was substituted.

All seven generated graphs pass ten sampled A*/Dijkstra comparisons each,
including genuinely disconnected node groups. The archived quest 315 replay
matches its decision and arrives after 559.5 yards without route swaps or
replans. On the installed pack, the first route appears at frame 112; the
largest callback is 24 ms and largest addon load is 17 ms on this host.
Native acceptance follows the user's standing policy; these are host checks
and do not claim agent-observed game traversal.

## Installed state (2026-09-22)

`install_roads.py` installed 145 addons (road index, five world networks,
139 patch addons) and verified 8,317 files. `retire` moved 805 legacy folders
(Dun Morogh regional mesh, compact paths, five-world packs) and their two
ownership receipts to `D:/RikUI-local/retired-legacy-navigation-20260922`.
A full client restart is needed for the new TOCs.

Host replays on the installed files (`tests/quest-adaptive-roads.lua`, quest
315, all six flavors): first route at frame 59-65 (about 1.2 simulated
seconds, versus frame 242 on the regional mesh), decision replay match with
596 candidates, a 559.5-yard walk with no replans, and a worst callback of
16-22 ms on this PC. The worst frame is the one-time network addon load.

## Tests

```text
python -B tools/terrain/test_world_bake.py
python -B tools/terrain/test_road_textures.py
python -B tools/terrain/test_quest_pockets.py
python -B tools/terrain/test_install_roads.py
luajit tests/run_tests.lua                                  # includes quest-roads
luajit tests/quest-roads-real.lua <network dir> <world> [pairs]
luajit tests/quest-roads-navigate-real.lua <network dir> <uiMapID> sx sy gx gy ...
luajit tests/quest-adaptive-roads.lua <AddOns root> <RIKQ packet> [questID] [frames] [flavor]
```

Everything here is modeled geometry. Native walking, doors, swimming and
transports are not verified.
