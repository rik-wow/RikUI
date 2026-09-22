# Adaptive planner acceptance and evidence

## Current integration evidence (2026-09-22 10:44 UTC)

The host suite passes **11,233 checks**. The installed-data soak adds 24 cycles, 48 map transitions and six planner-module reloads, with a last-half retained Lua heap range of 96,448.5–98,251.8 KiB (about 1.8 MiB spread). This is a host simulation, not a full native UI reload. The production event-chain test exposed13 failures before correction and now verifies unique combat XP attribution, actor-context boundaries, Classic acceptance arguments and exactly-once interaction learning.201 combat/XP attribution events cause zero strategic refreshes; a real quest update still refreshes.

**All six installed Perfect Stout archive replays pass**, including exact current-display replay from596 source candidates and zero walking replans/replacements during partial progress. Story's current area is regenerated from fresh source even when movement pushes it beyond the nearest-two shortlist; source usability and the768-action limit still apply. Current-decision replay v3 distinguishes search, continuity and fallback evidence.310/313/287 regressions pass, but313/287 select310after refinement; their walk evidence belongs to310.

**The compact Dun Morogh pack is installed and byte-verified**:133addon folders/827files,131bounded load groups,16,348,856source bytes including manifest. Manual315host replay had2ms maximum path load and78,266KiB retained Lua heap; six-style automatic runs retained roughly85–121MiB, first routes4.8–4.9simulated seconds, cold callback maxima18–22ms. Earlier concurrent loading still produced70ms. These are host elapsed measurements, not client guarantees.

The source-model benchmark now passes 396 cases: 276 completed-log orderings and 120 partial-objective/future-pickup scenarios. It compares 336 common-domain cases to both the unchanged legacy Optimizer and current Recommendations.Sort, plus 24 narrow authored turn-in projections. All 396 returned plans match the exhaustive optimum for their restricted production model. The broader cases add only two distinct source quest IDs; 1,224 potential cases are explicitly omitted. The authored comparison projects quest-stage order from a pinned external guide; it does not reproduce a complete guide's travel, timing or experience.

World acquisition has15,697geometry files/1,591,393,329bytes across1,888tiles. Production projection validates61assignments; WMO parsing covers866roots/4,101base groups with zero structural failures and unchanged previously accepted collision geometry. The production M2 verifier passes all 5,730 acquired models; all collision vertices, indices and normals of 132 exact newer-format assets match the independently executed pinned loader. Unknown extra physics remains unresolved even when the ordinary collision mesh is empty or outside the selected region. Unknown collision formats retain explicit exclusions. **Installed navigation remains Dun Morogh only**; other worlds need bounded baking and runtime validation.

Native UI inspection was retried with documented Computer Use initialization and reset; the native pipe still reports Windows error2. Host checks do not establish native gameplay, confirmed XP/time, client performance or engagement. Independent work continues. Older milestones below are historical and do not override this status.


This is the requirement-to-production-code/test/UI/evidence ledger for the complete authorized scope of [the requirements](quest-planner-requirements.md). Native Magistr owns lifecycle status. This ledger is not a roadmap export.

Baseline: commit 1169c27, clean checkout, 9,204 recorded Lua checks before this work. Existing terrain-coverage and quest-natural-journeys tasks and quest-forever-corpus native acceptance remain outstanding and are preserved. A planned file is not implemented evidence.

## Historical integration evidence (2026-09-22 09:52 UTC)

The standard host suite passes **11,137 checks**, including the real geometry, funnel and follower integration. Production now combines local endpoint meshes with a prepared directed network. It reconstructs and validates every intermediate surface and portal, preserves the route while walking through unloaded intermediate regions, and rejects unsupported floor changes, teleport jumps and invented reverse connections.

The current Dun Morogh pack contains 16,348,856 bytes of addon source, split into 131 bounded data groups plus its initializer. An isolated archived Perfect Stout replay measured a largest path-load call of 3 ms (previous monolithic load: 85 ms), first route at 4.9 simulated seconds, and 78,373 KiB total retained replay heap after collection. Walking retained the same 598.480-yard route with zero replans/replacements. A concurrent first-use run still had a 70 ms load; these host measurements are not client guarantees. Reports now call Windows `os.clock` measurements host elapsed time, consistent with [Microsoft's clock documentation](https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/clock).

The ordinary Balanced replay exposed an incomplete diagnostic trace when a valid action is retained before a replacement search finishes. Its route works, but exact current-decision evidence is being repaired before the six-style comparisons. The compact pack is **not installed yet**. Full-world acquisition has obtained all discovered concrete dependencies: 15,697 geometry files, 1,591,393,329 bytes across 1,888 terrain tiles. New building collision formats and world projections still require production integration and baking. Installed navigation remains Dun Morogh only.

The sections below retain earlier evidence milestones. They do not supersede this status or satisfy native/gameplay acceptance.

## Requirements

| ID | Behavior | Production ownership | Automated evidence | Visible behavior | Acceptance |
| --- | --- | --- | --- | --- | --- |
| R01 | Goals and hard constraints | Preferences; PlanState; PlanControls | quest-plan-state/live/acceptance tests: control conflicts, eligibility, exclusions | Flavor, session and reversible controls | Host verified; native UI pending |
| R02 | State and provenance | Context; Journal; PlanState | state/live/event-chain tests: live precedence, retraction, actor/source boundaries | Source and unknown explanations | Host verified; native pending |
| R03 | Future opportunities | quest_corpus.py; SemanticData; PlanGraph | compiler/state/search tests; installed all-record graph admission | Future pickups and up next | Host verified; native future availability pending |
| R04 | Executable actions | PlanGraph; PlanTransitions; Guidance | state/search/live tests: typed steps, evidence, recovery and qualified fallback | Current instruction and recovery | Supported host semantics verified; native mechanics pending |
| R05 | Resources, capacity and services | PlanState; PlanTransitions; PlanTravel | travel/search/live tests: no double spend, capacity, cooldowns, binding, current fares | Resource limits and useful service/discovery offers | Host verified; actual travel/service acceptance pending |
| R06 | XP, effort and rewards | PlanXP; PlanObserver; PlanCosts; PlanRewards | event-chain/xp/rewards/calibration tests: remaining shared combat XP, reward guards, time components | Qualified XP/time and reward explanations | Host attribution verified; confirmed gameplay XP/time pending |
| R07 | Uncertainty and risk | PlanCosts; PlanLearning; PlanTransitions | search/calibration/acceptance tests: ranges, unknowns, bounded retry and alternatives | Ranges, unavailable state and Retry | Host verified; native calibration pending |
| R08 | Accessible clusters and shared work | PlanGraph; PlanTransitions; Terrain | acceptance/search/real-geometry tests: pickup batching, shared kills, separate drops, directed floors | Shared visits and access limitations | Host verified; world geometry/native traversal pending |
| R09 | Recursive lookahead | PlanGraph; PlanSearch; PlanRuntime | search/acceptance tests: 18 quests/72 actions, future value, fresh current-action retention | Supported future continuation | Host verified; native session pending |
| R10 | Six plan flavors | Preferences; PlanSearch | acceptance/search tests: distinct six-style choices, fixed units and detour envelopes; six installed replays | Alternatives and efficiency tradeoff | Host verified; native choice/engagement pending |
| R11 | Variety, continuity and agency | PlanLearning; Preferences; PlanControls | acceptance/live tests: bounded history, explicit feedback, decline, unchanged flavor | Dismissible discovery and stable current action | Host verified; playtest pending |
| R12 | Session pacing | Preferences; PlanSearch; PlanTravel | search/acceptance/travel tests: short/long milestones and return reserve | Advisory session length and milestones | Host verified; native pacing pending |
| R13 | Capability and party | PlanState; PlanXP; PlanObserver; PlanCosts | calibration/event-chain tests: group/rest/gear/level boundaries, failure and suitability | Difficulty/group controls and learned sample counts | Host verified; native combat calibration pending |
| R14 | Hierarchical navigation | PathGraph/PathSearch/NavAttach/PathRoute/PathNavigate; Terrain/NavFollow | real-geometry tests; packed artifact verifier; installed315 replays; directed contraction oracle | Prepared routes, local attachments and explicit fallback | Dun Morogh host integration passes; world/native pending |
| R15 | Stable replanning | Controller; PlanRuntime; PlanGraph; Terrain | live/event-chain/installed tests: partial counts, completion, teleport, source loss;201 attribution events/0refreshes | Stable current action and change reason | Host verified; native walking pending |
| R16 | Runtime and fallback | Shared scheduler; PlanGraph/Search; Paths/Regions | caps/cancel/timeout tests; installed cold/walk/soak callback, load and memory measurements | Immediate instructions while refinement runs | Host bounded; native timing targets not yet verified |
| R17 | Explanations and controls | PlanControls; View; Commands; Guidance | live tests invoke real widget handlers and diagnostic details | Current/up next, reasons, alternatives, pin/defer/skip/avoid | Host widget handlers verified; visual/native pending |
| R18 | Learning and persistence | PlanLearning; PlanObserver; Controller/Codec | live/event-chain tests; installed24-cycle soak/6logic reloads; <=6000-byte persisted packet | Sample counts, inspect/reset and restored preferences | Host verified; native full reload/session pending |
| R19 | Compatibility and coverage | Corpus compiler; SemanticData; PlanState; Coverage diagnostics | compiler/state/installed all-record tests; bad partitions, unknown999, seasonal8653 | Separate semantic/future/navigation coverage | Host verified; unmodeled world/native coverage explicit |
| R20 | Evaluation and observability | PlanRuntime replay v3; Transfer; installed/heldout runners | 396 source-model cases; exact prefix oracle, nearest/fixed/legacy/heuristic and24 authored projections; installed soak | Decision replay and exclusion/change diagnostics | Model/host evidence passes; gameplay XP/time, native and engagement pending |

## Latest model and runtime verification (2026-09-22 09:15 UTC)

The standard host suite now passes11,026 checks, including guarded reward reads and local forward/reverse terrain attachments. The separate calibration suite passes9 cases/95 assertions for matching combat evidence, remaining-work XP, shared credit and group constraints. The compact directed search passes500 independently generated Floyd–Warshall comparisons (4,610 checks total).

The v2 Dun Morogh pack is16,304,505 bytes of addon source. It retains exact polygon/portal geometry for safe smoothing; all37,848 retained polygons,155,370 points,78,482 directed portals and38,048 network links passed the production Lua verifier. These establish data integrity and modeled feasibility only. The coordinator and corridor builder are still being integrated, so this is **not** an installed lightweight-navigation completion claim. Full-world geometry and native memory/traversal evidence remain outstanding.

## Current integrated evidence additions

As of 2026-09-22 08:36 UTC, the complete host Lua suite passes 9,697 checks. This includes guarded carried-item cooldown readiness, same-name hearth rebinding, current-flight-master fares, and purpose-backed optional flight-point discovery in `quest-plan-travel.lua` and `tests/quest-plan-travel.test.lua`. Only an explicitly undiscovered, faction-compatible client node can supply an offer; missing APIs/status, malformed nodes and duplicates produce no invented attraction. Costs reserve outbound and return time; arrival alone cannot prove an unlock. Bind labels and known flight nodes do not manufacture transport destinations, durations or free shortcuts.

The source-held-out runner `tests/quest-plan-heldout.lua` passed 276 cases:18 valid synthetic personas at levels10/20,46 qualified persona-map cohorts across five maps, all six flavors. Its report explicitly omits264 potential cases without three eligible same-map quests. All returned sequences are feasible and deterministic, with zero utility or envelope loss against exhaustive enumeration **for these three-turn-in cases**. There are only five distinct quest triples/15 quest IDs and16 enumerated states per case. This is shallow source-model ordering evidence, separate from the deep-chain and flavor-tradeoff scenarios. Current-heuristic and independent authored-guide comparisons remain required; no native XP or enjoyment measurement is inferred.

`tools/terrain/benchmark_backbone.py` validates the exact installed Dun Morogh source before contraction. The v2 comparison checks64 endpoint queries (39 connected), using goal-terminated Euclidean A* on both graphs and an independent exhaustive Dijkstra cost check. Host search totals are0.78065s original versus0.12038s compact including local attachments. All costs/reachability match. The272,339 polygons become5,672 gateway nodes/38,048 directed edges. The17,258,370-byte JSON and2,914,930-byte experimental zlib result are offline formats, not addon memory claims. `quest-path-codec.lua` and its tests add lossless bounded random-access numeric decoding; the prepared-network runtime is not yet integrated.

The source graph itself has24,345 disconnected components; its largest contains84,244 polygons. Missing modeled connectivity remains a coverage limitation even when search is faster. Only Dun Morogh terrain is installed. Full-world acquisition, native memory/load timing, and S18 gameplay evidence remain outstanding.

## Flavors

Every flavor shares the same state, legal transitions, travel and hard constraints. Preference units are fixed; unrelated candidates do not renormalize scores. Unknown XP remains unknown.

| Flavor | Required observable choice in a real tradeoff | Test/UI/native evidence |
| --- | --- | --- |
| Balanced | Useful local progress with coherent arcs and bounded variety | Production S15 variety family108s; real style widget; native pending |
| Efficient | Highest supported reliable progress per elapsed time; permitted repetition | Production S01 batching/S15 fastest90s family; real widget; native pending |
| Story | Preserve supported narrative/missable arcs within explicit detour allowance | Production S03 breadcrumb/S15 linked117s family; no narrative labels invented; native pending |
| Explorer | Optional recorded discoveries/varied routes within allowance; honor decline | Guarded undiscovered flight-point offers, outbound/return budget, decline and current unlock invalidation; native pending |
| Relaxed | Short predictable solo progress, low waiting and observed failure exposure | Production easier105s encounter vs Efficient100s; real widget; native pending |
| Challenge | Harder capability-appropriate objectives within the same feasibility rules | Production harder110s encounter vs Efficient100s; unknown capability removes fit bonus; native pending |

## Acceptance scenarios

| ID | Scenario | Required result/check | Production path | Host evidence | Native evidence |
| --- | --- | --- | --- | --- | --- |
| S01 | Pickups unlock three upcoming objectives | Graph/search batching | Graph/search | Production three-pickup route:300 XP/276s, all pickups before excursion | Pending |
| S02 | Turn-in unlocks valuable nearby follow-ups | Full continuation | PlanGraph → PlanSearch | Delayed 155 XP exact oracle; ordinary future graph/UI | Pending |
| S03 | Missable optional breadcrumb | Story/completion preservation | Compiler breadcrumb rules → transitions/search | Production Story preserves optional breadcrumb:105 XP/100s vs Efficient100/80; defer overrides | Pending |
| S04 | Mutually exclusive chains | Prefix feasibility | PlanTransitions → PlanSearch | Exclusive-branch 110 XP exact oracle | Pending |
| S05 | Shared kill credit, different drops | Separate acquisition | Graph shared credits → transitions | Deduplicated shared kill; drop credit isolated | Pending |
| S06 | Two turn-ins consume same five items | Inventory reservation | BagScan → state → transitions | Summed consumption; bank/equipment cannot pay twice | Pending |
| S07 | Full log or bags | Capacity/service plan | BagScan/services → transitions/search | Full log; full bags; observed services; whole-stack release | Pending |
| S08 | Marker below cliff/on another floor | Verified access or explicit unknown | Graph/Transitions → Terrain | Unknown phase rejected; directed/floor existing terrain tests | Pending |
| S09 | Lift/giver/follow-up unavailable | Bounded retry and alternative | PlanLearning feedback → transitions; Journey | Normal controller suppresses unavailable giver after two reports; explicit Retry action restores it; lift native evidence pending | Pending |
| S10 | Partial counts while walking | Remaining work without route reset | Controller/Runtime → Terrain | Installed automatic315: zero walking replans/replacements | Pending |
| S11 | Complete objective/source item lost | Immediate advance/recovery | Context/State → Controller/Runtime | Normal pipeline source loss and completion → turn-in | Pending |
| S12 | Teleport during path query | Stale rejection | Controller revision → Terrain | Normal controller teleport invalidation and new-origin result | Pending |
| S13 | New quest without provider semantics | Live fallback and coverage gap | Live observed fallback → controller | New quest999 through ordinary controller retains live instructions/marker and coverage gap | Pending |
| S14 | Value beyond shallow horizon | Bounded deep continuation | PlanSearch recursive continuations | 18 quests /72 actions /1000 XP | Pending |
| S15 | Balanced/Story/Efficient tradeoff | Distinct choices, identical feasibility | Preferences → PlanSearch → controls | Production Efficient/Balanced/Story choose300XP in90/108/117s with distinct families and bounded detours | Pending |
| S16 | Explorer detour declined | No repeated nag | Controls/Preference → persistence | Decline maintained through style/settings restore | Pending |
| S17 | Short versus long session | Suitable stopping point | Preferences → PlanSearch | 6-second versus7-second milestone regression | Pending |
| S18 | Native Perfect Stout, cold corpus+terrain | Useful timely stable guidance | Automatic corpus → controller → terrain | Latest six-style installed315: first route240–245frames/4.8–4.9s simulated; zero walking replans/replacements; actual native pending | Pending |
| S19 | Long session/reloads/map changes | Bounded memory and durable preferences | Learning/Codec/Controller | Installed corpus/navigation:24 cycles/48map transitions/six planner-module reloads; <=6000-byte codec restore; stale jobs cancelled; last-half retained heap96,448.5–98,251.8KiB; native memory pending | Pending |

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

## Implementation evidence: state and source graph

The first source slice adds production `quest-preferences.lua`, `quest-plan-state.lua` and `quest-plan-graph.lua`, plus `SemanticData.Frontier/Records`. The compiler now emits typed pickup predicates, distinct active/completed blockers, optional breadcrumb relationships, recurrence metadata, source XP, supported drop probabilities, encounter rank and service flags. The compact map/link index covers the full compiled universe; runtime admission remains explicitly bounded.

`tests/quest-plan-state.test.lua` covers six valid presets, invalid controls, live-state authority and isolation, unknown history/inventory, stale/untrusted rejection, separate future transitions, unknown quantities, live-only fallback, phase exclusion and cancellation. `tests/test_quest_corpus.py` covers prerequisite precedence/alternatives, distinct blocker scopes, unknown counts, reward provenance, drop correction precedence (including zero), all-persona indexes and existing ingestion guarantees. `tests/quest-corpus-installed.lua` now admits every record through the production graph and samples additional personas.

R01/R02/R03/R04/R06/R07/R19 have implemented foundation code with host tests; their integrated UI/gameplay acceptance remains pending. No future source quantity or NPC placeholder health is treated as observed fact. These modules are now connected to ordinary Controller.Update/Step; later sections record integration evidence.

The source contracts were checked against the [pinned eligibility consumer](https://github.com/Questie/Questie/blob/454b9d072965ee8f1a881429260fcf1fac8d60f7/Database/QuestieDB.lua), [pinned drop resolver](https://github.com/Questie/Questie/blob/454b9d072965ee8f1a881429260fcf1fac8d60f7/Database/DropTables/dropDB.lua), and [owned Forever support inputs](https://github.com/Questie/QuestieDB/tree/baa0998d49695c70a1fb8fec559fa9169e9adf33/support/Forever). Host corpus rebuild passed for 7,311 IDs and 18 source personas. Recorded final-source receipts and exact measurements live on the state/graph verification task.

## Implementation evidence: transitions, costs and search

Production now includes `quest-plan-transitions.lua`, `quest-plan-costs.lua`, `quest-plan-learning.lua` and `quest-plan-search.lua`. Tri-state pickup rules, typed resource consumption, branch locks, shared kill credit, conditional unknown-quantity completion, bag/log capacity and optional supported services share one transition model. Validation-only completion cannot grant rewards. Source-item acquisition preserves unknown totals with a lower bound. Future estimates never mutate the live snapshot.

Search combines individual actions (for batching/resource alternatives) with recursive quest continuations. Limits are 48,000 checked expansions, 128 actions per plan, 24 prerequisite quests, 64 beam rounds, width 16, 96 retained first-action alternatives and 128 exclusion diagnostics. This is bounded approximate search, not a global-optimality guarantee. Macros choose a cheap supported completion; primitive alternatives preserve resource-saving methods in the tested cases. Cost ranges expose engineering priors and local sample counts; source XP follows the pinned Questie estimator and remains an estimate.

`tests/quest-plan-search.test.lua` independently enumerates small finite quest jobs: delayed continuation reaches 155 XP, exclusive branches reach 110 XP, and an 18-quest/72-action continuation reaches 1,000 XP. All six flavors preserve legality and choose the delayed chain. A separate quantified preference comparison yields six distinct choices with fixed units. Tests cover duplicate spending/credit, unknown history/counts, stale conditional proofs, compiled skill/reputation/spell fields, source-item lower bounds, full log/bags, optional service capacity, resource-preserving acquisition, short/long stopping points, cycles, cancellation, bounded learning and identity-bound restore.

R04–R16/R18 now have additional production mechanisms and host evidence. Normal controller/UI wiring and the first installed automatic replay are now implemented. The full scenario audit and native/gameplay acceptance remain pending. The research supports explicit feasibility and measured bounded search; it does not certify this implementation. See the [MCTS evaluation](https://arxiv.org/html/2409.03170v1), [GNN distribution-shift evaluation](https://arxiv.org/html/2409.04653v2) and [D* Lite paper](https://www.cs.cmu.edu/afs/cs/Web/People/motionplanning/papers/sbp_papers/integrated3/koenig_dstarlite_aaai02b.pdf).


## Implementation evidence: ordinary controller and player controls

The ordinary corpus path now runs State → Graph → Search through revision-bound controller jobs, with immediate live fallback. Six style buttons and session/difficulty/group/travel/grind/exploration controls, quest/zone goals, optional services, spoilers and strict-session settings are in `quest-plan-controls.lua`. Main details show current instructions, evidence/recovery, up next, alternatives and estimates. Defer/Resume is a real row control; pin/do-now/skip/avoid retain separate semantics. Commands include `/rik quests preferences`, `flavor <name>`, `plan` and `plan-export`.

`quest-bag-scan.lua` reads bounded bag contents and equipped IDs separately. Partial scans yield lower bounds; generic free slots and observed stack headroom constrain collection. Aggregate item counts cannot pay consumable requirements. Optional merchant/trainer offers are observed only during interactions. Sales reserve exact counts/stack receipts, invalidate sold headroom and remain conditional until live state changes. Whole-item turn-ins can release known generic stacks.

`tests/quest-plan-live.test.lua` drives ordinary source loading, Controller, real widget handlers, all six styles, future up-next, partial counts, source-item loss, completion, teleport, defer/restore, decline, capability guards, services and replay encoding. Real settings-codec tests bound durable learned memory to 6,000 characters while preserving full session models. Character/build/locale binding rejects unrelated memory; preferences and completed-event history restore without jobs.

`tests/quest-adaptive-installed.lua` combines the installed 420-addon corpus with installed terrain and archived native observations. Automatic Balanced Perfect Stout reached its first route at176 frames (3.52 simulated seconds), used one terrain window, and retained the walking route with zero replans/replacements. Host callback maximum25ms includes source work; controller source-load maximum15ms; walking callback p99/max6/10ms. Process Lua heap varied126–189MiB before collection across diagnostic runs. These are host measurements with coarse clock resolution, not native latency claims. The existing manual315 replay also passes. Additional styles/310/313/287 and memory plateau checks remain required.

Action IDs now use source area identities, and current-action retention compares fresh-state continuations. Feasible current instructions are not replaced by intermediate search previews. The installed replay exposed and now guards the partial-progress route replacement bug.

Current full Lua suite:9,404 checks. Final committed-source gates are still required. Installation changed420 owned corpus addons; the RikUI source junction remains the delivery path. Full client restart is required for new TOC files.

Native capability inspection was attempted through the documented computer-use runtime: its Windows pipe was unavailable after documented recovery, and read-only process inventory found Battle.net but no running WoW process. No native UI, gameplay, performance or engagement receipt has been earned. Independent implementation and host acceptance work continue.

## Acceptance hardening milestone: rewards, episodes and replay

Production search now includes bounded same-hub pickup bundles. The S01 adversarial source graph attains the independently calculated spatial optimum:three pickups before leaving,300 XP in276s. Compiler `exclusiveWith` separates mutual exclusion from directed breadcrumb blockers; S03 Story completes the missable step before its target, and explicit defer still wins. S15 runs full production graph/search over identical exclusive families:Efficient90s, Balanced108s and Story117s for300XP, with visible efficiency costs0/16.67/23.08 percent. Relaxed/Challenge production searches select easier/harder supported encounters while Efficient keeps the shorter alternative.

`quest-plan-rewards.lua` guards selected-quest reward reads without changing selection. Guaranteed items plus at most one choice, money, explicitly learned reward spells and signed source reputation feed an explicit reward focus/target control. Equipment rewards are not called upgrades. Only earning turn-ins apply rewards; source reputation remains a separate conditional projection and cannot unlock hard standing requirements. Source contracts follow the [pinned reputation field](https://github.com/Questie/QuestieDB/blob/baa0998d49695c70a1fb8fec559fa9169e9adf33/src/meta/questMeta.lua), [Classic reward UI](https://github.com/Gethe/wow-ui-source/blob/classic/Interface/AddOns/Blizzard_UIPanels_Game/Vanilla/QuestInfo.lua), and [reward spell API](https://github.com/Gethe/wow-ui-source/blob/classic/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestInfoSystemDocumentation.lua).

`quest-plan-observer.lua` keeps bounded evidence episodes across context refreshes. Matching target combat/interaction windows and explicit waiting/recovery feedback train only on confirmed progress; AFK, identity/world changes and stale episodes invalidate attribution. Timing tests verify100 refreshes still measure10s combat, and stationary/AFK time does not become invented combat/waiting. Learned component durations use consistent per-unit costs. Compact learned summaries are recomputed from retained samples.

Version2 diagnostic traces capture the exact production graph, state, constraints, environment, learning snapshot and pre/post-retention sequences. `PlanRuntime.RerunReplay` invokes production search and the shared retention rule in an isolated offline context. Source mismatches, duplicate candidates and incomplete inputs reject; expected outputs only participate in comparison. Export/import reexecutes the production decision exactly and preserves live learning even on failure. Diagnostics have a separate bounded4MiB payload/8MiB wire budget; ordinary observation and persistence limits are unchanged.

Current host suite:9,461 checks. These changes remain within active `adaptive-acceptance`; combat-XP attribution, optional exploration, long-session/held-out evidence, final installed-source gates and native acceptance remain in progress.

## Subsequent acceptance work and player feedback

The current host suite passes 9,643 checks. S09 now exercises bounded unavailable
feedback and explicit Retry action through the ordinary controller; S13 preserves
live guidance for an unknown source quest. S19 runs two virtual hours, 24 map
changes and six module reloads with bounded learning and persisted preferences.
These are host observations, not native gameplay receipts.

Combat XP now has a bounded localized message/death-event correlator with strict
ambiguity and context rejection. Player XP deltas do not become invented combat
rewards. Cost estimates consume compatible local samples when available.
Difficulty-fit claims require three compatible combat samples in addition to an
observed character profile. Partial decision traces preserve the actual search
work boundary; dedicated partial-trace acceptance remains outstanding.

Player feedback exposed two availability defects: Goldwell the Elder appeared
on Balanced without event evidence, and future quest exploration triggers became
unsupported optional destinations. The trigger-to-attraction inference has been
removed. All six styles, including pins, reject unsupported seasonal pickups;
the compiler now carries pinned holiday memberships and the runtime accepts only
fresh exact quest/giver offers. Tests exercise offer closure, expiry, identity
changes and ordinary-category holiday membership. Purpose-backed optional
exploration still needs replacement production evidence; the removed fixture is
not retained as acceptance.

Navigation remains limited to the modeled Dun Morogh pack. The user requested
world coverage and questioned the runtime weight, proposing a precomputed
road/path network with local meshes for off-road approaches. A comparison using
the existing mesh is underway before selecting the wider data-delivery design.
No full-world data, road classification or measured memory reduction is claimed.

## Current known evidence gaps

The corpus has locations, methods and raw source relationships, but no guaranteed world-wide navigation or native interaction truth. Future objective counts, missing drop rates, vendor prices, exact capabilities and missing rewards still require source/live support and explicit unknowns. Available Forever XP and NPC drop support tables are now compiled with provenance. SavedVariables are declared but this beta's cross-reload behavior must be verified. Native new/changed chains, lift availability/timing, movement and engagement acceptance cannot be inferred from host tests.

This ledger will be updated as implementation and evidence land. No requirement or scenario is fully accepted merely because its mechanism exists.
