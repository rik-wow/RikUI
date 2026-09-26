-- Learned player cooldown priorities; research checked 2026-09-24.
-- IDs/ranks: verified Forever catalogue 1.60.1.69913. See docs/class-cooldowns.md.
-- Judgement leads: it is the seal cooldown, learned at level 4, and the native
-- cooldown manager configures no paladin entries (user report 2026-09-25).
RikUI.ClassCooldownProfiles.PALADIN = {
    "Judgement",
    "Hammer of Justice",
    "Blessing of Protection",
    "Blessing of Freedom",
    "Lay on Hands",
    "Divine Shield",
    "Divine Protection",
    "Holy Shield",
    "Holy Shock",
    "Repentance",
    "Exorcism",
    "Holy Strike",
}
-- One Seal cell in the strip: dim until a seal is up, then the client shows the active seal's
-- icon and timer over it, whichever seal it is (user's choice, 2026-09-25).
RikUI.ClassAuraCells.PALADIN = {
    { label = "Seal", unit = "player", families = { "Seal of Righteousness", "Seal of the Crusader", "Seal of Fury",
        "Seal of Command", "Seal of Light", "Seal of Wisdom", "Seal of Justice" } },
}
