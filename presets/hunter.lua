-- Rotation, control, cooldowns, pet care and tracking. See docs/class-presets.md.
RikUI.Presets.HUNTER = {
    ["class"] = "HUNTER",
    ["version"] = 3,
    ["roleOrder"] = { "dps", "beast", "survival" },
    ["roles"] = {
        ["dps"] = { label = "Marksmanship", trees = { 2 } },
        ["beast"] = { label = "Beast Mastery", trees = { 1 } },
        ["survival"] = { label = "Survival / melee", trees = { 3 } },
    },
    ["bars"] = {
        ["main"] = {
            [1] = {
                ["spell"] = "Auto Shot",
                ["level"] = 1,
            },
            [2] = {
                ["spell"] = "Serpent Sting",
                ["level"] = 4,
            },
            [3] = {
                ["spell"] = "Arcane Shot",
                ["level"] = 6,
            },
            [4] = {
                ["spell"] = "Aimed Shot", fallback = "Arcane Shot",
                ["level"] = 20,
            },
            [5] = {
                ["spell"] = "Multi-Shot",
                ["level"] = 18,
            },
            [6] = {
                ["spell"] = "Concussive Shot",
                ["level"] = 8,
            },
            [7] = {
                ["spell"] = "Freezing Trap",
                ["level"] = 20,
            },
            [8] = {
                ["spell"] = "Wing Clip",
                ["level"] = 12,
            },
            [9] = {
                ["spell"] = "Hunter's Mark",
                ["level"] = 6,
            },
            [10] = {
                ["spell"] = "Mend Pet",
                ["level"] = 12,
            },
            [11] = {
                ["spell"] = "Raptor Strike",
                ["level"] = 1,
            },
            [12] = {
                ["item"] = "Hearthstone",
            },
        },
        ["bar2"] = {
            [1] = {
                ["spell"] = "Rapid Fire",
                ["level"] = 26,
            },
            [2] = {
                ["spell"] = "Feign Death",
                ["level"] = 30,
            },
            [3] = {
                ["spell"] = "Deterrence",
            },
            [4] = {
                ["spell"] = "Intimidation",
            },
            [5] = {
                ["spell"] = "Bestial Wrath",
            },
            [6] = {
                ["spell"] = "Frost Trap",
                ["level"] = 28,
            },
            [7] = {
                ["spell"] = "Immolation Trap",
                ["level"] = 16,
            },
            [8] = {
                ["spell"] = "Explosive Trap",
                ["level"] = 34,
            },
            [9] = {
                ["spell"] = "Volley",
                ["level"] = 40,
            },
            [10] = {
                ["macro"] = "Pet Attack",
            },
            [11] = {
                ["macro"] = "Pet Follow",
            },
            [12] = {
                ["spell"] = "Counterattack",
                ["level"] = 30,
            },
        },
        ["bar3"] = {
            [1] = {
                ["spell"] = "Aspect of the Hawk",
                ["level"] = 10,
            },
            [2] = {
                ["spell"] = "Aspect of the Monkey",
                ["level"] = 4,
            },
            [3] = {
                ["spell"] = "Aspect of the Cheetah",
                ["level"] = 20,
            },
            [4] = {
                ["spell"] = "Aspect of the Beast",
                ["level"] = 30,
            },
            [5] = {
                ["spell"] = "Call Pet",
                ["level"] = 10,
            },
            [6] = {
                ["spell"] = "Revive Pet",
                ["level"] = 10,
            },
            [7] = {
                ["spell"] = "Dismiss Pet",
                ["level"] = 10,
            },
            [8] = {
                ["spell"] = "Feed Pet",
                ["level"] = 10,
            },
            [9] = {
                ["spell"] = "Beast Training",
                ["level"] = 10,
            },
            [10] = {
                ["spell"] = "Tame Beast",
            },
            [11] = {
                ["spell"] = "Flare",
                ["level"] = 32,
            },
            [12] = {
                ["spell"] = "Tranquilizing Shot",
                ["level"] = 60,
            },
        },
        ["bar4"] = {
            [1] = {
                ["spell"] = "Summon Hawk", fallback = "Arcane Shot",
                ["level"] = 25,
            },
            [2] = {
                ["spell"] = "Lacerate", fallback = "Raptor Strike",
                ["level"] = 30,
            },
            [3] = {
                ["spell"] = "Mongoose Bite",
                ["level"] = 16,
            },
            [4] = {
                ["spell"] = "Disengage",
                ["level"] = 20,
            },
            [5] = {
                ["spell"] = "Scatter Shot",
            },
            [6] = {
                ["spell"] = "Strider Kick",
            },
            [7] = {
                ["spell"] = "Sniper Shot",
                ["level"] = 40,
            },
            [8] = {
                ["spell"] = "Black Arrow",
                ["level"] = 50,
            },
            [9] = {
                ["spell"] = "Trueshot Aura",
                ["level"] = 25,
            },
            [10] = {
                ["spell"] = "Scorpid Sting",
                ["level"] = 22,
            },
            [11] = {
                ["spell"] = "Viper Sting",
                ["level"] = 36,
            },
            [12] = {
                ["spell"] = "Scare Beast",
                ["level"] = 14,
            },
        },
        ["bar5"] = {
            [1] = {
                ["spell"] = "Track Beasts",
                ["level"] = 1,
            },
            [2] = {
                ["spell"] = "Track Humanoids",
                ["level"] = 10,
            },
            [3] = {
                ["spell"] = "Track Hidden",
                ["level"] = 24,
            },
            [4] = {
                ["spell"] = "Track Undead",
                ["level"] = 18,
            },
            [5] = {
                ["spell"] = "Track Demons",
                ["level"] = 32,
            },
            [6] = {
                ["spell"] = "Track Elementals",
                ["level"] = 26,
            },
            [7] = {
                ["spell"] = "Track Giants",
                ["level"] = 40,
            },
            [8] = {
                ["spell"] = "Track Dragonkin",
                ["level"] = 50,
            },
            [9] = {
                ["spell"] = "Eagle Eye",
                ["level"] = 14,
            },
            [10] = {
                ["spell"] = "Eyes of the Beast",
                ["level"] = 14,
            },
            [11] = {
                ["spell"] = "Aspect of the Pack",
                ["level"] = 40,
            },
            [12] = {
                ["spell"] = "Aspect of the Wild",
                ["level"] = 46,
            },
        },
    },
    ["macros"] = {
        ["Pet Attack"] = {
            ["icon"] = 132161,
            ["body"] = "#showtooltip\n/petattack [@target,harm,nodead]",
        },
        ["Pet Follow"] = {
            ["icon"] = 132163,
            ["body"] = "#showtooltip\n/petfollow\n/petpassive",
        },
    },
    ["roleOverrides"] = {
        beast = {
            main = { [3] = { spell = "Summon Hawk", fallback = "Arcane Shot", level = 25 } },
            bar4 = { [1] = { spell = "Arcane Shot", level = 6 } },
        },
        survival = {
            main = {
                [1] = { spell = "Raptor Strike", level = 1 },
                [3] = { spell = "Mongoose Bite", level = 16 },
                [4] = { spell = "Lacerate", fallback = "Raptor Strike", level = 30 },
                [5] = { spell = "Counterattack", level = 30 },
                [11] = { spell = "Strider Kick" },
            },
            bar4 = {
                [2] = { spell = "Aimed Shot", fallback = "Arcane Shot", level = 20 },
                [3] = { spell = "Auto Shot", level = 1 },
                [6] = { spell = "Arcane Shot", level = 6 },
                [7] = { spell = "Multi-Shot", level = 18 },
                [12] = { spell = "Distracting Shot", level = 12 },
            },
            extra = { [1] = { spell = "Sniper Shot", level = 40 }, [2] = { spell = "Scare Beast", level = 14 } },
        },
    },
}

