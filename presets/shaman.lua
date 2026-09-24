-- Element-grouped totems: normal click/key first spell; Alt or right click second.
RikUI.Presets.SHAMAN = {
    ["class"] = "SHAMAN",
    ["version"] = 2,
    ["roleOrder"] = {
        "ele",
        "enh",
        "heal",
    },
    ["roles"] = {
        ["ele"] = {
            ["label"] = "Elemental",
            ["trees"] = {
                1,
            },
        },
        ["enh"] = {
            ["label"] = "Enhancement",
            ["trees"] = {
                2,
            },
        },
        ["heal"] = {
            ["label"] = "Restoration",
            ["trees"] = {
                3,
            },
        },
    },
    ["bars"] = {
        ["main"] = {
            [1] = {
                ["spell"] = "Lightning Bolt",
                ["level"] = 1,
            },
            [2] = {
                ["spell"] = "Flame Shock",
                ["level"] = 10,
            },
            [3] = {
                ["spell"] = "Earth Shock",
                ["level"] = 4,
            },
            [4] = {
                ["spell"] = "Frost Shock",
                ["level"] = 20,
            },
            [5] = {
                ["spell"] = "Chain Lightning",
                ["level"] = 32,
            },
            [6] = {
                ["spell"] = "Purge",
                ["level"] = 12,
            },
            [7] = {
                ["spell"] = "Lightning Shield",
                ["level"] = 8,
            },
            [8] = {
                ["spell"] = "Fire Nova",
                ["level"] = 12,
            },
            [9] = {
                ["macro"] = "Lesser Heal",
            },
            [10] = {
                ["macro"] = "Healing Wave",
            },
            [11] = {
                ["spell"] = "Lava Burst",
                ["level"] = 40,
            },
            [12] = {
                ["item"] = "Hearthstone",
            },
        },
        ["bar2"] = {
            [1] = {
                ["spell"] = "Nature's Swiftness",
            },
            [2] = {
                ["spell"] = "Rage of the Farseer",
            },
            [3] = {
                ["spell"] = "Mana Tide Totem",
                ["level"] = 40,
            },
            [4] = {
                ["macro"] = "Riptide",
            },
            [5] = {
                ["spell"] = "Water Shield",
            },
            [6] = {
                ["spell"] = "Totemic Recall",
                ["level"] = 20,
            },
            [7] = {
                ["spell"] = "Totemic Projection",
                ["level"] = 22,
            },
            [8] = {
                ["spell"] = "Tremor Totem",
                ["level"] = 18,
            },
            [9] = {
                ["macro"] = "Chain Heal",
            },
            [10] = {
                ["spell"] = "Ghost Wolf",
                ["level"] = 20,
            },
            [11] = {
                ["spell"] = "Earth Shock",
                ["level"] = 4,
            },
            [12] = {
                ["spell"] = "Grounding Totem",
                ["level"] = 30,
            },
        },
        ["bar3"] = {
            [1] = {
                ["macro"] = "Earth Totems",
            },
            [2] = {
                ["macro"] = "Fire Totems",
            },
            [3] = {
                ["macro"] = "Water Totems",
            },
            [4] = {
                ["macro"] = "Air Totems",
            },
            [5] = {
                ["spell"] = "Call of the Elements",
                ["level"] = 20,
            },
            [6] = {
                ["spell"] = "Call of the Ancestors",
                ["level"] = 30,
            },
            [7] = {
                ["spell"] = "Call of the Spirits",
                ["level"] = 40,
            },
            [8] = {
                ["spell"] = "Windfury Weapon",
                ["level"] = 30,
            },
            [9] = {
                ["spell"] = "Flametongue Weapon",
                ["level"] = 10,
            },
            [10] = {
                ["spell"] = "Rockbiter Weapon",
                ["level"] = 1,
            },
            [11] = {
                ["spell"] = "Frostbrand Weapon",
                ["level"] = 20,
            },
            [12] = {
                ["macro"] = "Ancestral Spirit",
            },
        },
        ["bar4"] = {
            [1] = {
                ["spell"] = "Stoneskin Totem",
                ["level"] = 4,
            },
            [2] = {
                ["spell"] = "Stoneclaw Totem",
                ["level"] = 8,
            },
            [3] = {
                ["spell"] = "Strength of Earth Totem",
                ["level"] = 10,
            },
            [4] = {
                ["spell"] = "Magma Totem",
                ["level"] = 26,
            },
            [5] = {
                ["spell"] = "Flametongue Totem",
                ["level"] = 28,
            },
            [6] = {
                ["spell"] = "Frost Resistance Totem",
                ["level"] = 24,
            },
            [7] = {
                ["spell"] = "Fire Resistance Totem",
                ["level"] = 28,
            },
            [8] = {
                ["spell"] = "Mana Spring Totem",
                ["level"] = 26,
            },
            [9] = {
                ["spell"] = "Poison Cleansing Totem",
                ["level"] = 22,
            },
            [10] = {
                ["spell"] = "Disease Cleansing Totem",
                ["level"] = 38,
            },
            [11] = {
                ["spell"] = "Nature Resistance Totem",
                ["level"] = 30,
            },
            [12] = {
                ["spell"] = "Windfury Totem",
                ["level"] = 32,
            },
        },
        ["bar5"] = {
            [1] = {
                ["spell"] = "Grace of Air Totem",
                ["level"] = 42,
            },
            [2] = {
                ["spell"] = "Windwall Totem",
                ["level"] = 36,
            },
            [3] = {
                ["spell"] = "Sentry Totem",
                ["level"] = 34,
            },
            [4] = {
                ["macro"] = "Water Breathing",
            },
            [5] = {
                ["macro"] = "Water Walking",
            },
            [6] = {
                ["spell"] = "Far Sight",
                ["level"] = 26,
            },
            [7] = {
                ["spell"] = "Astral Recall",
                ["level"] = 30,
            },
            [8] = {
                ["macro"] = "Cure Poison",
            },
            [9] = {
                ["macro"] = "Cure Disease",
            },
            [10] = {
                ["spell"] = "Stormstrike",
            },
        },
    },
    ["macros"] = {
        ["Ancestral Spirit"] = { icon = 136077, spells = { "Ancestral Spirit" },
            body = "#showtooltip Ancestral Spirit\n/cast [@mouseover,help,dead][help,dead] Ancestral Spirit" },
        ["Water Breathing"] = { icon = 136148, spells = { "Water Breathing" },
            body = "#showtooltip Water Breathing\n/cast [@mouseover,help,nodead][help,nodead][@player] Water Breathing" },
        ["Water Walking"] = { icon = 135863, spells = { "Water Walking" },
            body = "#showtooltip Water Walking\n/cast [@mouseover,help,nodead][help,nodead][@player] Water Walking" },
        ["Healing Wave"] = {
            ["icon"] = 136052,
            ["body"] = "#showtooltip Healing Wave\n/cast [@mouseover,help,nodead][help,nodead][@player] Healing Wave",
            ["spells"] = {
                "Healing Wave",
            },
        },
        ["Lesser Heal"] = {
            ["icon"] = 136043,
            ["body"] = "#showtooltip Lesser Healing Wave\n/cast [@mouseover,help,nodead][help,nodead][@player] Lesser Healing Wave",
            ["spells"] = {
                "Lesser Healing Wave",
            },
        },
        ["Chain Heal"] = {
            ["icon"] = 136042,
            ["body"] = "#showtooltip Chain Heal\n/cast [@mouseover,help,nodead][help,nodead][@player] Chain Heal",
            ["spells"] = {
                "Chain Heal",
            },
        },
        ["Riptide"] = {
            ["icon"] = 252995,
            ["body"] = "#showtooltip Riptide\n/cast [@mouseover,help,nodead][help,nodead][@player] Riptide",
            ["spells"] = {
                "Riptide",
            },
        },
        ["Cure Poison"] = {
            ["icon"] = 136067,
            ["body"] = "#showtooltip Cure Poison\n/cast [@mouseover,help,nodead][help,nodead][@player] Cure Poison",
            ["spells"] = {
                "Cure Poison",
            },
        },
        ["Cure Disease"] = {
            ["icon"] = 136083,
            ["body"] = "#showtooltip Cure Disease\n/cast [@mouseover,help,nodead][help,nodead][@player] Cure Disease",
            ["spells"] = {
                "Cure Disease",
            },
        },
        ["Earth Totems"] = {
            ["icon"] = 136102,
            ["body"] = "#showtooltip\n/cast [mod:alt][btn:2] Tremor Totem; Earthbind Totem",
            ["spells"] = {
                "Earthbind Totem",
                "Tremor Totem",
            },
        },
        ["Fire Totems"] = {
            ["icon"] = 135825,
            ["body"] = "#showtooltip\n/cast [mod:alt][btn:2] Magma Totem; Searing Totem",
            ["spells"] = {
                "Searing Totem",
                "Magma Totem",
            },
        },
        ["Water Totems"] = {
            ["icon"] = 135127,
            ["body"] = "#showtooltip\n/cast [mod:alt][btn:2] Mana Spring Totem; Healing Stream Totem",
            ["spells"] = {
                "Healing Stream Totem",
                "Mana Spring Totem",
            },
        },
        ["Air Totems"] = {
            ["icon"] = 136039,
            ["body"] = "#showtooltip\n/cast [mod:alt][btn:2] Windfury Totem; Grounding Totem",
            ["spells"] = {
                "Grounding Totem",
                "Windfury Totem",
            },
        },
    },
    ["roleOverrides"] = {
        ["enh"] = {
            ["main"] = {
                [1] = {
                    ["spell"] = "Stormstrike",
                },
                [2] = {
                    ["spell"] = "Earth Shock",
                    ["level"] = 4,
                },
                [3] = {
                    ["spell"] = "Flame Shock",
                    ["level"] = 10,
                },
                [5] = {
                    ["spell"] = "Fire Nova",
                    ["level"] = 12,
                },
            },
        },
        ["heal"] = {
            ["main"] = {
                [1] = {
                    ["macro"] = "Healing Wave",
                },
                [2] = {
                    ["macro"] = "Lesser Heal",
                },
                [3] = {
                    ["macro"] = "Chain Heal",
                },
                [4] = {
                    ["macro"] = "Riptide",
                },
                [5] = {
                    ["macro"] = "Cure Poison",
                },
                [6] = {
                    ["macro"] = "Cure Disease",
                },
                [7] = {
                    ["spell"] = "Water Shield",
                },
            },
        },
    },
}

