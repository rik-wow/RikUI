# Portable settings and presets

Research reviewed 2026-09-24:
- [Players sharing UI layouts](https://www.reddit.com/r/classicwow/comments/1wjudz5/protip_you_can_import_your_retail_ui_to_forever/) want to reuse setups and transfer other settings. These are community reports, not verified client guarantees.
- [Recent addon requests](https://www.reddit.com/r/classicwow/comments/1wn4jbq/top_addons_for_forever/) mention customization and threat readability.
- [Selective UI modules](https://www.reddit.com/r/WowUI/comments/1wjhap1/addon_classic_ui_in_wow_forever/) remain a user preference.
- [Lua 5.1 types](https://www.lua.org/manual/5.1/manual.html#2.2) define supported scalar/table behavior.
- [LibDeflate](https://github.com/SafeteeWoW/LibDeflate) was considered. Reusing RikUI's existing bounded parser avoids a second codec and a decompression stage.

RikUI.Serialize and RikUI.Deserialize use the existing deterministic codec. Sharing is strict: strings, finite numbers, booleans and plain nested tables with string/number keys. Unsupported values, metatables and cycles fail explicitly. Sparse slots and exact macro text survive. Limits are 32 nested tables, 8192 nodes/entries and 21600 encoded bytes. No input is executed.

Legacy CVar/macro persistence retains its filtering and wire format. The upcoming portable envelope uses !RIK2! to distinguish it from the never-shipped !RIK1! compression proposal. Portable strings are specific to RikUI, not Blizzard Edit Mode or other addons.

Native/game-client acceptance is supplied by the user; automated fixtures exercise format and behavior without claiming client observations.
