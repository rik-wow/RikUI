# Combat text

Combat text settings now expose native categories for outgoing damage/healing, resource gains, aura messages, combat entry/exit, avoided attacks, low health/mana warnings and reputation. Each is available only if the current client returns a supported boolean CVar value. No toggle changes at startup. Explicit changes wait until combat ends, coalesce, and verify readback; they are client-wide preferences, not profile exports.

Research reviewed 2026-09-24: [players request combat-text customization](https://www.reddit.com/r/WowUI/comments/1wkfntp/wow_forever_working_addons_addon/). Primary current sources: [Blizzard scrolling category definitions](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_CombatText/Shared/CombatTextConstants.lua) and [client CVar inventory](https://github.com/Ketho/BlizzardInterfaceResources/blob/live/Resources/CVars.lua). The [Forever combat-text implementation](https://github.com/merthanmerter/DogsScrollingCombatTextForever) also documents the native outgoing-damage CVar. The pinned Forever page could not be fetched in this review; current source plus runtime detection determines availability, not an assumption of identical build coverage. RikUI leaves attribution, amounts, fonts' animation sizes and spell icons with the existing renderer. User native acceptance applies.

`src/modules/combattext/combattext.lua` puts floating combat text in the RikUI font: the scrolling
text for your own damage taken, heals and gains, and the damage numbers over
enemies. The Combat text options page also exposes the client's scrolling
text visibility and Up/Down/Arc direction. These remain native client settings
shared across RikUI profiles; opening or enabling the module never changes them.
Explicit changes wait until combat ends and repeated requests coalesce.
Direction is available only while scrolling text is enabled, the direction
CVar exists, and classic-style world text is off. Missing or rejected native
controls stay unavailable rather than claiming support. Blizzard still owns
message content, rendering, crit sizing and any spell icons. Disable the `combattext` module in
`/rik config`, then log out to the character list and back in for the stock
font.

## Two systems, two writes

- Scrolling text is Blizzard Lua (`Blizzard_CombatText`, load on demand). Every
  string gets `SetFontObject(CombatTextFont)` and is then scaled with
  `SetTextHeight`, so the module writes the RikUI font with an outline to the
  `CombatTextFont` object at the size the object reports (25 when it reports
  none). The object comes from the shared font files and exists before the
  addon loads, so this happens once at login.
- Damage numbers over units are drawn by the engine, not by Lua. The engine
  takes the font file from the `DAMAGE_TEXT_FONT` global during login. The
  module sets it to the RikUI font file.

## When the global is set

The obvious place is file load, the earliest moment an addon runs. The module
flag lives in the saved variables, though, and those arrive with
`ADDON_LOADED`, after the files have run. So the write happens in an
`ADDON_LOADED` callback for RikUI itself. `src/core/core.lua` registers its own handler
first and has read the flag by then, which lets a disabled module leave the
global alone.

The engine reads the global once per login. Enabling or disabling the module
needs a trip to the character list; `/reload` is not enough for the damage
numbers.

## Diagnostics

`/rik debug` prints `Combat text font=<true|false> damage=<true|false>`. A
refused font prints one `Combat text font: <reason>` line.

## Verification

`tests/combattext.test.lua` proves: the font object restyled at Blizzard's
size with an outline; the global pointing at the RikUI font; nothing printed;
the debug line; a client without the font object; the fallback size; a refused
font reported once; the disabled module leaving both stock.

The stub cannot settle these: whether `ADDON_LOADED` is early enough for the
engine on 69913, whether the engine accepts a font inside an addon folder, and
how the outline looks on crits scaled with `SetTextHeight`. Native behavior is accepted by the user; the following is optional reference:

1. Fully exit and restart the client (new TOC entry).
2. Hit a mob: the numbers over it should be in the RikUI font. If they are
   stock, the global was set too late; report it.
3. Enable floating combat text for yourself in the options and take damage:
   the scrolling numbers should be in the RikUI font, crits growing as before.
4. `/rik debug` should print `Combat text font=true damage=true`.

## Source evidence

The native controls follow the pinned [CombatOverrides.lua](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_SettingsDefinitions_Frame/Mainline/CombatOverrides.lua):
`enableFloatingCombatText`, `floatingCombatTextFloatMode_v2` values 1/2/3, and
the `classicStyleWorldText == 0` condition. Actual CVar availability is checked
at runtime. The category extension above adds runtime-gated outgoing damage/healing controls; arbitrary numeric sizes are not inferred.

Research on 2026-09-24: [Forever players requesting combat-text customization](https://www.reddit.com/r/WowUI/comments/1wkfntp/wow_forever_working_addons_addon/).
This request is community feedback; the source and runtime checks determine supported controls.


Reviewed against the Forever [1.60.1 (69913) commit](https://github.com/Gethe/wow-ui-source/commit/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e):

- [Blizzard_CombatText.toc: load on demand](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_CombatText/Blizzard_CombatText.toc)
- [Shared/CombatText.lua: SetFontObject(CombatTextFont) and the SetTextHeight scaling](https://github.com/Gethe/wow-ui-source/blob/70ef1b2fd78061a73f886c4a1e79dc5b5cff6d5e/Interface/AddOns/Blizzard_CombatText/Shared/CombatText.lua)

`DAMAGE_TEXT_FONT` does not appear in the checked-out Blizzard Lua; its role
is long-standing addon knowledge, not something read in this source.
