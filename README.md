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

Use `/rik move` to drag labelled frame overlays, then repeat it to lock.
`/rik move reset` restores default positions; `/rik scale 0.8` changes the
shared scale (`/rik scale 1` restores normal size). These commands require
leaving combat. See [moving frames](docs/layout.md).

See [bar behavior and native checks](docs/bars.md), [setup](docs/setup.md),
and [media licenses](media/LICENSES.md). Code and original textures are MIT;
the bundled Noto Sans font is licensed under SIL OFL 1.1.
