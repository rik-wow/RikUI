# RikUI Windows setup

The native Win32 application uses standard Windows controls and Fluent visual conventions. Players choose their current Forever client and **Prepare and install**. Licensed build tools are embedded; no Git, Python, Node, MariaDB or Rust installation is needed.

Public setup contains the RikUI interface and licensed preparation dependencies. It obtains QuestieDB source, holiday inputs and current schema inputs separately from their publishers, then generates the supported corpus and navigation from those sources and the player's current client. Imported provider data and extracted client geometry never enter public packages. See [player installation instructions](../docs/player/installation.md) and the [interface contract](../docs/installer-guidance-flow.md).

## Build public setup

Run from the repository root with the declared developer commands. The existing Windows release workflow performs these steps automatically:

```powershell
npm ci --prefix tools/terrain --ignore-scripts
python -B tools/acquire_runtime_dependencies.py --output dist/dependencies
python -B tools/build_local_runtime.py --reader dist/dependencies/reader --extractor dist/dependencies/extractor/TACTTool.exe --output dist/preparation
python -B tools/build_installer_bundle.py --version 1.0.0-beta.17 --output dist/base-bundle.zip
python -B tools/build_public_installer.py --base dist/base-bundle.zip --runtime dist/preparation/runtime --output dist/public
```

The version above illustrates the reviewed release; subsequent tags supply their own semantic version. Forever metadata is always resolved live. Dependency revisions describe the licensed build libraries, not a client target. Public manifest generation executes the built program's **--verify-package** entry point and checks its actual embedded hashes against the public base and runtime inventory. Publish only the resulting program, manifest, checksums and notices.

## Current inputs and updates

Setup resolves Gethe's current `forever` head and `version.txt`, checks executable PE version and active `.build.info` product/configuration, and discovers the matching executable and directory without requiring a beta path. Provider, holiday, schema, road-list and compiler changes invalidate affected outputs. Current bytes and compatibility must verify before a no-op.

At startup/update it checks the existing public GitHub release channel for newer setup support. Installation registers the current-user daily **RikUI Current Forever Updates** task. The owned program copy is hash verified. Failures and successful daily checks are recorded in local application data. Paused preparation stays paused until the player resumes. A new unsupported schema or client prevents dependent generation or installation while preserving existing data. This does not claim future builds have been tested.

## Resource use and recovery

First preparation requires 16 GiB free on its preparation drive. A single current-acquisition extractor workspace avoids repeated metadata caches; geometry and polygon intermediates are losslessly compressed with bounded decoding and stored/decoded provenance checks. Players can choose another folder. Generation automatically chooses one to eight workers from available CPU and physical-memory capacity, with per-phase and ongoing disk guards. Progress shows measured bytes, files or jobs and elapsed time; no fabricated global percentage is used.

Verified completed generation resumes; corrupt/interrupted products are retained before replacement. Cache reuse binds client/source/tool hashes, acquisition bytes, placement index, terrain receipts, road textures, travel and local bundle inputs. Local inputs and old generations are not automatically pruned.

Installation stages and verifies bytes before replacing owned addon roots. A recoverable transaction retains backups under `Interface/RikUI-backups`, verifies installed bytes and rolls back failed swaps. Repeat installation of identical verified bytes adds no backup. Settings, unrelated addons and unowned private files are preserved. Linked game/addon paths are rejected. **Restore backup** retains replaced versions, including roots introduced by an update.

## Verification

```text
cargo fmt --manifest-path installer/Cargo.toml --check
cargo check --locked --manifest-path installer/Cargo.toml --all-targets
cargo test --locked --manifest-path installer/Cargo.toml
cargo clippy --locked --manifest-path installer/Cargo.toml --all-targets -- -D warnings
python -B tests/test_local_assembly.py
python -B tests/test_preparation_storage.py
node tools/terrain/test_compact_batch.mjs
python -B tests/test_setup_updates.py
python -B tools/verify_installer_ui.py --exe installer/target/release/rikui-installer.exe --output dist/native-checks
```

The native verifier exercises thirteen read-only real-window states, native UI Automation names/roles, keyboard order and DPI bounds. Images require full-size inspection and exact hash review; tests never promote baselines. [ui-review.json](ui-review.json) records reviewed captures and source provenance. Unchanged addon Lua captures retain their original provenance.

Changing Preparation folder carries the completed receipt and hash-verified local bundle into the new owned cache. Datasets and terrain stay in their original folders and must remain available; the worker freshly verifies them before reuse. Incomplete work remains on the previous drive, and pause state is preserved. Existing destination files are retained.

**--install-current <storage-folder>** exercises the same preparation and transaction backend as the primary GUI for isolated/automated delivery verification; **--preparation-folder <existing-folder>** invokes the same Preparation folder recovery and retains the previous completed inputs before verification; **--no-schedule** suppresses task registration only in isolated tests. The user accepts native gameplay; no routine gameplay sign-off is required. The executable currently has no Authenticode signature; checksums verify published bytes.
