-- Primary resource follows the client for every class and form.
return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local restore = widgets.install()
    local names, saved = { "UnitClass", "UnitPower", "UnitPowerMax", "UnitPowerType" }, {}
    for _, name in ipairs(names) do saved[name] = _G[name] end
    local state
    local function load(class, profile, combat, prepare)
        widgets.loadAddon(env, { "src/ui/skin.lua", "data/layouts.lua",
            "src/modules/personalresource/combat-resource.lua" }, profile, combat, function()
            state = { current=40, maximum=100, token="MANA", calls=0 }
            UnitClass = function() return class, class end
            UnitPowerType = function() return 0, state.token end
            UnitPower = function(unit, kind)
                assert(unit == "player" and kind == nil, "primary resource must follow the client")
                state.calls = state.calls + 1
                if state.fail then error("unavailable") end
                return state.current
            end
            UnitPowerMax = function() return state.maximum end
            if prepare then prepare() end
        end)
        return RikUI.CombatResource
    end
    local ok, reason = pcall(function()
        for _, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
            "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
            local resource = load(class)
            check(class .. " gets default-enabled core resource display", resource and resource.Holder
                and resource.Holder:IsShown() and resource.Bar.value == 40 and resource.Bar.high == 100
                and RikUI.Layout.Groups.combatresource.frames[1] == resource.Holder)
        end
        local resource = load("DRUID")
        local bar = resource.Bar
        state.token, state.current = "ENERGY", 65
        env.inCombat = true
        env.fire("UNIT_DISPLAYPOWER", "player")
        check("form change updates resource in combat", bar.value == 65 and bar.text.text == "65 / 100")
        state.token, state.current, state.maximum = "RAGE", 25, 120
        env.fire("UNIT_POWER_FREQUENT", "player", "RAGE")
        check("frequent resource events refresh current and maximum", bar.value == 25 and bar.high == 120)
        local calls = state.calls
        env.fire("UNIT_POWER_UPDATE", "target", "RAGE")
        env.fire("UNIT_POWER_UPDATE", env.SECRET, "RAGE")
        check("other units and opaque unit tokens are ignored", state.calls == calls)
        -- Model the client's secret-capable text sink as the unit-frame fixture does.
        local formatted = bar.text.SetFormattedText
        bar.text.SetFormattedText = function(self, format, ...)
            self.format, self.args = format, { ... }
        end
        state.current, state.maximum = env.SECRET, env.SECRET
        env.fire("UNIT_POWER_UPDATE", "player", env.SECRET)
        check("opaque resource values pass directly to native sinks",
            bar.value == env.SECRET and bar.high == env.SECRET
                and bar.text.args[1] == env.SECRET and bar.text.args[2] == env.SECRET)
        bar.text.SetFormattedText = formatted
        state.fail = true
        env.fire("UNIT_POWER_UPDATE", "player", "RAGE")
        check("failed reads clear stale fill and show unavailable", bar.value == 0 and bar.high == 1
            and bar.text.text == "Resource unavailable")
        state.fail, state.current, state.maximum = false, 30, 100
        env.fire("PLAYER_ENTERING_WORLD")
        check("later valid resource recovers", bar.value == 30 and bar.high == 100)
        state.maximum = 0
        env.fire("UNIT_MAXPOWER", "player")
        check("zero maximum clears safely", bar.value == 0 and bar.high == 1)
        env.inCombat = false
        resource = load("MAGE", { modules={combatresource=false} })
        check("resource display respects module opt-out", resource.Holder == nil)
        resource = load("MAGE", nil, false, function() UnitPowerMax = nil end)
        check("unsupported API creates no dead strip", resource.Holder == nil)
        resource = load("MAGE", nil, true)
        check("combat login defers construction", resource.Holder == nil)
        env.inCombat = false; env.fire("PLAYER_REGEN_ENABLED")
        check("deferred resource builds after combat", resource.Holder and resource.Holder:IsShown())
    end)
    restore()
    for _, name in ipairs(names) do _G[name] = saved[name] end
    env.inCombat = false
    check("combat resource suite completes", ok, reason)
end
