# Website artwork notice

World of Warcraft game imagery, spell icons and item icons are copyright
Blizzard Entertainment, Inc. All rights reserved. World of Warcraft and
Blizzard Entertainment are trademarks or registered trademarks of Blizzard
Entertainment, Inc. in the U.S. and/or other countries.

Blizzard artwork, including game captures, icons and Lua-rendered examples in
`public/assets/` and `ui-renders/`, is
excluded from this repository's MIT code license. No sublicense or transfer
of Blizzard's rights is granted by this repository.

The JPEG is the user's game capture, `WoWScrnShot_092726_120706.jpg`, selected
at their express request on 2026-09-27. Its original bytes are preserved.
SHA-256: `212b21a4c6745595bbb84f1bb2e84845c851bfcf4ff39221f71bd6ec687edd7d`.

The two combat captures, `WoWScrnShot_092726_122242.jpg` and
`WoWScrnShot_092726_122246.jpg`, were the newest two files in the user's
Classic Beta Screenshots folder when selected on 2026-09-27. Both retain their
original bytes. The UI-visible capture is a layout reference only and is not
shown as a website preview. The UI-hidden capture supplies the combat backdrop.

The spell and item icons were extracted from the user's installed
`wow_classic_beta` client, version 1.60.1.70009, through its local CASC indices.
BLP icons were decoded to PNG at their original 64 × 64 resolution.
Elwynn world-map tiles retain their original 256 × 256 resolution and are
assembled as SVG images for documentation illustrations.
They are served locally, with no requests to Blizzard's icon CDN.
[client-assets.json](client-assets.json) records source file IDs, paths,
build evidence and SHA-256 hashes for the icons and both combat captures.
Build identifiers record this extraction; future work must resolve the
then-current installed build.

## Icon identity and mockups

Spell illustrations use named entries from RikUI's spell catalogues, including
their spell IDs and FileDataIDs. Paladin bar placement was checked against the
user's selected preset, saved action snapshot and the UI-visible combat capture.
The icon crop matches RikUI's 0.08–0.92 texture coordinates. An inactive seal
is desaturated in the rendered preview; the extracted image remains unchanged.

The item examples use [Minor Healing Potion](https://www.wowhead.com/item=118/minor-healing-potion)
(`inv_potion_49`) and Hearthstone (`inv_misc_rune_01`).
Menu and window controls use RikUI's own SVG artwork from `media/icons`.
Documentation illustrations use sample values and are labeled mockups.
Optional client panels remain conditional; an illustration does not establish
that a particular client variant is available.

RikUI is an independent fan project. It is not affiliated with, endorsed by,
or sponsored by Blizzard Entertainment.

[Blizzard's usage guidelines](https://www.blizzard.com/en-us/legal/c1ae32ac-7ff9-4ac3-a03b-fc04b8697010/blizzard-legal-faq)
describe limited fansite use and its conditions; this notice does not grant
additional rights.
