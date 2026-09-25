# Local RikUI packages

From the checkout, with Python 3.10 or newer:

```text
python tests/check_manifest.py
luajit tests/run_tests.lua
python tests/test_package_addon.py
python tools/package_addon.py --version 0.1.0-dev
python tools/package_addon.py --verify dist/RikUI.zip
```

The builder writes `dist/RikUI.zip` and prints its SHA-256, byte count, runtime
file count and the stamped TOC version. Source checkouts use the BigWigs
`@project-version@` token, so local builds require an explicit `--version`.
Extract its single `RikUI` folder into
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

## Hosted releases

The BigWigs workflow in `.github/workflows/release.yml` runs on annotated
`v*` tags or manual dispatch on an existing version tag. GitHub exposes manual
dispatch after the workflow is present on the default branch. A dispatch on a branch
fails with an instruction to select a tag. Use semantic versions after the
leading `v`, and include `alpha` or `beta` for prereleases: BigWigs does not
classify a plain `-test` or `-rc.1` suffix as a prerelease.

The job checks the runtime manifest and package tests, builds with the pinned
BigWigs 2.6.1 action without uploading, and compares the ZIP with the checkout
using `tools/verify_release.py`. Only then does BigWigs upload to GitHub Releases.
The single `RikUI/` root contains runtime sources, media, bindings, required
licenses and the generated release changelog. Development assets, tools, tests,
agent files and the separate RikProbe addon are excluded by `.pkgmeta`.
No externals are fetched: the addon uses its own serialization codec.
The empty `libs/` placeholder is not shipped.

GitHub uses its automatic `GITHUB_TOKEN` with `contents: write`.
RikUI has no CurseForge project yet (confirmed 2026-09-24), so
`X-Curse-Project-ID: 0` explicitly disables that destination. When the project
exists, replace `0` with its numeric ID and configure repository secret
`CF_API_KEY`; the workflow maps it to BigWigs' `CF_API_TOKEN`. Never commit
an API key. A missing secret skips CurseForge uploads.
The existing `release-v1` roadmap item owns project creation and 1.0.0 publication.

For a local dry run on a tagged checkout, using Bash, Git, curl and zip:

```bash
bash /path/to/packager/release.sh -d -e -l -u
python tools/verify_release.py --version v0.0.1-beta.1 .release/RikUI-v0.0.1-beta.1-forever.zip
```

Use the same pinned packager commit as the workflow:
`e50a250f8705041e40f2fa1ddcb280a686d65aa0`. The `-d` flag skips all uploads;
the other flags skip externals/localization and normalize text line endings.
The BigWigs archive has a generated changelog and tag-stamped TOC; the separate
local builder has a hash manifest and deterministic ZIP bytes. Use the
corresponding verifier for each format. Neither verifier claims publisher
authenticity.

Research reviewed 2026-09-24:
[Semantic Versioning](https://semver.org/),
[Python ZIP API](https://docs.python.org/3/library/zipfile.html),
[Windows file naming rules](https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file) and
[BigWigs packager](https://github.com/BigWigsMods/packager),
[PackageMeta reference](https://github.com/BigWigsMods/packager/wiki/Preparing-the-PackageMeta-File)
and [GitHub workflow guide](https://github.com/BigWigsMods/packager/wiki/GitHub-Actions-workflow).

