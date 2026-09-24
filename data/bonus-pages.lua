-- Warrior BonusActionBar values verified in extracted Forever SpellShapeshiftForm
-- data for 1.60.1.69913 and 1.60.1.69977; see docs/bars.md source evidence.
-- First slot = (6 normal pages + bonus offset - 1) * 12 + 1.
-- Battle also has live RikProbe evidence in SDD.md; later stances await native acceptance.
RikUI.Data.BonusPages = {
    ROGUE = {
        { name = "stealth", offset = 1, firstAction = 73 },
    },
    WARRIOR = {
        { name = "battle", offset = 1, firstAction = 73 },
        { name = "defensive", offset = 2, firstAction = 85 },
        { name = "berserker", offset = 3, firstAction = 97 },
    },
}
