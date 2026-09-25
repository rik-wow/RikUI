# Quest timers

The final ten seconds use red time text and a faster 180ms pulse. Added time and pooled quest changes restore the appropriate warning level. Reduced motion uses a static red wash, and hiding stops all effects. API shape rechecked 2026-09-24 against [69913 QuestTimerInfo](https://raw.githubusercontent.com/Gethe/wow-ui-source/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua).

`src/modules/questtimers/questtimers.lua` shows the countdown of timed quests as a flat list.
Blizzard's `QuestTimerFrame` is a child of `ObjectiveTrackerFrame`, which the
[quest tracker](questtracker.md) parks, so without this module a timed quest
shows no countdown anywhere. Disable the `questtimers` module in `/rik config`
and reload to remove the list; the stock panel stays hidden with the objective
tracker either way.

## What you see

One 18px flat row per running timer, above the quest list: the quest's title
on the left and the time left on the right in gold, as `m:ss` or `h:mm:ss`. A
row fades in over 0.15s when its timer starts. In the last 30 seconds the row
pulses red. When a timer ends its row goes away. At most five rows are drawn.

Move it with `/rik move` under the key `questtimers`.

## How it works

`C_QuestLog.GetQuestTimers()` returns a list of `{ questID, questTimer }` with
the seconds left, the same call Blizzard's panel makes. It is read on
`QUEST_LOG_UPDATE` and `PLAYER_ENTERING_WORLD`, and once a second by an
`OnUpdate` on the holder that only runs while a timer is showing. The title
comes from `C_QuestLog.GetTitleForQuestID`; a quest without one shows the time
alone.

This is quest log state, not a unit value, so the seconds are formatted in Lua.
The read and the formatting still run under `pcall`: a read that raises hides
the list and prints one `Quest timers read: <reason>` line.

Rows are made as they are first needed and reused. They are plain frames, so
they show and hide in combat. The holder is built through the combat queue; a
combat login builds it when the fight ends and picks up a timer that is
already running.

## Diagnostics

`/rik debug` prints `Quest timers holder=<true|false> shown=<n>`.

## Verification

`tests/questtimers.test.lua` proves: the layout key and default; no rows and no
ticker at rest; a flat row with title and `m:ss`; the fade-in and the ticker
starting; no re-read inside a second; the re-read after a second without a
second fade; the red pulse under 30 seconds; a second row stacked under the
first with `h:mm:ss`; a missing title; the pulse stopping and the spare row
hiding; rows hidden and the ticker stopped at the end; nothing printed; a
failing read reported once; a timer starting in combat; the five-row cap; the
debug line; a combat login deferring the build and picking up a running timer;
a client without the API; the disabled module.

The stub cannot settle these: whether Forever has timed quests where you can
test, whether `GetQuestTimers` is populated on 69913, and whether the default
position clears the minimap buttons. Beta checklist:

1. Fully restart the client (new TOC entries). Accept a timed quest: a row
   with its title and a running countdown above the quest list.
2. Let it run under 30 seconds: red pulse. Let it expire or finish the quest:
   the row goes away.
3. `/rik debug` should print the `Quest timers` line.

## Source evidence

Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_QuestTimer.toc: loads for classic and camelot](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_QuestTimer/Blizzard_QuestTimer.toc)
- [Mainline/Blizzard_QuestTimer.xml: QuestTimerFrame's parent is ObjectiveTrackerFrame](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_QuestTimer/Mainline/Blizzard_QuestTimer.xml)
- [Blizzard_QuestTimer.lua: GetQuestTimers, questTimer and questID](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_QuestTimer/Blizzard_QuestTimer.lua)
