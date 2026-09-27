# Contributing

For community bar presets, follow the [community preset guide](presets/community/README.md) and inactive template. Submit a pull request with the preset and TOC registration, or paste a RikUI export string into a project CurseForge comment for review. Include attribution, intended use and dated exact-build evidence for class data.

Run `python tests/check_project.py` and `luajit tests/run_tests.lua` before submitting code. Keep changes focused and preserve explicit unknown client coverage.

For UI changes, add or extend a [Lua render scenario](tools/site-renders/README.md), capture the unchanged addon with the current Forever client inputs, and review the resulting images and pixel differences. Promote only the exact images you reviewed. Website builds and release checks reject missing or stale render evidence; they never update baselines. Keep browser checks for website layout and interaction alongside these renders.
