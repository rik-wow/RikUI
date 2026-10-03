# Combat timer and stopwatch

## Combat timer

Enable **Show combat timer** under **Settings → Combat timer**. The timer starts when you enter combat.

![Combat elapsed](render:timer-elapsed) ![Final duration](render:timer-final)

After combat ends, the final duration stays visible for five seconds by default. **Keep final duration** changes this to anything from 0 to 30 seconds.

A trailing **+** means the timer started after combat was already underway. It measures your time in combat, which can differ from a boss encounter's duration.

## Stopwatch

Enable **Show session stopwatch**, or use:

| Command | Action |
| --- | --- |
| `/rik stopwatch start` | Start or resume |
| `/rik stopwatch pause` | Pause |
| `/rik stopwatch reset` | Clear the elapsed time |
| `/rik stopwatch show` | Show the stopwatch |
| `/rik stopwatch hide` | Hide it |

![Session stopwatch](render:timer-stopwatch)

Left-click the stopwatch to start or pause it. Right-click to reset. Hiding it does not pause it.

The stopwatch clears on reload. Use `/rik move` to position either timer.
