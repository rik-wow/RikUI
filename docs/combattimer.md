# Combat timer

Enable **Show combat timer** in /rik config > Combat timer. The movable pill shows elapsed player combat time and keeps the last duration for five seconds. **Keep final duration** changes that delay from 0 to 30 seconds. Move it with /rik move.

A trailing + means tracking began while you were already in combat. Reloading or crossing into a new world starts a new observation. Missing or secret clocks display --:-- instead of invented time. The timer measures time in the player's combat state, not encounter duration, damage or boss phases.

The feature is off by default. It registers ordinary combat lifecycle events and does no update work while disabled or after the final duration expires. It uses no combat-log or restricted unit-value data. Native acceptance is supplied by the user's standing policy; automated checks cover state transitions, partial timing, duplicates, unreadable clocks and disabled updates.

This adds a TOC file: fully exit and restart the client after installing the update.

Prior art reviewed 2026-09-24: [pfUI combat timer](https://github.com/shagu/pfUI/blob/master/modules/panel.lua). Events match RikUI's existing combat queue contract.

