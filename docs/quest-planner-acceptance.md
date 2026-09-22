# Adaptive planner acceptance and evidence

This is the requirement-to-production-code/test/UI/evidence ledger for the complete authorized scope of [the requirements](quest-planner-requirements.md). Native Magistr owns lifecycle status. This ledger is not a roadmap export.

Baseline: commit 1169c27, clean checkout, 9,204 recorded Lua checks before this work. Existing terrain-coverage and quest-natural-journeys tasks and quest-forever-corpus native acceptance remain outstanding and are preserved. A planned file is not implemented evidence.

## Requirements

| ID | Behavior | Existing foundation | Planned production ownership | Required automated evidence | Visible behavior | Acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| R01 | Goals and constraints | Controller policy/manual selection; eligibility | quest-preferences.lua; quest-plan-state.lua | Control conflicts, hard constraints | Flavor/session/constraints | Pending |
| R02 | State and provenance | Reader/Context/Journal; exact identity | quest-plan-state.lua; Context | Live precedence, source retraction | Source/unknown explanation | Pending |
| R03 | Future opportunities | Raw corpus links; live-only loading | quest_corpus.py; SemanticData; quest-plan-graph.lua | AND/OR/exclusive/breadcrumb/cycles | Future pickup and up next | Pending |
| R04 | Executable actions | Steps and semantic methods | quest-plan-graph.lua; quest-plan-transitions.lua | Mechanic preconditions/effects/recovery | Action, evidence and recovery text | Pending |
| R05 | Resources/capacity/services | Prepared simulation consumes items | quest-plan-state.lua; quest-plan-transitions.lua | No double spend, capacity, services | Missing resources/service alternative | Pending |
| R06 | XP/time/rewards | Selected quest live XP; prepared durations | Compiler XP; quest-plan-costs.lua | Level scaling, cost components, no reward duplication | Honest estimates and incomplete XP | Pending |
| R07 | Uncertainty and risk | Source unknowns; route limitations | quest-plan-costs.lua; quest-plan-memory.lua | Ranges, retry bounds, alternatives | Range and risk explanations | Pending |
| R08 | Topology clusters | Source areas; directed terrain | quest-plan-graph.lua; transitions | Shared kills vs drops; future pickup batching | Shared visits and access limits | Pending |
| R09 | Recursive lookahead | Prepared beam depth <=8 | quest-plan-search.lua; graph | Deep chain, future value, incremental repair | Future continuation | Pending |
| R10 | Multiple plans/flavors | Live local heuristic | quest-preferences.lua; search | Stable units, six tradeoffs, no sunk costs | Alternatives and efficiency tradeoff | Pending |
| R11 | Variety/continuity/agency | Manual selection/pin/skip/avoid | quest-plan-memory.lua; preferences | Bounded history, explicit feedback, decline | Continuity and dismissible discovery | Pending |
| R12 | Session pacing | Prepared maxSeconds | search; preferences | Short/long, stopping reserve | Session length and milestones | Pending |
| R13 | Capability and party | Class/race/faction/level snapshot | state; costs; transitions | Solo/group gates, observed failure | Difficulty and group control | Pending |
| R14 | Hierarchical travel | Directed travel; terrain search/follower | graph travel adapter; controller | Cliff/floor/conditional access | Marker vs verified route | Pending |
| R15 | Stable replanning | Controller/terrain revision guards | controller; search; memory | Progress/completion/teleport/resource changes | Stable current action and change reason | Pending |
| R16 | Runtime/fallback | Sliced source/terrain/optimizer | graph/search shared scheduler | Caps, cancel, timeout, cold/warm timings | Immediate useful fallback | Pending |
| R17 | Explanations/controls | Tracker/details/map controls | quest-plan-view.lua; view/commands/guidance | Real widget interactions and details | All six presets and reversible controls | Pending |
| R18 | Learning/persistence | CharDB policy; session observations | quest-plan-memory.lua; persistence bridge | Migration, reload, bounded learning/reset | Learned sample counts and reset | Pending |
| R19 | Compatibility/coverage | Identity/personas/partitioned corpus | compiler; data; state | Bad partition isolation, locale, unknown quest | Semantic/future/navigation coverage | Pending |
| R20 | Evaluation/observability | 9204 baseline Lua checks; installed replays | tests/quest-plan*.lua; delivery receipt | Exact oracle, baselines, held-out/long-session | Replay diagnostics; native/playtest evidence | Pending |

## Flavors

Every flavor shares the same state, legal transitions, travel and hard constraints. Preference units are fixed; unrelated candidates do not renormalize scores. Unknown XP remains unknown.

| Flavor | Required observable choice in a real tradeoff | Test/UI/native evidence |
| --- | --- | --- |
| Balanced | Useful local progress with coherent arcs and bounded variety | Pending |
| Efficient | Highest supported reliable progress per elapsed time; permitted repetition | Pending |
| Story | Preserve supported narrative/missable arcs within explicit detour allowance | Pending |
| Explorer | Optional recorded discoveries/varied routes within allowance; honor decline | Pending |
| Relaxed | Short predictable solo progress, low waiting and observed failure exposure | Pending |
| Challenge | Harder capability-appropriate objectives within the same feasibility rules | Pending |

## Acceptance scenarios

| ID | Scenario | Required result/check | Production path | Host evidence | Native evidence |
| --- | --- | --- | --- | --- | --- |
| S01 | Pickups unlock three upcoming objectives | Graph/search batching | Pending integration | Pending | Pending |
| S02 | Turn-in unlocks valuable nearby follow-ups | Full continuation | Pending integration | Pending | Pending |
| S03 | Missable optional breadcrumb | Story/completion preservation | Pending integration | Pending | Pending |
| S04 | Mutually exclusive chains | Prefix feasibility | Pending integration | Pending | Pending |
| S05 | Shared kill credit, different drops | Separate acquisition | Pending integration | Pending | Pending |
| S06 | Two turn-ins consume same five items | Inventory reservation | Pending integration | Pending | Pending |
| S07 | Full log or bags | Capacity/service plan | Pending integration | Pending | Pending |
| S08 | Marker below cliff/on another floor | Verified access or explicit unknown | Pending integration | Pending | Pending |
| S09 | Lift/giver/follow-up unavailable | Bounded retry and alternative | Pending integration | Pending | Pending |
| S10 | Partial counts while walking | Remaining work without route reset | Pending integration | Pending | Pending |
| S11 | Complete objective/source item lost | Immediate advance/recovery | Pending integration | Pending | Pending |
| S12 | Teleport during path query | Stale rejection | Pending integration | Pending | Pending |
| S13 | New quest without provider semantics | Live fallback and coverage gap | Pending integration | Pending | Pending |
| S14 | Value beyond shallow horizon | Bounded deep continuation | Pending integration | Pending | Pending |
| S15 | Balanced/Story/Efficient tradeoff | Distinct choices, identical feasibility | Pending integration | Pending | Pending |
| S16 | Explorer detour declined | No repeated nag | Pending integration | Pending | Pending |
| S17 | Short versus long session | Suitable stopping point | Pending integration | Pending | Pending |
| S18 | Native Perfect Stout, cold corpus+terrain | Useful timely stable guidance | Pending integration | Pending | Pending |
| S19 | Long session/reloads/map changes | Bounded memory and durable preferences | Pending integration | Pending | Pending |

## Architecture and implementation contracts

The existing prepared-action optimizer accepts at most forty verified actions and a shallow beam. It remains useful for authored exact datasets. The ordinary corpus loader currently loads live-log partitions only. Production future planning therefore needs a compact indexed corpus frontier, on-demand source records, explicit hypothetical transitions, and integration into Controller.Update/Step.

Add a revisioned planning state independent of presentation. Preserve live progress, exact character/build/locale/source identity, observed inventory/capabilities and tri-state requirements. Source claims may support qualified opportunities; they never become live availability, guaranteed routes, exact drop counts or completed actions. Every transition has preconditions, interaction, expected effects, completion evidence and recovery. Predicted effects are isolated from live state.

Compile typed prerequisite relationships and compact map/chain indexes. Expand useful local pickups, predecessors and follow-ups within explicit graph budgets. AND/OR, exclusions, breadcrumb loss, repeat readiness, log slots and consumable quantities participate in every simulated prefix. Unsupported fields stay unknown. Source mechanics and counts must be independently justified; generic icons do not establish a particular quest or drop.

Use deterministic incremental beam search with chain/cluster continuations and bounded supported terminal value. Compare alternatives with fixed component units and an explicit detour envelope. Preserve delayed-reward branches using continuation estimates and diverse first actions; do not claim global optimality. Include time to a stopping point and never count speculative downstream rewards as earned XP. Simulated inventory, capacity, level, branch choices and repeat state determine legality.

Keep strategic work separate from continuous walking. Revision-bound jobs reject changed state/data/policy; partial counts repair remaining work while valid terrain corridors persist. Meaningful improvement thresholds apply only while the prior action remains feasible. Frame work, graph size, frontier, history, load queues, retries and diagnostics are bounded. Immediate live instructions remain available while refinement runs.

Learn cost aggregates only from supported local evidence, retaining sample count/range and context. Explicit preferences are separate from incidental deviations. Store bounded versioned preferences/history where supported; retain session functionality on persistence failure. Never restore running search jobs.

## Delivery boundaries and verification

Implementation is decomposed in native Magistr into state/data/graph, transitions/search/cost learning, normal controller/UI integration, and integrated acceptance/installation. All are authorized in this one continuing session. Completion of this design milestone is not completion of the planner.

For each source chunk: focused red/green regressions; full configured gates for cross-cutting state/graph/controller changes; atomic conventional commit; recorded final gates against committed source under that chunk's verification task; per-task and per-chunk closure. No whole-cycle finalization is required for inherited blocked tasks.

Evaluation compares identical state/information/constraints against nearest feasible work, current ordering, the existing local heuristic and authored routes where provided. A separate exhaustive small-case oracle checks complete finite prefix feasibility and path value. Held-out zones/personas, six-flavor tradeoffs, long chains, cold corpus/terrain, mid-action interruption and repeated reload/map transitions exercise production entry points. Diagnostics include inputs/revisions, exclusions, component costs, unknowns, chosen/alternative sequences, switching and bounded work/memory.

Host simulations, actual native UI/performance and gameplay/engagement are separately recorded. Proposed warm 250 ms / cold few seconds / approximately 1 ms per incremental frame targets require native measurements, including synchronous addon loads and total callbacks. Playtest questions cover repetition, coherence, stress, discovery, choice and enjoyment; overrides alone do not imply failure.

## Current known evidence gaps

The corpus has locations, methods and raw source relationships, but no guaranteed world-wide navigation or native interaction truth. Required counts, drop rates, vendor prices, exact capabilities and future rewards need source/live support, explicit unknowns and acquisition attempts. SavedVariables are declared but this beta's cross-reload behavior must be verified. Native new/changed chains, lift availability/timing, movement and engagement acceptance cannot be inferred from host tests.

This ledger will be updated as implementation and evidence land. No requirement or scenario is fully accepted merely because its mechanism exists.
