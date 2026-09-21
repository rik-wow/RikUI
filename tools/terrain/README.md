# Local Forever terrain datasource tools

These independently authored wrappers prepare a local exact-build terrain and collision datasource. They do not control the game, inspect process memory, modify the client, or assert that computed paths were walked. Generated assets and npm dependencies are written only to an explicit empty external directory, never beside the committed tool sources.

## Reproduce on another machine

Requirements: Python 3.13+ and Node 24+ with npm, a local installation containing the exact build, and the pinned TACTTool 0.2.0-alpha1 Windows x64 binary. Acquire the release from https://github.com/wowdev/TACTSharp/releases/tag/0.2.0-alpha1 . The wrapper verifies its 15,205,803-byte binary against SHA256 `efbcf7c018310719328ca3cf101d366195a1d96d7fbc07871bdff70d88fe1945` before execution. Downloading or launching a different extractor is not automatic.

From the tool source directory, with actual local paths supplied:

```powershell
python acquire.py --game-root 'C:\Program Files (x86)\World of Warcraft' --tact-tool 'C:\Tools\TACTTool\TACTTool.exe' --output-directory 'D:\RikUI-local\acquisition-69913'
.\reproduce.ps1 -AcquisitionDirectory 'D:\RikUI-local\acquisition-69913' -OutputDirectory 'D:\RikUI-local\bake-69913'
```

The acquisition profile contains only factual IDs, byte counts, hashes, build/source revisions and minimal mapping evidence for 391 assets (8,785,514 bytes): five WDT/ADT files, 158 direct collision dependencies, 26 WMO groups and 202 additional doodad models. The bound is 512 files and 16 MiB overall, with at most 4 MiB per asset. The original single-tile reproduction remains available; [REGION.md](REGION.md) describes the two-source region and its separate reproduction command. The profile is pinned by a canonical JSON SHA256, so formatting changes are harmless while changing any factual entry requires explicit parser/profile review. The extractor uses the supplied game root read-only, runs all four extraction batches in the external output directory, then checks every asset hash before writing compatible receipts. Missing data or an updated client fails verification instead of silently changing builds. Client processes are never closed or controlled.

Existing exact acquisitions can be checked without writes or copied with regenerated receipts:

```powershell
python acquire.py --verify-existing 'D:\RikUI-local\acquisition-69913'
python acquire.py --from-existing 'D:\RikUI-local\acquisition-69913' --output-directory 'D:\RikUI-local\verified-copy-69913'
```

Output must be nonexistent or empty, outside Git repositories, and disjoint from inputs. Existing files are not overwritten. Symlink/junction/reparse-point paths and path escapes are rejected. A failed run retains its diagnostic output; use a new empty directory for a retry. The bake wrapper copies only an explicit list of authored scripts, factual proof receipts, licenses and the lockfile; runs `npm ci --ignore-scripts`; sets `RIKUI_TERRAIN_ACQUISITION`; then executes all decoding, baking, tests and replay checks in that external directory.

Client identity: wow_classic_beta / Forever 1.60.1.69913 / enUS. Extraction receipt pins BuildConfig 6c0df97e8e481a9a41600e373367c200 and CDNConfig 5525ea1ce6668e895569c89c2d6a154c. The terrain wrapper admits only the three recorded input file hashes, expected IDs775971/778197/778198 and this exact receipt identity. Every direct M2 file is checked against receipt hashes. Generated geometry and navigation record hashes of their actual parser/wrapper code.

- `terrain_probe.py`: bounded MVER18 root/obj ADT reader, full framing checks, all256 unique MCNK chunks, staggered heights, low/high resolution holes, placement dependency inventory. Default2x2 chunk region; explicit --allow-full-tile permits all256 chunks.
- `collision_probe.py`: bounded M2 MD21/MD20 version272 collision arrays, placement transforms, explicit footprint inclusion/exclusion. No rendered-model triangles substituted for collision arrays.
- `wmo_probe.py`: framed MVER17 roots/groups, declared collision face flags, selected/default doodad sets, quaternion transforms and source hashes. Hash-bound version 274 profiles admit only independently demonstrated collision arrays; other version 274 assets remain unsupported. MOHD counts remain audit metadata; framed MODD records and strict MODS/MODR bounds govern decoding.
- `merge_geometry.py`: joins matching acquisition/terrain receipts and exact placement coverage, preserves source inconsistencies, and identifies entire affected MODF footprints for conservative exclusion.
- `bake.mjs`: small single-region Recast proof and exported polygon portals.
- `bake_tile.mjs`: fulltile Recast tiling with bounded JSONshards. Handles Detour signed JS sentinel conversions, clipped intertile portals, reciprocal references, component discovery and actual path queries.
- `plot_proof.py`: offline scientific figure using target-build UiMapAssignment. Does not automate UI.
- `test_probe.py`: parser boundaries, hole topology, winding, model coordinate transform, real-data resource/coverage checks.
- `test_wmo_probe.py`, `test_nav_artifact.py` and `test_acquire.py`: 46 tests in the original-tile reproduction, including malformed inputs, build isolation, declared set bounds, model transform reference cases, real convex polygon/portal topology, source bounds, excluded footprints and acquisition path/hash boundaries. The transform proof JSON preserves a previously executed 384-case comparison with the pinned reference; consuming its receipt is not a new native verification.

The corrected original-tile model has 4,489 polygons and 8,772 directed portals in 81 shards. Three header-count discrepancies are preserved as audit notes after comparison with unmodified pinned readers; they no longer incorrectly exclude complete building footprints. The two-source region includes an additional 128-yard strip, with 6,213 polygons, 12,112 portals and 99 shards. Its whole-placement exclusions cover unmodeled WMO liquid indications and unsupported doodad flags; it does not infer liquid geometry from a header alone. Both models exclude polygons outside their explicit source rectangle. Degenerate horizontal faces and incident links are removed with an audit record, while the compiler independently retains its strict convexity checks.

The bake rebuilds both proofs, tests them, rebakes the complete tile twice, and checks all 83 full tile files byte-for-byte. `verification-receipt.json` records actual script/package/artifact hashes. Paths and parser revisions in manifests are local provenance; a different directory produces different manifest hashes while polygon shard geometry remains identical. From the external bake directory, the optional figure is generated with `python plot_proof.py --geometry geometry-full.json --nav full-tile --out full-tile-proof.png`.

The small and full proofs remain `publishable=false`. Exact source bytes, completed static decoding, model assumptions and native verification are separate statuses. Player height/radius/climb/slope are explicit engineering sample parameters, not confirmed Forever physics. Dynamic doors, phasing, spawned gameobjects, enemies, swimming and transports require separate information. No connection beyond the explicit sourced region is invented. Regional seam links come from the combined geometry bake and actual Detour portals.

The JSON shards support an addon-side graph/polygon pathfinder. The Detour binary retains diagnostic geometry inside excluded footprints and must not be used as the filtered graph. WoW Lua cannot load this WASM/C++ binary. Keep these datasets outside RikUI settings/profile transport. Fulltile output is tiled so runtime can load/process bounded regions and retain portal connectivity. Runtime adjacency is declared portals only; coarse polygon center/portal-midpoint segments stay within the convex projected corridor. Coarse heights omit Detour detail triangles and are modeled estimates; overlapping floor selection requires height or an unknown result.

## Toolchain and source pins

Tested locally with Python3.13.9 and Node24.3.0. The optional visualization uses matplotlib3.11.1. Runtime addon does not require these packages.

Install offline bake dependency with `npm ci --ignore-scripts` beside the supplied package.json/package-lock.json. It resolves exactly recast-navigation0.43.1 and matching core/generators/wasm0.43.1; package integrity hashes are in package-lock.json.

- wow.export format/transform reference: https://github.com/Kruithne/wow.export/tree/c2fd7bde36a712be78a5da896c995b84fbfa2545 . MIT; retained license in licenses/. WDT in-memory indexing must not replace raw-file mapping evidence. Actual MCNK positions and target-build area mappings identify this tile.
- recast-navigation-js: https://github.com/isaac-mason/recast-navigation-js/tree/8769e8b9995f127033af9f6e6eeac3fad7d66201 . MIT wrapper; its pinned WASMbuild uses https://github.com/isaac-mason/recastnavigation/tree/599fd0f023181c0a484df2a18cf1d75a3553852e . Recast/Detour zlib notice retained.
- Exact extraction: TACTSharp0.2.0-alpha1, source c12f9fa3c4ceeb619b0453947cee86fccad6774a, tool binary/archive hashes and commands in the separate acquisition folder/manifest.

Software licenses cover their respective software; redistribution terms for extracted Blizzard game assets have not been established here. Geometry artifacts are local user-owned-client derivatives and are not designated as redistributable addon content.

The region reproduction passes 52 Python source/topology tests and eight mesh-filter checks,
compares 101 files byte-for-byte, and includes an explicit path crossing the ADT boundary.
This establishes reproducibility and graph connectivity within the model. At the user's
reported indoor position, the current model has a unique containing polygon in a small
disconnected component. Some observed quest POIs are outside polygons or in other
components. An observed marker is not proof of a safe standing point, interaction range,
or a feasible route. These gaps are retained rather than repaired by proximity links.

## Geography

Map0 (Eastern Kingdoms), raw MAID slot42*64+33, locally named Azeroth_33_42. Direct terrain positions establish worldX approximately[-5866.667,-5333.334],worldY[-1066.667,-533.334]. Target-build AreaTable identifies Dun Morogh, Kharanos, Misty Pine Refuge, Steelgrill's Depot and The Tundrid Hills in the tile.

Using the recorded target UiMapAssignment, the fulltile maps to UiMap1426 approximately X47.4196–58.2487%,Y44.3528–60.5965%. The initial2x2 region is around mapX52.16–53.51%,mapY51.46–53.49%; normalized mapping remains available for a later native check. Navcoordinates are right-handed Y-up: [gameworldY,altitude,gameworldX].

## Compile and install the local companion addon

Run the compiler from the committed tool directory after a successful bake.
Supply the manifest SHA256 printed by that specific run; source paths and parser
hashes make another run's manifest hash unsuitable.

```powershell
python compile_quest_terrain.py --manifest 'D:\RikUI-local\bake-69913\full-tile\manifest.json' --expected-sha256 '<the printed manifest SHA256>' --out 'D:\RikUI-local\RikUIQuestTerrain'
```

The output parent must exist and the addon directory must not exist. Copy that
directory to the target client's Interface\AddOns, then fully restart WoW so
the new TOCs are discovered. No generated mesh is committed or transported via
RikUI macros. The compiler writes bounded shards, a manifest and registration file plus offline
audit/probe files. The single-tile model has 81 shards; the expanded region has
99. Only runtime Lua files appear in the TOC.

`python -m unittest discover -s tools/terrain -p test_compile_quest_terrain.py`
runs 57 compiler boundary tests from the repository root. For the actual local
compiled addon, run
`luajit tests/quest-terrain-data.lua "D:/RikUI-local/RikUIQuestTerrain"`.
That checks production Lua validation and actual probe paths against an
independent shortest-path calculation. It does not establish native traversal.

The proof's `publishable=false` marker means it is not certified for redistribution
or native walkability. The compiler can provide explicitly modeled local guidance
outside all recorded exclusions. It never compiles the unfiltered Detour binary.
Current regional guidance needs a live selected destination; terrain supplies
geometry, not a verified quest corpus or invented XP/eligibility facts.
