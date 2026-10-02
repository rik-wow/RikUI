local loadfile = dofile("tests/load_addon.lua").Loadfile
-- Core contract tests, run by tests/run_tests.lua in the existing WoW stub.
return function(check)
    local env = require("wow_stub")
    local function contains(text)
        for _, line in ipairs(env.printed) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end
    local function loadCore(db, charDB)
        env.frames, env.printed, env.inCombat = {}, {}, false
        RikUI, RikUIDB, RikUICharDB = nil, db, charDB
        assert(loadfile("src/core/core.lua"))("RikUI", {})
        return RikUI
    end
    local function ready(core)
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        return core
    end

    do
        local repaired = ready(loadCore({ profiles = { Default = { scale = 100, textScale = -1, font = "missing",
            tooltip = { scale = 0 }, bags = { columns = 11.5, capacityThreshold = 99 },
            castbars = { height = -4, widthScale = 9 }, unitframes = { healthText = "unknown" },
            futurePreference = "keep" } } }))
        check("unsafe restored global sizes use defaults", repaired.Profile.scale == 1 and repaired.Profile.textScale == 1)
        check("unsafe restored feature dimensions use defaults", repaired.Profile.tooltip.scale == 1
            and repaired.Profile.bags.columns == 10 and repaired.Profile.bags.capacityThreshold == 4
            and repaired.Profile.castbars.height == 22 and repaired.Profile.castbars.widthScale == 1)
        check("unknown enum choices use defaults but future keys survive", repaired.Profile.font == "bundled"
            and repaired.Profile.unitframes.healthText == "both" and repaired.Profile.futurePreference == "keep")
        repaired.DB.profiles.Boundary = { scale = 0.25, textScale = 1.3, tooltip = { scale = 1.5 },
            bags = { columns = 16, capacityThreshold = 0 }, font = "game", unitframes = { healthText = "hidden" } }
        repaired:SetProfile("Boundary")
        check("legal settings limits survive profile selection", repaired.Profile.scale == 0.25 and repaired.Profile.textScale == 1.3
            and repaired.Profile.tooltip.scale == 1.5 and repaired.Profile.bags.columns == 16
            and repaired.Profile.bags.capacityThreshold == 0 and repaired.Profile.font == "game"
            and repaired.Profile.unitframes.healthText == "hidden")
    end

    do
        local journalCore = ready(loadCore())
        for _ = 1, 5 do journalCore.Runtime.Report("Repeated", "failure") end
        check("runtime failure prints once", #env.printed == 1)
        local history = journalCore:GetErrors()
        check("runtime errors retain occurrence count", #history == 1 and history[1].count == 5)
        history[1].count = 0
        check("runtime history is detached", journalCore:GetErrors()[1].count == 5)
        for index = 1, 25 do journalCore.Runtime.Report("Error " .. index, "detail") end
        check("runtime error history is bounded", #journalCore:GetErrors() == 20)
        SlashCmdList.RIKUI("errors")
        check("errors command shows retained details", contains("Error 25"))
        SlashCmdList.RIKUI("errors clear")
        check("errors clear empties session history", #journalCore:GetErrors() == 0)
        journalCore.Runtime.Report(env.SECRET, env.SECRET)
        check("secret error details remain opaque", journalCore:GetErrors()[1].detail == "unknown error")
        journalCore.Runtime.Report("Long", string.rep("a", 1000))
        check("error detail memory is bounded", #journalCore:GetErrors()[2].detail == 512)
    end

    do
        local invalid = {kept=true}
        local namesCore = ready(loadCore({profiles={Default={},[1]=invalid,["|bad"]={},["Alt"]={},["équipe"]={}}},
            {profile="|bad"}))
        check("invalid restored profile selection falls back", namesCore.CharDB.profile == "Default")
        check("invalid profile records are preserved", namesCore.DB.profiles[1] == invalid and invalid.kept == true)
        local names = namesCore:GetProfileNames()
        check("profile names exclude invalid keys and retain unicode", #names == 3 and names[1] == "Alt" and names[3] == "équipe")
        check("invalid direct profile selection refused", not namesCore:SetProfile("|bad"))
    end

    do
        local repaired = ready(loadCore({ profiles = { Default = {
            chat = { fontSize = 999, size = { width = -5, height = 200 } },
            panels = { questTextSize = 99 }, swingtimer = { stopLead = -1 },
            nameplates = { healthHeight = 100, nameHeight = "wide" },
            borderColor = { 2, 0.5, 0.5 }, customExtension = { retained = true },
        } } }))
        local profile = repaired.Profile
        check("saved chat font obeys portable limits", profile.chat.fontSize == 14)
        check("malformed optional chat size is removed", profile.chat.size == nil)
        check("saved panel text and swing lead obey portable limits", profile.panels.questTextSize == 0
            and profile.swingtimer.stopLead == 0.6)
        check("malformed optional appearance is removed", profile.nameplates.healthHeight == nil
            and profile.nameplates.nameHeight == nil and profile.borderColor == nil)
        check("unknown profile extension survives shared repair", profile.customExtension.retained == true)
    end

    do
        local supportCore = ready(loadCore())
        check("support report API exists", type(supportCore.SupportReport) == "function")
        if supportCore.SupportReport then
            supportCore:RegisterModule("supportBroken", { OnEnable = function() error("support fixture failure") end })
            supportCore:RegisterModule("supportHealthy", {})
            supportCore.Profile.modules.supportHealthy = false
            supportCore.CharDB.privateFixture = "DO_NOT_INCLUDE_CHARACTER_DATA"
            supportCore.Store = { BackupSummary = function() return "Backup fixture ready" end,
                Flush = function() error("report attempted a save") end }
            env.inCombat = true
            supportCore.Combat.Queue(function() end, "support:fixture")
            local report = supportCore:SupportReport()
            check("support reports actual failures and pending choices", report:find("supportBroken: failed", 1, true)
                and report:find("supportHealthy: enabled; next reload=off", 1, true))
            check("support includes backup and queued work", report:find("Backup fixture ready", 1, true)
                and report:find("Queued work: 1", 1, true))
            check("support excludes character records", not report:find("DO_NOT_INCLUDE_CHARACTER_DATA", 1, true))
            supportCore.Combat.Cancel("support:fixture"); env.inCombat = false
            local metadata = GetBuildInfo
            GetBuildInfo = function() error("optional metadata unavailable") end
            check("support survives optional metadata failure", type(supportCore:SupportReport()) == "string")
            GetBuildInfo = metadata
            for index = 1, 30 do supportCore.Runtime.Report("Report "..index .. string.rep("c", 512), string.rep("x", 1000)) end
            check("support report has bounded size", #supportCore:SupportReport() <= 20000 and supportCore:SupportReport():find("[Report truncated]", 1, true))
            SlashCmdList.RIKUI("support")
            check("support command has chat fallback", contains("RikUI support report"))
        end
    end

    do
        local reloadCore = loadCore()
        check("reload state before login is clear", not reloadCore:ProfileNeedsReload())
        reloadCore:RegisterModule("reloadFixture", {})
        ready(reloadCore)
        check("unchanged loaded profile needs no reload", not reloadCore:ProfileNeedsReload())
        for _, change in ipairs({ {"font", "game"}, {"textScale", 1.2}, {"reducedMotion", true} }) do
            local key, value = change[1], change[2]
            local previous = reloadCore.Profile[key]
            reloadCore.Profile[key] = value
            check("active profile " .. key .. " change needs reload", reloadCore:ProfileNeedsReload())
            reloadCore.Profile[key] = previous
            check("reverted " .. key .. " clears reload", not reloadCore:ProfileNeedsReload())
        end
        reloadCore:SetModuleEnabled("reloadFixture", false)
        check("module change in active profile needs reload", reloadCore:ProfileNeedsReload())
        reloadCore:SetModuleEnabled("reloadFixture", true)
        check("reverted module change clears reload", not reloadCore:ProfileNeedsReload())
    end

    do
        local blockedCore = ready(loadCore())
        blockedCore.DB.blockedActions = {{ event = "ADDON_ACTION_BLOCKED", func = "ProtectedFixture",
            combat = false, at = "fixture-time", zone = "PRIVATE_ZONE", stack = "PRIVATE_STACK" }}
        local report = blockedCore:SupportReport()
        check("support includes blocked action summary", report:find("ProtectedFixture", 1, true) and report:find("combat=false", 1, true))
        check("support excludes blocked zone and stack", not report:find("PRIVATE_ZONE", 1, true) and not report:find("PRIVATE_STACK", 1, true))
        check("blocked journal API exists", type(blockedCore.GetBlockedActions) == "function")
        if blockedCore.GetBlockedActions then
            local rows = blockedCore:GetBlockedActions()
            rows[1].func = "changed"
            check("blocked journal reads are detached", blockedCore.DB.blockedActions[1].func == "ProtectedFixture")
        end
        blockedCore.DB.blockedActions[1].combat = nil
        check("support distinguishes unknown combat state", blockedCore:SupportReport():find("combat=<unavailable>", 1, true))
        SlashCmdList.RIKUI("blocked")
        check("blocked command displays incidents", contains("ProtectedFixture"))
        SlashCmdList.RIKUI("blocked clear")
        check("blocked clear empties history", #blockedCore.DB.blockedActions == 0)
        blockedCore.DB.blockedActions = "damaged"
        check("support tolerates damaged journal", type(blockedCore:SupportReport()) == "string" and blockedCore.DB.blockedActions == "damaged")
    end

    do
        local errorCore = ready(loadCore())
        local clock, now = GetTime, 10
        GetTime = function() return now end
        errorCore.Runtime.Report("Active", "kept")
        for index = 1, 19 do errorCore.Runtime.Report("Old" .. index, "detail") end
        now = 20
        errorCore.Runtime.Report("Active", "kept")
        errorCore.Runtime.Report("New", "detail")
        local active
        for _, row in ipairs(errorCore:GetErrors()) do if row.context == "Active" then active = row end end
        check("recurring errors survive least-recent eviction", active and active.count == 2)
        check("error chronology preserves first and last occurrence", active and active.firstAt == 10 and active.lastAt == 20
            and active.firstSequence == 1 and active.lastSequence == 21)
        GetTime = function() error("clock unavailable") end
        errorCore.Runtime.Report("Clock", "failure")
        check("error reporting survives clock failure", #errorCore:GetErrors() == 20)
        GetTime = function() return env.SECRET end
        errorCore.Runtime.Report("SecretClock", "failure")
        local rows = errorCore:GetErrors()
        check("secret clocks stay opaque", rows[#rows].lastAt == nil)
        GetTime = clock
        SlashCmdList.RIKUI("errors")
        check("error command includes chronology", contains("first #"))
        check("support includes error chronology", errorCore:SupportReport():find("last #", 1, true))
    end

    local toc = assert(io.open("RikUI.toc", "r"))
    local tocText = toc:read("*a"):gsub("\r\n", "\n")
    toc:close()
    check("TOC targets Forever 16001", tocText:find("## Interface: 16001", 1, true))
    check("TOC declares account saved variables", tocText:find("## SavedVariables: RikUIDB, RikUIStudioDB\n", 1, true))
    check("TOC declares character saved variables", tocText:find("## SavedVariablesPerCharacter: RikUICharDB", 1, true))
    local core = loadCore()
    local files = {}
    for line in tocText:gmatch("[^\r\n]+") do
        if not line:match("^%s*#") and line:match("%S") then
            files[#files + 1] = line
            if line:match("%.lua$") then
                assert(_G.loadfile(line))("RikUI", {})
            else
                -- The generated-data include: committed, and the only non-Lua entry.
                local include = io.open(line, "r")
                check("TOC include exists: " .. line, include ~= nil and line == "generated/index.xml")
                if include then include:close() end
            end
        end
    end
    core = RikUI
    check("TOC loads the runtime bootstrap first", files[1] == "src/core/core.lua")
    check("TOC loads Studio after sharing and its transaction service", files[#files] == "src/configuration/options/setup-studio-view.lua"
        and files[#files - 1] == "src/setup/setup-studio.lua"
        and files[#files - 2] == "src/configuration/options/importexport.lua")
    check("TOC loads data and preset namespaces", type(core.Data) == "table" and type(core.Presets) == "table")

    core = loadCore()
    local enabled, disabled = 0, 0
    core:RegisterModule("enabled", { OnEnable = function(self) enabled = enabled + 1 end })
    core:RegisterModule("disabled", { OnEnable = function(self) disabled = disabled + 1 end })
    env.fire("ADDON_LOADED", "AnotherAddon")
    check("unrelated ADDON_LOADED leaves saved variables untouched", RikUIDB == nil and RikUICharDB == nil)
    RikUIDB = { profiles = { Default = { modules = { disabled = false } } } }
    env.fire("ADDON_LOADED", "RikUI")
    check("modules do not enable before login", enabled == 0 and disabled == 0)
    check("fresh database receives nested defaults", RikUIDB.version == 1 and core.Profile.scale == 1
        and type(core.Profile.positions) == "table" and type(RikUIDB.community) == "table")
    check("fresh character is not already configured", RikUICharDB.profile == "Default"
        and RikUICharDB.askRole == true and RikUICharDB.wizardDone == false and RikUICharDB.applied == nil)
    check("module enabled flags come from profile", core.Modules.enabled.enabled == true
        and core.Modules.disabled.enabled == false and core.Profile.modules.enabled == true)
    env.fire("PLAYER_LOGIN")
    env.fire("PLAYER_LOGIN")
    check("login enables only enabled modules once", enabled == 1 and disabled == 0)
    local profileBefore = core.Profile
    env.fire("ADDON_LOADED", "RikUI")
    check("repeated addon load preserves initialized profile", core.Profile == profileBefore and enabled == 1)
    local lateEnabled = 0
    core:RegisterModule("late", { OnEnable = function() lateEnabled = lateEnabled + 1 end })
    check("module registered after login enables once", lateEnabled == 1)

    local ownerCalls, ownerEvents = 0, 0
    local owner = { OnEnable = function()
        ownerCalls = ownerCalls + 1
        if ownerCalls > 1 then error("alias activation would remove original subscriptions") end
        core:RegisterEvent("UNIT_HEALTH", function() ownerEvents = ownerEvents + 1 end)
    end }
    core:RegisterModule("identityOwner", owner)
    local aliasOK = pcall(function() core:RegisterModule("identityAlias", owner) end)
    env.fire("UNIT_HEALTH", "player")
    check("duplicate module identity is rejected", not aliasOK)
    check("alias leaves original activation and callbacks intact", ownerCalls == 1 and ownerEvents == 1
        and core:GetModuleState("identityOwner") == "enabled")
    check("alias leaves no registry record or profile flag", core.Modules.identityAlias == nil
        and core:GetModuleState("identityAlias") == nil and core.Profile.modules.identityAlias == nil)
    core.Profile.modules.disabledAlias = false
    check("disabled alias cannot change original enabled flag",
        not pcall(function() core:RegisterModule("disabledAlias", owner) end) and owner.enabled == true)
    local invalidOwner = {}
    check("invalid registration does not claim identity", not pcall(function()
        core:RegisterModule("invalidIdentity", invalidOwner, { dependencies = false })
    end))
    check("valid registration after invalid options succeeds",
        pcall(function() core:RegisterModule("validIdentity", invalidOwner) end))

    local saved = { version = 2, community = { example = {} }, profiles = {
        Default = { scale = 0.8 }, Custom = { scale = 1.3, positions = { bars = { x = 42 } }, modules = { bars = false } },
    } }
    local character = { profile = "Custom", askRole = false, wizardDone = true, applied = { role = "tank" } }
    core = ready(loadCore(saved, character))
    check("saved tables and selected profile survive", RikUIDB == saved and RikUICharDB == character
        and core.Profile == saved.profiles.Custom and core.Profile.scale == 1.3)
    check("nested saved values and false flags survive defaults", core.Profile.positions.bars.x == 42
        and core.Profile.modules.bars == false and character.askRole == false and character.wizardDone == true)
    check("defaults merge all profiles without replacing version or applied", saved.profiles.Default.modules
        and saved.profiles.Default.scale == 0.8 and saved.version == 2 and character.applied.role == "tank")
    core.Profile.positions.test = true
    check("default tables are independent between profiles", saved.profiles.Default.positions.test == nil)
    core = ready(loadCore({}, { profile = "New" }))
    check("missing selected profile gets defaults", core.Profile == RikUIDB.profiles.New and core.Profile.scale == 1)
    core = ready(loadCore(false, { profile = false }))
    check("malformed saved variable containers recover", type(RikUIDB) == "table" and RikUICharDB.profile == "Default")

    local calls, eventName, unit = 0
    core:RegisterEvent("UNIT_HEALTH", function(event, value) calls = calls + 1; eventName, unit = event, value end)
    core:RegisterEvent("UNIT_HEALTH", function() calls = calls + 1 end)
    env.fire("UNIT_HEALTH", "player")
    check("event bus fans out event and arguments", calls == 2 and eventName == "UNIT_HEALTH" and unit == "player")
    local before = #env.printed
    local ok = core:RegisterEvent("NO_SUCH_EVENT", function() error("must not subscribe") end)
    core:RegisterEvent("NO_SUCH_EVENT", function() end)
    check("unknown event returns false and reports once", ok == false and #env.printed == before + 1
        and contains("NO_SUCH_EVENT"))
    local frame = env.frames[1]
    local register = frame.RegisterEvent
    frame.RegisterEvent = function(self, event)
        if event == "REJECTED_EVENT" then return false end
        return register(self, event)
    end
    check("false native registration is rejected", core:RegisterEvent("REJECTED_EVENT", function() end) == false)
    local survived = false
    core:RegisterEvent("SPELLS_CHANGED", function() error("subscriber failed") end)
    core:RegisterEvent("SPELLS_CHANGED", function() survived = true end)
    check("failing subscriber does not abort event dispatch", pcall(env.fire, "SPELLS_CHANGED") and survived
        and contains("subscriber failed"))

    local added, lateCalls = false, 0
    core:RegisterEvent("UNIT_HEALTH", function()
        if added then return end
        added = true
        core:RegisterEvent("UNIT_HEALTH", function() lateCalls = lateCalls + 1 end)
    end)
    env.fire("UNIT_HEALTH", "player")
    check("new event subscriber waits until next dispatch", lateCalls == 0)
    env.fire("UNIT_HEALTH", "player")
    check("new event subscriber receives subsequent events", lateCalls == 1)

    local secret = env.SECRET
    local oldMeta = getmetatable(secret)
    setmetatable(secret, { __tostring = function() error("secret was formatted") end,
        __add = function() error("secret was used in arithmetic") end })
    local readOk, value, missing, flag = core.Secret.Read(function() return secret, nil, false end)
    check("secret reader preserves values and nil holes", readOk and rawequal(value, secret) and missing == nil and flag == false)
    local failure, reason = core.Secret.Read(function() error("unit read failed") end)
    check("secret reader catches API failures", failure == false and reason:find("unit read failed", 1, true))
    check("secret helper reports secrecy", core.Secret.IsSecret(secret) == true and core.Secret.IsSecret(10) == false)
    local delivered
    local sinkOk = core.Secret.Apply(function(v) delivered = v end, function() return secret end)
    check("secret apply passes opaque value to sink", sinkOk and rawequal(delivered, secret))
    local sinkFailed = core.Secret.Apply(function() error("sink failed") end, function() return secret end)
    check("secret apply catches sink errors", sinkFailed == false)
    local argumentCount, first, middle, last
    core.Secret.Apply(function(...)
        argumentCount = select("#", ...)
        first, middle, last = ...
    end, function() return secret, nil, false end)
    check("secret apply preserves nil return slots", argumentCount == 3 and rawequal(first, secret) and middle == nil and last == false)
    local sinkCalled = false
    local failedApply = core.Secret.Apply(function() sinkCalled = true end, function() error("read failed") end)
    check("secret apply skips sink on failed read", failedApply == false and not sinkCalled)
    core:RegisterModule("diagnostic", { Debug = function(self, report)
        report("health", UnitHealth, "player")
        report("tuple", function() return nil, false, secret end)
        report("failure", function() error("debug read failed") end)
        report("empty", function() end)
    end })
    SlashCmdList.RIKUI("debug")
    check("debug prints secrecy rather than raw values", contains("diagnostic.health[1] secret=true")
        and contains("diagnostic.tuple[1] secret=false") and contains("diagnostic.tuple[3] secret=true"))
    check("debug reports failed reads", contains("debug read failed"))
    check("debug reports readers with no return values", contains("diagnostic.empty: no values returned"))
    setmetatable(secret, oldMeta)
    SlashCmdList.RIKUI("")
    check("empty slash command lists available commands", SLASH_RIKUI1 == "/rik" and contains("/rik debug"))
    local routed
    core:RegisterCommand("echo", function(args) routed = args end, "Echo a value")
    SlashCmdList.RIKUI("  ECHO  Hello World  ")
    check("slash router normalizes command but preserves arguments", routed == "Hello World")
    SlashCmdList.RIKUI("unknown")
    check("unknown slash command prints help", contains("Unknown command: unknown"))

    local order = {}
    core.Combat.Queue(function() order[#order + 1] = "now" end)
    check("combat queue runs immediately out of combat", order[1] == "now")
    env.inCombat = true
    core.Combat.Queue(function() order[#order + 1] = "first" end)
    core.Combat.Queue(function() error("queued failure") end)
    core.Combat.Queue(function() order[#order + 1] = "last" end)
    env.fire("PLAYER_REGEN_ENABLED")
    check("combat queue does not drain while still locked down", #order == 1)
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("combat queue preserves FIFO and survives failures", table.concat(order, ",") == "now,first,last"
        and contains("queued failure"))
    env.fire("PLAYER_REGEN_ENABLED")
    check("combat queue runs each item once", #order == 3)
    env.inCombat = true
    core.Combat.Queue(function() env.inCombat = true end)
    core.Combat.Queue(function() order[#order + 1] = "after-combat" end)
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("combat queue pauses if combat resumes during drain", #order == 3)
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("paused combat work survives for the next drain", order[4] == "after-combat")

    local appended = {}
    env.inCombat = true
    core.Combat.Queue(function()
        appended[#appended + 1] = "first"
        core.Combat.Queue(function() appended[#appended + 1] = "nested" end)
        env.fire("PLAYER_REGEN_ENABLED")
    end)
    core.Combat.Queue(function() appended[#appended + 1] = "second" end)
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("work added during drain stays FIFO and nested drains do not replay",
        table.concat(appended, ",") == "first,second,nested")

    core = loadCore()
    local lastEnabled = false
    core:RegisterModule("broken", { OnEnable = function() error("enable failed") end })
    core:RegisterModule("healthy", { OnEnable = function() lastEnabled = true end })
    ready(core)
    check("module failure does not prevent other modules enabling", lastEnabled and contains("enable failed"))
    check("duplicate module names fail explicitly", pcall(function() core:RegisterModule("healthy", {}) end) == false)
end
