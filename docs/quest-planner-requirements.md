# Adaptive quest planning requirements

Status: proposed product and engineering requirements, 2026-09-21 local.
User goal: XP-efficient, fun and engaging dynamic questing and leveling, with
multiple selectable flavors. Balanced is the proposed default. This document
defines the target behavior; it does not claim that the current addon implements
these requirements. Native Magistr remains authoritative for delivery status.

## Product objective and flavors

The planner should recommend a feasible, understandable next action that makes
useful leveling progress in the style the player chose. XP efficiency stays
visible, but the player can trade some efficiency for coherent stories, variety,
discovery, comfort or challenge. Fun is a preference to investigate with the
player, not a universal number the engine can know.

All flavors share one state model, action graph, travel model and solver.
Presets alter preferences, budgets and presentation. They must produce materially
different, explainable choices when a scenario offers meaningful tradeoffs.

| Flavor | Primary preference | Intended tradeoff |
| --- | --- | --- |
| Balanced (default) | Reliable progress, coherent local quest arcs, variety and reasonable travel | Accept worthwhile detours while avoiding aimless travel or repetitive grinding |
| Efficient | Reliable XP per elapsed play time | Favor batching and productive chains; tolerate repetition when the player permits it |
| Story | Quest and zone narrative continuity | Finish useful arcs and preserve breadcrumb opportunities within the chosen efficiency budget |
| Explorer | New places, discoveries and varied routes | Take optional, bounded detours; use recorded visitation history without pretending unknown history is new |
| Relaxed | Predictable solo progress and low pressure | Prefer manageable fights, short excursions and low waiting/risk |
| Challenge | Optional, capability-appropriate difficulty | Prefer interesting harder objectives while respecting explicit risk and group constraints |

Presets are starting points, not mandatory identities. Session intent and a
small set of understandable controls should be sufficient; tuning raw solver
weights must not be required. Story spoiler detail should be optional.

## Required behavior

### R01. Configurable goals and strict constraints

- Support a flavor plus session length, preferred difficulty, permitted group
  content, travel tolerance, grind tolerance, exploration allowance and optional
  quest/zone completion goals.
- Separate hard constraints from preferences. Class, faction, phase, prerequisites,
  inaccessible travel, user exclusions and available party/resources constrain
  feasible actions before scoring. A high nominal reward cannot override them.
- Distinguish “do this now”, pin, defer for this session, skip this quest and avoid
  this content/area. Resolve conflicting requests visibly; never silently treat
  a soft preference as a permanent exclusion.

### R02. Character and world state with provenance

- Model current and completed quests, objective progress, position/map/floor,
  level/XP, class/race/faction, relevant reputation/profession/skill state,
  inventory and known travel capabilities when the client exposes them.
- Separate live observations, source claims, inferred state, stale state and
  unknown values. Bind evidence to character, build, locale and data revision.
  Live progress is authoritative for completion; proximity is not completion.
- Reconcile contradictions and retract outdated inferences. Unsupported client
  fields remain unknown; missing source coverage must not erase live objectives.

### R03. A graph of current and future quest opportunities

- Represent acceptance, each objective, completion, turn-in and follow-up as
  distinct transitions. Include quests outside the current log when their
  availability can be supported by data.
- Encode AND/OR prerequisites, minimum levels, reputation gates, branching and
  mutually exclusive chains, optional prerequisites, breadcrumbs and opportunities
  that become unavailable after another action.
- Distinguish a breadcrumb from a mandatory prerequisite. Handle repeatables,
  resets and cycles with explicit bounds rather than assuming every chain is
  an acyclic list or allowing infinite reward loops.
- Preserve source uncertainty about future availability. A known quest ID or
  chain link alone does not establish where, when or whether it can be accepted.

### R04. Executable action semantics

- Each suggested action needs preconditions, target, interaction, expected
  state changes, live completion evidence and an abort/recovery condition.
- Cover supported kill, collect/drop, loot, talk, use-item, explore, escort,
  defend, deliver, craft and purchase mechanics. Treat compound objectives
  and ordered interaction stages explicitly.
- Choose among valid acquisition methods and locations. Do not turn a generic
  NPC quest icon into a claim that it supplies a particular quest or drop.
  Unsupported mechanics receive useful qualified instructions, not invented steps.

### R05. Inventory, capacity and services as changing state

- Model items gained and consumed; distinguish carried, banked and equipped
  resources where observable. Never spend one stack twice in a simulated plan.
- Account for quest-log capacity, bags, required currency, keys, source items,
  usable cooldowns, hearth binding and transport access.
- Include useful vendor, repair, training and other service stops when supported
  and enabled. Bundle them with nearby visits; avoid speculative mandatory chores.
  Equipment or skill upgrades may change expected combat capability, not just gold.

### R06. Full XP, effort and reward accounting

- Estimate quest XP, eligible combat XP and other confirmed leveling rewards,
  accounting for level-dependent reward changes and relevant modifiers when known.
  Level-ups can unlock quests, travel or capabilities and affect future costs.
- Count travel, combat, loot, interaction, reading preference, waiting/respawns,
  recovery, expected deaths and service detours in elapsed play time.
- Include player-valued unlocks, equipment, reputation and currency without
  counting the same downstream benefit twice. Report missing reward/cost data
  instead of manufacturing exact XP/hour.

### R07. Honest uncertainty and risk

- Model variable drop counts, spawn density, competition, rare-spawn waiting,
  encounter outcomes and uncertain travel with supported estimates or ranges.
  Unknown is neither zero cost nor impossible.
- Compare reliable progress with high-variance opportunities using the player's
  risk tolerance and session budget. A favorable mean must not conceal a serious
  chance of an unproductive session.
- Calibrate estimates from evidence; do not attach arbitrary confidence
  percentages. Limit retries and offer alternatives after repeated unavailable
  interactions. Information-gathering detours require a plausible bounded benefit.

### R08. Topology-aware objective clustering

- Cluster actions by shared accessible area, entrance/exit, floor, travel corridor,
  timing and objective compatibility, not just horizontal coordinate distance.
- Separate shared travel, shared enemy credit and shared item acquisition.
  One kill can credit two quests where supported; it cannot guarantee two rare
  drops or pay two item-consuming turn-ins with one item.
- Consider future clusters: pick up suitable quests before passing their targets,
  stage compatible collection, and combine objectives, services and turn-ins.
  Avoid extra pickups that consume needed log slots without enough expected value.

### R09. Recursive future planning

- Evaluate pickup -> objective -> turn-in -> unlock sequences across multiple
  quests and hubs, including future quests not yet accepted.
- Recognize when an apparently inefficient immediate step opens a valuable local
  cluster or chain. Compare alternative branches and the opportunity cost of
  leaving missable content behind.
- Use bounded, adaptive lookahead and a supported estimate of value beyond the
  immediate horizon. A fixed shallow depth must not systematically miss long
  worthwhile chains; speculative distant rewards must not defer progress forever.
- Recompute only relevant graph regions as eligibility and progress change.
  Keep a valid current action while evaluating more ambitious continuations.

### R10. Multi-objective plan selection

- Consider several feasible plans with different tradeoffs among progress,
  elapsed time, variety, narrative continuity, discovery, pressure and risk.
  Apply the selected flavor and explicit constraints consistently.
- Use stable scales for preference terms. Adding an unrelated candidate must not
  arbitrarily renormalize every score or change switching thresholds.
- Score useful remaining work and future outcomes; avoid sunk-cost bias from
  progress bonuses, double-counted unlocks, repeated novelty rewards and reward
  loops. Preserve meaningful comparisons when estimates are incomplete.
- Show the efficiency cost of a preference when supported by evidence. A detour
  allowance or efficiency envelope is more understandable than opaque weights.

### R11. Activity variety, continuity and player agency

- Track recent activity types and repetition over a bounded history. Favor variety
  when requested without interrupting nearly finished work solely to rotate tasks.
- Preserve useful story segments and local continuity. Distinguish semantic chain
  links from actual narrative relationships; do not invent a story classification.
- Make exploration optional, bounded and dismissible. Respect manual deviations:
  the player may be curious, not dissatisfied or “off route”.
- Adapt preferences cautiously through explicit feedback. Never silently change
  the flavor because the player ignored a recommendation.

### R12. Session-aware pacing and good stopping points

- Plan for short or long sessions, including time to finish, recover and reach a
  sensible stopping point. Avoid launching a long uncertain escort or rare-item
  grind near an intended stop unless the player chooses it.
- Offer natural milestones: finish a chain segment, complete a nearby cluster,
  unlock a hub or reach a safe service location.
- Keep session clocks and estimates advisory. Session length is a planning input,
  not pressure to hurry or remain in game.

### R13. Player-calibrated difficulty and party support

- Estimate encounter suitability from available character, group and experience
  evidence, with uncertainty. Level difference alone is insufficient.
- Relaxed and Challenge should change preferred difficulty and variance within
  the same hard constraints. Repeated failure should yield a defensible alternative.
- Respect solo/group/dungeon preferences and actual group availability.
  Where shared party state is legitimately available, account for differing
  prerequisites, quest credit eligibility and the cost of regrouping.
- Full cooperative optimization is an extension; truthful feasibility for current
  group-dependent quests is required even without it.

### R14. Hierarchical travel and real navigation

- Separate strategic zone/hub/chain choices, tactical objective ordering and
  continuous walking guidance. Walking progress must not restart strategic search.
- Use directed, conditional travel costs for entrances, floors, water, doors,
  flights, boats, lifts, portals and hearth travel when supported. Include waiting,
  cooldowns and unlocking the travel option.
- Prefer verified connectivity and usable approaches. A short map distance cannot
  prove a path across a cliff, cave ceiling or missing lift.
- Keep geometry coverage separate from quest-source coverage. If terrain is
  missing, expose a marker or qualified direction with an honest limitation.

### R15. Stable incremental replanning

- Replan on material changes: completion, accepted/abandoned quests, newly available
  chains, invalid targets, death/teleport, map/floor change, resource loss,
  party/capability changes or a meaningful new opportunity.
- Update remaining work after partial progress without discarding valid routes.
  Use commitment and meaningful improvement thresholds to suppress thrashing.
- Necessary invalidation overrides continuity. A completed, impossible or excluded
  action must stop competing immediately; low replan counts alone are not success.
- Cancel or reject stale asynchronous results using state and data revisions.
  Repair relevant costs/search regions and reuse valid work where practical.

### R16. Bounded runtime and useful fallback

- Produce a feasible initial recommendation quickly, refine it incrementally and
  retain the last still-valid answer while work continues.
- Budget solver work per frame; bound candidate counts, graph expansion, queues,
  caches, memory and retries. Share budgets across competing planner jobs.
- Every load/search must have progress, completion, cancellation, timeout and a
  useful failure state. “Preparing terrain” cannot be an indefinite end state.
- Initial targets to validate on the actual client: immediate live instructions
  or marker fallback, warm recommendation within 250 ms, first local cold route
  within a few seconds where data is installed, and about 1 ms/frame of incremental
  solver work. These are proposed targets, not achieved guarantees.
- Measure synchronous addon loading and total callbacks separately; a bounded
  search slice does not prove a bounded full frame. Tune explicit memory and
  loading budgets from native measurements.

### R17. Explanations, alternatives and controls

- Show an actionable current instruction, objective progress, a short “up next”
  list, and why this choice suits the selected flavor.
- Explain material detours, upcoming unlocks, uncertainty and recommendation
  changes in plain language. Detailed scoring/provenance belongs in diagnostics.
- Offer a few meaningful alternatives with supported tradeoffs and reversible
  pin/defer/skip/avoid controls. The current choice must remain visible and stable
  while alternatives are evaluated.
- Distinguish observed facts, source suggestions and estimated routes without
  drowning normal play in implementation details.

### R18. Learning and durable state

- Improve combat, collection, travel and waiting estimates from relevant local
  observations, with cold-start defaults, sample counts and uncertainty.
- Separate explicit player preferences from incidental behavior. Make learned
  preferences inspectable and resettable; one unusual session must not dominate.
- Preserve preferences, relevant completion knowledge and lightweight history
  across reloads where the client permits it. Reconcile with fresh live state and
  source/build changes; never restore stale route jobs as current truth.
- Keep planning usable when persistence fails. Existing session-only observations
  must remain useful. External model training or cloud services are not required.

### R19. Compatibility, coverage and operational correctness

- Use only supported client APIs and interactions; guidance must not depend on
  unavailable server knowledge or unsupported gameplay automation.
- Handle build, locale and persona differences, localization collisions,
  ambiguous objective names, partial data and newly added server quests.
- Report semantic, future-chain and navigation coverage separately, including
  unresolved fields. Importing every available record is not proof of complete
  world knowledge or a working plan for every quest.
- Provide revisioned schemas, deterministic ingestion, migration and fallback
  behavior so one bad partition does not invalidate unrelated guidance.

### R20. Evaluation, observability and acceptance

- Replay decisions from state, source revision, candidate set, constraints, flavor,
  cost components and uncertainty. Record why an action was excluded or changed.
- Compare identical information and constraints against current ordering, nearest
  feasible work, existing heuristics and authored routes. Use exact offline
  solutions for small cases to measure avoidable planning loss.
- Test held-out zones/personas, multiple flavors, long chains, long sessions,
  cold start, stale/incomplete data and mid-action interruptions.
- Measure confirmed XP per elapsed time, successful objective/interaction progress,
  infeasible suggestions, wasted visits, backtracking, switching, waiting without
  guidance, callback percentiles/worst stalls, memory and recovery.
- Assess engagement with playtests: perceived repetition, coherence, stress,
  discovery, choice and enjoyment. Overrides are clues, not automatic failure.
  Do not optimize hours played or clicks as a proxy for fun.
- A requirement is complete only with demonstrated behavior and recorded evidence.
  Host simulations, native UI checks and actual gameplay acceptance are distinct.

## Minimum adversarial acceptance suite

| Scenario | Required result |
| --- | --- |
| Pickups unlock three objectives along the upcoming route | Collect suitable quests first and avoid an unnecessary second trip |
| A turn-in unlocks a valuable nearby follow-up cluster | Compare the full continuation, not just the immediate turn-in XP |
| Optional breadcrumb disappears after another turn-in | Preserve it when the player's completion/story preferences justify doing so |
| Two chains are mutually exclusive | Never plan rewards from both incompatible branches |
| Two quests share kill credit but require different item drops | Share the visit; model collection effort separately |
| Two turn-ins consume the same five items | Reserve or acquire enough items; never spend the stack twice |
| Full quest log or bags | Produce a feasible capacity/service plan rather than a collection loop |
| Nearby marker is below a cliff or on another floor | Use verified access or explain missing travel knowledge |
| Lift, quest giver or follow-up unavailable | Bounded retry and useful alternative, with the unresolved fact retained |
| Partial count changes while walking | Update remaining work without resetting a valid route |
| Current objective completes or source item disappears | Advance or recover promptly; do not preserve invalid continuity |
| Teleport during a pending path query | Reject the stale result and plan from the new location |
| New server quest lacks provider semantics | Keep live instructions/marker useful and expose the coverage gap |
| Longer chain's value lies beyond a shallow search depth | Recognize supported continuation value without infinite expansion |
| Balanced, Story and Efficient face a real tradeoff | Produce distinct explainable choices within identical constraints |
| Explorer detour is declined | Honor the decline and continue the main plan without repeated nagging |
| Short session versus long session | Prefer suitable stopping points and avoid unsuitable commitments |
| Native Perfect Stout with cold corpus and terrain | Timely useful guidance and stable walking with meaningful diagnostics |
| Long session with repeated reloads and map transitions | Bounded state/memory, restored preferences, no stale job publication |

## Algorithm direction and research basis

The candidate architecture is a shared state/evidence model feeding a bounded
future-action graph and hierarchical, multi-objective search. It should produce a
usable initial plan, improve it in available frame time, commit to a sensible
next action, and repair affected parts as observations change. Offline exact
solvers are useful evaluation oracles; they need not run in the addon.

Search choice follows benchmark results. Beam search, bounded dynamic
programming, macro-actions and Monte Carlo tree search are candidates, not badges
of quality. Learned heuristics are optional accelerators only if they improve
quality/runtime on held-out game scenarios while preserving feasibility checks.

Primary research supports relevant techniques, not a claim that one published
solver is already suitable for this addon:

- [Carpin, 2024: stochastic orienteering with chance constraints and MCTS](https://arxiv.org/abs/2409.03170)
  studies online/anytime planning with uncertain travel and a bounded probability
  of violating a time budget. It motivates risk-aware evaluation, but quest
  prerequisites, resource consumption and subjective preferences require
  additional modeling.
- [Zuzuárregui and Carpin, 2025 revision: GNN-powered MCTS](https://arxiv.org/abs/2409.04653)
  explores learned rollout estimates for stochastic orienteering. This is an
  optional research direction, with training/generalization costs to justify.
- [Koenig and Likhachev, 2002: D* Lite](https://publications.ri.cmu.edu/d-lite)
  provides a foundational example of reusing search work for changed navigation
  problems. Path repair and quest-sequence optimization are separate layers.

“State of the art” is therefore an evaluation claim: superior useful decisions
under realistic state, uncertainty and runtime limits, demonstrated against
strong baselines. A recursive function, an XP score or a neural model alone
does not establish it.

## Current implementation boundary

The Forever corpus is imported and integrated into generic live guidance.
The live stability follow-up adds source action text, local distance/progress/
turn-in/shared-area preferences, pin/manual continuity, bounded source comparisons
and separate walking diagnostics. The existing sequence optimizer can search a
prepared action graph, but the full corpus does not yet construct the complete
future-action graph described here.

These pieces provide foundations for this specification. They do not implement
the flavor system, comprehensive future-chain/resource optimization, personalized
cost models or the complete acceptance suite. Missing native walking, interaction,
new-chain and lift evidence remains tracked in Magistr.
