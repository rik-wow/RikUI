# Compact preparation and public copy evidence: beta.17

Reviewed 2026-10-04 UTC. These are observed inputs and measurements, not pinned
client targets or a claim about future beta builds. Delivery receipts below are
added only after their corresponding published and installed bytes verify.

## Current cold preparation

The latest Forever UI head e3ecc27b64d30fdc735a3f6579b866858f9f9df1,
version.txt, selected WowB.exe and active .build.info agree on 1.60.1.70205,
product wow_classic_beta, configuration 842b2e5d11f8d6fe257a5b73bd5cf6c6.
Separately acquired QuestieDB source is 9d39232dab48e35811a7cc02473c2f4e42b62ab6,
holiday source e336784b388f60cd30402dfe0989323c97b19f73, and WoWDBDefs source
1d356b44c798e89802928457b2854003098e28ab. Resolution fingerprint is
7be1dbe41e5ee2b99ff97bb8a6ac1052e93d7982bbe513a64dfb7a1c16542808.

A fresh empty-cache preparation using packaged runtime24, without developer
Git/Python/Node in PATH, completed successfully in 3,925.4 seconds (65.4 minutes).
All 2,290 terrain jobs were generated, none reused; all seven supported road
worlds completed. The terrain phase took 1,859.9 seconds with eight bounded
workers on this 32-logical-CPU computer. Parallelism adapts to available memory
and CPU capacity; this time is not a promise for other hardware or updates.

The final cache occupies 12,295,703,457 logical bytes (11.45 GiB). Periodic samples
observed a maximum of 12,287,100,342 bytes before the final census; neither figure
is filesystem allocation or an exact between-sample peak. The final logical
size plus the 4 GiB preparation reserve fits the new 16 GiB startup minimum
with about 0.55 GiB remaining. Retained generations and installation backups
need additional room. Disk availability is checked during preparation; larger
future inputs can require more space. Minimum observed system available RAM was
13,486,956,544 bytes. The measurement receipt is retained at
D:/RikUI-local/compact-cold-proof-3/evidence.json.

The extractor shares its working cache instead of duplicating downloaded game
archives. Geometry and navigation evidence use bounded lossless gzip storage;
stored and decoded hashes, expansion limits and complete source receipts admit
reuse. Existing private data and older generations remain intact. Compact and
plain Recast inputs produce identical navigation output in regressions.

The full provider export covers eighteen player variants: 5,009 provider quests,
13,309 NPCs, 21,159 items and 6,967 objects. QuestV2 adds only membership evidence;
the 7,333-ID union includes 2,324 client-only IDs with explicitly unknown provider
semantics. Corpus revision is
326248964fa3c1c236f07a6785638f7262a4aed0d81307dc03ae6f005e16211a.
Nine translations remain in the private audit; runtime guide support is enUS.
Floors, phases, physics, provider lag and unsupported projections remain explicit.
The seven supported worlds are Eastern Kingdoms, Kalimdor, Alterac Valley,
Warsong Gulch, Arathi Basin, Zephras Isle and Darkspear Islands.

Road receipt SHA-256 is
15d6eb0911a4c978f74cc150f3f54e0ce3d98a3963299561544c4f51f9c338c6.
All 12,198 navigation files and six patch packs pass byte verification. Actual
addon Lua route/follow replays on maps 1426, 1429, 1411 and 1438 report zero
regressions for routes of 727–1,540 yards. The last route retains a five-yard
approach outside the endpoint patch. This is host Lua verification; nativeObserved
is false and the user's standing gameplay acceptance applies. Receipt:
D:/RikUI-local/compact-beta17-navigation-proof-1.json.

## Refresh, recovery and interface checks

Daily, startup and update paths freshly resolve publisher and client identities.
Changed client/provider/schema/tool inputs invalidate their affected products;
byte-verified unchanged products remain at their original paths. Schema-head
changes conservatively invalidate geometry even when only unrelated definitions
changed. A real provider advancement during preparation withheld stale admission
and preserved completed data; the failed and subsequent current proofs are retained.
Future beta builds and the release executable/product/directory are discovered
when available, rather than assumed from today's beta path.

Paused daily checks now resolve current inputs and verify retained bytes without
starting generation, installation or resuming the player's pause. The Python
progress observer permits check-only verification while honoring cancellation
for producing work. Full terrain progress uses a bounded summary throughout all
2,290 jobs; per-job receipts retain the complete admission evidence independently.
A controller-only runtime update changes bundle/tool scopes while preserving
verified physical geometry. Runtime26 contains the committed fixes; the fresh
cold proof accurately retains its original runtime24 provenance. A subsequent
runtime26 refresh completed with only the bundle/tool scope changed. Acquisition,
corpus, bakes, rasters, road outputs and all recorded product/support-file receipts
remain identical. The final local bundle SHA-256 is
d8c3323b8a45458b40c845025e63d6d2138c5ba3565f903636c15b3fb26f9823.
The refreshed receipt is D:/RikUI-local/compact-runtime26-refresh-result-1.json.

Configured project checks and required visual checks passed: 19,383 addon Lua
runtime checks and 285 reviewed captures / 527 images. Addon UI source is unchanged.
Focused preparation/update regressions include 188 Python checks, 50 terrain
checks and 28 controller checks. Rust has 29 passing tests, formatting, all-target
checking and clippy with warnings denied; thirteen actual installer window
states were reviewed at original size using verified current inputs.

The public website copy was audited across all 58 published routes, including
body text, accessible labels, image alternative text and page metadata. Pages
explain installation and gameplay controls to addon users; source-file links,
contributor instructions, renderer terminology and internal commentary were
removed. Unpublished Studio remains separate. The all-route browser guard prevents
these terms and private paths returning. Final responsive captures and production
checks are recorded with the delivery receipts.

## Delivery receipts

Public release, isolated consumer installation, actual client preservation,
operating daily updates and production website verification remain pending.
