-- Named form keys and native Cat/Bear pages; evidence: docs/class-presets.md.
RikUI.Presets.DRUID = {
    ["class"] = "DRUID",
    ["version"] = 1,
    ["roleOrder"] = {
        "feral",
        "balance",
        "heal",
        "tank",
    },
    ["roles"] = {
        ["feral"] = {
            ["label"] = "Feral / Cat",
            ["trees"] = {
                2,
            },
        },
        ["balance"] = {
            ["label"] = "Balance",
            ["trees"] = {
                1,
            },
        },
        ["heal"] = {
            ["label"] = "Restoration",
            ["trees"] = {
                3,
            },
        },
        ["tank"] = {
            ["label"] = "Feral / Bear tank",
            ["trees"] = {
                2,
            },
        },
    },
    ["bars"] = {
        ["main"] = {
            [1] = {
                ["spell"] = "Wrath",
                ["level"] = 1,
            },
            [2] = {
                ["spell"] = "Moonfire",
                ["level"] = 4,
            },
            [3] = {
                ["spell"] = "Starfire",
                ["level"] = 20,
            },
            [4] = {
                ["spell"] = "Insect Swarm",
                ["level"] = 20,
            },
            [5] = {
                ["spell"] = "Hurricane",
                ["level"] = 40,
            },
            [6] = {
                ["spell"] = "Entangling Roots",
                ["level"] = 8,
            },
            [7] = {
                ["spell"] = "Faerie Fire",
                ["level"] = 18,
            },
            [8] = {
                ["spell"] = "Hibernate",
                ["level"] = 18,
            },
            [9] = {
                ["macro"] = "Healing Touch",
            },
            [10] = {
                ["macro"] = "Regrowth",
            },
            [11] = {
                ["macro"] = "Rejuvenation",
            },
            [12] = {
                ["item"] = "Hearthstone",
            },
        },
        ["cat"] = {
            [1] = {
                ["spell"] = "Claw",
                ["level"] = 20,
            },
            [2] = {
                ["spell"] = "Rake",
                ["level"] = 24,
            },
            [3] = {
                ["spell"] = "Shred",
                ["level"] = 22,
            },
            [4] = {
                ["spell"] = "Rip",
                ["level"] = 20,
            },
            [5] = {
                ["spell"] = "Ferocious Bite",
                ["level"] = 32,
            },
            [6] = {
                ["spell"] = "Pounce",
                ["level"] = 36,
            },
            [7] = {
                ["spell"] = "Ravage",
                ["level"] = 32,
            },
            [8] = {
                ["spell"] = "Feral Charge",
            },
            [9] = {
                ["spell"] = "Tiger's Fury",
                ["level"] = 24,
            },
            [10] = {
                ["spell"] = "Prowl",
                ["level"] = 20,
            },
            [11] = {
                ["spell"] = "Mangle",
            },
            [12] = {
                ["item"] = "Hearthstone",
            },
        },
        ["bear"] = {
            [1] = {
                ["spell"] = "Maul",
                ["level"] = 10,
            },
            [2] = {
                ["spell"] = "Swipe",
                ["level"] = 16,
            },
            [3] = {
                ["spell"] = "Lacerate",
                ["level"] = 42,
            },
            [4] = {
                ["spell"] = "Mangle",
            },
            [5] = {
                ["spell"] = "Demoralizing Roar",
                ["level"] = 10,
            },
            [6] = {
                ["spell"] = "Growl",
                ["level"] = 10,
            },
            [7] = {
                ["spell"] = "Bash",
                ["level"] = 14,
            },
            [8] = {
                ["spell"] = "Feral Charge",
            },
            [9] = {
                ["spell"] = "Enrage",
                ["level"] = 12,
            },
            [10] = {
                ["spell"] = "Frenzied Regeneration",
            },
            [11] = {
                ["spell"] = "Challenging Roar",
                ["level"] = 28,
            },
            [12] = {
                ["item"] = "Hearthstone",
            },
        },
        ["bar2"] = {
            [1] = {
                ["spell"] = "Barkskin",
                ["level"] = 44,
            },
            [2] = {
                ["spell"] = "Berserk",
            },
            [3] = {
                ["spell"] = "Nature's Swiftness",
            },
            [4] = {
                ["spell"] = "Innervate",
                ["level"] = 40,
            },
            [5] = {
                ["spell"] = "Tranquility",
                ["level"] = 30,
            },
            [6] = {
                ["spell"] = "Rebirth",
                ["level"] = 20,
            },
            [7] = {
                ["macro"] = "Swiftmend",
            },
            [8] = {
                ["macro"] = "Wild Growth",
            },
            [9] = {
                ["spell"] = "Nature's Grasp",
                ["level"] = 10,
            },
            [10] = {
                ["spell"] = "Dash",
                ["level"] = 26,
            },
            [11] = {
                ["spell"] = "Bash",
                ["level"] = 14,
            },
            [12] = {
                ["spell"] = "Challenging Roar",
                ["level"] = 28,
            },
        },
        ["bar3"] = {
            [1] = {
                ["macro"] = "Bear Form",
            },
            [2] = {
                ["spell"] = "Cat Form",
                ["level"] = 20,
            },
            [3] = {
                ["spell"] = "Moonkin Form",
            },
            [4] = {
                ["spell"] = "Travel Form",
                ["level"] = 30,
            },
            [5] = {
                ["spell"] = "Aquatic Form",
                ["level"] = 16,
            },
            [6] = {
                ["spell"] = "Mark of the Wild",
                ["level"] = 1,
            },
            [7] = {
                ["spell"] = "Thorns",
                ["level"] = 6,
            },
            [8] = {
                ["spell"] = "Gift of the Wild",
                ["level"] = 50,
            },
            [9] = {
                ["spell"] = "Revive",
                ["level"] = 12,
            },
            [10] = {
                ["spell"] = "Teleport: Moonglade",
                ["level"] = 10,
            },
            [11] = {
                ["macro"] = "Cure Poison",
            },
            [12] = {
                ["macro"] = "Remove Curse",
            },
        },
        ["bar4"] = {
            [1] = {
                ["macro"] = "Abolish Poison",
            },
            [2] = {
                ["macro"] = "Healing Touch",
            },
            [3] = {
                ["macro"] = "Regrowth",
            },
            [4] = {
                ["macro"] = "Rejuvenation",
            },
            [5] = {
                ["spell"] = "Cower",
                ["level"] = 28,
            },
            [6] = {
                ["spell"] = "Soothe Animal",
                ["level"] = 22,
            },
            [7] = {
                ["spell"] = "Track Humanoids",
                ["level"] = 32,
            },
            [8] = {
                ["spell"] = "Prowl",
                ["level"] = 20,
            },
            [9] = {
                ["spell"] = "Omen of Clarity",
                ["level"] = 20,
            },
            [10] = {
                ["spell"] = "Dire Bear Form",
                ["level"] = 40,
            },
        },
        ["bar5"] = {},
    },
    ["macros"] = {
        ["Healing Touch"] = {
            ["icon"] = 136041,
            ["body"] = "#showtooltip Healing Touch\n/cast [@mouseover,help,nodead][help,nodead][@player] Healing Touch",
            ["spells"] = {
                "Healing Touch",
            },
        },
        ["Rejuvenation"] = {
            ["icon"] = 136081,
            ["body"] = "#showtooltip Rejuvenation\n/cast [@mouseover,help,nodead][help,nodead][@player] Rejuvenation",
            ["spells"] = {
                "Rejuvenation",
            },
        },
        ["Regrowth"] = {
            ["icon"] = 136085,
            ["body"] = "#showtooltip Regrowth\n/cast [@mouseover,help,nodead][help,nodead][@player] Regrowth",
            ["spells"] = {
                "Regrowth",
            },
        },
        ["Wild Growth"] = {
            ["icon"] = 236153,
            ["body"] = "#showtooltip Wild Growth\n/cast [@mouseover,help,nodead][help,nodead][@player] Wild Growth",
            ["spells"] = {
                "Wild Growth",
            },
        },
        ["Swiftmend"] = {
            ["icon"] = 134914,
            ["body"] = "#showtooltip Swiftmend\n/cast [@mouseover,help,nodead][help,nodead][@player] Swiftmend",
            ["spells"] = {
                "Swiftmend",
            },
        },
        ["Cure Poison"] = {
            ["icon"] = 136067,
            ["body"] = "#showtooltip Cure Poison\n/cast [@mouseover,help,nodead][help,nodead][@player] Cure Poison",
            ["spells"] = {
                "Cure Poison",
            },
        },
        ["Abolish Poison"] = {
            ["icon"] = 136068,
            ["body"] = "#showtooltip Abolish Poison\n/cast [@mouseover,help,nodead][help,nodead][@player] Abolish Poison",
            ["spells"] = {
                "Abolish Poison",
            },
        },
        ["Remove Curse"] = {
            ["icon"] = 135952,
            ["body"] = "#showtooltip Remove Curse\n/cast [@mouseover,help,nodead][help,nodead][@player] Remove Curse",
            ["spells"] = {
                "Remove Curse",
            },
        },
        ["Bear Form"] = {
            ["icon"] = 132276,
            ["body"] = "#showtooltip\n/cast [known:9634] Dire Bear Form; Bear Form",
            ["spells"] = {
                "Bear Form",
                "Dire Bear Form",
            },
        },
    },
    ["roleOverrides"] = {
        ["balance"] = {
            ["main"] = {
                [1] = {
                    ["spell"] = "Starfire",
                    ["level"] = 20,
                },
                [3] = {
                    ["spell"] = "Wrath",
                    ["level"] = 1,
                },
            },
        },
        ["heal"] = {
            ["main"] = {
                [1] = {
                    ["macro"] = "Healing Touch",
                },
                [2] = {
                    ["macro"] = "Rejuvenation",
                },
                [3] = {
                    ["macro"] = "Regrowth",
                },
                [4] = {
                    ["macro"] = "Wild Growth",
                },
                [5] = {
                    ["macro"] = "Swiftmend",
                },
                [6] = {
                    ["macro"] = "Remove Curse",
                },
                [7] = {
                    ["macro"] = "Abolish Poison",
                },
                [8] = {
                    ["spell"] = "Innervate",
                    ["level"] = 40,
                },
            },
        },
        ["tank"] = {
            ["main"] = {
                [1] = {
                    ["macro"] = "Bear Form",
                },
            },
        },
    },
}

