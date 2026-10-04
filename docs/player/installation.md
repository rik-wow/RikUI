# Install RikUI

RikUI **{{release.version}}** is a **{{release.channel}}** release for WoW Forever. Use [Windows setup](/install) for quest guidance and navigation prepared for your current game.

## Windows setup

Quest guidance currently requires **English game text (enUS)**. Set Forever's game text to English to use the supported quest guide.

1. Download **RikUI-Setup.exe** from the [installation page](/install). Open it and let it find your current Forever game. Use **Browse** if needed.
2. Allow **16 GiB free** for first preparation. Setup keeps temporary files compact to reduce disk use. Previous generations and backups use additional space. **Preparation folder** lets you choose another drive; setup checks space before starting and while working.
3. Choose **Prepare and install**. Setup downloads quest and holiday information from Questie, reads your current game files, and prepares supported routes on your computer. Its tools are included: you do not need Git, Python, Node or a database.
4. Follow the phase and measured progress. This can take substantial time. **Pause setup** retains work; reopen setup and choose **Resume setup** to continue. Incomplete work is never installed as a complete guide.
5. Close WoW when prompted. Setup checks the prepared files, installs them and keeps a backup. Restart WoW fully and enable RikUI in the AddOns list.

Setup downloads the quest information it needs automatically. You do not need to install QuestieDB first. Quest information and map data are prepared and kept on your computer.

**View details** lists your verified build, preparation folder, quest counts, prepared regions, coverage limits, logs and backups. Some new quests may not yet have complete instructions or locations. Routes may be unavailable on certain floors or during phased quests. Travel times are estimates.

## Preparation cost and current coverage

First setup downloads quest information, reads your game files and prepares walkable routes. This can take substantial time. Setup adjusts its workload to your computer and shows elapsed time as it works. Updates can reuse completed work after checking it. Pause setup whenever you need to; completed work is kept for the next run.

The currently verified regions are **Eastern Kingdoms, Kalimdor, Zephras Isle, Darkspear Islands, Alterac Valley, Warsong Gulch and Arathi Basin**. Routes for other maps and instances are not currently supported. Some floors and phased areas may also lack routes.

The quest database includes 5,009 quests and accounts for supported character differences. Another 2,324 quest IDs in the current game files lack complete guide information. A quest appearing in the browser does not mean your character can accept it.

## First login

Open `/rik config` to customize the interface. Appearance offers themes and readability choices; feature pages have enable switches and their own settings. Use `/rik move` to arrange frames.

Use `/rik setup` for the separate character wizard: role, keys, action-bar presets and modules. Review its summary before applying. See [First setup](wizard.md).

## Updates

Setup checks for new RikUI releases, Forever versions and quest information when it opens or updates. A daily Windows task, **RikUI Current Forever Updates**, also checks automatically. When needed, setup prepares updated data. It checks existing files before reusing them.

Keep Forever updated through Battle.net. A version mismatch asks you to update and check again. Setup can find your game if its name or installation folder changes for release. New client builds require current compatible data, and stale guidance is withheld. Future builds are verified when available.

If an update needs more disk space, choose **Preparation folder** on a roomier drive. Setup keeps completed data in its original folders and verifies it before reuse; keep those folders available. Incomplete work remains on the previous drive. Existing files in the chosen folder are preserved.

A paused preparation stays paused until you explicitly resume. Connection, download, disk-space or preparation problems preserve your existing installation and local files. Follow the explanation, then reopen setup to retry. If WoW is running, prepared work waits for it to close.

## Restore a backup

Choose **Restore backup** to restore the previous RikUI installation. Backups are retained under **Interface/RikUI-backups**. Settings, unrelated addons and private data remain preserved. Keep backups until you no longer need them, and allow space for both versions.

## Interface-only addon ZIP

Download [{{release.zip}}]({{release.download}}) from the [current release]({{release.url}}). Close WoW and extract the `RikUI` folder into the current game's `Interface/AddOns`, with `RikUI.toc` directly inside `AddOns/RikUI`.

The ZIP includes the interface. Setup prepares the quest guide and routes separately. Existing local data and settings are preserved when updating through setup. Use Windows setup for complete supported local quest and navigation preparation.

Gear source browsing can also use a separately installed [QuestieDB](https://github.com/Questie/QuestieDB) addon with current Forever support. Saved gear goals are preserved if that optional provider is absent.
