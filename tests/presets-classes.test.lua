-- Exercise each declared role/page against actual class catalogue IDs and the spellbook reader.
local function levelingChecks(check, class, cases)
    local oldClass, oldBook, oldEnum = UnitClass, C_SpellBook, Enum
    local known = {}
    UnitClass = function() return class, class end
    Enum = { SpellBookSpellBank = { Player = 1 }, SpellBookItemType = { Spell = 1 } }
    C_SpellBook = {
        GetNumSpellBookSkillLines = function() return 1 end,
        GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #known } end,
        GetSpellBookItemInfo = function(index) return { itemType = 1, spellID = known[index] } end,
    }
    for _, case in ipairs(cases) do
        local role, page, slot, primary, fallback = unpack(case)
        local resolved = assert(RikUI.Setup.Resolve(class, role))
        local entry = resolved.bars[page][slot]
        local label = class .. " " .. role .. " " .. page .. "/" .. slot
        check(label .. " keeps the intended primary and starter", entry.spell == primary and entry.fallback == fallback)
        local first, second = RikUI.Spells.Entry(primary, class), RikUI.Spells.Entry(fallback, class)
        known = {}
        check(label .. " grants neither spell by level", RikUI.Setup.KnownSpell(entry, class) == nil)
        known = { second.ranks[1], second.ranks[#second.ranks] }
        check(label .. " selects highest learned starter rank", RikUI.Setup.KnownSpell(entry, class) == second.ranks[#second.ranks])
        known[#known + 1], known[#known + 2] = first.ranks[1], first.ranks[#first.ranks]
        check(label .. " promotes highest learned primary rank", RikUI.Setup.KnownSpell(entry, class) == first.ranks[#first.ranks])
        check(label .. " keeps resolution declarative", entry.spell == primary)
    end
    UnitClass, C_SpellBook, Enum = oldClass, oldBook, oldEnum
end

-- Learned fallback selection, validation, placement and preview.
local function fallbackChecks(check)
    require("wow_stub")
    local loader = dofile("tests/load_addon.lua")
    RikUI, RikUIDB, RikUICharDB = nil, nil, nil
    loader.Core()
    assert(loadfile("data/spells.lua"))()
    assert(loadfile("src/setup/setup.lua"))()
    assert(loadfile("src/setup/setup-actions.lua"))()
    local setup = RikUI.Setup
    local entry = { spell = "Mortal Strike", level = 40, fallback = "Rend" }
    local preset = { class = "WARRIOR", roles = { dps = {} }, macros = {}, bars = { main = { entry }, battle = {} } }
    RikUI.Presets.WARRIOR = preset
    check("valid fallback belongs to the same class", #setup.ValidatePreset(preset) == 0)
    for _, bad in ipairs({ "", "Moonfire", "Mortal Strike", true, {} }) do
        entry.fallback = bad
        check("malformed or unresolved fallback rejected " .. tostring(bad), #setup.ValidatePreset(preset) > 0)
    end
    entry.fallback = "Rend"
    preset.bars.main[2] = { item = "Hearthstone", fallback = "Rend" }
    check("fallback rejected on nonspell actions", #setup.ValidatePreset(preset) > 0)
    preset.bars.main[2] = nil
    local resolved = assert(setup.Resolve("WARRIOR"))
    check("fallback survives inherited pages", resolved.bars.battle[1].fallback == "Rend")
    check("fallback selector exists", type(setup.KnownSpell) == "function")
    if not setup.KnownSpell then return end
    local original = RikUI.Spells.HighestKnownRank
    local known, failure, requestedClass = {}, nil, nil
    RikUI.Spells.HighestKnownRank = function(name, class)
        requestedClass = class
        return known[name], failure, known[name] and 1
    end
    local id, reason, rank, name = setup.KnownSpell(entry, "WARRIOR")
    check("neither spell learned leaves slot empty", id == nil and reason == nil)
    known.Rend = 772
    id, reason, rank, name = setup.KnownSpell(entry, "WARRIOR")
    check("learned fallback wins with explicit class", id == 772 and name == "Rend" and requestedClass == "WARRIOR")
    known["Mortal Strike"] = 12294
    id, reason, rank, name = setup.KnownSpell(entry, "WARRIOR")
    check("primary wins when both are learned", id == 12294 and name == "Mortal Strike")
    failure = "Spellbook lookup failed"
    id, reason = setup.KnownSpell(entry, "WARRIOR")
    check("book error is never treated as unlearned", id == nil and reason == failure)
    failure, known["Mortal Strike"] = nil, nil
    local restore, written = setup.RestoreSlot
    setup.RestoreSlot = function(slot, action) written = action; return {} end
    setup.WriteSlot(1, entry, preset)
    check("Apply writes the learned fallback", written and written.id == 772)
    setup.RestoreSlot = restore
    assert(loadfile("src/configuration/wizard/wizard-preview.lua"))()
    local icon, label, ready = RikUI.WizardPreview.Details(entry, preset, 10)
    check("preview explains actual action and later upgrade", ready and icon == RikUI.SpellData.Rend.icon
        and label:find("Rend", 1, true) and label:find("Mortal Strike", 1, true))
    RikUI.Spells.HighestKnownRank = original
end

-- Cross-class catalogue and preset integration; callable by the standard runner.
return function(check)
    package.path = "tests/?.lua;" .. package.path
    require("wow_stub")
    local loader = dofile("tests/load_addon.lua")
    RikUI, RikUIDB, RikUICharDB = nil, nil, nil
    loader.Core()
    for _, path in ipairs(loader.Manifest()) do
        if path:match("^data/spells") or path == "data/bonus-pages.lua" or path == "data/racials.lua" or path:match("^presets/") then assert(loadfile(path))() end
    end
    assert(loadfile("src/setup/setup.lua"))()
    assert(loadfile("src/setup/setup-racials.lua"))()
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


    for _, role in ipairs(mage.roleOrder) do
        local page = RikUI.Setup.Resolve("MAGE", role)
        check("Mage " .. role .. " can decurse without retargeting", page.bars.main[11].macro == "Remove Curse"
            and page.bars.bar3[1].macro == "Intellect")
        check("Mage " .. role .. " preserves movement and interrupt", page.bars.bar2[10].spell == "Blink"
            and page.bars.bar2[11].spell == "Counterspell")
    end
    for _, name in ipairs({ "Remove Curse", "Intellect", "Dampen Magic", "Amplify Magic" }) do
        local macro = mage.macros[name]
        check("Mage friendly utility " .. name .. " is learned and mouseover gated", macro and macro.spells
            and macro.body:find("[@mouseover,help,nodead][help,nodead][@player]", 1, true))
    end

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


    for _, role in ipairs(priest.roleOrder) do
        local page = RikUI.Setup.Resolve("PRIEST", role)
        check("Priest " .. role .. " exposes targeted utility", page.bars.main[8].macro == "Dispel Magic"
            and page.bars.bar2[12].macro == "Penance" and page.bars.bar3[5].macro == "Resurrection")
    end
    for _, name in ipairs({ "Penance", "Dispel Magic" }) do
        local macro = priest.macros[name]
        check("Priest " .. name .. " supports friendly mouseover without losing hostile target", macro
            and macro.body:find("[@mouseover,help,nodead][exists,nodead][@player]", 1, true)
            and macro.spells[1] == name)
    end
    check("Priest resurrection only selects dead friendly units", priest.macros.Resurrection
        and priest.macros.Resurrection.body:find("[@mouseover,help,dead][help,dead]", 1, true)
        and not priest.macros.Resurrection.body:find("@player", 1, true))
    check("Priest Power Infusion is learned-gated friendly utility", priest.macros["Power Infusion"]
        and priest.macros["Power Infusion"].spells[1] == "Power Infusion")

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
    for tree, expected in ipairs({ "dps", "fury", "tank" }) do
        points = { 0, 0, 0 }; points[tree] = 10
        check("Warrior tree selects " .. expected, RikUI.Setup.GuessRole("WARRIOR") == expected)
    end
    local fury = RikUI.Setup.Resolve("WARRIOR", "fury")
    check("Fury promotes Bloodthirst through stance pages", fury and fury.bars.main[1].spell == "Bloodthirst"
        and fury.bars.berserker[1].spell == "Bloodthirst" and fury.bars.bar5[11].spell == "Heroic Strike")
    check("Arms and tank promote talent strikes", RikUI.Setup.Resolve("WARRIOR", "dps").bars.main[2].spell == "Mortal Strike"
        and RikUI.Setup.Resolve("WARRIOR", "tank").bars.defensive[2].spell == "Shield Slam")

    for tree, expected in ipairs({ "assassination", "dps", "subtlety" }) do
        points = { 0, 0, 0 }; points[tree] = 10
        check("Rogue tree selects " .. expected, RikUI.Setup.GuessRole("ROGUE") == expected)
    end
    for _, sample in ipairs({ { "assassination", "Mutilate" }, { "subtlety", "Hemorrhage" } }) do
        local current = RikUI.Setup.Resolve("ROGUE", sample[1])
        check("Rogue " .. sample[1] .. " puts builder on main", current and current.bars.main[1].spell == sample[2])
        check("Rogue " .. sample[1] .. " retains openers and interrupt", current
            and current.bars.stealth[1].spell == "Ambush" and current.bars.stealth[8].spell == "Kick"
            and current.bars.bar4[9].spell == "Sinister Strike")
    end

    for tree, expected in ipairs({ "beast", "dps", "survival" }) do
        points = { 0, 0, 0 }; points[tree] = 10
        check("Hunter tree selects " .. expected, RikUI.Setup.GuessRole("HUNTER") == expected)
    end
    local melee = RikUI.Setup.Resolve("HUNTER", "survival")
    local beast = RikUI.Setup.Resolve("HUNTER", "beast")
    check("Hunter Survival makes melee attacks primary", melee and melee.bars.main[1].spell == "Raptor Strike"
        and melee.bars.main[3].spell == "Mongoose Bite" and melee.bars.main[4].spell == "Lacerate")
    check("Hunter Survival preserves ranged fallback and pet controls", melee and melee.bars.bar4[2].spell == "Aimed Shot"
        and melee.bars.bar2[10].macro == "Pet Attack" and melee.bars.main[7].spell == "Freezing Trap")
    check("Hunter Beast Mastery exposes hawk and retains Arcane Shot", beast and beast.bars.main[3].spell == "Summon Hawk"
        and beast.bars.bar4[1].spell == "Arcane Shot")
    check("Hunter Survival retains threat shot and sniper utility", melee and melee.bars.bar4[12].spell == "Distracting Shot"
        and melee.bars.extra[1].spell == "Sniper Shot")
    for _, role in ipairs(preset.roleOrder) do
        local current = RikUI.Setup.Resolve("HUNTER", role)
        local found = {}
        for _, slots in pairs(current.bars) do
            for _, entry in pairs(slots) do found[entry.spell or entry.macro or entry.item] = true end
        end
        for _, slots in pairs(preset.bars) do
            for _, entry in pairs(slots) do
                check("Hunter " .. role .. " preserves " .. (entry.spell or entry.macro or entry.item),
                    found[entry.spell or entry.macro or entry.item])
            end
        end
    end
    check("Hunter legacy dps marker resolves to Marksmanship", RikUI.Setup.Resolve("HUNTER", "dps").bars.main[1].spell == "Auto Shot")

    for tree, expected in ipairs({ "heal", "heal", "shadow" }) do
        points = { 0, 0, 0 }; points[tree] = 10
        check("Priest ten-point tree " .. tree .. " chooses " .. expected,
            RikUI.Setup.GuessRole("PRIEST") == expected)
    end

    for tree, expected in ipairs({ "ele", "enh", "heal" }) do
        if RikUI.Presets.SHAMAN then
            points = { 0, 0, 0 }; points[tree] = 10
            check("Shaman ten-point tree " .. tree .. " chooses " .. expected,
                RikUI.Setup.GuessRole("SHAMAN") == expected)
        end
    end

    for tree, expected in ipairs({ "heal", "tank", "dps" }) do
        if RikUI.Presets.PALADIN then
            points = { 0, 0, 0 }; points[tree] = 10
            check("Paladin ten-point tree " .. tree .. " chooses " .. expected,
                RikUI.Setup.GuessRole("PALADIN") == expected)
        end
    end

    for tree, expected in ipairs({ "balance", "feral", "heal" }) do
        if RikUI.Presets.DRUID then
            points = { 0, 0, 0 }; points[tree] = 10
            check("Druid ten-point tree " .. tree .. " chooses " .. expected,
                RikUI.Setup.GuessRole("DRUID") == expected)
        end
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


    local warlock = assert(RikUI.Presets.WARLOCK, "Warlock preset missing")
    local affliction = assert(RikUI.Setup.Resolve("WARLOCK", "affliction"))
    local destruction = assert(RikUI.Setup.Resolve("WARLOCK", "destruction"))
    check("Warlock preserves Forever Banes and role attacks", affliction.bars.main[2].spell == "Bane of Agony"
        and destruction.bars.main[1].spell == "Incinerate"
        and RikUI.Spells.Entry("Curse of Agony", "WARLOCK") == nil)
    check("Warlock pet commands follow Hunter key decision",
        warlock.bars.bar2[10].macro == "Pet Attack" and warlock.bars.bar2[11].macro == "Pet Follow"
        and warlock.macros["Pet Attack"].body == RikUI.Presets.HUNTER.macros["Pet Attack"].body)


    for _, role in ipairs(warlock.roleOrder) do
        local resolved = assert(RikUI.Setup.Resolve("WARLOCK", role))
        check("Warlock control slots survive " .. role, resolved.bars.main[6].macro == "Fear"
            and resolved.bars.bar2[6].macro == "Banish" and resolved.bars.bar2[12].macro == "Banish")
        check("Warlock pet heal follows role " .. role,
            resolved.bars.main[role == "demonology" and 5 or 10].macro == "Health Funnel")
    end
    for _, name in ipairs({ "Fear", "Banish" }) do
        local macro = warlock.macros[name]
        check("Warlock living hostile targeting " .. name, macro
            and macro.body == "#showtooltip " .. name .. "\n/cast [@mouseover,harm,nodead][harm,nodead] " .. name
            and macro.spells[1] == name)
    end
    check("Warlock pet heal never changes enemy target", warlock.macros["Health Funnel"]
        and warlock.macros["Health Funnel"].body == "#showtooltip Health Funnel\n/cast [@pet,exists,nodead] Health Funnel"
        and warlock.macros["Health Funnel"].spells[1] == "Health Funnel")

    local shaman = assert(RikUI.Presets.SHAMAN, "Shaman preset missing")
    local enhancement = assert(RikUI.Setup.Resolve("SHAMAN", "enh"))
    local elemental = assert(RikUI.Setup.Resolve("SHAMAN", "ele"))
    local restoration = assert(RikUI.Setup.Resolve("SHAMAN", "heal"))
    check("Shaman roles have separate rotations", enhancement.bars.main[1].spell == "Stormstrike"
        and elemental.bars.main[1].spell == "Lightning Bolt" and restoration.bars.main[1].macro == "Healing Wave")
    check("Shaman interrupt and totem utility remain reachable", elemental.bars.bar2[11].spell == "Earth Shock"
        and shaman.bars.bar3[1].macro == "Earth Totems" and shaman.macros["Air Totems"].spells[1] == "Grounding Totem")
    check("Forever Fire Nova is not a fabricated Fire Nova Totem family",
        RikUI.Spells.Entry("Fire Nova", "SHAMAN") and not RikUI.Spells.Entry("Fire Nova Totem", "SHAMAN"))


    for _, name in ipairs({ "Earth Totems", "Fire Totems", "Water Totems", "Air Totems" }) do
        local macro = shaman.macros[name]
        check("Shaman totem alternative works on keyboard " .. name,
            macro.body == "#showtooltip\n/cast [mod:alt][btn:2] " .. macro.spells[2] .. "; " .. macro.spells[1])
    end
    for _, role in ipairs(shaman.roleOrder) do
        local resolved = assert(RikUI.Setup.Resolve("SHAMAN", role))
        check("Shaman group utility survives " .. role, resolved.bars.bar3[12].macro == "Ancestral Spirit"
            and resolved.bars.bar5[4].macro == "Water Breathing" and resolved.bars.bar5[5].macro == "Water Walking")
    end
    check("Shaman resurrection only targets fallen allies", shaman.macros["Ancestral Spirit"]
        and shaman.macros["Ancestral Spirit"].body == "#showtooltip Ancestral Spirit\n/cast [@mouseover,help,dead][help,dead] Ancestral Spirit")
    for _, name in ipairs({ "Water Breathing", "Water Walking" }) do
        local macro = shaman.macros[name]
        check("Shaman water utility uses friendly targets " .. name, macro
            and macro.body == "#showtooltip " .. name .. "\n/cast [@mouseover,help,nodead][help,nodead][@player] " .. name
            and macro.spells[1] == name)
    end

    local paladin = assert(RikUI.Presets.PALADIN, "Paladin preset missing")
    local holy = assert(RikUI.Setup.Resolve("PALADIN", "heal"))
    local protection = assert(RikUI.Setup.Resolve("PALADIN", "tank"))
    local retribution = assert(RikUI.Setup.Resolve("PALADIN", "dps"))
    check("Paladin has distinct healing tank and damage rotations", holy.bars.main[1].macro == "Holy Light"
        and protection.bars.main[1].spell == "Hammer of the Righteous" and retribution.bars.main[1].spell == "Holy Strike")
    check("Paladin Righteous Fury and shared healing remain accessible", protection.bars.bar3[8].spell == "Righteous Fury"
        and retribution.bars.bar2[10].macro == "Flash of Light")
    for _, role in ipairs(paladin.roleOrder) do
        local resolved = assert(RikUI.Setup.Resolve("PALADIN", role))
        check("Paladin defensive support survives " .. role, resolved.bars.bar2[6].macro == "Protection"
            and resolved.bars.bar2[7].macro == "Freedom" and resolved.bars.bar2[8].macro == "Sacrifice"
            and resolved.bars.bar3[9].macro == "Redemption")
        check("Paladin dual-use talents survive " .. role, resolved.bars.bar2[12].macro == "Holy Shock"
            and resolved.bars.bar4[5].macro == "Light's Vigil")
    end
    check("Holy role keeps paired talents on main bar", holy.bars.main[3].macro == "Holy Shock"
        and holy.bars.main[7].macro == "Light's Vigil")
    for _, name in ipairs({ "Holy Shock", "Light's Vigil" }) do
        local macro = paladin.macros[name]
        check("Paladin retains offensive target fallback " .. name, macro
            and macro.body == "#showtooltip " .. name .. "\n/cast [@mouseover,help,nodead][exists,nodead][@player] " .. name
            and macro.spells[1] == name)
    end
    for _, name in ipairs({ "Protection", "Freedom" }) do
        local spell = "Blessing of " .. name
        local macro = paladin.macros[name]
        check("Paladin emergency blessing target " .. name, macro and macro.spells[1] == spell
            and macro.body == "#showtooltip " .. spell .. "\n/cast [@mouseover,help,nodead][help,nodead][@player] " .. spell)
    end
    check("Sacrifice needs an explicit ally", paladin.macros.Sacrifice
        and paladin.macros.Sacrifice.body == "#showtooltip Blessing of Sacrifice\n/cast [@mouseover,help,nodead][help,nodead] Blessing of Sacrifice")
    check("Redemption only targets dead allies", paladin.macros.Redemption
        and paladin.macros.Redemption.body == "#showtooltip Redemption\n/cast [@mouseover,help,dead][help,dead] Redemption")

    local oldRace = UnitRace
    UnitRace = function() return "Undead", "Scourge", 5 end
    local undead = assert(RikUI.Setup.Resolve("PALADIN", "tank"))
    check("Undead Paladin gets racial utilities without losing existing slots",
        undead.bars.bar3[11].spell == "Will of the Forsaken" and undead.bars.bar3[12].spell == "Cannibalize"
        and undead.bars.extra[1].spell == paladin.bars.bar3[11].spell
        and RikUI.Setup.SlotToAction("extra", 1) == 13)
    UnitRace = function() return "Windshaper Skyborne", "Skyborne", 96 end
    local sky = assert(RikUI.Setup.Resolve("MAGE", "frost"))
    check("Skyborne faction racials use numeric race ID", sky.bars.bar3[12].spell == "Skysight")
    UnitRace = function() return "High Order Skyborne", "Skyborne", 95 end
    check("High Order Skyborne keeps its own racial", RikUI.Setup.Resolve("MAGE", "frost").bars.bar3[12].spell == "Read Ley Line")
    UnitRace = function() return "Unknown", "Unknown", 999 end
    check("Unknown races keep their existing utility", RikUI.Setup.Resolve("MAGE", "frost").bars.bar3[11].spell == "Conjure Mana Agate")

    UnitRace = function() return "Gnome", "Gnome", 7 end
    check("Gnome Eureka IDs remain class specific", RikUI.Spells.Entry("Eureka!", "MAGE").ranks[1] == 1259817
        and RikUI.Spells.Entry("Eureka!", "WARRIOR").ranks[1] == 1259813)
    local first = RikUI.Setup.Resolve("MAGE", "frost")
    local second = RikUI.Setup.Resolve("MAGE", "frost")
    first.bars.extra[1].spell = "mutated result"
    check("racial placement never mutates the preset or another resolution",
        second.bars.extra[1].spell == "Conjure Mana Agate" and RikUI.Presets.MAGE.bars.bar3[11].spell == "Conjure Mana Agate")
    local full = { class = "MAGE", bars = { bar3 = { [11] = { spell = "Conjure Mana Agate" } }, extra = {} } }
    for slot = 1, 12 do full.bars.extra[slot] = { item = "kept" } end
    RikUI.Setup.AddRacials(full)
    check("full extra page never discards an existing utility action", full.bars.bar3[11].spell == "Conjure Mana Agate")

    local oldAction = GetActionInfo
    GetActionInfo = function(slot) return "spell", 10000 + slot end
    assert(loadfile("src/setup/setup-snapshot.lua"))()
    local snapshot = assert(RikUI.Setup.CaptureSnapshot(undead,
        { macros = false, binds = false, cvars = false, layout = false }, {}, {}, "Default"))
    check("racial and displaced action slots are captured for Undo",
        snapshot.bars[59].id == 10059 and snapshot.bars[60].id == 10060 and snapshot.bars[13].id == 10013)
    GetActionInfo = oldAction
    UnitRace = oldRace


    local druid = assert(RikUI.Presets.DRUID, "Druid preset missing")
    local feral = assert(RikUI.Setup.Resolve("DRUID", "feral"))
    local bear = assert(RikUI.Setup.Resolve("DRUID", "tank"))
    check("Druid combat forms map independent native pages",
        feral.bars.cat[1].spell == "Claw" and bear.bars.bear[1].spell == "Maul"
        and RikUI.Setup.SlotToAction("cat", 1) == 73 and RikUI.Setup.SlotToAction("bear", 1) == 97)
    check("Druid travel and Moonkin do not invent native bonus pages",
        feral.bars.travel == nil and feral.bars.moonkin == nil and #RikUI.Data.BonusPages.DRUID == 2)
    check("Druid form shortcuts are named independently of learned indices",
        druid.bars.bar3[1].macro == "Bear Form" and druid.bars.bar3[2].spell == "Cat Form"
        and druid.bars.bar3[3].spell == "Moonkin Form")
    check("same-name class abilities cannot overwrite one another",
        RikUI.Spells.Entry("Lacerate", "DRUID").ranks[1] ~= RikUI.Spells.Entry("Lacerate", "HUNTER").ranks[1]
        and RikUI.Spells.Entry("Nature's Swiftness", "DRUID").ranks[1] == 17116
        and RikUI.Spells.Entry("Nature's Swiftness", "SHAMAN").ranks[1] == 16188)

    for _, role in ipairs(druid.roleOrder) do
        local resolved = assert(RikUI.Setup.Resolve("DRUID", role))
        check("Druid support cooldowns survive " .. role, resolved.bars.bar2[4].macro == "Innervate"
            and resolved.bars.bar2[6].macro == "Rebirth" and resolved.bars.bar3[9].macro == "Revive")
        check("Druid group buffs survive " .. role, resolved.bars.bar3[6].macro == "Mark of the Wild"
            and resolved.bars.bar3[7].macro == "Thorns" and resolved.bars.bar3[8].macro == "Gift of the Wild")
        check("Druid utility does not displace form attacks " .. role,
            resolved.bars.cat[1].spell == "Claw" and resolved.bars.bear[1].spell == "Maul")
    end
    check("Restoration Innervate uses shared target rules",
        RikUI.Setup.Resolve("DRUID", "heal").bars.main[8].macro == "Innervate")
    for _, name in ipairs({ "Innervate", "Mark of the Wild", "Thorns", "Gift of the Wild" }) do
        local macro = druid.macros[name]
        check("Druid living support targets " .. name, macro and macro.spells[1] == name
            and macro.body == "#showtooltip " .. name .. "\n/cast [@mouseover,help,nodead][help,nodead][@player] " .. name)
    end
    for _, name in ipairs({ "Rebirth", "Revive" }) do
        local macro = druid.macros[name]
        check("Druid distinct resurrection targets " .. name, macro and macro.spells[1] == name
            and macro.body == "#showtooltip " .. name .. "\n/cast [@mouseover,help,dead][help,dead] " .. name)
    end

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
    levelingChecks(check, "WARRIOR", {
        { "dps", "main", 2, "Mortal Strike", "Rend" },
        { "dps", "battle", 2, "Mortal Strike", "Rend" },
        { "dps", "defensive", 2, "Mortal Strike", "Rend" },
        { "fury", "main", 1, "Bloodthirst", "Heroic Strike" },
        { "fury", "berserker", 1, "Bloodthirst", "Heroic Strike" },
        { "tank", "main", 2, "Shield Slam", "Heroic Strike" },
        { "tank", "defensive", 2, "Shield Slam", "Heroic Strike" },
    })
    levelingChecks(check, "ROGUE", {
        { "assassination", "main", 1, "Mutilate", "Sinister Strike" },
        { "subtlety", "main", 1, "Hemorrhage", "Sinister Strike" },
    })
    levelingChecks(check, "WARLOCK", {
        { "destruction", "main", 1, "Incinerate", "Shadow Bolt" },
        { "destruction", "main", 2, "Conflagrate", "Corruption" },
        { "destruction", "main", 4, "Shadowburn", "Bane of Agony" },
        { "destruction", "main", 5, "Soul Fire", "Drain Life" },
    })
    levelingChecks(check, "MAGE", {
        { "frost", "main", 1, "Frostbolt", "Fireball" },
        { "arcane", "main", 1, "Arcane Missiles", "Fireball" },
        { "arcane", "main", 2, "Arcane Blast", "Arcane Missiles" },
        { "fire", "main", 2, "Scorch", "Fire Blast" },
        { "fire", "main", 4, "Pyroblast", "Fireball" },
    })
    levelingChecks(check, "HUNTER", {
        { "dps", "main", 4, "Aimed Shot", "Arcane Shot" },
        { "beast", "main", 3, "Summon Hawk", "Arcane Shot" },
        { "survival", "main", 4, "Lacerate", "Raptor Strike" },
    })
    levelingChecks(check, "PRIEST", {
        { "shadow", "main", 1, "Mind Flay", "Smite" },
        { "shadow", "main", 2, "Mind Blast", "Smite" },
        { "shadow", "main", 4, "Devouring Plague", "Shadow Word: Pain" },
        { "shadow", "main", 5, "Shadow Word: Death", "Mind Blast" },
    })
    levelingChecks(check, "PALADIN", {
        { "tank", "main", 1, "Hammer of the Righteous", "Holy Strike" },
        { "tank", "main", 3, "Seal of Fury", "Seal of Righteousness" },
        { "dps", "main", 11, "Seal of Command", "Seal of Righteousness" },
    })
    levelingChecks(check, "SHAMAN", {
        { "enh", "main", 1, "Stormstrike", "Lightning Bolt" },
        { "ele", "main", 5, "Chain Lightning", "Lightning Bolt" },
        { "ele", "main", 11, "Lava Burst", "Lightning Bolt" },
        { "heal", "main", 7, "Water Shield", "Lightning Shield" },
    })
    fallbackChecks(check)
end

