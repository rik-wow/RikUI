-- Class role layouts; spellbook and DB2 evidence: docs/class-presets.md.
RikUI.Presets.MAGE = {
    ["class"] = "MAGE",
    ["version"] = 1,
    ["roleOrder"] = {
        "frost",
        "fire",
        "arcane",
    },
    ["roles"] = {
        ["frost"] = {
            ["label"] = "Frost",
            ["trees"] = {
                3,
            },
        },
        ["fire"] = {
            ["label"] = "Fire",
            ["trees"] = {
                2,
            },
        },
        ["arcane"] = {
            ["label"] = "Arcane",
            ["trees"] = {
                1,
            },
        },
    },
    ["bars"] = {
        ["main"] = {
            [1] = {
                ["spell"] = "Frostbolt",
                ["level"] = 4,
            },
            [2] = {
                ["spell"] = "Ice Lance",
                ["level"] = 20,
            },
            [3] = {
                ["spell"] = "Fire Blast",
                ["level"] = 6,
            },
            [4] = {
                ["spell"] = "Cone of Cold",
                ["level"] = 26,
            },
            [5] = {
                ["spell"] = "Blizzard",
                ["level"] = 20,
            },
            [6] = {
                ["spell"] = "Polymorph",
                ["level"] = 8,
            },
            [7] = {
                ["spell"] = "Frost Nova",
                ["level"] = 10,
            },
            [8] = {
                ["spell"] = "Counterspell",
                ["level"] = 24,
            },
            [9] = {
                ["spell"] = "Arcane Explosion",
                ["level"] = 14,
            },
            [10] = {
                ["spell"] = "Mana Shield",
                ["level"] = 20,
            },
            [11] = {
                ["spell"] = "Remove Lesser Curse",
                ["level"] = 18,
            },
            [12] = {
                ["item"] = "Hearthstone",
            },
        },
        ["bar2"] = {
            [1] = {
                ["spell"] = "Evocation",
                ["level"] = 20,
            },
            [2] = {
                ["spell"] = "Ice Block",
            },
            [3] = {
                ["spell"] = "Cold Snap",
            },
            [4] = {
                ["spell"] = "Ice Barrier",
                ["level"] = 40,
            },
            [5] = {
                ["spell"] = "Presence of Mind",
            },
            [6] = {
                ["spell"] = "Arcane Power",
            },
            [7] = {
                ["spell"] = "Combustion",
            },
            [8] = {
                ["spell"] = "Blast Wave",
                ["level"] = 30,
            },
            [9] = {
                ["spell"] = "Flamestrike",
                ["level"] = 16,
            },
            [10] = {
                ["spell"] = "Blink",
                ["level"] = 20,
            },
            [11] = {
                ["spell"] = "Counterspell",
                ["level"] = 24,
            },
            [12] = {
                ["spell"] = "Slow Fall",
                ["level"] = 12,
            },
        },
        ["bar3"] = {
            [1] = {
                ["spell"] = "Arcane Intellect",
                ["level"] = 1,
            },
            [2] = {
                ["spell"] = "Conjure Water",
                ["level"] = 4,
            },
            [3] = {
                ["spell"] = "Conjure Food",
                ["level"] = 6,
            },
            [4] = {
                ["spell"] = "Frost Armor",
                ["level"] = 1,
            },
            [5] = {
                ["spell"] = "Ice Armor",
                ["level"] = 30,
            },
            [6] = {
                ["spell"] = "Mage Armor",
                ["level"] = 34,
            },
            [7] = {
                ["spell"] = "Dampen Magic",
                ["level"] = 12,
            },
            [8] = {
                ["spell"] = "Amplify Magic",
                ["level"] = 18,
            },
            [9] = {
                ["spell"] = "Fire Ward",
                ["level"] = 20,
            },
            [10] = {
                ["spell"] = "Frost Ward",
                ["level"] = 22,
            },
            [11] = {
                ["spell"] = "Conjure Mana Agate",
                ["level"] = 28,
            },
            [12] = {
                ["spell"] = "Conjure Mana Jade",
                ["level"] = 38,
            },
        },
        ["bar4"] = {
            [1] = {
                ["spell"] = "Fireball",
                ["level"] = 1,
            },
            [2] = {
                ["spell"] = "Pyroblast",
                ["level"] = 20,
            },
            [3] = {
                ["spell"] = "Scorch",
                ["level"] = 22,
            },
            [4] = {
                ["spell"] = "Arcane Missiles",
                ["level"] = 8,
            },
            [5] = {
                ["spell"] = "Arcane Blast",
                ["level"] = 20,
            },
            [6] = {
                ["spell"] = "Frostfire Bolt",
                ["level"] = 40,
            },
            [7] = {
                ["spell"] = "Felfire",
                ["level"] = 60,
            },
            [8] = {
                ["spell"] = "Arcane Brilliance",
                ["level"] = 56,
            },
            [9] = {
                ["spell"] = "Conjure Mana Citrine",
                ["level"] = 48,
            },
            [10] = {
                ["spell"] = "Conjure Mana Ruby",
                ["level"] = 58,
            },
            [11] = {
                ["spell"] = "Comprehend Scroll",
                ["level"] = 6,
            },
            [12] = {
                ["spell"] = "Polymorph: Cow",
                ["level"] = 60,
            },
        },
        ["bar5"] = {
            [1] = {
                ["spell"] = "Teleport: Stormwind",
                ["level"] = 20,
            },
            [2] = {
                ["spell"] = "Teleport: Ironforge",
                ["level"] = 20,
            },
            [3] = {
                ["spell"] = "Teleport: Darnassus",
                ["level"] = 30,
            },
            [4] = {
                ["spell"] = "Teleport: Orgrimmar",
                ["level"] = 20,
            },
            [5] = {
                ["spell"] = "Teleport: Undercity",
                ["level"] = 20,
            },
            [6] = {
                ["spell"] = "Teleport: Thunder Bluff",
                ["level"] = 30,
            },
            [7] = {
                ["spell"] = "Portal: Stormwind",
                ["level"] = 40,
            },
            [8] = {
                ["spell"] = "Portal: Ironforge",
                ["level"] = 40,
            },
            [9] = {
                ["spell"] = "Portal: Darnassus",
                ["level"] = 50,
            },
            [10] = {
                ["spell"] = "Portal: Orgrimmar",
                ["level"] = 40,
            },
            [11] = {
                ["spell"] = "Portal: Undercity",
                ["level"] = 40,
            },
            [12] = {
                ["spell"] = "Portal: Thunder Bluff",
                ["level"] = 50,
            },
        },
    },
    ["macros"] = {},
    ["roleOverrides"] = {
        ["fire"] = {
            ["main"] = {
                [1] = {
                    ["spell"] = "Fireball",
                    ["level"] = 1,
                },
                [2] = {
                    ["spell"] = "Scorch",
                    ["level"] = 22,
                },
                [4] = {
                    ["spell"] = "Pyroblast",
                    ["level"] = 20,
                },
                [5] = {
                    ["spell"] = "Flamestrike",
                    ["level"] = 16,
                },
            },
        },
        ["arcane"] = {
            ["main"] = {
                [1] = {
                    ["spell"] = "Arcane Missiles",
                    ["level"] = 8,
                },
                [2] = {
                    ["spell"] = "Arcane Blast",
                    ["level"] = 20,
                },
                [4] = {
                    ["spell"] = "Arcane Explosion",
                    ["level"] = 14,
                },
            },
        },
    },
}

