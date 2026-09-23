# Personal resource display

The `personalresource` module gives Blizzard's existing health, power and alternate-power bars the RikUI statusbar texture, dark backing, one-pixel edge and font. Disable **Personal resource** under **System → Modules** in `/rik config` and reload to restore the stock appearance.

This is a skin for the client's display. It does not enable the display, load its addon, change CVars, or create a replacement when the frame is unavailable. Visibility and positioning remain controlled by the client.

## Ownership and lifecycle

The module changes regions on the existing StatusBars. It never reads health or power, writes bar values/ranges/colours, replaces scripts or events, or changes parent, position or size. Native text keeps its content. Heal/absorb and mana-cost predictions, feedback effects and class-specific artwork remain stock.

The unnamed decorative background is identified by its exact atlas; other regions are preserved. New backing and edge textures are retained in a weak table, with no bookkeeping fields added to Blizzard frames. The skin applies to an already shown frame and after its native OnShow script, reusing the same textures on later shows. Addon-load and world-entry events discover a frame that appears later.

Missing or forbidden frames/bars are skipped. A rejected skin is reported once and not retried for that bar; usable bars continue. A rejected hook is also reported once. `/rik debug` prints `Personal resource bars=<n> failed=<n>`.

## Verification and source limits

`tests/personalresource.test.lua` covers all three bars, exact background matching, native text and predictions, repeated shows, combat login, late loading, missing/forbidden regions, refused writes/hooks and disabled loading. Ownership traps reject value and geometry writes. Manifest and architecture checks cover production loading and prerequisites.

Native behavior is accepted under the user's standing policy; these are automated stub results, not an agent-observed client playtest.

The reviewed [69913 XML](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_PersonalResourceDisplay/Blizzard_PersonalResourceDisplay.xml) defines the three bars and their regions. The [client Lua](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_PersonalResourceDisplay/Blizzard_PersonalResourceDisplay.lua) owns setup, updates and layout. Its [TOC](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_PersonalResourceDisplay/Blizzard_PersonalResourceDisplay.toc) declares a mainline gate while including a [Camelot override](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_PersonalResourceDisplay/Camelot/Blizzard_PersonalResourceDisplay.lua) that disables class-resource templates. Those sources do not establish availability on every Forever build; unsupported or absent displays are left alone.
