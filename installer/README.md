# RikUI Windows installer

A native Win32 graphical installer written in Rust. The GUI uses Microsoft's
windows-sys bindings and standard Windows controls. No egui, webview, browser
engine, Python installation or Rust installation is needed by the player.

The installer is not published with the 1.0.0 beta. The beta is the addon ZIP
on the [releases page](https://github.com/rik-wow/RikUI/releases); this
installer is built locally until the data it can carry has passed the
[licensing review](../docs/corpus-licensing.md).

Select the Forever folder containing WowB.exe, then **Install / update**.
The executable carries its package offline. **Choose package** accepts another
RikUI bundle ZIP; **Get latest release** opens the public releases page.
There is no background network updater or credential storage.

## Complete local build

With Rust 1.95 or later and Python 3.10 or later:

~~~powershell
python -B tools/build_installer_bundle.py --version 1.0.0-beta.1 --output dist/RikUI-local-all-in-one.zip --corpus dist/installer-corpus/quest-data.zip --local-roads "C:/Program Files (x86)/World of Warcraft/_classic_beta_/Interface/AddOns"
$env:RIKUI_BUNDLE = (Resolve-Path dist/RikUI-local-all-in-one.zip).Path
cargo build --release --locked --manifest-path installer/Cargo.toml
~~~

The output is installer/target/release/rikui-installer.exe. The corpus argument
is the verified private quest-data release archive. The optional local-roads
argument reads the existing generated roads and their companion patch packs.
All input data is retained. Output bundle names must be new.

A build without RIKUI_BUNDLE is a development executable that requires a
selected package. A bundle built without corpus/roads states exactly which
components it includes; it is not the complete distribution requested here.
Do not publish the data-bearing bundle until the
[licensing review](../docs/corpus-licensing.md) is resolved.

## Update and recovery

- Close WoW first. The GUI checks for a running WowB.exe.
- Updates copy the existing addon folders into staging, then overlay verified
  files. Existing generated data and unowned files remain present.
- Only RikUI and the strict RikUIQuestRoads_W<world>_P<page> folder pattern can
  be replaced. Other addons and WTF settings are outside the transaction.
- Every replaced folder is retained under Interface/RikUI-backups. Rollback
  restores the previous folders and also backs up the current folders.
- A first install has no previous version to restore. Rollback leaves newly
  introduced folders present. There is no delete/uninstall button.
- An interrupted directory swap is recovered when the installer next opens
  that game folder. Keep the backup directory if Windows blocks recovery.
- Junctions and symbolic links in installation paths are rejected. A checkout
  junction such as the developer's RikUI folder must continue to use the
  existing developer tools.
- Backups are deliberately not automatically pruned. A complete update needs
  disk space for staging and the retained prior version.

The manifest binds every file's size and SHA-256. Archives reject traversal,
Windows device paths, case collisions, links, duplicate members and oversized
payloads. Hash verification detects damaged packages; it is not a publisher
signature. Use packages from trusted sources. The executable is not Authenticode
signed in this first build.

## Development checks

~~~text
cargo test --locked --manifest-path installer/Cargo.toml
cargo clippy --locked --manifest-path installer/Cargo.toml --all-targets -- -D warnings
cargo audit --file installer/Cargo.lock
cargo run --release --locked --manifest-path installer/Cargo.toml --example verify -- dist/RikUI-local-all-in-one.zip
~~~

The --smoke-test executable argument creates the actual native window, checks
its controls and embedded package, and exits. It does not alter a game install.
Filesystem tests use temporary game fixtures. Game-client behavior is accepted
by the user under the project's native acceptance policy.
