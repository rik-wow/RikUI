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
remain identical. That intermediate controller refresh produced bundle SHA-256
d8c3323b8a45458b40c845025e63d6d2138c5ba3565f903636c15b3fb26f9823;
its receipt is D:/RikUI-local/compact-runtime26-refresh-result-1.json.

The exact published Windows setup embeds interface base SHA-256
93f38ce4c91ad296f8ae39c9bdbe99ea822ba38c2f992add32806abb2020cff0.
Windows checkout line endings differ from the private proof's interface text;
all 332 nonmanifest source entries normalize identically. Derived manifests
correctly differ in byte lengths/hashes. The final assembly was refreshed against
the exact public base, verified all 333 base files byte-for-byte, and retained
all physical input/output inventories unchanged. Final local bundle SHA-256 is
f0dfd34981b305ff818eb8ec91e90205f58fd6eef95b21758b0c96de1394dfed.
Receipt: D:/RikUI-local/published-beta17-base-refresh-result-1.json.

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

GitHub release: https://github.com/rik-wow/RikUI/releases/tag/v1.0.0-beta.17.
CurseForge release: https://www.curseforge.com/wow/addons/rikui/files/9062297.
Both downloaded addon archives verify 333 files and SHA-256
8ab93d989f41d758e3c700eeddeb92f273353d2d736847590596aa487a5a0ccc.
CurseForge's public publisher API confirms file 9062297; its CDN download matches.

The public setup is 67,913,728 bytes, SHA-256
ee0a88e9f8536e22eadee5f07d97853f41b004f95ef8e5266ec0f4665c94a5d3.
Downloaded checksums, executable embedded payload, licensed runtime and notices
verify. Public payloads contain neither imported provider datasets nor client
geometry. Exact setup receipts are retained under
D:/RikUI-local/published-beta17-setup-proof-1 and
D:/RikUI-local/published-beta17-website-setup-proof-1.

The existing https://rikwow.com/install channel now serves beta.17 and accurately
discloses the separate QuestieDB dependency, 16 GiB minimum plus retained data,
measured hour-or-more first preparation and current supported coverage.
Worker deployment is 16aae5bc-eec7-4751-b4ce-115224edd399. Four immutable download
objects match the GitHub release bytes, including manifest, notices and checksums;
HEAD, ranges and conditional responses verify. Production browser checks pass
24/24 across all58 public routes, responsive sizes, keyboard controls and the
player-only copy guard. Final source passes 44 website regressions; 22 exact
reviewed browser image hashes and their source identities verify. Receipts:
D:/RikUI-local/published-beta17-website-proof-1,
web/install-review.json and web/public-copy-review.json.

The public setup is installed into the selected current Forever client. Native
verification checks all 12,997 owned files across seven roots against the final
public-base bundle. It confirms 545 settings files, 110 unowned addon files and
899 source files unchanged, and 13,076 previous owned-root files in completed
backup 01791143345160950700. The retained source junction and all earlier backups
remain intact. Receipt: D:/RikUI-local/current-client-beta17-preservation-proof-1.json.
The preparation preference now selects the supported compact cache through
setup's preparation-folder flow; the previous cache and private data remain.

The isolated clean consumer fixture completed first installation, unchanged
update and paused current-input checking with all strict byte, sentinel and backup
assertions. Its explicit-resume action then encountered the publisher's shared
60/hour unauthenticated metadata quota. Installed data stayed intact; the failed
run and traceback are retained. Recovery resumes from that checkpoint after the
reported quota reset. Individual timings/exit receipts for the first three actions
were not flushed before failure; their passing assertions are evidenced by the
exact driver's control flow reaching the fourth action, not fabricated timings.

The registered current-user **RikUI Current Forever Updates** task uses the exact
public setup executable, has an enabled daily trigger, and completed its observed
2026-10-04 run with Task Scheduler result 0. The daily receipt reports checked;
fresh source/client resolution agrees, the probe reports no changed inputs or
rebuild scopes, all installed bytes verify, the latest preparation receipt and
bundle remain unchanged, and no additional backup was created. The active cache
is unpaused. Receipt: D:/RikUI-local/current-client-beta17-daily-proof-1.json.
Changed-input fixtures and the observed publisher advancement verify selective
refresh and stale-admission rejection separately; no future client is claimed tested.

The recovered isolated resume passed with exit 0 (187.7 seconds) and no extra
backup. Invalid PE selection failed with exit 1 (7.0 seconds) while preserving
installed data and sentinels. Restoring the current executable recovered with
exit 0 (184.1 seconds), again a no-op. The final 12,997 installed files, settings,
private sentinels, backup count, current resolution and public program/bundle
identities verify. The isolated game uses a relocated directory and renamed
current executable; this exercises discovery and does not claim the future
release client has been tested. Receipt:
D:/RikUI-local/isolated-public-beta17-proof-1/recovered-evidence.json.
The original failed run remains retained and is not relabeled successful.

Release workflow 37228398982 passed the existing addon/CurseForge/setup channel
checks. Website workflow 37229555152 passed on final public-site commit
924573c9628f2347c9fa0a73d5f17b7cb979ab4e, alongside the independently observed
production browser/download checks. No required supported-scope implementation
or delivery requirement remains. Provider and spatial coverage limits above
remain explicit; today's verification makes no claim about future beta builds.
