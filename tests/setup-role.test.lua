local loadfile = dofile("tests/load_addon.lua").Loadfile
-- Role inference and popup choices through the real core event/command paths.
return function(check)
    local env = require("wow_stub")
    local globals = { "C_SpecializationInfo", "C_ClassTalents", "C_Traits", "StaticPopupDialogs", "StaticPopup_Show",
        "StaticPopup_Hide", "GetNumTalentTabs", "GetTalentTabInfo" }
    local saved = {}
    for _, name in ipairs(globals) do saved[name] = _G[name] end
    local points, popups, calls, reads, setup, failRead, unavailable, failedShow, busy
    local function printed(fragment)
        for _, line in ipairs(env.printed) do
            if line:find(fragment, 1, true) then return true end
        end
    end
    local function fresh(rejectEvent)
        env.frames, env.printed, env.inCombat = {}, {}, false
        RikUIDB, RikUICharDB = nil, nil
        points, popups, calls, reads = { 0, 0, 0 }, {}, {}, 0
        failRead, unavailable, failedShow, busy = false, false, false, false
        GetNumTalentTabs, GetTalentTabInfo = nil, nil
        C_SpecializationInfo = nil
        C_ClassTalents = { GetActiveConfigID = function() return not unavailable and 42 or nil end }
        C_Traits = {
            ConfigHasStagedChanges = function(id) assert(id == 42); return false end,
            GetConfigInfo = function(id) assert(id == 42); return { treeIDs = { 900 } } end,
            GetGroupDisplayInfoByTreeID = function(id)
                assert(id == 900)
                return { { groupID = 11, displayName = "Arms" },
                    { groupID = 22, displayName = "Fury" },
                    { groupID = 33, displayName = "Protection" } }
            end,
            GetGroupCurrencyInfo = function(id, groups)
                assert(id == 42 and #groups == 3)
                reads = reads + 1
                if failRead then error("talents unavailable") end
                return { { traitNodeGroupID = 22, currencyInfos = { { spent = points[2] } } },
                    { traitNodeGroupID = 33, currencyInfos = { { spent = points[3] } } },
                    { traitNodeGroupID = 11, currencyInfos = { { spent = points[1] } } } }
            end,
        }
        StaticPopupDialogs = {}
        StaticPopup_Show = function(which, text1, text2, data)
            if failedShow then return nil end
            local dialog = { which = which, data = data, shown = true }
            popups[#popups + 1] = dialog
            dialog.text = string.format(StaticPopupDialogs[which].text, text1, text2)
            return dialog
        end
        StaticPopup_Hide = function(which)
            for _, dialog in ipairs(popups) do if dialog.which == which then dialog.shown = false end end
        end
        if rejectEvent then env.KNOWN_EVENTS.PLAYER_TALENT_UPDATE = nil end
        for _, file in ipairs({ "src/core/core.lua", "data/spells.lua", "presets/warrior.lua", "src/setup/setup.lua", "src/setup/setup-talents.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        setup = RikUI.Setup
        setup.IsApplying, setup.IsUndoing = function() return busy end, function() return false end
        setup.Apply = function(class, role, opts) calls[#calls + 1] = { class = class, role = role, opts = opts } end
        local chunk = loadfile("src/setup/setup-role.lua")
        if chunk then chunk("RikUI", {}) end
        env.KNOWN_EVENTS.PLAYER_TALENT_UPDATE = true
        env.fire("ADDON_LOADED", "RikUI")
        RikUICharDB.applied = { class = "WARRIOR", role = "dps" }
        env.fire("PLAYER_LOGIN")
    end
    local function changed() env.fire("PLAYER_TALENT_UPDATE") end
    local function click(handler)
        local dialog = popups[#popups]
        StaticPopupDialogs[dialog.which][handler](dialog, dialog.data, "clicked")
    end
    local function restore()
        for _, name in ipairs(globals) do _G[name] = saved[name] end
    end

    fresh()
    local available = type(setup.GuessRole) == "function"
    check("role service exposes GuessRole", available)
    if not available then restore(); return end
    check("talent events register through core", env.frames[1].events.CHARACTER_POINTS_CHANGED
        and env.frames[1].events.PLAYER_TALENT_UPDATE)
    check("Warrior defines explicit first role", RikUI.Presets.WARRIOR.roleOrder
        and RikUI.Presets.WARRIOR.roleOrder[1] == "dps")
    check("zero points defaults to first role", setup.GuessRole("WARRIOR") == "dps")
    points = { 0, 0, 9 }
    check("nine total points still defaults", setup.GuessRole("WARRIOR") == "dps")
    points = { 0, 0, 10 }
    local role, trees = setup.GuessRole("WARRIOR")
    check("ten spent Protection points chooses tank", role == "tank")
    check("returns actual points and tree labels", trees and trees[3].points == 10
        and trees[3].name == "Protection")
    points = { 6, 6, 10 }
    check("separate damage trees no longer outweigh larger Protection tree", setup.GuessRole("WARRIOR") == "tank")
    points = { 10, 5, 10 }
    check("ties use explicit order", setup.GuessRole("WARRIOR") == "dps")
    RikUI.Presets.WARRIOR.roleOrder = { "tank", "dps", "fury" }
    check("tie follows changed first role", setup.GuessRole("WARRIOR") == "tank")
    points = { 1, 1, 0 }
    check("under threshold uses declared first role", setup.GuessRole("WARRIOR") == "tank")
    check("Resolve shares the declared default role", setup.Resolve("WARRIOR").role == "tank")
    check("unsupported class has no fabricated guess", setup.GuessRole("MAGE") == nil)

    fresh()
    C_Traits.GetGroupCurrencyInfo = function()
        return { { traitNodeGroupID = 33, currencyInfos = { { spent = 12 } } } }
    end
    local sparseRole, sparseTrees = setup.GuessRole("WARRIOR")
    check("omitted unspent groups count as zero beside a funded tree", sparseRole == "tank"
        and sparseTrees and sparseTrees[1].points == 0 and sparseTrees[2].points == 0
        and sparseTrees[3].points == 12)
    fresh()
    C_Traits.GetGroupCurrencyInfo = function() return {} end
    local emptyRole, emptyTrees = setup.GuessRole("WARRIOR")
    check("empty group currency array represents no spent points", emptyRole == "dps"
        and emptyTrees and #emptyTrees == 3 and emptyTrees[1].points == 0
        and emptyTrees[2].points == 0 and emptyTrees[3].points == 0)
    for _, currency in ipairs({ {}, { currencyInfos = {} }, { currencyInfos = { {} } },
        { currencyInfos = { { spent = env.SECRET } } } }) do
        fresh()
        currency.traitNodeGroupID = 33
        C_Traits.GetGroupCurrencyInfo = function() return { currency } end
        local badRole, _, badReason = setup.GuessRole("WARRIOR")
        check("present malformed currency is not treated as an unspent tree", badRole == nil)
        check("unreadable currency diagnostic identifies its tree", badReason
            and badReason:find("Protection", 1, true))
    end

    for _, value in ipairs({ -1, 0.5, "10", env.SECRET, math.huge }) do
        fresh()
        points[3] = value
        local ok, guess, _, reason = pcall(setup.GuessRole, "WARRIOR")
        check("invalid/secret points fail closed " .. type(value), ok and guess == nil and type(reason) == "string")
    end
    fresh()
    points[2] = nil
    check("missing tree data has no guess", setup.GuessRole("WARRIOR") == nil)
    failRead = true
    local ok, guess, _, reason = pcall(setup.GuessRole, "WARRIOR")
    check("throwing API is caught", ok and guess == nil and type(reason) == "string")
    fresh()
    unavailable = true
    local before = reads
    check("uninitialized API avoids tree reads", setup.GuessRole("WARRIOR") == nil and reads == before)
    C_Traits = nil
    SlashCmdList.RIKUI("role")
    check("missing talent API is an explicit diagnostic", printed("Role unavailable"))

    fresh()
    C_Traits.ConfigHasStagedChanges = function() return true end
    check("uncommitted talent previews never infer a role", setup.GuessRole("WARRIOR") == nil)

    fresh()
    points = { 1, 2, 12 }
    SlashCmdList.RIKUI("role")
    check("role command prints guess and each tree", printed("tank") and printed("Arms=1")
        and printed("Fury=2") and printed("Protection=12"))
    check("role diagnostic never prompts or applies", #popups == 0 and #calls == 0)
    before = reads
    SlashCmdList.RIKUI("role extra")
    check("role rejects extra arguments", printed("Usage: /rik role") and reads == before)
    env.fire("CHARACTER_POINTS_CHANGED")
    check("points event shows role switch prompt", #popups == 1 and popups[1].text:find("Protection", 1, true))
    local dialog = StaticPopupDialogs[popups[1].which]
    check("popup exposes three distinct choices", dialog.button1 == "Yes" and dialog.button2 == "No"
        and dialog.button3 == "Stop asking" and type(dialog.OnAlt) == "function")
    changed(); env.fire("PLAYER_LOGIN")
    check("repeated events and login callback show only one prompt", #popups == 1)
    click("OnAccept")
    check("Yes applies selected role exactly once", #calls == 1 and calls[1].class == "WARRIOR"
        and calls[1].role == "tank")
    local opts = calls[1] and calls[1].opts or {}
    check("role switch enables only bars and macros", opts.bars == true and opts.macros == true
        and opts.binds == false and opts.cvars == false and opts.layout == false)
    click("OnAccept"); changed()
    check("duplicate acceptance does not apply again", #calls == 1 and #popups == 1)

    fresh()
    points = { 0, 0, 10 }; changed(); click("OnCancel"); changed()
    check("No dismisses only this session", #calls == 0 and #popups == 1 and RikUICharDB.askRole == true)
    fresh()
    points = { 0, 0, 10 }; changed(); click("OnAlt"); changed()
    check("Stop asking persists preference", RikUICharDB.askRole == false and #calls == 0 and #popups == 1)

    for _, change in ipairs({
        function() points = { 10, 0, 0 } end,
        function() RikUICharDB.applied = nil end,
        function() RikUICharDB.applied = { class = "WARRIOR", role = "dps" } end,
        function() RikUICharDB.askRole = false end,
        function() busy = true end,
        function() RikUICharDB.undo = { progress = { bars = true } } end,
    }) do
        fresh()
        points = { 0, 0, 10 }; changed(); change(); click("OnAccept")
        check("stale/busy confirmation never applies", #calls == 0)
    end
    fresh()
    points = { 0, 0, 10 }; changed()
    env.inCombat = true
    click("OnAccept")
    check("accepted prompt queues safely in combat", #calls == 0)
    points = { 10, 0, 0 }
    env.inCombat = false; env.fire("PLAYER_REGEN_ENABLED")
    check("queued switch revalidates changed talents", #calls == 0)

    fresh()
    env.inCombat = true; points = { 0, 0, 10 }; changed(); changed()
    check("prompt waits until combat ends", #popups == 0)
    env.inCombat = false; env.fire("PLAYER_REGEN_ENABLED")
    check("coalesced combat events show one prompt", #popups == 1)

    fresh()
    failRead = true; changed()
    failRead = false; points = { 0, 0, 10 }; changed()
    check("failed read does not consume popup allowance", #popups == 1)
    fresh()
    failedShow = true; points = { 0, 0, 10 }; changed()
    failedShow = false; changed()
    check("unavailable popup frame can be retried", #popups == 1)
    fresh(true)
    points = { 0, 0, 10 }; env.fire("CHARACTER_POINTS_CHANGED")
    check("unsupported talent event leaves points event working", #popups == 1)

    for _, change in ipairs({
        function() RikUICharDB.applied = nil end,
        function() RikUICharDB.applied.class = "MAGE" end,
        function() RikUICharDB.askRole = false end,
        function() busy = true end,
        function() RikUICharDB.undo = { progress = { bars = true } } end,
    }) do
        fresh(); change()
        points = { 0, 0, 10 }; changed()
        check("ineligible state never prompts", #popups == 0 and #calls == 0)
    end
    for _, breakData in ipairs({
        function() C_Traits.GetGroupDisplayInfoByTreeID = function()
            return { { groupID = 33, displayName = "Protection" } }
        end end,
        function() C_Traits.GetGroupCurrencyInfo = function() return nil end end,
        function() C_Traits.GetConfigInfo = function() error("config failed") end end,
        function() C_ClassTalents.GetActiveConfigID = function() return env.SECRET end end,
        function() C_Traits.ConfigHasStagedChanges = function() return env.SECRET end end,
        function() RikUI.Presets.WARRIOR.roleOrder = { "dps" } end,
        function() RikUI.Presets.WARRIOR.roles.dps.trees = { 1, 1 } end,
    }) do
        fresh(); breakData()
        check("partial or invalid metadata cannot infer a role", setup.GuessRole("WARRIOR") == nil)
        changed()
        check("partial or invalid metadata cannot prompt", #popups == 0)
    end

    fresh()
    points = { 0, 0, 10 }; changed()
    click("OnHide"); click("OnAccept")
    check("hidden popup cannot later apply a stale callback", #calls == 0)
    fresh()
    points = { 0, 0, 10 }; changed()
    click("OnHide"); click("OnCancel"); changed()
    check("popup displacement does not stop asking permanently", RikUICharDB.askRole == true and #popups == 1)

    restore()
end
