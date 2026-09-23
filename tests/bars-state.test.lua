local loadfile = dofile("tests/load_addon.lua").Loadfile
-- Real client rendering and combat secrecy require a separate beta observation.
return function(check)
    local env = require("wow_stub")
    local saved = {}
    for _, name in ipairs({ "GetActionCooldown", "GetActionCount", "IsUsableAction", "IsActionInRange" }) do
        saved[name] = _G[name]
    end
    env.frames, env.printed, env.inCombat = {}, {}, false
    RikUI, RikUIDB, RikUICharDB = nil, nil, nil
    assert(loadfile("src/core/core.lua"))("RikUI", {})
    assert(loadfile("src/platform/hooks.lua"))("RikUI", {})
    assert(loadfile("src/modules/bars/bars.lua"))("RikUI", {})
    -- Diagnostic-only load avoids needing secure frame creation.
    RikUI.Bars.OnEnable = nil
    assert(loadfile("src/modules/bars/bars-state.lua"))("RikUI", {})
    env.fire("ADDON_LOADED", "RikUI")
    local slots = {}
    GetActionCooldown = function(slot) slots.cooldown = slot; return env.SECRET, env.SECRET, 1, env.SECRET end
    GetActionCount = function(slot) slots.count = slot; return env.SECRET end
    IsUsableAction = function(slot) slots.usable = slot; return true, false end
    IsActionInRange = function(slot) slots.range = slot; return env.SECRET end
    local ok, reason = pcall(function()
        SlashCmdList.RIKUI("bardebug 73")
        env.inCombat = true
        SlashCmdList.RIKUI("debug")
        local output = table.concat(env.printed, "\n")
        check("debug samples all four APIs for the selected absolute slot", slots.cooldown == 73
            and slots.count == 73 and slots.usable == 73 and slots.range == 73)
        check("debug reports combat and per-return secrecy without printing opaque values",
            output:find("slot=73 combat=true", 1, true)
            and output:find("bars.GetActionCooldown[1] secret=true", 1, true)
            and output:find("bars.GetActionCount[1] secret=true", 1, true)
            and output:find("bars.IsUsableAction[1] secret=false", 1, true)
            and output:find("bars.IsActionInRange[1] secret=true", 1, true)
            and not output:find("<secret>", 1, true))
        IsActionInRange = function() return false end
        env.printed = {}
        SlashCmdList.RIKUI("debug")
        check("debug prints readable range result for native evidence",
            table.concat(env.printed, "\n"):find("range=false", 1, true))
        for _, value in ipairs({ "0", "-1", "1.5", "nan", "73 extra" }) do
            SlashCmdList.RIKUI("bardebug " .. value)
        end
        check("invalid diagnostic slots do not replace the selected slot", RikUI.Bars.DebugSlot == 73)
        GetActionCount = function() error("sample unavailable") end
        check("failed debug reader is contained", pcall(function() SlashCmdList.RIKUI("debug") end))
    end)
    for name, value in pairs(saved) do _G[name] = value end
    env.inCombat = false
    if not ok then error(reason) end
end
