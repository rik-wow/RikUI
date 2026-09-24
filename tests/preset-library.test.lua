return function(check)
    local env = require("wow_stub")
    local previous = RikUI
    env.frames, env.inCombat = {}, false
    dofile("tests/load_addon.lua").Core()
    RikUI.DB, RikUI.CharDB = { community = {} }, {}
    dofile("data/spells.lua"); dofile("presets/warrior.lua"); dofile("src/setup/setup.lua")
    dofile("src/persistence/codec.lua"); dofile("src/setup/preset-schema.lua")
    local file = io.open("src/setup/preset-library.lua", "r")
    if file then file:close(); dofile("src/setup/preset-library.lua") end
    local library, setup = RikUI.PresetLibrary, RikUI.Setup
    check("preset library is available", library ~= nil)
    if not library then RikUI = previous; return end
    local preset = setup.CopyState(RikUI.Presets.WARRIOR)
    preset.bars.main[1] = { spell = "Rend", level = 4 }
    local ok = library.Add("My bars", preset)
    check("named preset stored", ok and RikUI.DB.community["My bars"] ~= nil)
    preset.bars.main[1].spell = "bad"
    check("storage isolates caller changes", library.Get("WARRIOR", "My bars").bars.main[1].spell == "Rend")
    check("duplicate name rejected", library.Add("My bars", RikUI.Presets.WARRIOR) == nil)
    check("wrong class rejected", library.Get("MAGE", "My bars") == nil)
    check("bad names rejected", library.Add("|cffff0000bad", preset) == nil and library.Add("", preset) == nil)
    env.inCombat = true
    check("combat import refused", library.Add("Combat", RikUI.Presets.WARRIOR) == nil)
    env.inCombat = false
    local resolved = setup.Resolve("WARRIOR", "dps", "My bars")
    check("named source resolves through normal overlays", resolved and resolved.bars.main[1].spell == "Rend"
        and resolved.presetName == "My bars")
    RikUI.Profile = { positions = {} }
    setup.IsUndoing = function() return false end
    setup.CaptureSnapshot = function() return {} end
    dofile("src/setup/setup-apply.lua")
    local result = setup.Apply("WARRIOR", "dps", { presetName = "My bars", macros=false, bars=false,
        binds=false, cvars=false, layout=false })
    check("Apply records the named source after success", result and result.status == "applied"
        and RikUI.CharDB.applied.presetName == "My bars")
    check("default resolution uses last applied named source", setup.Resolve("WARRIOR", "dps").bars.main[1].spell == "Rend")
    check("explicit bundled choice resets source", setup.Resolve("WARRIOR", "dps", "").bars.main[1].spell == "Heroic Strike")
    RikUI.DB.community["My bars"] = { class = "WARRIOR", roles = false }
    check("corrupt saved source fails closed", setup.Resolve("WARRIOR", "dps") == nil)
    RikUI.DB.community["My bars"] = nil
    check("missing saved source never falls back silently", setup.Resolve("WARRIOR", "dps") == nil)
    RikUI.DB.community[7] = {}
    RikUI.DB.community.bad = { class = "WARRIOR" }
    check("picker excludes corrupt and mixed-key data", #library.Entries("WARRIOR") == 1)
    local bundle = setup.CopyState(RikUI.Presets.WARRIOR)
    bundle.author = "Example author"
    check("bundled registration API", type(library.Register) == "function")
    if library.Register then
        check("bundled source registers", library.Register("Example", bundle) == true)
        bundle.author = "Mutated"
        check("bundle is copied without saved-variable writes", library.Get("WARRIOR", "Example").author == "Example author"
            and RikUI.DB.community.Example == nil)
        check("bundle appears with attribution", library.Entries("WARRIOR")[2].text == "Community: Example — Example author")
        check("bundle cannot be shadowed by import", library.Add("Example", RikUI.Presets.WARRIOR) == nil)
        check("duplicate registration refused", library.Register("Example", bundle) == nil)
        bundle.author = nil
        check("bundle requires author", library.Register("Missing author", bundle) == nil)
        bundle.author = "|bad"
        check("author markup rejected", #setup.ValidateSharedPreset(bundle) > 0)
        RikUI.CommunityPresets.Broken = { class = "WARRIOR" }
        check("diagnostics include malformed bundle", #library.ValidateAll() > 0)
        check("invalid bundle excluded", #library.Entries("WARRIOR") == 2)
    end
    RikUI = previous
end
