# Talent-based role suggestions

`/rik role` prints the current role guess and the points in each talent tree.
It does not change talents or apply a preset. For Warrior, Arms + Fury points
count toward DPS and Protection points count toward tank. Below **10 total
spent points**, the first role in `roleOrder` wins; ties use that same order.
Warrior declares `{ "dps", "tank" }`.

When the inferred role differs from the applied preset, RikUI offers at most
one popup per login or UI reload. It only prompts for an applied preset matching
the player's class, with `RikUICharDB.askRole == true`.

- **Yes** runs the existing Apply engine with bars and macros enabled and
  bindings, CVars and layout disabled. This replaces designated preset slots
  and macros and creates the usual single Undo snapshot. `/rik undo` restores
  the state before this switch, including the previous role.
- **No**, Escape, or another popup hiding the suggestion dismisses it for this
  session. The character preference stays enabled.
- **Stop asking** sets `RikUICharDB.askRole = false` and does not apply anything.

Suggestions wait until combat ends. An accepted switch also waits and rechecks
talents, the applied marker, preset, character preference and pending Setup work
before calling Apply. Changed conditions cancel it with a chat message.
Pending Apply/Undo and saved partial Undo progress suppress suggestions.

## Talent API and contract

`RikUI.Setup.GuessRole(class)` returns `role, trees`. Each tree record contains
`id` (trait group ID), `name` and `points`, in the native talent header order.
On unavailable/invalid data it returns `nil, nil, reason`; no zero-point guess is
fabricated. The entire talent read and mapping is protected by `pcall`, and
numeric inputs are rejected if secret, missing, negative, fractional or infinite.

The implementation follows the **1.60.1 Camelot client source**, reviewed
2026-09-18:

1. `C_ClassTalents.GetActiveConfigID()` identifies the active configuration.
2. `C_Traits.GetConfigInfo(configID).treeIDs` identifies its trait trees.
3. `C_Traits.GetGroupDisplayInfoByTreeID(treeID)` supplies the three groups in
   the same array order used by Blizzard's talent headers.
4. `C_Traits.GetGroupCurrencyInfo(configID, groupIDs)` supplies currency records,
   matched by `traitNodeGroupID`, using `currencyInfos[1].spent`.
5. While `C_Traits.ConfigHasStagedChanges(configID)` is true, inference is
   unavailable so preview allocations cannot trigger a switch.

Exactly three complete display groups are required. A group omitted from the
currency result counts as zero, matching Blizzard's empty-tree header. A present
group with missing, invalid or secret points is rejected with the tree name in
the diagnostic. A missing/failed currency response remains an error.
The preset must have an explicit `roleOrder` containing each role once and
valid `roles[role].trees` indices. Roles sum all their mapped trees.
The default resolver also respects the first `roleOrder` entry, with the
existing DPS fallback for older presets without ordering metadata.

The event handlers use core's guarded registration for
`CHARACTER_POINTS_CHANGED`, `PLAYER_TALENT_UPDATE`, `TRAIT_CONFIG_UPDATED`,
`ACTIVE_COMBAT_CONFIG_CHANGED`, login and world entry. An unsupported event
does not prevent the other subscriptions from working.

Primary source references:

- [Camelot talent headers and group currency consumer](https://raw.githubusercontent.com/Gethe/wow-ui-source/1.60.1/Interface/AddOns/Blizzard_PlayerSpells/Camelot/ClassTalents/Blizzard_ClassTalentsFrame.lua)
- [Generated trait API](https://raw.githubusercontent.com/Gethe/wow-ui-source/1.60.1/Interface/AddOns/Blizzard_APIDocumentationGenerated/SharedTraitsDocumentation.lua)
- [Active-config API](https://raw.githubusercontent.com/Gethe/wow-ui-source/1.60.1/Interface/AddOns/Blizzard_APIDocumentationGenerated/ClassTalentsDocumentation.lua)
- [Talent UI event handling](https://raw.githubusercontent.com/Gethe/wow-ui-source/1.60.1/Interface/AddOns/Blizzard_PlayerSpells/ClassTalents/Blizzard_ClassTalentsFrame.lua)
- [StaticPopup callbacks and hide order](https://raw.githubusercontent.com/Gethe/wow-ui-source/1.60.1/Interface/AddOns/Blizzard_StaticPopup/StaticPopup.lua)

## Verification status and beta check

The LuaJIT suite covers talent totals, threshold/ties, malformed or unavailable
data, secret values, uncommitted changes, events, popup choices and stale
callbacks. Integration uses the real Apply, macro/bar writers, combat queue
and Undo to check that bindings, CVars and layout stay unchanged.

**Verified in the beta on 2026-09-18:** after reload, `/rik role` reported
`dps (Arms=0, Fury=0, Protection=0)` for a user-confirmed level-1 Warrior.
This exercises the actual trait API path, native tree labels, empty allocation
and default-role diagnostic. The earlier failure exposed omitted zero-point
groups; the reader was corrected and the beta retry succeeded.

Nonzero point totals, role-change event delivery and native popup interactions
have automated coverage but remain unobserved in-game. Follow-up live coverage
is tracked in the `setup-role-beta-coverage` backlog item. The steps below are
for that follow-up; they are not claims of completed checks.

In the beta client, after loading these files:

1. Type `/reload`, then `/rik role`. Compare the three tree names and totals
   with the talent window, and record the client build and output.
2. Check once below 10 spent points and with an allocation favoring Protection
   (at least 10 spent points). If that character is unavailable, state the
   tested allocation; do not claim the untested one.
3. With a matching applied preset and asking enabled, commit a talent change
   that makes the inferred role differ. Check the three choices are visible
   and the prompt is readable; test No and Stop asking across reloads.
4. Confirm Yes with recognizable existing bar/macro content, bindings, CVars
   and layout. Check only bars/macros change, then Undo restores the old role.
   Repeat a deferred confirmation with combat and verify no duplicate prompt.

Record observed output and any API errors in SDD.md before closing the chunk.
