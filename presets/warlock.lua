-- Native pet controls and role rotations; evidence: docs/class-presets.md.
RikUI.Presets.WARLOCK = {
    ["class"] = "WARLOCK",
    ["version"] = 3,
    ["roleOrder"] = {
        "affliction",
        "demonology",
        "destruction",
    },
    ["roles"] = {
        ["affliction"] = {
            ["label"] = "Affliction",
            ["trees"] = {
                1,
            },
        },
        ["demonology"] = {
            ["label"] = "Demonology",
            ["trees"] = {
                2,
            },
        },
        ["destruction"] = {
            ["label"] = "Destruction",
            ["trees"] = {
                3,
            },
        },
    },
    ["bars"] = {
        ["main"] = {
            [1] = {
                ["spell"] = "Shadow Bolt",
                ["level"] = 1,
            },
            [2] = {
                ["spell"] = "Bane of Agony",
                ["level"] = 8,
            },
            [3] = {
                ["spell"] = "Corruption",
                ["level"] = 4,
            },
            [4] = {
                ["spell"] = "Immolate",
                ["level"] = 1,
            },
            [5] = {
                ["spell"] = "Drain Life",
                ["level"] = 14,
            },
            [6] = {
                ["macro"] = "Fear",
            },
            [7] = {
                ["spell"] = "Life Tap",
                ["level"] = 6,
            },
            [8] = {
                ["spell"] = "Searing Pain",
                ["level"] = 18,
            },
            [9] = {
                ["spell"] = "Drain Soul",
                ["level"] = 10,
            },
            [10] = {
                ["macro"] = "Health Funnel",
            },
            [11] = {
                ["spell"] = "Death Coil",
                ["level"] = 42,
            },
            [12] = {
                ["item"] = "Hearthstone",
            },
        },
        ["bar2"] = {
            [1] = {
                ["spell"] = "Amplify Curse",
            },
            [2] = {
                ["spell"] = "Fel Domination",
            },
            [3] = {
                ["spell"] = "Soul Link",
            },
            [4] = {
                ["spell"] = "Demonic Sacrifice",
            },
            [5] = {
                ["spell"] = "Howl of Terror",
                ["level"] = 40,
            },
            [6] = {
                ["macro"] = "Banish",
            },
            [7] = {
                ["spell"] = "Rain of Fire",
                ["level"] = 20,
            },
            [8] = {
                ["spell"] = "Hellfire",
                ["level"] = 30,
            },
            [9] = {
                ["spell"] = "Shadow Ward",
                ["level"] = 32,
            },
            [10] = {
                ["macro"] = "Pet Attack",
            },
            [11] = {
                ["macro"] = "Pet Follow",
            },
            [12] = {
                ["macro"] = "Banish",
            },
        },
        ["bar3"] = {
            [1] = {
                ["spell"] = "Demon Skin",
                ["level"] = 1,
            },
            [2] = {
                ["spell"] = "Demon Armor",
                ["level"] = 20,
            },
            [3] = {
                ["spell"] = "Create Healthstone",
                ["level"] = 10,
            },
            [4] = {
                ["spell"] = "Create Soulstone",
                ["level"] = 18,
            },
            [5] = {
                ["spell"] = "Summon Imp",
                ["level"] = 1,
            },
            [6] = {
                ["spell"] = "Summon Voidwalker",
                ["level"] = 10,
            },
            [7] = {
                ["spell"] = "Summon Succubus",
                ["level"] = 20,
            },
            [8] = {
                ["spell"] = "Summon Incubus",
                ["level"] = 20,
            },
            [9] = {
                ["spell"] = "Summon Felhunter",
                ["level"] = 30,
            },
            [10] = {
                ["spell"] = "Ritual of Summoning",
                ["level"] = 20,
            },
            [11] = {
                ["spell"] = "Unending Breath",
                ["level"] = 16,
            },
            [12] = {
                ["spell"] = "Detect Invisibility",
                ["level"] = 26,
            },
        },
        ["bar4"] = {
            [1] = {
                ["spell"] = "Curse of Weakness",
                ["level"] = 4,
            },
            [2] = {
                ["spell"] = "Curse of Recklessness",
                ["level"] = 14,
            },
            [3] = {
                ["spell"] = "Curse of the Elements",
                ["level"] = 20,
            },
            [4] = {
                ["spell"] = "Curse of Tongues",
                ["level"] = 26,
            },
            [5] = {
                ["spell"] = "Curse of Exhaustion",
            },
            [6] = {
                ["spell"] = "Siphon Life",
                ["level"] = 30,
            },
            [7] = {
                ["spell"] = "Drain Mana",
                ["level"] = 24,
            },
            [8] = {
                ["spell"] = "Bane of Doom",
                ["level"] = 60,
            },
            [9] = {
                ["spell"] = "Wrack",
            },
            [10] = {
                ["spell"] = "Bane of Havoc",
            },
            [11] = {
                ["spell"] = "Conflagrate", fallback = "Corruption",
                ["level"] = 25,
            },
            [12] = {
                ["spell"] = "Shadowburn", fallback = "Bane of Agony",
                ["level"] = 20,
            },
        },
        ["bar5"] = {
            [1] = {
                ["spell"] = "Create Firestone",
                ["level"] = 28,
            },
            [2] = {
                ["spell"] = "Create Spellstone",
                ["level"] = 36,
            },
            [3] = {
                ["spell"] = "Sense Demons",
                ["level"] = 24,
            },
            [4] = {
                ["spell"] = "Eye of Kilrogg",
                ["level"] = 22,
            },
            [5] = {
                ["spell"] = "Subjugate Demon",
                ["level"] = 30,
            },
            [6] = {
                ["spell"] = "Inferno",
                ["level"] = 50,
            },
            [7] = {
                ["spell"] = "Portal of Summoning",
                ["level"] = 60,
            },
            [8] = {
                ["spell"] = "Ritual of Doom",
                ["level"] = 60,
            },
            [9] = {
                ["spell"] = "Summon Felsteed",
                ["level"] = 40,
            },
            [10] = {
                ["spell"] = "Summon Dreadsteed",
                ["level"] = 60,
            },
            [11] = {
                ["spell"] = "Soul Fire", fallback = "Drain Life",
                ["level"] = 48,
            },
            [12] = {
                ["spell"] = "Incinerate", fallback = "Shadow Bolt",
                ["level"] = 40,
            },
        },
    },
    ["macros"] = {
        ["Fear"] = { icon = 136183, spells = { "Fear" },
            body = "#showtooltip Fear\n/cast [@mouseover,harm,nodead][harm,nodead] Fear" },
        ["Banish"] = { icon = 136135, spells = { "Banish" },
            body = "#showtooltip Banish\n/cast [@mouseover,harm,nodead][harm,nodead] Banish" },
        ["Health Funnel"] = { icon = 136168, spells = { "Health Funnel" },
            body = "#showtooltip Health Funnel\n/cast [@pet,exists,nodead] Health Funnel" },
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
        ["demonology"] = {
            ["main"] = {
                [5] = {
                    ["macro"] = "Health Funnel",
                },
                [10] = {
                    ["spell"] = "Drain Life",
                    ["level"] = 14,
                },
            },
        },
        ["destruction"] = {
            ["main"] = {
                [1] = {
                    ["spell"] = "Incinerate", fallback = "Shadow Bolt",
                    ["level"] = 40,
                },
                [2] = {
                    ["spell"] = "Conflagrate", fallback = "Corruption",
                    ["level"] = 25,
                },
                [3] = {
                    ["spell"] = "Immolate",
                    ["level"] = 1,
                },
                [4] = {
                    ["spell"] = "Shadowburn", fallback = "Bane of Agony",
                    ["level"] = 20,
                },
                [5] = {
                    ["spell"] = "Soul Fire", fallback = "Drain Life",
                    ["level"] = 48,
                },
            },
        },
    },
}

