# Install RikUI

RikUI **{{release.version}}** is a **{{release.channel}}** release for WoW Forever. Use [Windows setup](/install) for quest guidance and navigation prepared for your current game.

## Windows setup

Quest guidance currently requires **English game text (enUS)**. All nine provider translation sets are retained in your local source audit; translated runtime guides are not supported. Set Forever's game text to English to use the supported quest guide.

1. Download **RikUI-Setup.exe** from the [installation page](/install). Open it and let it find your current Forever game. Use **Browse** if needed.
2. Allow at least **80 GiB free** for first preparation, plus space for retained generations and backups. **Preparation folder** lets you choose a roomier drive.
3. Choose **Prepare and install**. Setup obtains QuestieDB source and holiday information separately from their publishers, reads your current game files, and builds supported routes locally. Its tools are included: you do not need Git, Python, Node or a database.
4. Follow the phase and measured progress. This can take substantial time. **Pause setup** retains work; reopen setup and choose **Resume setup** to continue. Incomplete work is never installed as a complete guide.
5. Close WoW when prompted. Setup stages verified files, retains backups and verifies installed bytes. Restart WoW fully and enable RikUI in the AddOns list.

An installed QuestieDB ZIP is not a source checkout. Setup gets the supported source directly from its publisher. Imported reference datasets and extracted client geometry stay on your computer and are absent from public downloads.

**View details** lists your verified build, preparation folder, quest counts, prepared regions, coverage limits, logs and backups. Current client quest IDs missing provider objectives stay unknown. Provider information can lag the server; unsupported phases, floors, physics and projections are explicit. Transport times are estimates.

## Preparation cost and current coverage

The October 4, 2026 reference run on a Ryzen 9 7950X3D took **about 74 minutes** for retained terrain/route preparation and verification with four workers, after initial acquisition and quest composition. Current game input acquisition took 7.7 minutes separately. All 2,290 terrain jobs verified, including 47 reused after a pause. Setup normally uses two workers; downloads, quest composition and your hardware affect total time.

The currently verified regions are **Eastern Kingdoms, Kalimdor, Zephras Isle, Darkspear Islands, Alterac Valley, Warsong Gulch and Arathi Basin**. This is the supported regional set, with floors, phases, physics and projection gaps still explicit. It does not establish navigation for other maps or instances.

All eighteen supported provider variants were composed. The provider contains 5,009 quest records; 2,324 additional current client IDs lack provider semantics and remain unknown. Inventory membership is not proof that a quest is available to your character.

## First login

Open `/rik config` to customize the interface. Appearance offers themes and readability choices; feature pages have enable switches and their own settings. Use `/rik move` to arrange frames.

Use `/rik setup` for the separate character wizard: role, keys, action-bar presets and modules. Review its summary before applying. See [First setup](wizard.md).

## Updates

Setup checks the published installer channel and the latest Forever client, provider and schema inputs at startup and update. A daily Windows task, **RikUI Current Forever Updates**, repeats those checks. Changed inputs rebuild affected products. Unchanged files are reused only after their bytes and current compatibility verify.

Keep Forever updated through Battle.net. A version mismatch asks you to update and check again. Setup discovers the current executable, product and directory; it does not require the beta folder to survive release. New client builds require current compatible data, and stale guidance is withheld. Future builds are verified when available.

If an update needs more disk space, choose **Preparation folder** on a roomier drive. Setup keeps completed data in its original folders and verifies it before reuse; keep those folders available. Incomplete work remains on the previous drive. Existing files in the chosen folder are preserved.

A paused preparation stays paused until you explicitly resume. Network, provider, schema, space or generation failures preserve your existing installation and local files. Follow the explanation, then reopen setup to retry. If WoW is running, prepared work waits for it to close.

## Restore a backup

Choose **Restore backup** to restore previous owned addon files. Backups are retained under **Interface/RikUI-backups**. Settings, unrelated addons and private data remain preserved. Keep backups until you no longer need them, and allow space for both versions.

## Interface-only addon ZIP

Download [{{release.zip}}]({{release.download}}) from the [current release]({{release.url}}). Close WoW and extract the `RikUI` folder into the current game's `Interface/AddOns`, with `RikUI.toc` directly inside `AddOns/RikUI`.

The public ZIP contains the interface without imported gear, quest or road datasets. Existing local data and settings are preserved during an ownership-aware installer update. Use Windows setup for complete supported local quest and navigation preparation.

Gear source browsing can also use a separately installed [QuestieDB](https://github.com/Questie/QuestieDB) Forever addon with public contract 3. Saved gear goals are preserved if that optional provider is absent.
