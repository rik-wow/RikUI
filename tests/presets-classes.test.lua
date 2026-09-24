-- Cross-class catalogue and preset integration; callable by the standard runner.
return function(check)
    package.path = "tests/?.lua;" .. package.path
    require("wow_stub")
    local loader = dofile("tests/load_addon.lua")
    RikUI, RikUIDB, RikUICharDB = nil, nil, nil
    loader.Core()
    for _, path in ipairs(loader.Manifest()) do
        if path:match("^data/spells") or path == "data/bonus-pages.lua" or path:match("^presets/") then assert(loadfile(path))() end
    end
    assert(loadfile("src/setup/setup.lua"))()
    local class = "HUNTER"
    local preset = RikUI.Presets[class]
    check("Hunter has a bundled class preset", type(preset) == "table")
    assert(preset, "Hunter preset missing")
    check("Hunter preset validates", #RikUI.Setup.ValidatePreset(preset) == 0)
    local data = RikUI.SpellCatalogs[class]
    check("Hunter source ranks retain Aimed Shot at 20", data["Aimed Shot"].level == 20
        and data["Aimed Shot"].ranks[1] == 19434)
    check("unknown talent acquisition stays unknown", data["Strider Kick"].level == nil)
    local resolved = assert(RikUI.Setup.Resolve(class))
    check("Hunter pet attack is on Mouse4 and trap stays reachable", resolved.bars.bar2[10].macro == "Pet Attack"
        and resolved.bars.main[7].spell == "Freezing Trap")
    local oldClass = UnitClass
    UnitClass = function() return "Hunter", "HUNTER" end
    check("lookup isolates Hunter catalogue from Warrior", RikUI.Spells.Entry("Arcane Shot") == data["Arcane Shot"]
        and RikUI.Spells.Entry("Heroic Strike") == nil)
    UnitClass = oldClass

    local mage = RikUI.Presets.MAGE
    check("Mage has Frost Fire and Arcane presets", mage and mage.roles.frost and mage.roles.fire and mage.roles.arcane)
    assert(mage, "Mage preset missing")
    local frost = assert(RikUI.Setup.Resolve("MAGE", "frost"))
    local fire = assert(RikUI.Setup.Resolve("MAGE", "fire"))
    local arcane = assert(RikUI.Setup.Resolve("MAGE", "arcane"))
    check("Mage rotations switch without changing movement and interrupt", frost.bars.main[1].spell == "Frostbolt"
        and fire.bars.main[1].spell == "Fireball" and arcane.bars.main[1].spell == "Arcane Missiles"
        and frost.bars.bar2[10].spell == "Blink" and fire.bars.bar2[11].spell == "Counterspell")
    check("Forever talent IDs are preserved rather than modern replacements",
        RikUI.Spells.Entry("Ice Block", "MAGE").ranks[1] == 11958
        and RikUI.Spells.Entry("Cold Snap", "MAGE").ranks[1] == 12472)


    local rogue = assert(RikUI.Presets.ROGUE, "Rogue preset missing")
    local stealth = assert(RikUI.Setup.Resolve("ROGUE"))
    check("Rogue stealth openers inherit control and hearthstone", stealth.bars.stealth[1].spell == "Ambush"
        and stealth.bars.stealth[3].spell == "Cheap Shot" and stealth.bars.stealth[8].spell == "Kick"
        and stealth.bars.stealth[12].item == "Hearthstone")
    check("Rogue stealth targets native bonus slots", RikUI.Setup.SlotToAction("stealth", 1) == 73
        and RikUI.Data.BonusPages.ROGUE[1].offset == 1)
    check("Rogue poison recipes retain distinct rank families", RikUI.Spells.Entry("Instant Poison II", "ROGUE")
        and RikUI.Spells.Entry("Instant Poison", "ROGUE"))


    local priest = assert(RikUI.Presets.PRIEST, "Priest preset missing")
    local healing = assert(RikUI.Setup.Resolve("PRIEST", "heal"))
    local shadow = assert(RikUI.Setup.Resolve("PRIEST", "shadow"))
    check("Priest healer and shadow rotations differ", healing.bars.main[1].macro == "Lesser Heal"
        and shadow.bars.main[1].spell == "Mind Flay")
    check("Shadow retains mouseover healing and has no fabricated bonus page",
        shadow.bars.bar2[10].macro == "Flash Heal" and shadow.bars.shadow == nil
        and RikUI.Data.BonusPages.PRIEST == nil)
    check("Priest heals prefer living mouseover then target then self",
        priest.macros["Flash Heal"].body == "#showtooltip Flash Heal\n/cast [@mouseover,help,nodead][help,nodead][@player] Flash Heal")


    local savedTalents, savedTraits = C_ClassTalents, C_Traits
    assert(loadfile("src/setup/setup-talents.lua"))()
    local points = { 0, 0, 0 }
    C_ClassTalents = { GetActiveConfigID = function() return 1 end }
    C_Traits = {
        ConfigHasStagedChanges = function() return false end,
        GetConfigInfo = function() return { treeIDs = { 1 } } end,
        GetGroupDisplayInfoByTreeID = function() return {
            { groupID = 1, displayName = "First" }, { groupID = 2, displayName = "Second" },
            { groupID = 3, displayName = "Third" } } end,
        GetGroupCurrencyInfo = function()
            local groups = {}
            for i = 1, 3 do groups[i] = { traitNodeGroupID = i, currencyInfos = { { spent = points[i] } } } end
            return groups
        end,
    }
    for tree, expected in ipairs({ "heal", "heal", "shadow" }) do
        points = { 0, 0, 0 }; points[tree] = 10
        check("Priest ten-point tree " .. tree .. " chooses " .. expected,
            RikUI.Setup.GuessRole("PRIEST") == expected)
    end
    C_ClassTalents, C_Traits = savedTalents, savedTraits

    local savedBook, savedEnum = C_SpellBook, Enum
    Enum = { SpellBookSpellBank = { Player = 1 }, SpellBookItemType = { Spell = 1 } }
    local learned = {}
    C_SpellBook = {
        GetNumSpellBookSkillLines = function() return 1 end,
        GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #learned } end,
        GetSpellBookItemInfo = function(i) return { spellID = learned[i], itemType = 1 } end,
    }
    for _, sample in ipairs({ { "HUNTER", "Arcane Shot" }, { "MAGE", "Frostbolt" }, { "PRIEST", "Renew" } }) do
        UnitClass = function() return sample[1], sample[1] end
        local ranks = RikUI.Spells.Entry(sample[2]).ranks
        learned = { ranks[1], ranks[#ranks] }
        check(sample[1] .. " resolver selects highest learned rank", RikUI.Spells.HighestKnownRank(sample[2]) == ranks[#ranks])
        learned = { ranks[1] }
        check(sample[1] .. " unlearning does not leave a stale high rank", RikUI.Spells.HighestKnownRank(sample[2]) == ranks[1])
    end
    UnitClass, C_SpellBook, Enum = oldClass, savedBook, savedEnum

    for class, current in pairs(RikUI.Presets) do
        check(class .. " catalogue validates every page and role", #RikUI.Setup.ValidatePreset(current) == 0)
        for _, role in ipairs(current.roleOrder) do
            local page = assert(RikUI.Setup.Resolve(class, role))
            check(class .. " " .. role .. " retains Hearthstone", page.bars.main[12].item == "Hearthstone")
        end
        for name, macro in pairs(current.macros) do
            check(class .. " macro size " .. name, #name <= 16 and #macro.body <= 255 and type(macro.icon) == "number")
        end
    end
end

