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
secret). Left click targets, right click opens the unit menu, hovering shows
the unit tooltip. The Blizzard
frames for those units are hidden; disable the `unitframes` module and reload
to restore them. See [unit frames](docs/unitframes.md).

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

Use `/rik move` to drag labelled frame overlays, then repeat it to lock.
`/rik move reset` restores default positions; `/rik scale 0.8` changes the
shared scale (`/rik scale 1` restores normal size). These commands require
leaving combat. See [moving frames](docs/layout.md).

See [bar behavior and native checks](docs/bars.md), [unit frames](docs/unitframes.md),
[castbars](docs/castbars.md), [auras](docs/auras.md), [tooltips](docs/tooltip.md), [setup](docs/setup.md),
and [media licenses](media/LICENSES.md). Code and original textures are MIT;
the bundled Noto Sans font is licensed under SIL OFL 1.1.
