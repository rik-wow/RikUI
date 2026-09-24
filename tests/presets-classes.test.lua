-- Cross-class catalogue and preset integration; callable by the standard runner.
return function(check)
    package.path = "tests/?.lua;" .. package.path
    require("wow_stub")
    local loader = dofile("tests/load_addon.lua")
    RikUI, RikUIDB, RikUICharDB = nil, nil, nil
    loader.Core()
    for _, path in ipairs(loader.Manifest()) do
        if path:match("^data/spells") or path:match("^presets/") then assert(loadfile(path))() end
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
end

