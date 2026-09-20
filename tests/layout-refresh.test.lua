-- Layout refresh is a service contract, independent of feature modules.
return function(check)
    local env = require("wow_stub")
    local loader = dofile("tests/load_addon.lua")
    local defaults = { point = "CENTER", relativePoint = "CENTER", x = 25, y = -40 }
    local function boot()
        env.frames, env.printed, env.inCombat = {}, {}, false
        RikUI, RikUIDB, RikUICharDB = nil, nil, nil
        local core = loader.Core()
        core.Setup = { DefaultPositions = {} }
        assert(loadfile("src/layout/layout.lua"))("RikUI", {})
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        return core, core.Layout
    end
    local function frame(name)
        local result = { name = name, writes = 0 }
        function result:SetScale(value)
            assert(not InCombatLockdown(), "layout wrote in combat")
            self.scale, self.writes = value, self.writes + 1
        end
        function result:ClearAllPoints() self.point = nil end
        function result:SetPoint(...) self.point = { ... } end
        function result:HookScript() end
        return result
    end
    local function reported(text)
        for _, line in ipairs(env.printed) do if line:find(text, 1, true) then return true end end
        return false
    end

    local core, layout = boot()
    local first, second, third = frame("first"), frame("second"), frame("third")
    local calls = {}
    local function appearance(target)
        calls[#calls + 1] = target.name
        target.gryphons = core.Profile.gryphons
    end
    layout.Register(first, "shared", defaults, { onApply = appearance })
    layout.Register(second, "shared", defaults, { onApply = function() error("later options replaced owner") end })
    layout.Register(third, "other", defaults, { onApply = appearance })
    calls = {}
    core.Profile.gryphons = true
    layout.Apply()
    check("layout callbacks follow frame registration order with first group options",
        table.concat(calls, ",") == "first,second,third" and first.gryphons and second.gryphons)
    check("appearance runs after geometry", first.point[4] == 25 and first.scale == 1)
    check("invalid appearance callback cannot partially register a group",
        not pcall(layout.Register, frame("invalid"), "invalid", defaults, { onApply = true })
        and layout.Groups.invalid == nil)

    calls = {}
    first.SetScale = function() error("frame write failed") end
    core.Profile.scale = 0.7
    layout.Apply()
    check("a broken frame spares its siblings and later groups",
        second.scale == 0.7 and third.scale == 0.7 and table.concat(calls, ",") == "second,third")
    check("frame errors identify their layout group", reported("Layout shared") and reported("frame write failed"))

    core, layout = boot()
    first, second, third = frame("first"), frame("second"), frame("third")
    calls = {}
    layout.Register(first, "shared", defaults, { onApply = function(target)
        if target == first then error("appearance failed") end
        calls[#calls + 1] = target.name
    end })
    layout.Register(second, "shared", defaults)
    layout.Register(third, "other", defaults, { onApply = function(target) calls[#calls + 1] = target.name end })
    local completed = 0
    layout.RefreshMovers = function() error("movers failed") end
    layout.NotifyLimits = function() completed = completed + 1 end
    calls = {}
    layout.Apply()
    check("appearance failures do not skip other frames or completion",
        table.concat(calls, ",") == "second,third" and completed == 1 and reported("appearance failed"))
    check("completion failures are isolated and contextual", reported("Layout movers") and reported("movers failed"))
    layout.RefreshMovers = nil
    layout.Apply()
    check("a failed completion does not strand the next layout pass", completed == 2)

    core, layout = boot()
    first = frame("settled")
    layout.Register(first, "settled", defaults)
    local settled = false
    layout.NotifyLimits = function()
        if settled then return end
        settled = true
        core.Profile.positions.settled = { point = "CENTER", relativePoint = "CENTER", x = 80, y = 90 }
        layout.Apply()
    end
    layout.Apply()
    check("completion can apply positions changed by a settle pass", first.point[4] == 80 and first.point[5] == 90)

    core, layout = boot()
    first, second = frame("floating"), frame("healthy")
    local floatingCalls = 0
    layout.Register(first, "floating", defaults, { floating = function() return true end,
        onApply = function() floatingCalls = floatingCalls + 1 end })
    layout.Register(second, "healthy", defaults)
    floatingCalls = 0
    layout.Apply()
    check("floating groups keep their anchors while refreshing appearance",
        first.writes == 0 and first.point == nil and floatingCalls == 1)
    layout.Groups.floating.floating = function() error("floating failed") end
    core.Profile.scale = 0.8
    layout.Apply()
    check("floating reader failures spare other groups", second.scale == 0.8 and reported("floating failed"))

    core, layout = boot()
    first = frame("recursive")
    local recursiveCalls = 0
    layout.Register(first, "recursive", defaults, { onApply = function()
        recursiveCalls = recursiveCalls + 1
        if recursiveCalls < 3 then layout.Apply() end
    end })
    check("nested layout requests coalesce with the active pass", recursiveCalls == 1)
    layout.Apply()
    check("coalescing releases the guard after a pass", recursiveCalls == 2)

    core, layout = boot()
    first, second = frame("first"), frame("second")
    calls = {}
    env.inCombat = true
    layout.Register(first, "shared", defaults, { onApply = function(target)
        calls[#calls + 1] = target.name
        target.gryphons = core.Profile.gryphons
    end })
    layout.Register(second, "shared", defaults)
    layout.Apply()
    core.Profile.scale, core.Profile.gryphons = 0.6, true
    layout.Apply()
    check("combat defers geometry and appearance", #calls == 0 and first.writes == 0 and second.writes == 0)
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("combat requests apply latest settings in one pass", table.concat(calls, ",") == "first,second"
        and first.writes == 1 and second.writes == 1 and first.scale == 0.6 and second.gryphons)

    local barsCalls = 0
    core.Bars = { ApplyLayout = function() barsCalls = barsCalls + 1 end }
    core.Setup.IsApplying = function() return false end
    core.DB.profiles.Other = { scale = 0.9, gryphons = false,
        positions = { shared = { point = "LEFT", relativePoint = "LEFT", x = 70, y = 80 } } }
    calls = {}
    check("profile selection uses the shared service without calling Bars", core:SetProfile("Other")
        and barsCalls == 0 and first.point[4] == 70 and first.scale == 0.9
        and first.gryphons == false and table.concat(calls, ",") == "first,second")

    core, layout = boot()
    first, second, third = frame("first"), frame("second"), frame("late")
    layout.Register(first, "visited", defaults)
    local registered = false
    layout.Register(second, "registrar", defaults, { onApply = function()
        if registered then return end
        registered = true
        layout.Register(third, "visited", defaults)
    end })
    check("a frame registered during refresh is included without recursive passes", third.writes == 1
        and third.point[4] == 25 and first.writes == 2 and second.writes == 1)

    for _, deferred in ipairs({ false, true }) do
        core, layout = boot()
        local mode = deferred and "deferred" or "immediate"
        local groupOwner, explicitOwner, callerOwner = {}, {}, {}
        local watching, childRegistered = false, false
        local hits, handlers = {}, {}
        for _, name in ipairs({ "owned", "floating", "explicit", "unowned", "caller", "child" }) do
            local key = name
            hits[key] = 0
            handlers[key] = function() hits[key] = hits[key] + 1 end
        end
        local function subscribe(name)
            core:RegisterEvent("UNIT_HEALTH", handlers[name])
        end
        local function appearance()
            if not watching then return end
            subscribe("owned")
            if not childRegistered then
                childRegistered = true
                core.Combat.Queue(function()
                    layout.Register(frame("child"), "child", defaults, {
                        onApply = function() subscribe("child") end,
                    })
                end)
            end
            error("owned appearance failure")
        end
        layout.Register(frame("unowned"), "unowned", defaults, {
            onApply = function() if watching then subscribe("unowned") end end,
        })
        groupOwner.OnEnable = function()
            layout.Register(frame("owned"), "owned", defaults, {
                floating = function()
                    if watching then subscribe("floating") end
                    return false
                end,
                onApply = appearance,
            })
            layout.Register(frame("explicit"), "explicit", defaults, {
                owner = explicitOwner,
                onApply = function() if watching then subscribe("explicit") end end,
            })
        end
        callerOwner.OnEnable = function()
            -- Later frames share the first registration's options and owner.
            layout.Register(frame("sibling"), "owned", defaults, {
                owner = callerOwner,
                onApply = function() error("later registration replaced callback") end,
            })
            core:RegisterEvent("SPELLS_CHANGED", function()
                layout.Apply()
                subscribe("caller")
            end)
        end
        core:RegisterModule("layoutowner", groupOwner)
        core:RegisterModule("layoutcaller", callerOwner)
        watching, env.inCombat = true, deferred
        env.fire("SPELLS_CHANGED")
        if deferred then
            check("owned layout callbacks wait through combat", not childRegistered and core.Combat.Pending() == 1)
        end
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        env.fire("UNIT_HEALTH", "player")
        check(mode .. " layout callbacks subscribe and survive appearance errors",
            hits.owned == 1 and hits.floating == 1 and hits.explicit == 1 and hits.unowned == 1
            and hits.caller == 1 and hits.child == 1 and reported("owned appearance failure"))
        core:UnregisterOwner(groupOwner)
        env.fire("UNIT_HEALTH", "player")
        check(mode .. " refresh retains the first group owner's appearance and predicate subscriptions",
            hits.owned == 1 and hits.floating == 1 and hits.explicit == 2 and hits.caller == 2)
        check(mode .. " refresh child work and nested registration inherit the group owner", hits.child == 1)
        core:UnregisterOwner(explicitOwner)
        env.fire("UNIT_HEALTH", "player")
        check(mode .. " refresh honors explicit ownership", hits.explicit == 2 and hits.caller == 3)
        core:UnregisterOwner(callerOwner)
        env.fire("UNIT_HEALTH", "player")
        check(mode .. " refresh restores caller ownership and keeps unowned groups independent",
            hits.caller == 3 and hits.unowned == 4)
    end
end
