# Portable settings and presets

Imported preset definitions now participate in the restart macro backup, including empty slot tables and exact macro text. The existing twelve-macro limit still applies: if all user settings and presets cannot fit, RikUI reports a backup failure and leaves the previous backup untouched. Keep portable exports for large libraries. No preset is applied by recovery.

UI profile exports include the low-space-only capacity setting, its threshold, and durability percentage visibility. Tests cover every defaulted portable preference so additions cannot silently disappear from backups. Invalid thresholds and flag types reject an import before creating a profile.

Research reviewed 2026-09-24:
- [Players sharing UI layouts](https://www.reddit.com/r/classicwow/comments/1wjudz5/protip_you_can_import_your_retail_ui_to_forever/) want to reuse setups and transfer other settings. These are community reports, not verified client guarantees.
- [Recent addon requests](https://www.reddit.com/r/classicwow/comments/1wn4jbq/top_addons_for_forever/) mention customization and threat readability.
- [Selective UI modules](https://www.reddit.com/r/WowUI/comments/1wjhap1/addon_classic_ui_in_wow_forever/) remain a user preference.
- [Lua 5.1 types](https://www.lua.org/manual/5.1/manual.html#2.2) define supported scalar/table behavior.
- [LibDeflate](https://github.com/SafeteeWoW/LibDeflate) was considered. Reusing RikUI's existing bounded parser avoids a second codec and a decompression stage.

RikUI.Serialize and RikUI.Deserialize use the existing deterministic codec. Sharing is strict: strings, finite numbers, booleans and plain nested tables with string/number keys. Unsupported values, metatables and cycles fail explicitly. Sparse slots and exact macro text survive. Limits are 32 nested tables, 8192 nodes/entries and 21600 encoded bytes. No input is executed.

Legacy CVar/macro persistence retains its filtering and wire format. The portable envelope uses !RIK2! to distinguish it from the never-shipped !RIK1! compression proposal. Portable strings are specific to RikUI, not Blizzard Edit Mode or other addons.

Use /rik export [role] to copy the last-applied preset (or the bundled class preset before setup). Export describes the preset definition, not live bar edits. Use /rik import, enter a unique name and paste, then click Save import. Setup and support in options offers the same controls. Open /rik setup and click the preset selector on Your role to cycle through valid presets for your class. Preview and Apply use that draft choice; skipping leaves your existing applied setup alone.

Imports do not overwrite existing names, execute text, or apply bars automatically. Presets may contain arbitrary macro bodies: inspect the source before choosing Apply. Up to six roles fit the wizard. The format supports existing verified class catalogs only; unknown spell names fail with a path. It is not an exchange format for Blizzard Edit Mode, retail profiles or other addons.

Use /rik profileexport and /rik profileimport (or Profiles → Export/Import) for UI preferences. Import saves a separately named profile and leaves your current selection unchanged. Select it in Profiles and reload to apply all module settings. Duplicate names, malformed settings and combat imports are refused without changes.

Profile sharing includes module toggles, frame anchors, global scale, bar fade/stock/gryphon/ghost/border options, chat appearance and size, tooltip, bags, quest tracker, minimap, swing timer, druid mana, world-map fog, nameplate threat text and XP-bar preferences. It excludes chat lines, account/character records, live bars, bindings, CVars, layout undo, quest journals and unrecognized fields. Future settings require explicit schema support. Imports reject unknown fields; exports omit fields outside this list. Position coordinates remain relative to their anchors; a different screen size can require rearranging.

The [Forever saved-variable workaround report](https://www.reddit.com/r/wowforever/comments/1wlh5qf/foreversvfix_workaround_for_addon_settings_not/) was reviewed 2026-09-24 as community motivation for portable backups. This does not establish that bug on this client, and importing a string does not repair the client's persistence subsystem.

Native/game-client acceptance is supplied by the user; automated fixtures exercise format and behavior without claiming client observations.
