-- Source-backed form mana: event filtering, profile control and opaque value rendering.
return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local restore = widgets.install()
    local names = { "UnitClass", "UnitPower", "UnitPowerMax", "UnitPowerType" }
    local saved, powerTypes = {}, Enum.PowerType
    for _, name in ipairs(names) do saved[name] = _G[name] end
    local state
    local function load(class, profile, combat, prepare)
        widgets.loadAddon(env, { "src/ui/skin.lua", "data/layouts.lua", "src/modules/personalresource/druid-mana.lua" },
            profile, combat, function()
                state = { current = 500, maximum = 1000, power = 3, calls = 0 }
                Enum.PowerType = { Mana = 0, Rage = 1, Energy = 3 }
                UnitClass = function() return class or "Druid", (class or "Druid"):upper() end
                UnitPowerType = function() return state.power end
                UnitPower = function(unit, kind)
                    assert(unit == "player" and kind == 0, "must request explicit player mana")
                    state.calls = state.calls + 1
                    if state.fail then error("unavailable") end
                    return state.current
                end
                UnitPowerMax = function(unit, kind)
                    assert(unit == "player" and kind == 0, "maximum must request explicit mana")
                    return state.maximum
                end
                if prepare then prepare() end
            end)
        return RikUI.DruidMana
    end
    local ok, reason = pcall(function()
        local mana = load()
        local holder, bar = mana.Holder, mana.Bar
        check("Cat gets a movable mana strip alongside its primary resource", holder:IsShown()
            and RikUI.Layout.Groups.druidmana.frames[1] == holder and holder.width == 121 and holder.height == 18
            and bar.value == 500 and bar.high == 1000 and bar.text.text == "Mana 500 / 1000")
        state.current = 800
        env.fire("UNIT_POWER_FREQUENT", "target", "MANA")
        env.fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
        env.fire("UNIT_POWER_FREQUENT", env.SECRET, "MANA")
        env.fire("UNIT_POWER_FREQUENT", "player", env.SECRET)
        check("unrelated and opaque event arguments do not trigger reads", bar.value == 500 and state.calls == 1)
        env.fire("UNIT_POWER_FREQUENT", "player", "MANA")
        check("mana regeneration updates directly", bar.value == 800)
        state.power, state.maximum = 1, 1200
        env.inCombat = true
        env.fire("UNIT_DISPLAYPOWER", "player")
        env.fire("UNIT_MAXPOWER", "player", "MANA")
        check("Bear in combat keeps explicit mana and refreshed maximum", holder:IsShown() and bar.high == 1200)
        state.power = 0
        env.fire("UNIT_DISPLAYPOWER", "player")
        check("caster hides the redundant strip", not holder:IsShown())
        state.power = 3
        env.fire("UPDATE_SHAPESHIFT_FORM")
        check("returning to Cat restores it", holder:IsShown())
        state.current, state.maximum = env.SECRET, env.SECRET
        env.fire("UNIT_POWER_UPDATE", "player", "MANA")
        check("opaque values go to native sinks and clear stale numerical text", bar.value == env.SECRET
            and bar.high == env.SECRET and bar.text.text == "Mana" and #env.printed == 0)
        state.power = env.SECRET
        env.fire("UNIT_DISPLAYPOWER", "player")
        check("unknown primary resource hides safely", not holder:IsShown())
        state.power, state.current, state.maximum = 3, 300, 0
        env.fire("UNIT_DISPLAYPOWER", "player")
        check("zero maximum clears stale fill", bar.value == 0 and bar.high == 1 and bar.text.text == "Mana unavailable")
        state.maximum, state.fail = 1000, true
        env.fire("UNIT_POWER_UPDATE", "player", "MANA")
        check("API failure leaves no old mana value", bar.value == 0 and bar.text.text == "Mana unavailable")
        state.fail = false
        check("the mana setting lives on the class page, not a page of its own", mana.Options == nil
            and type(mana.ClassSettings) == "table" and mana.ClassSettings[1].key == "show")
        local setting = mana.ClassSettings[1]
        setting.set(false)
        check("the setting saves and hides immediately in combat", not setting.get()
            and RikUI.Profile.druidmana.show == false and not holder:IsShown())
        setting.set(true)
        check("the setting restores current mana immediately", holder:IsShown() and bar.value == 300)
        env.inCombat = false
        RikUI.DB.profiles.NoMana = { druidmana = { show = false } }
        RikUI:SetProfile("NoMana")
        check("profile switching refreshes the saved preference", not holder:IsShown())
        mana = load("Warrior")
        check("other classes allocate no frame", mana.Holder == nil)
        mana = load("Druid", { modules = { druidmana = false } })
        check("disabled module allocates no frame", mana.Holder == nil)
        mana = load("Druid", nil, false, function() UnitPowerMax = nil end)
        check("missing required API leaves native resources alone", mana.Holder == nil and #env.printed == 0)
        mana = load("Druid", nil, true)
        check("combat login queues initial construction", mana.Holder == nil)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat constructs and refreshes once", mana.Holder and mana.Holder:IsShown())
    end)
    restore()
    Enum.PowerType = powerTypes
    for _, name in ipairs(names) do _G[name] = saved[name] end
    env.inCombat = false
    check("Druid mana suite completes", ok, reason)
end

