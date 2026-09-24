# Quest tracker

`src/modules/questtracker/questtracker.lua` and `src/modules/questtracker/questtracker-blocks.lua` replace the stock objective
tracker with a compact list of watched quests. `ObjectiveTrackerFrame` is
parked through the [shared hide helper](../SDD.md) once the list exists.
Disable the `questtracker` module in `/rik config` and reload to get the stock
tracker back.

## What you see

A 240px column at the top right, under the minimap. The header is an 18px flat
plaque with the label, the number of watched quests and a `-` or `+` glyph.
Under it, one block per watched quest in watch order:

- a 2px accent on the left edge and the title as `[level] Title`, both in the
  quest's difficulty colour (`GetQuestDifficultyColor`), gold when the client
  gives no level;
- one line per objective as `- text`, light grey, dimmed once the objective is
  finished.

A complete quest shrinks to a green title and one `Ready to turn in` line. A
failed quest turns red with a `Failed` line. Titles and objectives never wrap;
a long one truncates, which keeps every row a fixed height (14px title, 12px
line, 6px between quests). With nothing watched the whole list hides.

## Motion

A quest seen for the first time fades in over 0.15s. When an objective's text
changes, that line flashes white for 0.4s. A quest that turns complete glows
green once for 0.6s. Expanding the list fades every block in. A refresh that
changes nothing replays nothing, and quests that only move up the list do not
fade again.

In Settings > Gameplay > Quest tracker, **Hide completed objectives** removes finished steps from active quests and reduces their height. Ready and failed summaries stay visible. The option is off by default; full details remain available on hover.

**Ready quests first** brings turn-ins to the top, preserving watch order within both groups. Turning it off restores native watch order. It never changes which quests are tracked, and profile changes refresh the list.

## Hover details

Hover a quest to read its full title and every objective with wrapping text, including completed objectives. Ready and failed states appear above the objectives. The tooltip updates with quest progress and clears when the block hides or is reused.

## Clicks

Click a quest to open it in the quest log (`QuestMapFrame_OpenToQuestDetails`).
Shift-click stops tracking it (`C_QuestLog.RemoveQuestWatch`). Hovering a quest
lights it and shows both hints. Click the header to collapse the list to the
header; the state is saved in the profile as `questtracker.collapsed`.

## Refresh

`QUEST_LOG_UPDATE`, `QUEST_WATCH_LIST_CHANGED` and `PLAYER_ENTERING_WORLD`
request a render. The client fires these in bursts, so requests within 0.1s
collapse into one read of the quest log. The read runs under `pcall`; a failure
prints one `Quest tracker read` line and keeps the last good list on screen.

## Layout

The holder is `RikUIQuestTracker`, registered with the [shared layout](layout.md)
under `questtracker`, so `/rik move`, `/rik move reset` and `/rik scale` apply.
The default is `TOPRIGHT` of the screen at `x=-126, y=-260`, left of the two right-hand bars. The list grows
downward from there.

The list never grows into the frame under it. It registers with `grow = "DOWN"`
and `onLimit = tracker.SetRoom`; after every layout pass the layout reports the
room down to the next frame or the screen edge, and `view.Limit` becomes the
tallest the list may get (its current height plus that room, so a render that
shortens the list does not change the limit). Quests are laid out in watch
order until the next one would not fit with a 14px line under it; that line
reads `+N more` in grey. Later quests stay hidden even if a shorter one would
fit, so the order on screen is always the watch order. Move the list or the
frame under it and the cap follows. A client that reports no screen size gives
no room figure and the list is uncapped.

## Stock frame

`ObjectiveTrackerFrame` is parked with its events kept, only after the list is
built, inside one `Combat.Queue` closure; at a combat login nothing is touched
until `PLAYER_REGEN_ENABLED`. The list itself is unprotected frames, so it
shows, hides and resizes in combat. A client without the `C_QuestLog` watch
calls prints one `Quest tracker unavailable` line and keeps the stock tracker.

Parking the stock tracker removes all of its modules, not only quests:
scenario steps, bonus objectives, tracked achievements and the auto-complete
popup go with it. Forever's Classic content does not use them today. If one
turns out to matter, disable this module.

## Diagnostics

`/rik debug` prints `Quest tracker holder=<bool> quests=<n> collapsed=<bool>`.

## Verification

`tests/questtracker.test.lua` fakes the quest log with three quests. It proves:
the layout key and top-right defaults; one block per watched quest in order;
the level tag, font, difficulty colour and no wrapping; objective lines with
finished ones dimmed; the holder's width and height; the header label, count,
glyph and border; the first fade; a changed objective flashing only its line; a
burst of events rendering once; a complete quest's shape, colour and single
glow; an unchanged refresh replaying nothing; a failed quest; a newly watched
quest fading in alone; an unwatched quest leaving; click and shift-click; hover
highlight and hints; collapse, its saved state and the expand fade; nothing
watched hiding the list and the list returning in combat; a failing read
reported once with the last list kept; the stock tracker parked; the debug
line; a collapsed profile after a reload; a combat login building nothing until
regen; a client without quest info or difficulty colours; a client without the
quest log API; a disabled module leaving everything untouched; the growth
direction, limit callback and label given to the layout; a list capped at 70
units showing one quest and `+1 more`; the full list back when the room
returns; no cap without a room figure.

The stub cannot show how the list looks or whether addon code may open the
quest map in combat. Beta checklist:

1. Reload with quests watched: the list sits under the minimap and the stock
   tracker is gone. `/rik debug` should print the quest count.
2. Kill a quest mob: the objective line updates and flashes. Finish the quest:
   the block turns green, shrinks to `Ready to turn in` and glows once.
3. Track and untrack a quest from the quest log and watch the list follow.
4. Click a quest out of combat and in combat; note any blocked-action message.
   Shift-click one to stop tracking it.
5. Collapse the list, reload, and check it stays collapsed.
6. `/rik move`, drag the list, lock, reload.
7. Drag the list to just above another frame with more quests watched than
   fit: the list must stop short of that frame and end in `+N more`.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_QuestObjectiveTracker.lua: the watch loop, GetQuestLogLeaderBoard, completion and failure, the click handlers and the events](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ObjectiveTracker/Blizzard_QuestObjectiveTracker.lua)
- [Camelot/Blizzard_QuestObjectiveTrackerOverride.lua: the only camelot change is no timer bar](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_ObjectiveTracker/Camelot/Blizzard_QuestObjectiveTrackerOverride.lua)
