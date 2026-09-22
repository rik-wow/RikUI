# Adaptive planner acceptance and evidence

This is the requirement-to-production-code/test/UI/evidence ledger for the complete authorized scope of [the requirements](quest-planner-requirements.md). Native Magistr owns lifecycle status. This ledger is not a roadmap export.

Baseline: commit 1169c27, clean checkout, 9,204 recorded Lua checks before this work. Existing terrain-coverage and quest-natural-journeys tasks and quest-forever-corpus native acceptance remain outstanding and are preserved. A planned file is not implemented evidence.

## Requirements

| ID | Behavior | Existing foundation | Production ownership | Required automated evidence | Visible behavior | Acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| R01 | Goals and constraints | Controller policy/manual selection; eligibility | quest-preferences.lua; quest-plan-state.lua | Control conflicts, hard constraints | Flavor/session/constraints | Pending |
| R02 | State and provenance | Reader/Context/Journal; exact identity | quest-plan-state.lua; Context | Live precedence, source retraction | Source/unknown explanation | Pending |
| R03 | Future opportunities | Raw corpus links; live-only loading | quest_corpus.py; SemanticData; quest-plan-graph.lua | AND/OR/exclusive/breadcrumb/cycles | Future pickup and up next | Pending |
| R04 | Executable actions | Steps and semantic methods | quest-plan-graph.lua; quest-plan-transitions.lua | Mechanic preconditions/effects/recovery | Action, evidence and recovery text | Pending |
| R05 | Resources/capacity/services | Prepared simulation consumes items | quest-plan-state.lua; quest-plan-transitions.lua | No double spend, capacity, services | Missing resources/service alternative | Pending |
| R06 | XP/time/rewards | Selected quest live XP; prepared durations | Compiler XP; quest-plan-costs.lua | Level scaling, cost components, no reward duplication | Honest estimates and incomplete XP | Pending |
| R07 | Uncertainty and risk | Source unknowns; route limitations | quest-plan-costs.lua; quest-plan-learning.lua | Ranges, retry bounds, alternatives | Range and risk explanations | Pending |
| R08 | Topology clusters | Source areas; directed terrain | quest-plan-graph.lua; transitions | Shared kills vs drops; future pickup batching | Shared visits and access limits | Pending |
| R09 | Recursive lookahead | Prepared beam depth <=8 | quest-plan-search.lua; graph | Deep chain, future value, incremental repair | Future continuation | Pending |
| R10 | Multiple plans/flavors | Live local heuristic | quest-preferences.lua; search | Stable units, six tradeoffs, no sunk costs | Alternatives and efficiency tradeoff | Pending |
| R11 | Variety/continuity/agency | Manual selection/pin/skip/avoid | quest-plan-learning.lua; preferences | Bounded history, explicit feedback, decline | Continuity and dismissible discovery | Pending |
| R12 | Session pacing | Prepared maxSeconds | search; preferences | Short/long, stopping reserve | Session length and milestones | Pending |
| R13 | Capability and party | Class/race/faction/level snapshot | state; costs; transitions | Solo/group gates, observed failure | Difficulty and group control | Pending |
| R14 | Hierarchical travel | Directed travel; terrain search/follower | graph travel adapter; controller | Cliff/floor/conditional access | Marker vs verified route | Pending |
| R15 | Stable replanning | Controller/terrain revision guards | controller; search; memory | Progress/completion/teleport/resource changes | Stable current action and change reason | Pending |
| R16 | Runtime/fallback | Sliced source/terrain/optimizer | graph/search shared scheduler | Caps, cancel, timeout, cold/warm timings | Immediate useful fallback | Pending |
| R17 | Explanations/controls | Tracker/details/map controls | quest-plan-controls.lua; view/commands/guidance | Real widget interactions and details | All six presets and reversible controls | Pending |
| R18 | Learning/persistence | CharDB policy; session observations | quest-plan-learning.lua; persistence bridge | Migration, reload, bounded learning/reset | Learned sample counts and reset | Pending |
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
| S01 | Pickups unlock three upcoming objectives | Graph/search batching | Graph/search | Batching regression still required | Pending |
| S02 | Turn-in unlocks valuable nearby follow-ups | Full continuation | PlanGraph → PlanSearch | Delayed 155 XP exact oracle; ordinary future graph/UI | Pending |
| S03 | Missable optional breadcrumb | Story/completion preservation | Compiler breadcrumb rules → transitions/search | Availability enforced; Story opportunity regression still required | Pending |
| S04 | Mutually exclusive chains | Prefix feasibility | PlanTransitions → PlanSearch | Exclusive-branch 110 XP exact oracle | Pending |
| S05 | Shared kill credit, different drops | Separate acquisition | Graph shared credits → transitions | Deduplicated shared kill; drop credit isolated | Pending |
| S06 | Two turn-ins consume same five items | Inventory reservation | BagScan → state → transitions | Summed consumption; bank/equipment cannot pay twice | Pending |
| S07 | Full log or bags | Capacity/service plan | BagScan/services → transitions/search | Full log; full bags; observed services; whole-stack release | Pending |
| S08 | Marker below cliff/on another floor | Verified access or explicit unknown | Graph/Transitions → Terrain | Unknown phase rejected; directed/floor existing terrain tests | Pending |
| S09 | Lift/giver/follow-up unavailable | Bounded retry and alternative | PlanLearning feedback → transitions; Journey | Retry cap mechanisms; integrated unavailable test still required | Pending |
| S10 | Partial counts while walking | Remaining work without route reset | Controller/Runtime → Terrain | Installed automatic315: zero walking replans/replacements | Pending |
| S11 | Complete objective/source item lost | Immediate advance/recovery | Context/State → Controller/Runtime | Normal pipeline source loss and completion → turn-in | Pending |
| S12 | Teleport during path query | Stale rejection | Controller revision → Terrain | Normal controller teleport invalidation and new-origin result | Pending |
| S13 | New quest without provider semantics | Live fallback and coverage gap | Live observed fallback → controller | Unknown-record graph fallback; integrated case still required | Pending |
| S14 | Value beyond shallow horizon | Bounded deep continuation | PlanSearch recursive continuations | 18 quests /72 actions /1000 XP | Pending |
| S15 | Balanced/Story/Efficient tradeoff | Distinct choices, identical feasibility | Preferences → PlanSearch → controls | Six Score tradeoffs + six real widgets; full-search tradeoff still required | Pending |
| S16 | Explorer detour declined | No repeated nag | Controls/Preference → persistence | Decline maintained through style/settings restore | Pending |
| S17 | Short versus long session | Suitable stopping point | Preferences → PlanSearch | 6-second versus7-second milestone regression | Pending |
| S18 | Native Perfect Stout, cold corpus+terrain | Useful timely stable guidance | Automatic corpus → controller → terrain | Installed archived315: first route176frames/3.52s simulated; actual native pending | Pending |
| S19 | Long session/reloads/map changes | Bounded memory and durable preferences | Learning/Codec/Controller | Bounded 128models,256completionIDs,6000-byte durable memory; full long-run still required | Pending |

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

## Current known evidence gaps

The corpus has locations, methods and raw source relationships, but no guaranteed world-wide navigation or native interaction truth. Future objective counts, missing drop rates, vendor prices, exact capabilities and missing rewards still require source/live support and explicit unknowns. Available Forever XP and NPC drop support tables are now compiled with provenance. SavedVariables are declared but this beta's cross-reload behavior must be verified. Native new/changed chains, lift availability/timing, movement and engagement acceptance cannot be inferred from host tests.

This ledger will be updated as implementation and evidence land. No requirement or scenario is fully accepted merely because its mechanism exists.
