# Kharanos two-source terrain region

This bounded offline profile acquires exact Forever 1.60.1.69913 bytes for Azeroth ADTs 32_42 and 33_42 and their retained static dependencies. It builds one shared Recast navigation model covering the full 33_42 tile plus a 128-yard strip into 32_42. The output carries both original tile/root/obj hashes; no synthetic joined ADT is relabeled as an original source.

The pinned acquisition profile has 391 files / 8,785,514 bytes: five terrain/WDT files, 158 direct collision assets, 26 WMO groups and 202 doodad models. The acquisition cap is 512 files / 16 MiB; individual files remain limited to 4 MiB. The original TACTTool hash/build/config pins remain enforced. Local locked files may cause that pinned tool to obtain matching exact-config objects from Blizzard's CDN; it never stops the game or modifies game files. Logs and actual file hashes record this boundary.

From a source-tools directory, reproduce a new external acquisition from the retained verified bytes:

```powershell
python .\acquire.py --from-existing 'C:\external\verified-region-acquisition' --output-directory 'C:\external\region-acquisition-copy'
```

Or acquire read-only with the existing pinned TACTTool executable:

```powershell
python .\acquire.py --game-root 'C:\Program Files (x86)\World of Warcraft' --tact-tool 'C:\external\TACTTool.exe' --output-directory 'C:\external\region-acquisition'
```

Then reproduce the region and all checks into a different empty external directory:

```powershell
.\reproduce-region.ps1 -AcquisitionDirectory 'C:\external\region-acquisition' -OutputDirectory 'C:\external\region-bake'
```

The wrapper copies authored tools/metadata only, uses the pinned npm lockfile with `npm ci --ignore-scripts`, bakes twice, compares every output byte and records test results in `region-verification-receipt.json`. Generated assets/mesh and game files stay outside the repository. The resulting `region/manifest.json` is the strict compiler input; its exact SHA256 must be supplied separately. Generated data is not deployed by these scripts.

The original and neighboring placement lists contain 27 equal duplicates; only exact equal records with matching kind/uniqueID are deduplicated, and conflicting duplicates reject the build. Cross-boundary connections arise from one combined geometry bake and Detour portals. No proximity seam is added. An explicit model path crosses the original/source-tile boundary in the recorded probes.

The shipped model profile remains cs=0.5, ch=0.1, height=18, climb=3, radius=1, slope=40. These are engineering parameters, not measured Forever player physics. The runtime bound remains 8,192 polygons / 32,768 portals / 128 shards. A generated face with zero horizontal area is excluded with its incident links and retained in `degeneratePolygons`; the regression fixture includes the actual vertical triangle that exposed the defect.

MOHD doodad counts are audit metadata; framed MODD records and MODS/MODR bounds determine decoded records. WMO 113872 indicates liquidType 15 in two groups without an MLIQ mesh; that whole placement footprint is excluded. WMO 111052 selected doodads have unsupported flags 2; its full footprint is explicitly excluded and lies outside the admitted rectangle. Unknown flag semantics are not inferred. Native traversal, actual floor/altitude, doors, gameobjects and phasing remain unverified.

Two additional v274 M2 files, 197388 and 197389, have collision arrays independently demonstrated using the unmodified pinned wow.export loader. Only their exact byte hashes are added; other v274 models stay unsupported. The summary proof is `m2-274-collision-profiles.json`; raw model records remain external.

A source-covered coordinate does not guarantee a containing walkable polygon, connected path, correct floor, or quest interaction range. In particular, a quest POI can be an objective marker rather than a safe player standing point. Missing paths remain missing; no nearest-floor snapping is performed.
