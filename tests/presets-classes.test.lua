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

