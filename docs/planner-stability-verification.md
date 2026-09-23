# Hook and planner stability verification

Verified locally on 2026-09-22; planner revision `adaptive-8`.

The fixes centralize safe hooks, acknowledge and cancel the supertrack tutorial
before parking the tracker, estimate strategic travel from the road index and
transport links, score all benefits per hour, preserve incumbent plans through
pruning, and record published switches in `RikUIDB.planSwitches`.
`/rik quests switches` prints the last ten; `/rik quests plan-export` exports
the current decision.

## Evidence

| Check | Result |
| --- | --- |
| Manifest and Lua compilation | Pass |
| Full stub suite, LuaJIT and PUC Lua 5.1 | 11,524 checks pass on each |
| Held-out benchmark, adaptive-7 vs final adaptive-8 | 396/396 within the exact efficiency envelope before and after; zero constrained utility loss |
| Installed Muren corpus regression, PUC Lua 5.1 | 11/11 walk positions retain the real 1679 turn-in; zero switches; new export replays as match |
| Installed Perfect Stout road regression, PUC Lua 5.1 | Pinned quest 315 retained; endpoint reached after 559.5 yards; zero route swaps or off-route replans |
| Installed source | Beta client's RikUI directory is a junction to this repository |

The held-out benchmark uses 276 restricted turn-in cases and 120 broader cases
across six styles, with real corpus records and synthetic character/travel state.
Its exact comparison shares production mechanics; this is not independent proof
of world reachability. Reports are in
`D:/RikUI-local/observations/heldout-adaptive-{7,8-final}.json`.

The Muren regression rebuilds the graph through `PlanGraph.Begin` from the
installed corpus. It verifies Muren's actual 85 XP reward and breadcrumb to 1678;
it never clones another quest's action. The archived packet
`plan-after-switch.rikp` uses adaptive-7, so exact replay is explicitly skipped
with `source_mismatch`. A newly generated adaptive-8 trace replays exactly.
The eleven full searches use the 48,000-work cap, take at most 1.688 CPU seconds
each on the measured host, and load no road networks. Production search yields
between work units; that total is not a single callback measurement.

The road regression uses `forever-69913-enUS-9c563e01-native.rikq`, which
contains Perfect Stout. The earlier 8dbb9a00 packet does not contain 315 and
cannot establish that quest's acceptance. With the correct packet, guidance
appears at frame 191, the measured maximum callback is 23 ms, and maximum addon
load is 16 ms. These are host replay timings.

A separate 139-stop index measurement estimates 27.8 seconds to Muren,
249.2 seconds to central Stormwind and 822.8 seconds to central Darnassus.
Cold capture plus queries took 28 ms; 10,000 cached queries took 42 ms in PUC 5.1.
These strategic costs remain explicitly unverified estimates, not walking paths.
Ironforge's UI map is 1455; 1537 in source action IDs is its area ID.

## Native acceptance still required

No game process was running during verification, so a fresh native session was
not observed. Fully restart the beta client, check login and nameplates, drag
and resize chat, enter and exit Edit Mode, and leave the unsupertracked quest
tracker visible for over two minutes. Then walk a turn-in trip and inspect
`/rik quests switches`. Native UI, gameplay and performance acceptance remains
separate from the passing host regressions.
