<!-- magistr:codex -->
## Magistr in Codex

Launch with `magistr codex-launch --project-root . --` or `./.codex/run`. The native launcher resolves dependencies and applies the documented Codex skill-discovery compatibility boundary. Use `magistr codex-launch --project-root . --diagnose` for read-only diagnostics.

Use the configured `magistr` MCP server for roadmap_*, think_*, ship_*, signal_* and magistr_* tools. It embeds think-and-ship; do not start a standalone workflow server. Use Workbench map/search/read/edit/files/run/script/undo for workspace content; follow .agents/skills/workbench-routing/SKILL.md. A held Workbench lock belongs to its existing connection: do not kill the owner or launch a competing probe.

Use the nine project skills: $next, $next-loop, $validate, $roadmap, $roadmap-refresh, $signals, $craft, $init and $workbench-routing. $next runs one chunk in this Codex session. $next-loop is a bounded fresh-session handoff: finish one chunk, write the handoff, stop, and resume the bound only in a new Codex session. Read .magistr/project.json for commands and required custom gates and .claude/rules/conventions.md for shared project conventions. Claude hooks are additional enforcement only; Codex must explicitly run and record required gates.

The native roadmap is authoritative. Read .magistr/project.json before exporting a view: roadmap_exports=false forbids ROADMAP.md/ROADMAP.json and all file exports. Otherwise export only when the project requests a view.

Preserve existing objectives and worktree changes. Follow the requested scope; setup, review and planning do not authorize starting a roadmap chunk. $next implements one ready chunk; $next-loop is bounded. Recovery, acceptance, recorded checks and an atomic commit are required before completing work.
<!-- /magistr:codex -->

## Workbench defaults

The user authorizes automatic application of Workbench writes within the requested task. Pass `autoApply: true` by default to Workbench `edit`, `files`, and write-producing `script` calls; for applying scripts also pass `dryRun: false`. This standing preference applies to future sessions and overrides the routing skill's preference for the confirmation-token flow. Continue to review changes and verify results. Respect protected paths, policy denials, unrelated changes, and the existing server lock.

## Native acceptance policy

The user accepts native/game-client behavior as working and will report regressions. Do not require native playtests, screenshots, interaction runs, or native performance/sign-off evidence to implement, close, commit, or advance work. Do not create or retain routine native-acceptance-only blockers or backlog chores. This standing instruction supersedes native-verification requirements in project skills, handoffs, and older roadmap records.

Continue meaningful automated checks and code review for changed behavior. Record the user's acceptance as acceptance; do not invent agent-observed native test results. Preserve explicit unknown source data and supported-coverage limits without treating them as requests for the user to perform testing.

## Client version policy

Never pin a Forever build or Blizzard UI commit for new work. Before reading Blizzard UI source, resolve the latest Forever build: the head of the `forever` branch of Gethe/wow-ui-source (its commit message names the build, e.g. `1.60.1 (NNNNN)`; `version.txt` holds the full version), cross-checked against the user's `WowB.exe` file version when available. Read source from that head. Build numbers and commit SHAs in docs, data and code comments are evidence of what was reviewed at the time, not a target; when one disagrees with the current build, re-check against the current source before relying on it.

## Class research policy

Always research current online WoW Forever player feedback and class-specific requests before planning or implementing class work. Record dated source links and separate community requests from confirmed client behavior. Verify spell IDs, ranks, form pages and APIs against current primary sources or exact-build client data; preserve unknown coverage explicitly.
