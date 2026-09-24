-- Warrior preset: Forever spellbooks checked 2026-09-18 (build 1.60.1.69913).
-- Sources, sparse page composition and acquisition caveats: docs/presets.md.
RikUI.Presets.WARRIOR = {
    class = "WARRIOR",
    version = 3,
    roleOrder = { "dps", "fury", "tank" },
    roles = {
        dps = { label = "Arms", trees = { 1 } },
        fury = { label = "Fury", trees = { 2 } },
        tank = { label = "Protection", trees = { 3 } },
    },
    bars = {
        main = {
            { spell = "Heroic Strike", level = 1 },
            { spell = "Rend", level = 4 },
            { spell = "Thunder Clap", level = 6 },
            { spell = "Hamstring", level = 8 },
            { macro = "Execute" },
            { spell = "Charge", level = 4 }, -- Q
            { spell = "Overpower", level = 12 }, -- E
            { spell = "Pummel", level = 38 }, -- R
            { spell = "Bloodrage", level = 10 }, -- F
            { spell = "Shield Block", level = 16 }, -- T
            { spell = "Demoralizing Shout", level = 14 }, -- G
            { item = "Hearthstone" },
        },
        battle = {
            [8] = { spell = "Shield Bash", level = 12 },
            [10] = { macro = "Shield Block" },
        },
        defensive = {
            [4] = { spell = "Disarm", level = 18 },
            [6] = { spell = "Taunt", level = 10 },
            [7] = { spell = "Revenge", level = 14 },
            [8] = { spell = "Shield Bash", level = 12 },
        },
        berserker = {
            [2] = { spell = "Slam", level = 20 },
            [3] = { spell = "Whirlwind", level = 36 },
            [6] = { spell = "Intercept", level = 30 },
            [7] = { spell = "Victory Rush", level = 20 },
            [10] = { macro = "Shield Block" },
        },
        bar2 = {
            { spell = "Retaliation", level = 20 },
            { spell = "Shield Wall", level = 28 },
            { spell = "Recklessness", level = 50 },
            { spell = "Berserker Rage", level = 32 },
            { spell = "Challenging Shout", level = 26 },
            { spell = "Mocking Blow", level = 16 },
            { spell = "Disarm", level = 18 },
            { spell = "Intimidating Shout", level = 22 },
            { spell = "Victory Rush", level = 20 },
            { macro = "Charge" }, -- Mouse4
            { macro = "Interrupt" }, -- Mouse5
            { spell = "Cleave", level = 20 },
        },
        bar3 = {
            { spell = "Battle Shout", level = 1 },
            { spell = "Sunder Armor", level = 10 },
            { spell = "Slam", level = 20 },
            { spell = "Battle Stance", level = 1 },
            { spell = "Defensive Stance", level = 10 },
            { spell = "Berserker Stance", level = 30 },
            { spell = "Mortal Strike", fallback = "Rend", level = 40 },
            { spell = "Bloodthirst", fallback = "Heroic Strike", level = 40 },
            { spell = "Shield Slam", fallback = "Heroic Strike", level = 40 },
        },
        -- Mounts, professions, food and racials depend on the character.
        bar4 = {},
        bar5 = {},
    },
    -- `spells` lists the attacks a macro exists to cast. Its bar slot stays
    -- empty until the character knows one of them; the stance fallback alone
    -- never earns the macro a slot.
    macros = {
        Execute = {
            icon = 135358,
            body = "#showtooltip Execute\n/cast [stance:1/3] Execute; [stance:2] Battle Stance",
            spells = { "Execute" },
        },
        ["Shield Block"] = {
            icon = 132110,
            body = "#showtooltip Shield Block\n/cast [stance:2] Shield Block; Defensive Stance",
            spells = { "Shield Block" },
        },
        Charge = {
            icon = 132337,
            body = "#showtooltip Charge\n/cast [stance:1] Charge; Battle Stance",
            spells = { "Charge" },
        },
        Interrupt = {
            icon = 132938,
            body = "#showtooltip\n/cast [stance:3] Pummel; Shield Bash",
            spells = { "Pummel", "Shield Bash" },
        },
    },
    roleOverrides = {
        dps = {
            main = { [2] = { spell = "Mortal Strike", fallback = "Rend", level = 40 } },
            bar5 = { [11] = { spell = "Rend", level = 4 } },
        },
        fury = {
            main = { [1] = { spell = "Bloodthirst", fallback = "Heroic Strike", level = 40 } },
            bar5 = { [11] = { spell = "Heroic Strike", level = 1 } },
        },
        tank = {
            main = {
                [1] = { spell = "Sunder Armor", level = 10 },
                [2] = { spell = "Shield Slam", fallback = "Heroic Strike", level = 40 },
                [6] = { spell = "Taunt", level = 10 },
                [7] = { spell = "Revenge", level = 14 },
                [8] = { spell = "Shield Bash", level = 12 },
            },
            bar5 = { [11] = { spell = "Rend", level = 4 }, [12] = { spell = "Heroic Strike", level = 1 } },
            -- Keep tank stance pages usable when leaving Defensive.
            battle = {
                [6] = { spell = "Charge", level = 4 },
                [7] = { spell = "Overpower", level = 12 },
            },
            berserker = {
                [8] = { spell = "Pummel", level = 38 },
            },
        },
    },
}
