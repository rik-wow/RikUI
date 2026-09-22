# Dun Morogh regional terrain

This supersedes the western/central installation described in [WEST.md](WEST.md).
The exact-source compiler now covers the 70 acquired Dun Morogh ADTs and preserves
directed connectivity across runtime region boundaries. It is a static walking
model for Forever 1.60.1.69913/enUS, interface16001, not verified native traversal
or complete quest/world coverage.

## Reproduce

Use the hash-pinned acquisition produced by acquire_map.py, Python 3.13+, Node 24+
and a **new external directory**:

```text
python tools/terrain/portable_map.py --source "<verified map acquisition>" --output "<new external directory>"
```

The wrapper verifies all 1,590 source files (77,298,678 bytes), copies the authored
tools into the external directory, installs pinned dependencies without package
scripts, checks the tiler/filter, decodes terrain and collision, bakes twice,
compares every mesh output byte, validates topology and compiles regional addons.
It does not install or launch the game. The local reproduction compared 3,981
identical generated mesh files. Generated game assets remain outside Git.

The accepted local bake is quest-navigation-map-bake-v6/manifest.json, SHA256
42f00821f42c8ae96efabe33239a880f4a8e20eeb7fe2ea2f10e779fdd030282.
Its installed compiler output is quest-navigation-regional-v2, catalog revision
5fde96619a4db32fde75bc7ee395c94a3010a6e8a9b579c21c43ca0341c173e0.
Paths are local evidence identifiers, not portable download locations.

All 2,551 installed addon files were checked against receipt hashes and lengths
after replacement. The previous companion is preserved at
D:/RikUI-local/RikUIQuestTerrain-before-regions-69913-20260921.
Production Lua replays were repeated using the files under the actual client's
Interface/AddOns directory. Native client loading still requires a restart and
has not been observed.

## Geometry and exclusions

The filtered corpus contains 272,339 polygons and 514,264 directed portals.
Partitioning preserves every polygon, portal, isolated component and modeled
floor: 231 spatial regions, 5,768 directed seams, at most 2,932 polygons and 5,487
outgoing portals per region. Partition reconstruction verifies losslessness;
region proximity never creates an edge.

Collision coverage remains conservative: 24 unresolved WMO placements, 3,265
liquid footprints and 2 unsupported inline-physics placements are excluded.
The latter use independently decoded, exact-hash PCOL bounds only to enlarge an
exclusion; they are never treated as walkable geometry. Whole-placement WMO
exclusions include decoded group extents beyond root MODF bounds.

A single global vertical origin exceeded Recast's 13-bit span field and silently
collapsed heights in an earlier candidate. That candidate was rejected.
bounded_tiled.mjs now computes each tile's vertical range from all overlapping
triangles, aligns it to the shared float32 cell-height lattice, adds guards and
rejects spans above 8,190 voxels or more than 512 overlapping chunky-mesh nodes.
The accepted bake's maxima are 5,919 voxels and 160 chunks. Three real WASM fixtures
cover separated low/high floors, adjacent tiles with differing Y origins and
an unrepresentable local height range.

Cross-tile links are checked on both polygon boundaries at both endpoints and
their midpoint. Sixteen directed links exceeding the modeled 1-yard step were
removed in both directions. XZ coordinates recover the configured Recast voxel
lattice; height is not flattened or clamped.

## Runtime loading

The catalog addon and 231 LoadOnDemand addons contain about 71.6 MB of compact numeric
source pages. Install all 232 addon folders together and restart the client so it
discovers their TOCs. Catalog/page revision, byte/count limits and numeric grammar
are checked before incremental NavMesh validation. Files must also match the
offline compile receipt; runtime revision labels are not cryptographic payload
verification.

A working set is limited to 32 regions, 65,536 polygons and 131,072 directed portals.
The coarse directed region graph selects a candidate path plus a neighborhood;
failed local searches can request bounded expansion. This graph is a residency
heuristic, not a shortest walking-path proof. An exhausted window reports a
coverage frontier rather than claiming the destination was reached.

Only one addon loads per preparation call. Loading defers in combat, handles
synchronous reentrancy, and rejects stale destination/map/suspension tokens.
Accepted mesh publication happens only after all normal geometry checks.
Malformed pages are quarantined until an explicit retry. Loaded source pages
remain cached (128MB corpus cap) because WoW cannot unload/reexecute a loaded
addon; decoded meshes are bounded working sets.

LoadAddOn is synchronous: a time check between calls does not impose a hard
callback latency ceiling. Current headless regional replays load 8–11 addons,
prepare 15,767–18,127 polygons over roughly 100–135 callbacks, and measure 9–10 ms
maximum preparation callbacks on this host. These are host CPU timings, not
in-client frame measurements.

## Coverage and acceptance boundaries

Bitter Rivals/distillery, Grizzled Den and Frostmane run through the actual
regional catalog, page loader, validator, search and follower. The previously
uncovered quest 319 marker now lies in the connected main component. Quest 98326
still overlaps two connected floors; neither is silently selected. Quests 96608
and 384 have no usable marker in the archived observation.

The Grizzled Den marker is 4.699 yards beyond the connected cave surface. Guidance
ends at an explicitly labeled approach; this does not establish interaction reach
or complete the quest. Bitter Rivals' basement selection remains a quest-text
inference pinned to this exact catalog, not an observed target altitude.

Native walking, doors/dynamic obstacles, liquid behavior, cave interaction reach,
Forever movement calibration, transport anchors/unlocks and neighboring-zone
corpora remain unverified. Full-map acquisition/compilation is not full-map
walkability, and this is not full-world routing. See [MOVEMENT.md](MOVEMENT.md)
and the current journey evidence in [questplanner.md](../../docs/questplanner.md).
