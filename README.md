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
outlined labels and shared bundled media. Gryphon end caps are off by default:
`/rik gryphons on` enables them and `/rik gryphons off` hides them.
The preference is saved per profile; changes during combat apply afterward.
The Blizzard action, stance and pet bars are hidden once their RikUI
replacements exist; `/rik stockbars show|hide|status` restores, hides or
reports them. Edit Mode cannot move hidden frames and prints a warning.

The player, target, target-of-target and pet frames sit centre-bottom above
the bars: flat class- or reaction-coloured health and power bars with
`current / max` text and a threat border, no percent (the beta keeps health
secret). Left click targets, right click opens the unit menu. The Blizzard
frames for those units are hidden; disable the `unitframes` module and reload
to restore them. See [unit frames](docs/unitframes.md).

Use `/rik move` to drag labelled frame overlays, then repeat it to lock.
`/rik move reset` restores default positions; `/rik scale 0.8` changes the
shared scale (`/rik scale 1` restores normal size). These commands require
leaving combat. See [moving frames](docs/layout.md).

See [bar behavior and native checks](docs/bars.md), [unit frames](docs/unitframes.md), [setup](docs/setup.md),
and [media licenses](media/LICENSES.md). Code and original textures are MIT;
the bundled Noto Sans font is licensed under SIL OFL 1.1.
