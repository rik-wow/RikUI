-- Runtime resilience contracts; all client globals come from the existing stub.
return function(check)
    local env = require("wow_stub")
    local loader = dofile("tests/load_addon.lua")
    local function fresh(db, charDB)
        env.frames, env.printed, env.inCombat = {}, {}, false
        RikUI, RikUIDB, RikUICharDB = nil, db, charDB
        return loader.Core()
    end
    local function ready(core)
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        return core
    end
    local function reported(text)
        for _, line in ipairs(env.printed) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end

    do
        local recovery = fresh()
        recovery:RegisterModule("base", {})
        recovery:RegisterModule("feature", {}, { dependencies = { "base" } })
        recovery:RegisterModule("missing", {}, { dependencies = { "absent" } })
        ready(recovery)
        SlashCmdList.RIKUI("module base off")
        check("module command saves disabled preference without live teardown",
            recovery.Profile.modules.base == false and recovery:GetModuleState("base") == "enabled")
        SlashCmdList.RIKUI("module feature on")
        check("module command enables required providers", recovery.Profile.modules.base == true)
        SlashCmdList.RIKUI("module base status")
        check("module command shows runtime and saved state", reported("base: enabled; next reload=on"))
        local before = recovery.Profile.modules.base
        SlashCmdList.RIKUI("module base delete")
        check("invalid module command does not mutate", recovery.Profile.modules.base == before and reported("Usage: /rik module"))
        recovery.Profile.modules.missing = false
        SlashCmdList.RIKUI("module missing on")
        check("module command reports dependency errors", recovery.Profile.modules.missing == false and reported("Missing required module"))
        SlashCmdList.RIKUI("module")
        check("module command lists modules deterministically", reported("feature: enabled"))
    end

    local core, calls = fresh(), {}
    local second = function() calls[#calls + 1] = "second" end
    local late = function() calls[#calls + 1] = "late" end
    local added = false
    local first = function()
        calls[#calls + 1] = "first"
        core:UnregisterEvent("SPELLS_CHANGED", second)
        if not added then added = true; core:RegisterEvent("SPELLS_CHANGED", late) end
    end
    check("event registration accepts an existing subscription", core:RegisterEvent("SPELLS_CHANGED", first)
        and core:RegisterEvent("SPELLS_CHANGED", first))
    core:RegisterEvent("SPELLS_CHANGED", second)
    env.fire("SPELLS_CHANGED")
    check("dispatch deduplicates, skips removed handlers and defers additions", table.concat(calls, ",") == "first")
    env.fire("SPELLS_CHANGED")
    check("new handlers receive next event in order", table.concat(calls, ",") == "first,first,late")
    check("unsubscribe reports whether subscription existed", core:UnregisterEvent("SPELLS_CHANGED", first)
        and not core:UnregisterEvent("SPELLS_CHANGED", first))
    core:UnregisterEvent("SPELLS_CHANGED", late)
    local nativeRegistered = false
    for _, frame in ipairs(env.frames) do
        if frame:IsEventRegistered("SPELLS_CHANGED") then nativeRegistered = true end
    end
    check("last unsubscribe releases native event", not nativeRegistered)

    core, calls = fresh(), {}
    local nested = false
    core:RegisterEvent("SPELLS_CHANGED", function()
        calls[#calls + 1] = nested and "inner-first" or "outer-first"
        if not nested then nested = true; env.fire("SPELLS_CHANGED"); nested = false end
    end)
    core:RegisterEvent("SPELLS_CHANGED", function() calls[#calls + 1] = nested and "inner-last" or "outer-last" end)
    env.fire("SPELLS_CHANGED")
    check("nested dispatch preserves its own cursor", table.concat(calls, ",") ==
        "outer-first,inner-first,inner-last,outer-last")

    core, calls = fresh(), {}
    local enablingState
    core:RegisterModule("dependent", { OnEnable = function() calls[#calls + 1] = "dependent" end },
        { dependencies = { "provider" } })
    core:RegisterModule("provider", { OnEnable = function()
        enablingState = core:GetModuleState("provider")
        calls[#calls + 1] = "provider"
    end })
    check("new module state is registered", core:GetModuleState("provider") == "registered")
    ready(core)
    check("dependencies start before consumers", table.concat(calls, ",") == "provider,dependent")
    check("module states expose activation", enablingState == "enabling"
        and core:GetModuleState("provider") == "enabled" and core:GetModuleState("dependent") == "enabled")
    env.fire("PLAYER_LOGIN")
    check("repeated login does not restart modules", #calls == 2)

    core = fresh({ profiles = { Default = { modules = { off = false } } } })
    core:RegisterModule("off", { OnEnable = function() error("disabled module started") end })
    ready(core)
    check("disabled module does not start", core:GetModuleState("off") == "disabled")

    core, calls = fresh(), {}
    core:RegisterModule("consumer", { OnEnable = function() calls[#calls + 1] = "consumer" end },
        { dependencies = { "broken" } })
    core:RegisterModule("broken", { OnEnable = function()
        core:RegisterEvent("SPELLS_CHANGED", function() calls[#calls + 1] = "leaked" end)
        error("enable fault")
    end })
    core:RegisterModule("healthy", { OnEnable = function() calls[#calls + 1] = "healthy" end })
    ready(core)
    env.fire("SPELLS_CHANGED")
    check("failure cleans owned events, blocks dependents and spares unrelated modules",
        core:GetModuleState("broken") == "failed" and core:GetModuleState("consumer") == "blocked"
        and table.concat(calls, ",") == "healthy" and reported("enable fault"))

    core = fresh()
    local cycleStarted = false
    local cycleHook = function() cycleStarted = true end
    core:RegisterModule("left", { OnEnable = cycleHook }, { dependencies = { "right" } })
    core:RegisterModule("right", { OnEnable = cycleHook }, { dependencies = { "left" } })
    core:RegisterModule("missing", { OnEnable = cycleHook }, { dependencies = { "absent" } })
    ready(core)
    check("cycles and missing dependencies do not execute hooks", not cycleStarted
        and core:GetModuleState("left") == "blocked" and core:GetModuleState("right") == "blocked"
        and core:GetModuleState("missing") == "blocked")

    for _, hook in ipairs({ "Restore", "RestoreLate" }) do
        core = fresh()
        local started = false
        core.Store = { Restore = function() end, RestoreLate = function() return false end }
        core.Store[hook] = function() error("store " .. hook .. " fault") end
        core:RegisterModule("healthy", { OnEnable = function() started = true end })
        ready(core)
        check("store " .. hook .. " errors do not prevent startup", started
            and core.Profile.scale == 1 and reported("store " .. hook .. " fault"))
    end

    core = fresh({ profiles = { Default = { scale = "invalid", gryphons = "false",
        tooltip = { hideInCombat = 1 }, chat = { timestamps = {} }, modules = { active = "yes" } } } },
        { askRole = "yes", wizardDone = 0 })
    core:RegisterModule("active", {})
    ready(core)
    check("invalid saved scalars recover to typed defaults", core.Profile.scale == 1
        and core.Profile.gryphons == false and core.Profile.tooltip.hideInCombat == false
        and core.Profile.chat.timestamps == true and core.CharDB.askRole == true and core.CharDB.wizardDone == false)
    check("invalid module flags normalize consistently", core.Profile.modules.active == true
        and core:GetModuleState("active") == "enabled")

    core, calls = fresh(), {}
    env.inCombat = true
    core.Combat.Queue(function() calls[#calls + 1] = "stale" end, "layout")
    core.Combat.Queue(function() calls[#calls + 1] = "other" end, "other")
    core.Combat.Queue(function() calls[#calls + 1] = "latest" end, "layout")
    core.Combat.Queue(function() calls[#calls + 1] = "cancelled" end, "cancel")
    check("keyed combat work coalesces and cancels", core.Combat.Pending() == 3
        and core.Combat.Cancel("cancel") and not core.Combat.Cancel("cancel") and core.Combat.Pending() == 2)
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("coalescing retains FIFO position", table.concat(calls, ",") == "latest,other" and core.Combat.Pending() == 0)
    check("completed work is not cancellable", not core.Combat.Cancel("layout"))

    do
        local function tick()
            for _, frame in ipairs(env.frames) do env.runScript(frame, "OnUpdate", 0.016) end
        end
        core = fresh()
        local ran, order, owner, owned = 0, {}, {}, true
        local repeatWork
        repeatWork=function()
            ran=ran+1
            owned=owned and core.Runtime.owner==owner
            if ran<150 then core.Combat.Queue(repeatWork) end
        end
        env.inCombat=true
        core.Runtime.owner=owner;core.Combat.Queue(repeatWork);core.Runtime.owner=nil
        env.inCombat=false;env.fire("PLAYER_REGEN_ENABLED")
        check("self-requeued combat work yields a bounded batch",ran==100 and core.Combat.Pending()==1)
        core.Combat.Queue(function() order[#order+1]="obsolete" end,"replace")
        core.Combat.Queue(function() order[#order+1]="latest" end,"replace")
        core.Combat.Queue(function() order[#order+1]="cancelled" end,"cancel")
        core.Combat.Cancel("cancel")
        core.Combat.Queue(function() error("continuation fault") end)
        core.Combat.Queue(function() order[#order+1]="survived" end)
        check("new work cannot bypass a scheduled continuation",ran==100 and #order==0)
        env.inCombat=true;tick()
        check("combat pauses the pending continuation",ran==100 and #order==0)
        env.inCombat=false;env.fire("PLAYER_REGEN_ENABLED")
        check("resumed batches preserve FIFO coalescing cancellation and errors",ran==150
            and table.concat(order,",")=="latest,survived" and core.Combat.Pending()==0
            and reported("continuation fault") and owned and core.Runtime.owner==nil)
        tick()
        check("completed continuation does not replay",ran==150 and #order==2)

        core=fresh();ran=0
        local ok,value=core.Combat.Queue(function()
            core.Combat.Queue(repeatWork)
            return "result"
        end)
        check("immediate work retains results and bounds nested work",ok and value=="result"
            and ran==99 and core.Combat.Pending()==1)
        tick()
        check("nested immediate work resumes next frame",ran==150 and core.Combat.Pending()==0)
        tick()
        check("completed immediate batch does not replay",ran==150 and core.Combat.Pending()==0)
        ok=core.Combat.Queue(function() error("immediate fault") end)
        check("immediate failure preserves its false result",not ok and reported("immediate fault"))
        ran=0
        local keyedRepeat
        keyedRepeat=function()
            ran=ran+1
            if ran<150 then core.Combat.Queue(keyedRepeat,"last") end
        end
        core.Combat.Queue(keyedRepeat,"last")
        check("cancelling final scheduled job empties queue",ran==100
            and core.Combat.Cancel("last") and core.Combat.Pending()==0)
        tick()
        check("cancelled continuation never fires its callback",ran==100)
    end


    core, calls = ready(fresh()), {}
    core:RegisterModule("lateconsumer", { OnEnable = function() calls[#calls + 1] = "consumer" end },
        { dependencies = { "lateprovider" } })
    check("missing late provider blocks before activation", core:GetModuleState("lateconsumer") == "blocked")
    core:RegisterModule("lateprovider", { OnEnable = function() calls[#calls + 1] = "provider" end })
    check("new provider unblocks a consumer that never started",
        table.concat(calls, ",") == "provider,consumer" and core:GetModuleState("lateconsumer") == "enabled")

    core, calls = fresh(), {}
    local healthy = { OnEnable = function()
        core:RegisterEvent("SPELLS_CHANGED", function()
            core:RegisterEvent("UNIT_HEALTH", function() calls[#calls + 1] = "healthy" end)
        end)
    end }
    core:RegisterModule("healthyowner", healthy)
    core:RegisterModule("failingowner", { OnEnable = function()
        env.fire("SPELLS_CHANGED")
        error("owner failure")
    end })
    ready(core)
    env.fire("UNIT_HEALTH", "player")
    check("nested event subscriptions inherit the handler owner", #calls == 1)
    core:UnregisterOwner(healthy)
    env.fire("UNIT_HEALTH", "player")
    check("owner removal includes nested subscriptions", #calls == 1)

    core = ready(fresh())
    local owner, received = {}, 0
    core:RegisterEvent("SPELLS_CHANGED", function()
        core.Combat.Queue(function()
            core:RegisterEvent("UNIT_HEALTH", function() received = received + 1 end)
        end)
    end, owner)
    env.inCombat = true
    env.fire("SPELLS_CHANGED")
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    core:UnregisterOwner(owner)
    env.fire("UNIT_HEALTH", "player")
    check("deferred work preserves subscription ownership", received == 0)


    core = fresh()
    check("malformed dependency list is rejected", not pcall(core.RegisterModule, core, "invalid", {}, { dependencies = false }))
    core.Setup = { DefaultPositions = {} }
    assert(loadfile("src/layout/layout.lua"))("RikUI", {})
    local applied = 0
    core.Layout.RefreshMovers = function() applied = applied + 1 end
    core:RegisterModule("badlayoutuser", { OnEnable = function()
        core.Layout.Apply()
        error("layout caller failed")
    end })
    env.fire("ADDON_LOADED", "RikUI")
    env.inCombat = true
    env.fire("PLAYER_LOGIN")
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    local afterDrain = applied
    core.Layout.Apply()
    check("module failure does not strand shared service pending work", afterDrain > 0 and applied > afterDrain)

    core, calls = fresh(), {}
    core:RegisterModule("dynamicconsumer", { OnEnable = function() calls[#calls + 1] = "consumer" end },
        { dependencies = { "dynamicprovider" } })
    core:RegisterModule("registrar", { OnEnable = function()
        calls[#calls + 1] = "registrar"
        core:RegisterModule("dynamicprovider", { OnEnable = function() calls[#calls + 1] = "provider" end })
    end })
    ready(core)
    check("provider registered during activation unblocks earlier consumer",
        table.concat(calls, ",") == "registrar,provider,consumer"
        and core:GetModuleState("dynamicconsumer") == "enabled")

    local cyclicAccount = {}
    cyclicAccount.profiles = cyclicAccount
    core = ready(fresh(cyclicAccount))
    check("account alias cannot corrupt known default types", core.DB.version == 1
        and core.DB.profiles ~= core.DB and core.Profile.scale == 1)

    local cyclicProfile, profileContainer = {}, {}
    cyclicProfile.chat = cyclicProfile
    profileContainer.Default, profileContainer.Alias = cyclicProfile, profileContainer
    core = ready(fresh({ profiles = profileContainer }))
    check("profile schema cycles are repaired without leaking nested defaults",
        core.Profile.chat ~= core.Profile and core.Profile.chat.fontSize == 14 and core.Profile.fontSize == nil)
    check("profile container alias becomes a distinct profile",
        core.DB.profiles.Alias ~= core.DB.profiles and core.DB.profiles.Alias.scale == 1)
    local other = { scale = 0.9 }
    other.chat = other
    core.DB.profiles.Other = other
    check("profile switch repairs known schema cycles", core:SetProfile("Other")
        and core.Profile.scale == 0.9 and core.Profile.chat ~= core.Profile and core.Profile.fontSize == nil)

    core = fresh()
    local commandOwner, explicitOwner, callerOwner = {}, {}, {}
    local commandHits, explicitHits, callerHits, unownedHits = 0, 0, 0, 0
    core:RegisterCommand("unowned", function()
        core:RegisterEvent("UNIT_HEALTH", function() unownedHits = unownedHits + 1 end)
    end, "Unowned command")
    core:RegisterCommand("explicit", function()
        core:RegisterEvent("UNIT_HEALTH", function() explicitHits = explicitHits + 1 end)
        error("owned command fault")
    end, "Explicit owner command", explicitOwner)
    commandOwner.OnEnable = function()
        core:RegisterCommand("owned", function()
            SlashCmdList.RIKUI("explicit")
            SlashCmdList.RIKUI("unowned")
            core.Combat.Queue(function()
                core:RegisterEvent("UNIT_HEALTH", function() commandHits = commandHits + 1 end)
            end, "test:command")
        end, "Inherited owner command")
    end
    core:RegisterModule("commandowner", commandOwner)
    ready(core)
    core:RegisterEvent("SPELLS_CHANGED", function()
        SlashCmdList.RIKUI("owned")
        core:RegisterEvent("UNIT_HEALTH", function() callerHits = callerHits + 1 end)
    end, callerOwner)
    env.inCombat = true
    env.fire("SPELLS_CHANGED")
    check("owned command errors stay isolated", reported("owned command fault")
        and core.Combat.Pending() == 1)
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    env.fire("UNIT_HEALTH", "player")
    check("nested commands and deferred work all run", commandHits == 1
        and explicitHits == 1 and callerHits == 1 and unownedHits == 1)
    core:UnregisterOwner(explicitOwner)
    env.fire("UNIT_HEALTH", "player")
    check("explicit command owner survives nested failure", explicitHits == 1 and commandHits == 2)
    core:UnregisterOwner(commandOwner)
    env.fire("UNIT_HEALTH", "player")
    check("command registration captures module ownership through combat deferral", commandHits == 2
        and callerHits == 3 and unownedHits == 3)
    core:UnregisterOwner(callerOwner)
    env.fire("UNIT_HEALTH", "player")
    check("command dispatch restores caller ownership and isolates unowned commands",
        callerHits == 3 and unownedHits == 4)
    check("owner cleanup preserves command availability", core:HasCommand("owned") and core:HasCommand("explicit"))

    core = fresh()
    local diagnosticOwner, diagnosticHits = {}, 0
    diagnosticOwner.Debug = function()
        core:RegisterEvent("UNIT_HEALTH", function() diagnosticHits = diagnosticHits + 1 end)
        error("owned debug fault")
    end
    core:RegisterModule("diagnosticowner", diagnosticOwner)
    ready(core)
    SlashCmdList.RIKUI("debug")
    env.fire("UNIT_HEALTH", "player")
    core:UnregisterOwner(diagnosticOwner)
    env.fire("UNIT_HEALTH", "player")
    check("module diagnostics preserve ownership and contain failures",
        diagnosticHits == 1 and reported("owned debug fault"))

    core = fresh()
    env.inCombat = true
    local survived = false
    core.Combat.Queue(function() error("queue fault") end)
    core.Combat.Queue(function() survived = true end)
    core.Print = function() error("report fault") end
    env.inCombat = false
    check("broken diagnostic sink cannot strand work", pcall(env.fire, "PLAYER_REGEN_ENABLED")
        and survived and core.Combat.Pending() == 0)
end
