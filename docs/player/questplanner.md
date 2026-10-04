# Quest planner

## Start quest guidance

Type `/rik quests show` to open the quest browser. Choose a quest and inspect its objectives.

![Quest browser](render:planner-browser)

Use **Objective** to switch between objectives, then **Route to objective** to guide toward the one you want. **Next location** cycles through other known locations for that objective.

![Pin and skip controls](render:planner-pins)

The guide advances when your quest progress changes. Reaching a marker alone does not finish an objective.

## Guide controls

The guidance row shows your current objective and direction. Its controls let you pause or resume, open the map, pin a quest, skip a step and open more choices.

![Guidance row](render:planner-guidance) ![Current objective](render:planner-objective)

- **Pin** keeps a chosen quest as your priority.
- **Skip** lets you move past a step you do not want to follow.
- **Map** shows the current guidance on the world map.
- **Preferences** opens the quest-planner settings.

You can also use `/rik quests pin QUEST_ID`, `/rik quests route auto`, `/rik quests map` and `/rik quests retry`. **Route details** in the browser lists the current objective, available route information and any missing quest or map details.

![Objective details](render:planner-details)

## Map and direction arrow

The map shows unfinished objectives for the selected quest. Click a numbered pin to route to that objective.

Turn on the direction arrow with `/rik quests arrow on`. Where a route is available, the arrow follows it. A straight direction to a marker does not guarantee a walkable path.

![Direction arrow](render:planner-arrow)

Some objectives are inside buildings or on another floor. Use the floor controls when the automatic choice is wrong: `/rik quests floor 1`, `floor 2` or `floor auto`.

## Missing locations

Some Forever quests do not yet have locations or complete instructions in the database. Their objectives still appear, but the guide may have no waypoint or route to offer.

![Partial data state](render:planner-partial)

Locations can also differ by phase or floor. Use your quest text and the game map when guidance does not match what you see. The planner does not complete quests, move your character or interact with NPCs for you.

## Preferences

Open **Settings → Gameplay → Quest planner** to choose your journey style, session preferences, rewards and other goals. The planner's **Preferences** button opens the same page.

![Preferences](render:planner-preferences)
