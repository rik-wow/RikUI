-- Friendly living mouseover, target, then self heals in every role.
RikUI.Presets.PRIEST = {
    ["class"] = "PRIEST",
    ["version"] = 2,
    ["roleOrder"] = {
        "heal",
        "shadow",
    },
    ["roles"] = {
        ["heal"] = {
            ["label"] = "Discipline / Holy",
            ["trees"] = {
                1,
                2,
            },
        },
        ["shadow"] = {
            ["label"] = "Shadow",
            ["trees"] = {
                3,
            },
        },
    },
    ["bars"] = {
        ["main"] = {
            [1] = {
                ["macro"] = "Lesser Heal",
            },
            [2] = {
                ["macro"] = "Heal",
            },
            [3] = {
                ["macro"] = "Flash Heal",
            },
            [4] = {
                ["macro"] = "Renew",
            },
            [5] = {
                ["macro"] = "Power Shield",
            },
            [6] = {
                ["spell"] = "Smite",
                ["level"] = 1,
            },
            [7] = {
                ["spell"] = "Shadow Word: Pain",
                ["level"] = 4,
            },
            [8] = {
                ["macro"] = "Dispel Magic",
            },
            [9] = {
                ["macro"] = "Greater Heal",
            },
            [10] = {
                ["macro"] = "Cure Disease",
            },
            [11] = {
                ["spell"] = "Fade",
                ["level"] = 8,
            },
            [12] = {
                ["item"] = "Hearthstone",
            },
        },
        ["bar2"] = {
            [1] = {
                ["spell"] = "Inner Focus",
            },
            [2] = {
                ["macro"] = "Power Infusion",
            },
            [3] = {
                ["spell"] = "Desperate Prayer",
                ["level"] = 10,
            },
            [4] = {
                ["spell"] = "Lightwell",
                ["level"] = 40,
            },
            [5] = {
                ["macro"] = "Mending",
            },
            [6] = {
                ["spell"] = "Prayer of Healing",
                ["level"] = 30,
            },
            [7] = {
                ["spell"] = "Holy Nova",
                ["level"] = 20,
            },
            [8] = {
                ["spell"] = "Shackle Undead",
                ["level"] = 20,
            },
            [9] = {
                ["spell"] = "Mind Control",
                ["level"] = 30,
            },
            [10] = {
                ["macro"] = "Flash Heal",
            },
            [11] = {
                ["spell"] = "Psychic Scream",
                ["level"] = 14,
            },
            [12] = {
                ["macro"] = "Penance",
            },
        },
        ["bar3"] = {
            [1] = {
                ["spell"] = "Power Word: Fortitude",
                ["level"] = 1,
            },
            [2] = {
                ["spell"] = "Divine Spirit",
                ["level"] = 30,
            },
            [3] = {
                ["spell"] = "Inner Fire",
                ["level"] = 12,
            },
            [4] = {
                ["spell"] = "Shadow Protection",
                ["level"] = 30,
            },
            [5] = {
                ["macro"] = "Resurrection",
            },
            [6] = {
                ["spell"] = "Levitate",
                ["level"] = 34,
            },
            [7] = {
                ["macro"] = "Abolish Disease",
            },
            [8] = {
                ["spell"] = "Fear Ward",
                ["level"] = 20,
            },
            [9] = {
                ["spell"] = "Prayer of Fortitude",
                ["level"] = 48,
            },
            [10] = {
                ["spell"] = "Prayer of Spirit",
                ["level"] = 60,
            },
            [11] = {
                ["spell"] = "Prayer of Shadow Protection",
                ["level"] = 56,
            },
            [12] = {
                ["spell"] = "Shadowform",
            },
        },
        ["bar4"] = {
            [1] = {
                ["spell"] = "Mind Blast",
                ["level"] = 10,
            },
            [2] = {
                ["spell"] = "Mind Flay",
                ["level"] = 20,
            },
            [3] = {
                ["spell"] = "Shadow Word: Death",
                ["level"] = 32,
            },
            [4] = {
                ["spell"] = "Devouring Plague",
                ["level"] = 20,
            },
            [5] = {
                ["spell"] = "Vampiric Embrace",
            },
            [6] = {
                ["spell"] = "Silence",
            },
            [7] = {
                ["spell"] = "Holy Fire",
                ["level"] = 20,
            },
            [8] = {
                ["macro"] = "Binding Heal",
            },
            [9] = {
                ["spell"] = "Mind Soothe",
                ["level"] = 20,
            },
            [10] = {
                ["spell"] = "Mind Vision",
                ["level"] = 22,
            },
            [11] = {
                ["spell"] = "Mana Burn",
                ["level"] = 24,
            },
            [12] = {
                ["macro"] = "Renew",
            },
        },
        ["bar5"] = {
            [1] = {
                ["spell"] = "Confounding Flash",
                ["level"] = 10,
            },
            [2] = {
                ["spell"] = "Starshards",
                ["level"] = 10,
            },
            [3] = {
                ["spell"] = "Contingency Plan",
                ["level"] = 20,
            },
            [4] = {
                ["spell"] = "Elune's Grace",
                ["level"] = 20,
            },
            [5] = {
                ["spell"] = "Feedback",
                ["level"] = 20,
            },
            [6] = {
                ["spell"] = "Divine Grace",
                ["level"] = 10,
            },
            [7] = {
                ["spell"] = "Chastise",
                ["level"] = 20,
            },
            [8] = {
                ["spell"] = "Hex of Weakness",
                ["level"] = 10,
            },
            [9] = {
                ["spell"] = "Touch of Weakness",
                ["level"] = 10,
            },
            [10] = {
                ["spell"] = "Dark Sacrifice",
                ["level"] = 20,
            },
            [11] = {
                ["spell"] = "Shadowguard",
                ["level"] = 20,
            },
        },
    },
    ["macros"] = {
        ["Penance"] = { icon = 237545, spells = { "Penance" },
            body = "#showtooltip Penance\n/cast [@mouseover,help,nodead][exists,nodead][@player] Penance" },
        ["Dispel Magic"] = { icon = 135894, spells = { "Dispel Magic" },
            body = "#showtooltip Dispel Magic\n/cast [@mouseover,help,nodead][exists,nodead][@player] Dispel Magic" },
        ["Power Infusion"] = { icon = 135939, spells = { "Power Infusion" },
            body = "#showtooltip Power Infusion\n/cast [@mouseover,help,nodead][help,nodead][@player] Power Infusion" },
        ["Resurrection"] = { icon = 135955, spells = { "Resurrection" },
            body = "#showtooltip Resurrection\n/cast [@mouseover,help,dead][help,dead] Resurrection" },
        ["Lesser Heal"] = {
            ["icon"] = 135929,
            ["body"] = "#showtooltip Lesser Heal\n/cast [@mouseover,help,nodead][help,nodead][@player] Lesser Heal",
            ["spells"] = {
                "Lesser Heal",
            },
        },
        ["Heal"] = {
            ["icon"] = 135915,
            ["body"] = "#showtooltip Heal\n/cast [@mouseover,help,nodead][help,nodead][@player] Heal",
            ["spells"] = {
                "Heal",
            },
        },
        ["Flash Heal"] = {
            ["icon"] = 135907,
            ["body"] = "#showtooltip Flash Heal\n/cast [@mouseover,help,nodead][help,nodead][@player] Flash Heal",
            ["spells"] = {
                "Flash Heal",
            },
        },
        ["Renew"] = {
            ["icon"] = 135953,
            ["body"] = "#showtooltip Renew\n/cast [@mouseover,help,nodead][help,nodead][@player] Renew",
            ["spells"] = {
                "Renew",
            },
        },
        ["Power Shield"] = {
            ["icon"] = 135940,
            ["body"] = "#showtooltip Power Word: Shield\n/cast [@mouseover,help,nodead][help,nodead][@player] Power Word: Shield",
            ["spells"] = {
                "Power Word: Shield",
            },
        },
        ["Greater Heal"] = {
            ["icon"] = 135913,
            ["body"] = "#showtooltip Greater Heal\n/cast [@mouseover,help,nodead][help,nodead][@player] Greater Heal",
            ["spells"] = {
                "Greater Heal",
            },
        },
        ["Binding Heal"] = {
            ["icon"] = 135883,
            ["body"] = "#showtooltip Binding Heal\n/cast [@mouseover,help,nodead][help,nodead][@player] Binding Heal",
            ["spells"] = {
                "Binding Heal",
            },
        },
        ["Mending"] = {
            ["icon"] = 135944,
            ["body"] = "#showtooltip Prayer of Mending\n/cast [@mouseover,help,nodead][help,nodead][@player] Prayer of Mending",
            ["spells"] = {
                "Prayer of Mending",
            },
        },
        ["Cure Disease"] = {
            ["icon"] = 135935,
            ["body"] = "#showtooltip Cure Disease\n/cast [@mouseover,help,nodead][help,nodead][@player] Cure Disease",
            ["spells"] = {
                "Cure Disease",
            },
        },
        ["Abolish Disease"] = {
            ["icon"] = 136066,
            ["body"] = "#showtooltip Abolish Disease\n/cast [@mouseover,help,nodead][help,nodead][@player] Abolish Disease",
            ["spells"] = {
                "Abolish Disease",
            },
        },
    },
    ["roleOverrides"] = {
        ["shadow"] = {
            ["main"] = {
                [1] = {
                    ["spell"] = "Mind Flay",
                    ["level"] = 20,
                },
                [2] = {
                    ["spell"] = "Mind Blast",
                    ["level"] = 10,
                },
                [3] = {
                    ["spell"] = "Shadow Word: Pain",
                    ["level"] = 4,
                },
                [4] = {
                    ["spell"] = "Devouring Plague",
                    ["level"] = 20,
                },
                [5] = {
                    ["spell"] = "Shadow Word: Death",
                    ["level"] = 32,
                },
                [6] = {
                    ["spell"] = "Vampiric Embrace",
                },
                [7] = {
                    ["spell"] = "Silence",
                },
                [9] = {
                    ["macro"] = "Power Shield",
                },
                [10] = {
                    ["macro"] = "Renew",
                },
            },
        },
    },
}

