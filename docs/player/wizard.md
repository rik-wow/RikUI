# Setup wizard

## First setup

Type `/rik setup` to open the wizard. It has six pages. Work through them in order, then check the summary before clicking **Apply**. You can go back to change a choice at any time. **Skip setup** closes the wizard without applying anything; `/rik setup` brings it back. Run setup outside combat.

### 1. Welcome

The first page names your class and lists what setup will change: action bars, keybinds, macros, game settings and screen layout. Nothing is applied until the last page, and `/rik undo` reverts all of it afterwards.

![Welcome](render:wizard-1)

### 2. Your role

Pick what you play. The role decides which abilities go on the bars. The preview below the choices shows each bar page; **Previous bar** and **Next bar** page through them, and dim slots are abilities you have not learned yet. Hover an ability for its name, key and learning status. You can switch roles later with `/rik role`.

![Your role](render:wizard-2)

### 3. Keybinds

Every ability sits on a key you can reach without moving your hand: 1–5 and the keys around WASD on the main bar, the same keys with Shift for cooldowns and with Ctrl for utility. Untick **Mouse 4/5** if your mouse has no side buttons; those two abilities then use Shift-G and Ctrl-G. **Also rebind A/D to strafe** is optional.

![Keybinds](render:wizard-3)

### 4. Screen layout

Choose **Centered**, **Classic**, **HUD** or **Healer**. Each picture shows where the action bars, unit frames, cast bars, auras, minimap, chat and tracker will sit. Tick **Keep my current positions** to leave your frames where they are. You can still move single frames later with [Move frames](layout.md).

![Screen layout](render:wizard-4)

### 5. Modules and settings

The left columns list the interface pieces RikUI replaces. Untick any you would rather keep from the game; a module change needs a reload. The right column lists the game settings the preset applies, such as camera zoom, nameplate options and auto loot. Untick a setting to leave it as it is.

![Modules and settings](render:wizard-5)

### 6. Review and apply

The summary lists what **Apply** will change: macros, action bars, keybinds, game settings and layout. Untick a step to leave that part alone, click **Back** to change a choice, or click **Apply** to finish.

![Review and apply](render:wizard-6)

## Changing your mind

Use `/rik undo` to undo the last setup. To move a few frames without running setup again, use [Move frames](layout.md).

Turn off the **Wizard** module in Settings if you do not want it to open automatically. You can still open setup yourself.
