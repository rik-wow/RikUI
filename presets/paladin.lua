-- Three roles share utility and targeted mouseover healing.
RikUI.Presets.PALADIN = {
    ["class"] = "PALADIN",
    ["version"] = 1,
    ["roleOrder"] = {
        "dps",
        "tank",
        "heal",
    },
    ["roles"] = {
        ["dps"] = {
            ["label"] = "Retribution",
            ["trees"] = {
                3,
            },
        },
        ["tank"] = {
            ["label"] = "Protection",
            ["trees"] = {
                2,
            },
        },
        ["heal"] = {
            ["label"] = "Holy",
            ["trees"] = {
                1,
            },
        },
    },
    ["bars"] = {
        ["main"] = {
            [1] = {
                ["spell"] = "Holy Strike",
                ["level"] = 6,
            },
            [2] = {
                ["spell"] = "Judgement",
                ["level"] = 4,
            },
            [3] = {
                ["spell"] = "Seal of Righteousness",
                ["level"] = 1,
            },
            [4] = {
                ["spell"] = "Consecration",
                ["level"] = 20,
            },
            [5] = {
                ["spell"] = "Hammer of Wrath",
                ["level"] = 44,
            },
            [6] = {
                ["spell"] = "Hammer of Justice",
                ["level"] = 8,
            },
            [7] = {
                ["spell"] = "Exorcism",
                ["level"] = 20,
            },
            [8] = {
                ["macro"] = "Purify",
            },
            [9] = {
                ["macro"] = "Holy Light",
            },
            [10] = {
                ["macro"] = "Flash of Light",
            },
            [11] = {
                ["spell"] = "Seal of Command",
                ["level"] = 20,
            },
            [12] = {
                ["item"] = "Hearthstone",
            },
        },
        ["bar2"] = {
            [1] = {
                ["spell"] = "Divine Protection",
                ["level"] = 6,
            },
            [2] = {
                ["spell"] = "Divine Shield",
                ["level"] = 34,
            },
            [3] = {
                ["macro"] = "Lay on Hands",
            },
            [4] = {
                ["spell"] = "Divine Favor",
            },
            [5] = {
                ["spell"] = "Holy Shield",
                ["level"] = 40,
            },
            [6] = {
                ["spell"] = "Blessing of Protection",
                ["level"] = 10,
            },
            [7] = {
                ["spell"] = "Blessing of Freedom",
                ["level"] = 18,
            },
            [8] = {
                ["spell"] = "Blessing of Sacrifice",
                ["level"] = 46,
            },
            [9] = {
                ["spell"] = "Repentance",
            },
            [10] = {
                ["macro"] = "Flash of Light",
            },
            [11] = {
                ["spell"] = "Hammer of Justice",
                ["level"] = 8,
            },
            [12] = {
                ["spell"] = "Holy Shock",
                ["level"] = 30,
            },
        },
        ["bar3"] = {
            [1] = {
                ["spell"] = "Blessing of Might",
                ["level"] = 4,
            },
            [2] = {
                ["spell"] = "Blessing of Wisdom",
                ["level"] = 14,
            },
            [3] = {
                ["spell"] = "Blessing of Kings",
                ["level"] = 20,
            },
            [4] = {
                ["spell"] = "Blessing of Salvation",
                ["level"] = 26,
            },
            [5] = {
                ["spell"] = "Devotion Aura",
                ["level"] = 1,
            },
            [6] = {
                ["spell"] = "Retribution Aura",
                ["level"] = 16,
            },
            [7] = {
                ["spell"] = "Concentration Aura",
                ["level"] = 22,
            },
            [8] = {
                ["spell"] = "Righteous Fury",
                ["level"] = 16,
            },
            [9] = {
                ["spell"] = "Redemption",
                ["level"] = 12,
            },
            [10] = {
                ["macro"] = "Cleanse",
            },
            [11] = {
                ["spell"] = "Seal of Light",
                ["level"] = 30,
            },
            [12] = {
                ["spell"] = "Seal of Wisdom",
                ["level"] = 38,
            },
        },
        ["bar4"] = {
            [1] = {
                ["spell"] = "Seal of Fury",
                ["level"] = 10,
            },
            [2] = {
                ["spell"] = "Seal of Justice",
                ["level"] = 22,
            },
            [3] = {
                ["spell"] = "Seal of the Crusader",
                ["level"] = 6,
            },
            [4] = {
                ["spell"] = "Hammer of the Righteous",
                ["level"] = 40,
            },
            [5] = {
                ["spell"] = "Light's Vigil",
                ["level"] = 40,
            },
            [6] = {
                ["spell"] = "Voice of Truth",
            },
            [7] = {
                ["spell"] = "Swift Judgement",
            },
            [8] = {
                ["spell"] = "Templar's Bulwark",
            },
            [9] = {
                ["spell"] = "Divine Intervention",
                ["level"] = 30,
            },
            [10] = {
                ["spell"] = "Holy Wrath",
                ["level"] = 50,
            },
            [11] = {
                ["spell"] = "Turn Undead",
                ["level"] = 24,
            },
            [12] = {
                ["spell"] = "Sense Undead",
                ["level"] = 20,
            },
        },
        ["bar5"] = {
            [1] = {
                ["spell"] = "Shadow Resistance Aura",
                ["level"] = 28,
            },
            [2] = {
                ["spell"] = "Frost Resistance Aura",
                ["level"] = 32,
            },
            [3] = {
                ["spell"] = "Fire Resistance Aura",
                ["level"] = 36,
            },
            [4] = {
                ["spell"] = "Blessing of Light",
                ["level"] = 40,
            },
            [5] = {
                ["spell"] = "Greater Blessing of Might",
                ["level"] = 52,
            },
            [6] = {
                ["spell"] = "Greater Blessing of Wisdom",
                ["level"] = 54,
            },
            [7] = {
                ["spell"] = "Greater Blessing of Kings",
                ["level"] = 60,
            },
            [8] = {
                ["spell"] = "Greater Blessing of Salvation",
                ["level"] = 60,
            },
            [9] = {
                ["spell"] = "Greater Blessing of Light",
                ["level"] = 60,
            },
            [10] = {
                ["spell"] = "Summon Warhorse",
                ["level"] = 40,
            },
            [11] = {
                ["spell"] = "Summon Charger",
                ["level"] = 60,
            },
        },
    },
    ["macros"] = {
        ["Holy Light"] = {
            ["icon"] = 135920,
            ["body"] = "#showtooltip Holy Light\n/cast [@mouseover,help,nodead][help,nodead][@player] Holy Light",
            ["spells"] = {
                "Holy Light",
            },
        },
        ["Flash of Light"] = {
            ["icon"] = 135907,
            ["body"] = "#showtooltip Flash of Light\n/cast [@mouseover,help,nodead][help,nodead][@player] Flash of Light",
            ["spells"] = {
                "Flash of Light",
            },
        },
        ["Lay on Hands"] = {
            ["icon"] = 135928,
            ["body"] = "#showtooltip Lay on Hands\n/cast [@mouseover,help,nodead][help,nodead][@player] Lay on Hands",
            ["spells"] = {
                "Lay on Hands",
            },
        },
        ["Purify"] = {
            ["icon"] = 135949,
            ["body"] = "#showtooltip Purify\n/cast [@mouseover,help,nodead][help,nodead][@player] Purify",
            ["spells"] = {
                "Purify",
            },
        },
        ["Cleanse"] = {
            ["icon"] = 135953,
            ["body"] = "#showtooltip Cleanse\n/cast [@mouseover,help,nodead][help,nodead][@player] Cleanse",
            ["spells"] = {
                "Cleanse",
            },
        },
    },
    ["roleOverrides"] = {
        ["tank"] = {
            ["main"] = {
                [1] = {
                    ["spell"] = "Hammer of the Righteous",
                    ["level"] = 40,
                },
                [3] = {
                    ["spell"] = "Seal of Fury",
                    ["level"] = 10,
                },
                [5] = {
                    ["spell"] = "Holy Shield",
                    ["level"] = 40,
                },
                [7] = {
                    ["spell"] = "Righteous Fury",
                    ["level"] = 16,
                },
            },
        },
        ["heal"] = {
            ["main"] = {
                [1] = {
                    ["macro"] = "Holy Light",
                },
                [2] = {
                    ["macro"] = "Flash of Light",
                },
                [3] = {
                    ["spell"] = "Holy Shock",
                    ["level"] = 30,
                },
                [4] = {
                    ["macro"] = "Cleanse",
                },
                [5] = {
                    ["macro"] = "Lay on Hands",
                },
                [7] = {
                    ["spell"] = "Light's Vigil",
                    ["level"] = 40,
                },
            },
        },
    },
}

