# Gear goals

## Compare equipment

Open your character window and click **Gear goals**, or type `/rik gear`. Choose an equipment slot, then a candidate. Search by item, quest or dungeon name; use the **Quests** and **Dungeons** filters.

![Equipment comparison](render:gear-browse)

The two cards show your equipped item and the candidate. Hover either card for its native tooltip. The table aligns **Current**, **New** and signed **Change** values. Matching bars compare the amount of each stat within that row; they do not rank different stats against one another. Gains and losses have icons as well as color. These are stat tradeoffs, not a universal upgrade score.

![Two-hand replacement](render:gear-twohand)

A two-handed candidate replaces both equipped hands: both cards appear and their stats are added before comparison. Rings and trinkets compare the particular slot you selected. Effects, sets, weapon damage and proficiency still need the tooltip.

## Choose a source

Click **Choose source**, or the **Source & steps** tab. Select a quest or supported dungeon reference. Quest requirements, progress and alternative prerequisite branches appear here. Choose a branch explicitly when one is needed.

![Source and prerequisites](render:gear-prerequisites)

**Pin goal** keeps the candidate for this character. **Pursue goal** also adds its unfinished quest steps to the quest planner’s effective priorities. Existing skips, group restrictions and travel preferences remain yours. **Open quest guide** opens the existing planner. Dungeon goals track their source; they do not invent a dungeon route.

Sources are maintained references. They do not guarantee the current server’s reward, drop rate or difficulty. A currently observed quest reward offer takes precedence when available.

## Keep goals for this character

**My goals** lists up to eight equipment slots. **Stop pursuit** removes the active goal’s extra planner priorities; **Remove** deletes the selected saved goal.

![Character goals](render:gear-goals)

A goal becomes **Acquired** when the item is observed in your bags or equipped inventory. It remains recorded if you later dispose of the item, until you remove it. Bank-only possession is not checked. RikUI never equips an item or selects a quest reward.

![Acquired item](render:gear-acquired)

Turn **Tracker** on for a compact active-goal card. Click it to return to the goal. Arrange it through `/rik move`, using RikUI’s existing movement controls.

![Compact goal tracker](render:gear-tracker)

## Themes and readability

Gear goals uses RikUI’s shared controls, font, borders, textures and theme accents. Your accessibility settings apply too.

![Ocean theme](render:gear-ocean) ![Ink theme](render:gear-ink) ![Enlarged text](render:gear-readable)

## Data availability

Public source browsing requires an installed **QuestieDB** addon with Forever data and contract version 3. [QuestieDB’s project](https://github.com/Questie/QuestieDB) documents its installation and supported contract. RikUI does not bundle that addon or its database.

A privately generated current-client catalog is also supported. The session index is built in bounded background slices and reused when the window reopens. **Refresh sources** explicitly rebuilds it. Only visible candidates request full item metadata.

![Unavailable item statistics](render:gear-unavailable)

Missing metadata, completion flags or requirements remain unknown. Use **Retry item data** for a selected item. Missing optional providers preserve saved goals; those goals can still be removed. New dungeon coverage, exact Forever payout coverage and special prerequisites can be incomplete.
