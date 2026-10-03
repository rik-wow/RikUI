# Unit frames

## Player and target

The player frame sits left of the character and the target frame sits to the right. Each shows the unit's name, health and power, with the level on the power row. Player health bars use class colours; enemy targets are red.

![Player](render:units-player) ![Target](render:units-target)

Target of target is a smaller frame beside the target. Pet and focus have their own, smaller frames.

![Target of target](render:units-tot) ![Pet](render:units-pet) ![Focus](render:units-focus)

Left-click a frame to target its unit. Right-click for the unit menu.

## Health and power text

Open **Settings → Unit frames** to choose current and maximum values, current values only, or no text. Bars continue updating with the labels hidden, so the fill still shows how much health is left.

![Low health](render:units-low-health)

## Party and raid

Party frames show your group together. Raid frames use a compact grid so more players fit on screen. Out-of-range units fade.

![Party](render:units-party) ![Raid grid](render:units-raid)

To arrange them while solo, use `/rik party test` or `/rik raid test` outside combat. Run the command again to close the preview. Reloading also closes it.

## Move the frames

Use `/rik move` to position the player, target, target of target, pet, focus, party and raid groups separately. See [Move frames](layout.md) for scale, presets and reset controls.
