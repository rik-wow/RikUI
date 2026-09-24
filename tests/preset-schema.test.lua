return function(check)
    local env = require("wow_stub")
    local previous = RikUI
    env.frames = {}
    dofile("tests/load_addon.lua").Core()
    dofile("src/persistence/codec.lua")
    for _, path in ipairs(dofile("tests/load_addon.lua").Manifest()) do
        if path:match("^data/spells") or path:match("^presets/[^/]+%.lua$") then dofile(path) end
    end
    dofile("src/setup/setup.lua")
    local f = io.open("src/setup/preset-schema.lua", "r")
    if f then f:close(); dofile("src/setup/preset-schema.lua") end
    local validate = RikUI.Setup.ValidateSharedPreset or RikUI.Setup.ValidatePreset
    for class, preset in pairs(RikUI.Presets) do
        local issues = validate(preset)
        check("shared schema accepts " .. class, #issues == 0, table.concat(issues, "; "))
    end
    local function bad(label, change, path)
        local preset = RikUI.Setup.CopyState(RikUI.Presets.WARRIOR)
        change(preset)
        local ok, issues = pcall(validate, preset)
        check("shared schema rejects " .. label, ok and type(issues) == "table" and #issues > 0
            and (not path or table.concat(issues, "; "):find(path, 1, true)))
    end
    bad("unknown class", function(p) p.class = "UNKNOWN" end, "class")
    bad("fractional version", function(p) p.version = 1.5 end, "version")
    bad("missing roles", function(p) p.roles = nil end, "roles")
    bad("malformed role", function(p) p.roles.dps = false end, "roles.dps")
    bad("empty role label", function(p) p.roles.dps.label = "" end, "label")
    bad("sparse trees", function(p) p.roles.dps.trees = { [2] = 1 } end, "trees")
    bad("unknown tree", function(p) p.roles.dps.trees = { 4 } end, "trees")
    bad("duplicate order", function(p) p.roleOrder[2] = p.roleOrder[1] end, "roleOrder")
    bad("missing order role", function(p) p.roleOrder = { "dps" } end, "roleOrder")
    bad("extra order role", function(p) p.roleOrder[4] = "ghost" end, "roleOrder")
    bad("orphan override", function(p) p.roleOverrides.ghost = {} end, "roleOverrides")
    bad("invalid macro body", function(p) p.macros.Execute.body = {} end, "macros.Execute")
    bad("long macro body", function(p) p.macros.Execute.body = string.rep("x", 256) end, "body")
    bad("invalid icon", function(p) p.macros.Execute.icon = false end, "icon")
    bad("unknown scope", function(p) p.macros.Execute.scope = "raid" end, "scope")
    bad("sparse macro spells", function(p) p.macros.Execute.spells = { [2] = "Execute" } end, "spells")
    bad("unknown spell", function(p) p.bars.main[1].spell = "Made Up Spell" end, "Made Up Spell")
    bad("wrong spell level", function(p) p.bars.main[1].level = 999 end, "level")
    bad("extra slot key", function(p) p.bars.main[1].oops = true end, "oops")
    bad("extra root key", function(p) p.extraField = true end, "extraField")
    bad("function", function(p) p.macros.Execute.body = function() end end)
    bad("cycle", function(p) p.self = p end)
    RikUI = previous
end
