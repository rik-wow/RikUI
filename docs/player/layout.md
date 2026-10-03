# Move and resize frames

## Move a frame

Type `/rik move`. Every frame gets a tinted panel with its name and a lock button; drag a panel to move that frame. Type `/rik move` again, or click **Done** beside the minimap, when you have finished.

![Frame mover](render:layout-mover)

You can also hold Ctrl, Alt and Shift together to show a tag on every frame. Click a tag to unlock just that frame, or click **Unlock all** at the top of the screen.

![Frame tags](render:layout-tags)

Frames stay within the screen and make room for nearby elements. Hold Shift while dragging for free placement.

## Resize a frame

Frames that can change size, such as the chat window, have a grip in the bottom-right corner of their panel while they are unlocked. Drag it to resize; the frame stops at its neighbours and at the screen edge. `/rik chat unlock` unlocks the chat window on its own.

![Resize handle](render:layout-resize)

## Fine positioning

Open **Settings → General**, choose a frame under **Frame to position**, then use **Left**, **Right**, **Up** and **Down** to move it one screen unit at a time. It stops at other frames and at the screen edge, which makes it easy to line up neighbours.

![Position nudges](render:layout-nudges)

## Scale and presets

Use `/rik scale 1` for normal size. Values from `0.25` to `3` are allowed. **Frame scale** in Settings shows the same control as a percentage.

Choose a whole-screen layout under **Layout preset** in Settings, or use:

| Command | Layout |
| --- | --- |
| `/rik layout hud` | Combat HUD |
| `/rik layout centered` | Centered |
| `/rik layout classic` | Classic |
| `/rik layout healer` | Healer |

![Layout presets](render:layout-presets)

Classic keeps player and target in the corner on short screens. Healer places party or raid frames above the combat column, with your own unit frames above them.

![Classic and Healer on a short screen](preview:layout-short-presets)

![Healer party and raid placement](preview:layout-healer-groups)

`/rik hud` arranges only the combat HUD. Player and target frames sit on opposite sides of the character.

## Reset or undo

`/rik layout undo`, or **Undo layout change** in Settings, restores the layout before your last layout change. `/rik move reset` restores frame positions while keeping your scale.

![Undo layout change](render:layout-undo)

Arrange protected frames outside combat. Your positions are saved with the active profile.
