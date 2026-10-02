# Curated Setup Pack maintenance

The website's collection is `web/setup-collection.json`: a version 1 registry of at most 32 entries. Each entry names a unique URL slug, a description (at most 400 characters), an authentic capture scenario and either a bundled library name or a validated portable `code`. Creator entries use the same importer and exact shared Lua engine as the addon. No submitted Lua is loaded.

Receive submissions, updates, removals and attribution corrections through [the public repository's issues](https://github.com/rik-wow/RikUI/issues). Confirm image permission, attribution, remix parent, stable identity, revision, selected character content and compatibility descriptions. A revision update retains the identity and increments its revision; a remix names its parent and uses its own identity. The editor's Share button creates an immediately usable result link without a server-side account library.

For a new creator entry, decode and validate its data, resolve desktop/exploration at its declared source viewport, and inspect conflicts. Add a scenario in `tools/site-renders/scenarios.json` with that resolved configuration as bounded `profile` data. Exercise actual controls using trusted existing fixtures, never a submitted script. The public build checks that a creator capture's startup profile exactly matches the validated pack's resolved profile. Collection descriptions, attribution and URL changes are metadata; they do not enter rendering fixtures or capture dependency hashes.

Resolve the current Forever branch and installed client before creating captures. Stage unchanged addon source into an isolated renderer scratch directory with the existing stage/isolation commands, render the affected scenario, inspect its image at original size and compare the reviewed baseline. Promote only the exact reviewed hash through `promote.py`; builds and tests never promote images.

Run the configured project gates, browser editor/gallery and keyboard checks, and production website build. Production Studio data must have `reviewOnly: false`. Normal deployment uses `npm run deploy` from `web`; verify the live page, copyable import code, editor entry, install link and published version. Public output contains reviewed captures and public addon Lua, never private corpus inputs, extracted client assets, observations or recovery history.

Four RikUI-authored packs launch the collection: Centered, Classic, HUD and Healer. The documented issue and registry process supports further creator packs without a public social network.
