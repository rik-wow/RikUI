# Local RikUI packages

From the checkout, with Python 3.10 or newer:

```text
python tests/check_manifest.py
luajit tests/run_tests.lua
python tests/test_package_addon.py
python tools/package_addon.py
python tools/package_addon.py --verify dist/RikUI.zip
```

The builder writes `dist/RikUI.zip` and prints its SHA-256, byte count, runtime
file count and the unchanged TOC version. Extract its single `RikUI` folder into
the Forever beta client's `Interface/AddOns` folder. Fully restart the client
after installing files or media. Existing separately installed quest/terrain
companion addons remain separate; the base archive does not contain extracted
client assets or world datasets.

The archive contains every TOC-listed Lua source, `Bindings.xml`, the MIT license,
runtime media, media license notices and `package-manifest.json`. Development
tools, tests, agent configuration, SVG sources and local state are excluded.
The manifest lists the exact byte size and SHA-256 of every payload file.

Builds validate the existing TOC and icon inventories, required assets and path
containment before creating output. A temporary archive is verified and then
replaces the output in one filesystem operation. Invalid or missing inputs leave
an existing archive intact. Verification checks member inventory and content
hashes; it establishes integrity against the embedded manifest, not publisher
authenticity.

Sorted entries, fixed timestamps and permissions, and uncompressed ZIP members
make identical input bytes produce identical archive bytes independent of source
modification times or compression-library versions. The modest size tradeoff
avoids dependence on a particular compressor. The source files are not rewritten.

This is a local install artifact, not a published 1.0.0 release. The native
`packaging` and `release-v1` roadmap items still own hosted release automation,
CurseForge project identity and publication.

Research reviewed 2026-09-24:
[Python ZIP API](https://docs.python.org/3/library/zipfile.html) and
[BigWigs packager](https://github.com/BigWigsMods/packager).

