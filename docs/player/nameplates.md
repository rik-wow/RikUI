# Nameplates

## Enemy nameplates

Enemy plates show a name, health percentage and level. Your debuffs appear above the name, and the cast bar sits below the health bar.

![Enemy plate](render:plates-enemy) ![Debuff row](render:plates-debuffs) ![Nameplate cast](render:plates-cast)

The target and focus have arrows beside their plates. The target is larger by default, while other plates dim. A red line marks a unit attacking you.

![Target and focus](render:plates-target-focus)

Special units carry a small marker beside the plate: a gold star for an elite, a red skull for a world boss, a silver diamond for a rare and a silver star for a rare elite.

![Elite and rare markers](render:plates-markers)

## Threat

**Show threat text** adds a percentage beside the level. When a percentage is unavailable, **AGGRO** can appear while the unit is attacking you.

![Threat indication](render:plates-threat)

## Readable names

**Adaptive name width** gives long names and surnames more room above a compact health bar. It is on by default. Turn it off for the original fixed row.

![Adaptive and fixed name labels](preview:plates-adaptive-names)

Set **Minimum name width** and **Maximum name width** under **Settings → Nameplates**. Defaults are 160 and 280 UI units; both sliders range from 120 to 400. Labels stay at least as wide as the health bar and level badge. If the maximum is below the minimum, the minimum wins. Names beyond the limit still truncate.

![Maximum label width](preview:plates-name-width-limit)

A reused plate shrinks for its new name. If the client hides the text measurement, the label keeps the fixed row. Your preferences are included in profile sharing.

![A reused plate with a short name](render:plates-pooled-short-name) ![Nameplate readability settings](render:plates-name-options)

## Size and visibility

Open **Settings → Nameplates** to adjust the health row and name row from 12 to 24 pixels. You can also change target enlargement and the opacity of other plates.

The game's nameplate settings control which friendly and enemy plates are shown. Friendly name-only plates keep their usual placement.

![Friendly name](render:plates-friendly)
