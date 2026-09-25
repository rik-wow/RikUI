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
file count and the TOC version (unchanged by default). Extract its single `RikUI` folder into
the Forever beta client's `Interface/AddOns` folder. Fully restart the client
after installing files or media. Existing separately installed quest/terrain
companion addons remain separate; the base archive does not contain extracted
client assets or world datasets.

To label a local release candidate without modifying the checkout:

```text
python tools/package_addon.py --version 0.2.0-rc.1 --output dist/RikUI-0.2.0-rc.1.zip
```

Versions follow Semantic Versioning (maximum 64 ASCII characters, no leading
`v`). The override changes only the packaged TOC and manifest, with hashes
computed after stamping. Verification requires matching valid versions in both.
A missing or duplicate TOC version is rejected even with an override; `--version`
cannot be combined with `--verify`.

The archive contains every TOC-listed Lua source, `Bindings.xml`, the MIT license,
runtime media, media license notices and `package-manifest.json`. Development
tools, tests, agent configuration, SVG sources and local state are excluded.
The manifest lists the exact byte size and SHA-256 of every payload file.

Builds validate the existing TOC and icon inventories, required assets and path
containment before creating output. A temporary archive is verified and then
replaces the output in one filesystem operation. Invalid or missing inputs leave
an existing archive intact. Verification checks required assets, every TOC source, permitted runtime payloads,
canonical install paths, case collisions, regular-file members, unique manifest keys and content hashes; it establishes integrity against the embedded manifest, not publisher
authenticity.

Sorted entries, fixed timestamps and permissions, and uncompressed ZIP members
make identical input bytes produce identical archive bytes independent of source
modification times or compression-library versions. The modest size tradeoff
avoids dependence on a particular compressor. The source files are not rewritten.

This is a local install artifact, not a published 1.0.0 release. The native
`packaging` and `release-v1` roadmap items still own hosted release automation,
CurseForge project identity and publication.

Research reviewed 2026-09-24:
[Semantic Versioning](https://semver.org/),
[Python ZIP API](https://docs.python.org/3/library/zipfile.html),
[Windows file naming rules](https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file) and
[BigWigs packager](https://github.com/BigWigsMods/packager).

