# Terrain stage diagnostics

This offline tool explains where the current terrain model loses a surface or
connection. It preserves the original source geometry, origin, grid phase and
shipping profile. It does not change the compiled addon, certify a walkable
route, select the player's floor, or create links across missing geometry.

Copy the authored stage scripts together into an external tools directory.
Use the full geometry and manifest retained by the region reproduction, the
manifest's exact printed SHA256, and its pinned external node_modules directory:

```powershell
node inspect_stages.mjs --manifest 'D:\RikUI-local\bake\region\manifest.json' --manifest-sha256 '<manifest SHA256>' --geometry 'D:\RikUI-local\bake\geometry-region-full.json' --modules 'D:\RikUI-local\bake\node_modules' --sites 'D:\RikUI-local\sites.json' --output 'D:\RikUI-local\new-stage-proof'
```

The sites file is an array of at most four objects with unique safe names and
finite `x`, `z`, and `modelY` values. Coordinates use the navigation convention
[game world Y, modeled altitude, game world X]. Each point must lie inside the
source region. `modelY` identifies a diagnostic surface to inspect, not a known
character altitude. Keep character-specific sites and generated output outside
Git and RikUI settings.

The tool checks the supplied manifest hash, its geometry hash, geometry identity,
indices, bounds and original midpoint origin. It accepts the pinned 0.43.1
generator and current shipping profile only: cs 0.5, ch 0.1, radius 1, height 18,
climb 3, slope 40, tile size 128. Changing discretization or physical limits is a
separate experiment; a cropped region has a different grid phase and cannot
silently replace the original calculation.

Executable modules, loaders, WASM and package metadata are hash-checked before
import. Dependency resolution must select those pinned files. Inputs are bounded,
symbolic paths are refused, and the output directory must be new. Failed runs
create no output until preflight, capture and control checks pass. A disk write
failure may retain incomplete diagnostic files; retry in a new directory.
The output must be outside a Git worktree and disjoint from source/module
directories. Reads use one descriptor and a bounded buffer, rejecting size changes.

Run `node test_stages.mjs '<pinned node_modules>'` for contract, malformed-input,
resource, dependency-tampering and failure-cleanup checks. On a Windows workspace
whose Node realpath lookup fails, add `--preserve-symlinks --preserve-symlinks-main`
after `node`; the tool still refuses symbolic input paths.

## What the stages establish

The pinned generator exposes solid and compact heightfields, but retained
intermediates are already mutated. The diagnostic wraps its original filter
calls to take detached snapshots before and after filtering. Temporary compact
fields inspect early solid states and are discarded; they never enter the
generated tile. Hooks and allocations are cleaned up after the run.

For each inspected tile, instrumented output must equal an uninstrumented
control byte for byte. A receipt records input/module/tool hashes, exact
configuration, tile coordinates, stage summaries and output hashes. Repeating
the same inputs in another process should reproduce the diagnostic artifacts.

Reports distinguish rasterized surfaces, low-obstacle filtering, ledge
filtering, clearance filtering, compaction, radius erosion and region
partitioning. A change from walkable area to null area identifies a stage, not
the real-world reason a player can or cannot pass. Raw spans no longer contain
source triangle IDs. Specific source attribution requires separate geometric
intersection evidence.

A component reaching a tile border is not proof that it connects to the next
tile or to a quest. A visibility portal in a WMO is not a movement connection.
A nearby quest marker is not necessarily a safe standing point or interaction
location. No endpoint snapping or inferred final-polygon links are performed.

Limits include 32 MiB of input geometry, 600,000 position scalars, 2,000,000 index
scalars, four sites, 20,000 cells and 200,000 spans per captured stage, 128 solid
spans per cell, ten stages, and 24 MiB per diagnostic file. Aggregate output and
snapshot accounting are bounded as well; these are structural/serialized-data
bounds, not a promise about total JavaScript process memory.

## Observed limitations in the initial region

Original-grid diagnosis of the first indoor point found its modeled floor
already separated before optional filtering and contour/portal export. Near
an entry visibility aperture, rasterization combines a small lip and ramp into
a neighboring height difference above the current climb limit. This identifies
a model bottleneck; it does not establish the character's actual movement limit
or justify adding a link through the wall.

A resolution experiment preserved the intended physical radius, height and
climb while halving cell dimensions. Original origin and 64-yard core tile were
preserved; the generator's radius-plus-three-cell padding changed from 2.0 to
1.25 yards. It improved prefilter connectivity at checkpoints well inside both
extents, but ledge filtering still disconnected the final approach. The shipping profile
was not changed. At one observed quest marker and a later player coordinate,
a lower modeled surface survived the earlier filters and was removed by radius
erosion. Overlapping upper surfaces and unknown character altitude prevent
selecting a convenient floor from that result.

These are exact-source diagnostic findings. Native walking, actual doorway
clearance and a usable route from the supplied character positions remain
unverified. The runtime continues to report missing paths instead of promoting
these experiments to traversal facts.

The integrated tool reproduced two original-grid sites with 8,699,751 bytes of
snapshots. The receipt SHA256 is
`8930cd335fb60047ba4c332100c49a32e4965869de991900b8c91516cf4790e0`;
its pinned manifest is
`6f509e1ad4c7ed2fd5a4894b66b0d5e7c7ba4d59ea41768c294d04e288df1c30`
and full geometry is
`3f06ec2366289852850c6d9346e0939bc15a560b09833fc1606de35081f00883`.
Generated files and character-specific inputs remain in the external local
archive. Independent source-triangle and finer-resolution experiment receipts
are recorded in Magistr; they are separate from this stage tool's output.
