# RikUI (draft)

RikUI is a Classic-style interface and character setup addon for the WoW:
Forever beta. The current target is interface 16001; see [SDD.md](SDD.md)
for measured client limitations and implementation scope.

Install this directory as `Interface/AddOns/RikUI` inside the beta client.
**Fully exit and restart the client after adding or updating media files.**
A UI reload alone may not discover new font or texture assets.

Use `/rik help` for available commands. `/rik config` opens the options panel
(also under Options > AddOns > RikUI) with module toggles, scale, bar
appearance and profiles; see [options](docs/options.md).
The bars use flat square icons,
outlined labels and shared bundled media; hovering a button shows its
tooltip. Gryphon end caps are off by default:
`/rik gryphons on` enables them and `/rik gryphons off` hides them.
The preference is saved per profile; changes during combat apply afterward.
The Blizzard action, stance and pet bars are hidden once their RikUI
replacements exist; `/rik stockbars show|hide|status` restores, hides or
reports them. Edit Mode cannot move hidden frames and prints a warning.

The player, target, target-of-target and pet frames sit centre-bottom above
the bars: flat class- or reaction-coloured health and power bars with
`current / max` text and a threat border, no percent (the beta keeps health
secret). Left click targets, right click opens the unit menu, hovering shows
the unit tooltip. The Blizzard
frames for those units are hidden; disable the `unitframes` module and reload
to restore them. See [unit frames](docs/unitframes.md).

In a party, up to four member frames stack on the left edge at middle height
with the same bars, a leader icon and a T/H/D role letter. Members out of
range fade. The frames hide when you're solo or in a raid, and the Blizzard
party frame is hidden with the rest. `/rik party test` shows all four frames
solo, pointed at you, so you can check and move them without a group.

In a raid the party frames give way to a grid of up to forty small frames in
the same spot: name, class-coloured health, a thin power bar, range fade. They
fill in raid order, five to a column, not by subgroup. The Blizzard raid
frames are hidden; the raid manager tab on the left edge stays. I haven't been
able to test this in a real raid on the beta yet.

Castbars sit under the player and target frames with the spell icon, name
and remaining time; casts fill gold, channels drain blue, interrupted casts
flash red, and the target bar shows a shield on the icon while a cast cannot
be interrupted. The fill comes from the client's duration object, so it works
even when the target's cast times are secret. The Blizzard casting bar is
hidden; disable the `castbars` module to restore it. See
[castbars](docs/castbars.md).

Buffs, weapon enchants and debuffs sit at the top right as flat icons with
stack counts, dispel-coloured debuff borders and the client's own countdown
numbers. Right-click a buff to cancel it. The rows are Blizzard aura
containers in RikUI's skin, so they keep updating in combat where addon code
cannot read auras on this build. The Blizzard buff and debuff frames are
hidden; disable the `auras` module to restore them. See [auras](docs/auras.md).

The target frame carries the target's debuffs above it, your own at full size
and other casters' smaller and dimmer, with the target's buffs on the line
above. The pet frame gets a debuff row the same way. Disable the `unitauras`
module to drop them.

Tooltips sit bottom right in a flat box with the RikUI font. Unit names are
class or reaction coloured with the guild line in light blue, the health bar
under them is Blizzard's own secret-safe bar in RikUI's skin, item tooltips
end with the item level and spell tooltips with the spell ID. The Tooltips
options page can hide unit tooltips in combat. Disable the `tooltip` module
to get the stock tooltips back. See [tooltips](docs/tooltip.md).

The minimap is a bordered square at the top right with the zone name above it
and the local clock and your coordinates below. Scroll to zoom, right-click
for the tracking menu, left-click to ping. The round cluster art, zoom
buttons and day/night ring are hidden; the mail indicator sits inside the
square. Disable the `minimap` module to get the round cluster back. See
[minimap](docs/minimap.md).

The micro menu and bag bar are one flat row at the bottom right: a lettered
button per stock micro button, then the backpack, bag slots with free-slot
counts and the keyring. Clicks go through Blizzard's own buttons, so panels
open the same way in and out of combat. See [micro menu](docs/micromenu.md).

Experience is a thin purple row under the main bar with a blue rested segment;
a watched faction adds a second row in its standing colour. Fills ease, a gain
flashes the row and hovering shows the numbers. See [XP bar](docs/xpbar.md).

Breath, fatigue and feign death are flat bars at the top of the screen with
the label and the time left; the last ten seconds pulse red. See
[mirror timers](docs/mirrortimers.md).

Forever's swing timer becomes flat bars between the cast bars: one per weapon
that is swinging, with the time to the next swing, a flash on every swing and
dimming with red time when the target is out of range. See
[swing timer](docs/swingtimer.md).

Worn gear shows as a small pill at the top centre (`2 worn`, or `1 broken, 2
worn` in red with a pulse) instead of the armoured figure; hover it for the
slots. See [durability](docs/durability.md).

Rogues and druids get combo points as five flat pips between the player and
target frames, gold with a red fifth, easing and flashing as they build. See
[combo points](docs/combopoints.md).

Shamans get their active totems as a row of flat icons under the player cast
bar, each with a sweep and a countdown. The row is display only. See
[totem row](docs/totems.md).

Watched quests are a compact list under the minimap: level-tagged titles in
their difficulty colour, one line per objective, green when ready to turn in.
Progress flashes its line, click opens the quest log, shift-click stops
tracking and the header collapses the list. See [quest tracker](docs/questtracker.md).

Timed quests show their countdown as a flat row above the quest list, pulsing
red in the last 30 seconds. See [quest timers](docs/questtimers.md). The queue
status tooltip and the framerate label get the flat look too; see
[small HUD frames](docs/hudframes.md).

Blizzard's windows (character, spellbook and talents, map and quest log,
merchant, bank, mail, trade, quest givers, and since 2026-09-20 the trainer,
auction house, friends, guild, macros, professions, inspect, dressing room,
stable, help, addon list and options windows) keep their content and get the flat
dark skin: no parchment or portrait ring, a gold title, a flat close button and
flat tabs with a blue accent on the selected one. Disable the `panels` module
and reload for the stock look. See [panel skin](docs/panels.md). Inside the
map, the breadcrumb bar is flat too; see [world map bar](docs/worldmap.md).

Confirmation popups, the Escape menu and the release-spirit button get the
same flat look: no stone border, flat buttons with gold text, a fade-in each
time they show. See [popups](docs/popups.md).

Zone names, the red error line and raid warnings use the RikUI font at
Blizzard's sizes. See [screen text](docs/screentext.md).

Floating combat text and the damage numbers over enemies use the RikUI font
too. Turning that on or off needs a trip to the character list, not only a
reload. See [combat text](docs/combattext.md).

Right-click menus, dropdown lists and their submenus open on the same flat
panel with a fade-in; the rows stay Blizzard's. See [menus](docs/menus.md).

Speech bubbles in the open world are flat panels in the RikUI font that keep
their say, yell and party colours. Bubbles in instances are off limits to
addons and stay stock. See [chat bubbles](docs/chatbubbles.md).

Inside Blizzard's windows the buttons, check boxes, edit boxes, sliders,
scrollbars and dropdowns are flat too, with a highlight that fades in under
the cursor. See [window controls](docs/controls.md).

The ready check, role poll, stack split box, queue-ready dialogs, autocomplete
list and colour picker are flat panels that fade in. See
[small dialogs](docs/dialogs.md).

The stunned, feared and silenced banner is a flat panel with two pulsing red
lines, a cropped icon and RikUI text. See
[loss of control](docs/lossofcontrol.md).

The extra action button, zone ability buttons and spell flyout get the bar
look: a cropped icon in a thin edge that follows your bar border colour. See
[extra buttons](docs/extrabuttons.md).

Alert toasts (loot won, money, new recipes) are flat panels with a cropped
icon and Blizzard's text colours, on Blizzard's own timing and stacking. See
[alert toasts](docs/alerts.md). The Battle.net, play-time and voice chat toasts
get the same look; see [social toasts](docs/toasts.md). The level-up text, the
boss kill banner and the tracker's top banner use the RikUI typeface without
the banner art; see [banners](docs/banners.md). Blizzard's built-in damage meter
gets a flat header and flat bars while its own settings keep working; see
[damage meter](docs/damagemeter.md).

Battleground score bars, capture bars and event progress bars get a flat frame
and the RikUI typeface while keeping Blizzard's faction-coloured fills. See
[UI widgets](docs/widgets.md).

The loot window is a compact flat list at the cursor: icon, quality-coloured
name and stack size, click to loot, Escape to close. Auto-loot is untouched.
The group roll frames get the same flat skin with need, greed and pass left
alone. See [loot](docs/loot.md).

Nameplates keep Blizzard's plates under a new layout: a chunky flat bar with
the health percent inside and the name in its own plaque on top, a level box, an elite or rare marker and
your own debuffs above. Your target grows while the others dim, and gets side
arrows and a pulsing line; a red line marks mobs that are on you. Health eases
instead of jumping and flashes on a hit. See [nameplates](docs/nameplates.md).

Chat keeps Blizzard's windows with the RikUI font, a flat edit box docked
under the window, `HH:MM` timestamps and flat tabs that stay visible, with a
gold dot on a tab that got messages while you were on another and a pulse for
whispers. A row of small channel buttons under the window (`S Y P R G O W 1 2`)
opens or switches the edit box with one click, and the edit box border takes
the colour of the channel you are typing in. Alt-click a name to invite,
Ctrl-click for a who. The button column, scroll bar and social buttons are
hidden; the mouse wheel scrolls. The small button in a window's top-right
corner opens its lines as selectable text, and web addresses in chat are
links that open a box to copy from. Names are class-coloured, channel tags
are short (`[G]`, `[P]`, `[2]`), your own name turns gold with a soft sound
when someone says it, and repeated public spam shows once per ten seconds.
Scroll up and a small button counts what you are missing and takes you back;
Ctrl-wheel jumps to either end and Shift-wheel pages. Windows keep 1000 lines
and the last 200 come back dimmed after a reload. Up and Down recall what you
sent, and whispers and channels stay selected after sending. Each of those,
font size and timestamps are on the Chat options page. While unlocked, the
gold grip in the corner resizes the window. Click the padlock in the main chat window's corner to
unlock it, drag the padlock to move the window, click again to lock; no Edit
Mode needed and the position is remembered (`/rik chat lock|unlock|reset`
does the same). Disable the `chat` module to get the stock chat back. See
[chat](docs/chat.md).

B opens one bag frame with every slot of all five bags, ten to a row, with
stack counts, quality-coloured borders, a search box that dims what does not
match, a Sort button and your money. Clicks, drags, right-click use and
vendor selling run on Blizzard's own item buttons. The bank stays Blizzard's.
Drag it by its title to move it; the place is remembered.
`bags-items.lua` and `chat-move.lua` are new files, so fully restart the
client after updating.
Disable the `bags` module to get the stock bags back. See [bags](docs/bags.md).

Hold the frame-lock key (Key Bindings, RikUI section; Ctrl+Alt+Shift while unbound) to show a lock on every frame, click a lock to free that frame, then drag it: frames snap to each other and to the screen, and can never overlap. `/rik move` unlocks or locks everything at once.
`/rik move reset` restores default positions; `/rik scale 0.8` changes the
shared scale (`/rik scale 1` restores normal size). These commands require
leaving combat. See [moving frames](docs/layout.md).

See [bar behavior and native checks](docs/bars.md), [unit frames](docs/unitframes.md),
[castbars](docs/castbars.md), [auras](docs/auras.md), [tooltips](docs/tooltip.md), [minimap](docs/minimap.md), [chat](docs/chat.md), [bags](docs/bags.md), [micro menu](docs/micromenu.md), [XP bar](docs/xpbar.md), [mirror timers](docs/mirrortimers.md), [swing timer](docs/swingtimer.md), [combo points](docs/combopoints.md), [durability](docs/durability.md), [quest tracker](docs/questtracker.md), [panel skin](docs/panels.md), [popups](docs/popups.md), [screen text](docs/screentext.md), [menus](docs/menus.md), [chat bubbles](docs/chatbubbles.md), [totem row](docs/totems.md), [alert toasts](docs/alerts.md), [UI widgets](docs/widgets.md), [combat text](docs/combattext.md), [quest timers](docs/questtimers.md), [small HUD frames](docs/hudframes.md), [world map bar](docs/worldmap.md), [window controls](docs/controls.md), [small dialogs](docs/dialogs.md), [loss of control](docs/lossofcontrol.md), [extra buttons](docs/extrabuttons.md), [social toasts](docs/toasts.md), [banners](docs/banners.md), [damage meter](docs/damagemeter.md), [loot](docs/loot.md), [nameplates](docs/nameplates.md),
[setup](docs/setup.md),
and [media licenses](media/LICENSES.md). Code and original textures are MIT;
the bundled Noto Sans font is licensed under SIL OFL 1.1.
