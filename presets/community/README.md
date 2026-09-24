# Community presets

Community presets are attributed alternatives to the built-in class presets. Imported and bundled presets use the same structural and spell-catalogue checks. The setup source button cycles through valid sources for your class and shows “Community: name — author”. Selection is a draft until Apply.

Copy `template.lua.example` to a uniquely named `.lua` file here, replace every placeholder and fill the bars using documented catalogue names. Add its path to RikUI.toc immediately after src/setup/preset-library.lua. WoW loads only files explicitly listed in the TOC; there is no filesystem scan.

Call `RikUI.PresetLibrary.Register("Unique preset name", preset)`. Direct assignments to `RikUI.CommunityPresets[name]` are supported, but Register reports errors earlier and copies the data. Bundled sources require class, author, version, roles, roleOrder, bars and macros; roleOverrides is optional. See [sharing](../../docs/sharing.md) for bounds. Authors are plain text up to 80 bytes. Names are unique across bundles and imports; an old import colliding with a newly bundled name is unavailable until renamed or removed, never silently replaced.

Run `/rik preset validate` for bundled classes, community files and saved imports. Also run `python tests/check_manifest.py` and `luajit tests/run_tests.lua`. Validation checks known catalogue references, not unverified client spell coverage or build-specific ranks.

Submit a pull request with the Lua file, TOC entry, author, intended role, exact client build and dated sources for any class facts. Alternatively paste a `/rik export` string into a RikUI CurseForge comment with the same attribution and context, for maintainer review; posting does not automatically bundle it. No URL is claimed for an unpublished project.

Research reviewed 2026-09-24: [players sharing Forever layouts](https://www.reddit.com/r/classicwow/comments/1wjudz5/protip_you_can_import_your_retail_ui_to_forever/) requested easier transfer of settings. This is community demand, not evidence of RikUI/client compatibility. The inactive template is scaffolding, not a recommended build.
