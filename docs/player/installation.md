# Install RikUI

RikUI **{{release.version}}** is a **{{release.channel}}** release for WoW Forever. Check the current release notes for compatibility and known limitations.

## Public addon ZIP

Download [{{release.zip}}]({{release.download}}) from the [current RikUI release]({{release.url}}). Close the game and extract the `RikUI` folder into `_classic_beta_/Interface/AddOns`, so `RikUI.toc` is directly inside `AddOns/RikUI`. Enable RikUI in the AddOns list.

The public ZIP includes the addon without quest and road datasets. Locally installed quest data and settings are preserved when updating.

## Local Windows installer

The Windows installer is not published yet. If you already have a local installer bundle, use these steps:

1. Close World of Warcraft.
2. Open the installer and select your Forever folder—the one containing **WowB.exe**.
3. Check the package's included components.
4. Click **Install / update**.
5. Start the game and enable RikUI in the AddOns list.

The installer carries its package with it. You do not need Rust or Python installed. **Choose package** lets you select another RikUI bundle, and **Get latest release** opens the releases page.

Quest data is not included in every public package. Check the release notes before downloading.

## First login

Open `/rik config` to customize your interface. **Appearance** offers themes and readability recipes; each feature page has an enable switch and its own settings. **Bars and layout** lets you select and arrange each bar independently.

Use `/rik setup` for the separate character wizard: role, keys, action-bar presets and modules. Review its summary before applying.

Use `/rik config` for settings and `/rik move` to arrange frames. See [First setup](wizard.md) for the wizard.

## Updates

Close the game before updating. Existing settings, other addons and locally installed quest data are preserved.

Restart the game fully after installing an update so it can load new addon files.

## Rollback

Use the installer's rollback option to restore the previous addon folders. Backups are kept under **Interface/RikUI-backups**. Keep that folder if you may need to recover an earlier installation.

A first installation has no previous version to restore. Backups are kept until you remove them, so leave enough free space for both the update and the old version.
