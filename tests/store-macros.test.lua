local loadfile = dofile("tests/load_addon.lua").Loadfile
-- The second tier of the settings store. Measured on 69913 (2026-09-20): a CVar an addon registers
-- survives /reload but not a client restart; an account macro survives both. So what differs from the
-- defaults is also kept in account macros named "RikUI data N". The macro API is faked with a table
-- that outlives the "restart"; the CVar table is emptied, as the client does.
return function(check)
    local env = require("wow_stub")
    local NAMES = { "C_CVar", "UnitName", "GetRealmName", "C_Timer", "GetMacroInfo", "CreateMacro", "EditMacro", "DeleteMacro" }
    local saved = {}
    for _, name in ipairs(NAMES) do saved[name] = _G[name] end
    local cvars, macros, tickers, character, full, writes = {}, {}, {}, "Peepee Jameson", false, 0
    local function fakeClient()
        local registered = {}
        C_CVar = {
            RegisterCVar = function(name, value) registered[name] = true; if cvars[name] == nil then cvars[name] = value or "" end end,
            GetCVar = function(name) return cvars[name] end,
            SetCVar = function(name, value) cvars[name] = value; return true end,
        }
        GetMacroInfo = function(name) if macros[name] then return name, "icon", macros[name] .. "\n" end end
        CreateMacro = function(name, _, body)
            assert(not InCombatLockdown(), "macro created in combat")
            if full then return nil end
            macros[name], writes = body, writes + 1
            return 1
        end
        EditMacro = function(name, _, _, body)
            assert(not InCombatLockdown(), "macro edited in combat")
            macros[name], writes = body, writes + 1
            return 1
        end
        DeleteMacro = function(name) assert(not InCombatLockdown(), "macro deleted in combat"); macros[name] = nil end
        C_Timer = { NewTicker = function(_, callback) tickers[#tickers + 1] = callback; return {} end }
        UnitName, GetRealmName = function() return character end, function() return "Classic Beta PvE" end
    end
    local WITH_LAYOUT = { "src/core/core.lua", "src/platform/hooks.lua", "src/platform/hide.lua", "src/ui/media.lua", "src/setup/setup.lua", "src/setup/setup-apply.lua", "src/layout/layout-geometry.lua",
        "data/layouts.lua", "src/layout/layout-audit.lua", "src/layout/layout.lua", "src/layout/layout-rects.lua", "src/ui/motion.lua", "src/ui/skin.lua", "src/layout/layout-unlock.lua",
        "src/layout/layout-drag.lua", "src/layout/layout-presets.lua", "src/persistence/store.lua", "src/persistence/store-macros.lua" }
    local files = { "src/core/core.lua", "src/persistence/store.lua", "src/persistence/store-macros.lua" }
    local function boot(combat, db, charDB)
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        tickers = {}
        fakeClient()
        RikUI, RikUIDB, RikUICharDB = nil, db, charDB
        for _, file in ipairs(files) do assert(loadfile(file))("RikUI", {}) end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI
    end
    local function restart(combat)
        cvars = {}
        return boot(combat)
    end
    local function printed(text)
        for _, line in ipairs(env.printed) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end
    local function count(values)
        local total = 0
        for _ in pairs(values) do total = total + 1 end
        return total
    end
    local function tick() for _, callback in ipairs(tickers) do callback() end end

    local ok, reason = pcall(function()
        local core = boot()
        local store = core.Store
        local pruned = store.Prune({ scale = 1, gryphons = false, modules = { chat = true, bags = false },
            positions = { chat = { point = "CENTER", x = 219 } }, chat = { fontSize = 14, size = { width = 500, height = 200 } },
            layoutUndo = { positions = {} } }, core.Defaults.profile)
        check("only what differs from the defaults is kept: no default values, no enabled modules, no undo copies",
            pruned.scale == nil and pruned.gryphons == nil and pruned.modules.chat == nil and pruned.modules.bags == false
            and pruned.positions.chat.x == 219 and pruned.chat.fontSize == nil and pruned.chat.size.width == 500
            and pruned.layoutUndo == nil)
        check("a table with nothing left is dropped", store.Prune({ scale = 1, modules = { chat = true } }, core.Defaults.profile) == nil)


        local before, messages = writes, #env.printed
        core.Profile.cycle = core.Profile
        local _, pruneReason = store.Prune(core.Profile, core.Defaults.profile)
        check("prune reports cyclic data", type(pruneReason) == "string")
        store.FlushMacros()
        store.FlushMacros()
        check("invalid profile preserves macros and reports once", writes == before and #env.printed == messages + 1)
        core.Profile.cycle = nil
        core.CharDB.cycle = core.CharDB
        store.FlushMacros()
        check("invalid character data preserves macros", writes == before)
        core.CharDB.cycle = nil
        core.Profile.scale = 0.87
        store.FlushMacros()
        check("macro saving recovers after invalid data is repaired", writes > before)
        core.Profile.scale = 1

        core.Profile.positions.chat = { point = "CENTER", relativePoint = "BOTTOMLEFT", x = 219, y = 107 }
        core.Profile.chat.size = { width = 500, height = 200 }
        core.Profile.modules.bags = false
        core.CharDB.wizardDone = true
        core.CharDB.applied = { class = "WARRIOR", role = "dps", at = 1758200000, presetVersion = 1 }
        core.CharDB.undo = { big = string.rep("x", 4000) }
        core.CharDB.chatHistory = { { { text = "line" } } }
        tick()
        local names = {}
        for name in pairs(macros) do names[#names + 1] = name end
        table.sort(names)
        local tidy = #names >= 1
        for _, name in ipairs(names) do
            local body = macros[name]
            tidy = tidy and name:match("^RikUI data %d+$") ~= nil and #name <= 16 and #body <= 255
                and body:sub(1, 7) == "#rikui " and not body:find("\n", 1, true)
        end
        check("the settings go into account macros named RikUI data N whose body is one comment line of at most 255",
            tidy and #names <= 3, table.concat(names, ", "))

        core = restart()
        check("after a client restart, with no saved variables and no CVars, the settings come back from the macros",
            core.Profile.positions.chat ~= nil and core.Profile.positions.chat.x == 219 and core.Profile.chat.size.width == 500
            and core.Profile.modules.bags == false and core.Modules ~= nil and core.CharDB.wizardDone == true
            and core.CharDB.applied.role == "dps" and core.Store.MacroStatus().restored and not printed("restored from RikUI's macros"))
        check("defaults are whole again around what was restored", core.Profile.chat.fontSize == 14 and core.Profile.scale == 1
            and core.CharDB.profile == "Default")
        check("the undo snapshot and the chat history are not kept across a restart", core.CharDB.undo == nil
            and core.CharDB.chatHistory == nil)

        character = "Fat Franky"
        core = restart()
        check("another character shares the account settings and starts with its own character settings",
            core.Profile.positions.chat.x == 219 and core.CharDB.wizardDone == false)
        core.CharDB.wizardDone = true
        core.CharDB.askRole = false
        tick()
        character = "Peepee Jameson"
        core = restart()
        check("and saving it did not lose the first character's settings", core.CharDB.applied ~= nil
            and core.CharDB.applied.role == "dps" and core.CharDB.askRole == true)

        local before = writes
        tick()
        check("nothing is written when nothing changed", writes == before)
        env.inCombat = true
        core.Profile.scale = 0.8
        tick()
        check("macros are never touched in combat", writes == before)
        env.inCombat = false
        tick()
        check("the change is written once combat is over", writes > before)

        core.Profile.positions = {}
        core.Profile.chat.size = nil
        core.Profile.scale = 1
        core.Profile.modules.bags = true
        core.CharDB.applied = nil
        local had = count(macros)
        for index = 1, 40 do core.Profile.positions["frame" .. index] = { point = "CENTER", relativePoint = "CENTER", x = index, y = index } end
        tick()
        local grown = count(macros)
        core.Profile.positions = {}
        tick()
        check("more settings take more macros, and the spare ones are deleted again when the settings shrink",
            grown > had and count(macros) < grown)

        macros["RikUI data 1"] = macros["RikUI data 1"]:sub(1, -4) .. "zzz"
        core = restart()
        check("a macro someone edited is refused by its checksum, said once, and nothing half restored",
            printed("RikUI's macros are damaged") and next(core.Profile.positions) == nil)

        macros, full = {}, true
        core = restart()
        core.Profile.scale = 0.7
        tick()
        tick()
        local complaints = 0
        for _, line in ipairs(env.printed) do
            if line:find("macro", 1, true) and line:find("full", 1, true) then complaints = complaints + 1 end
        end
        check("a full macro list is reported once and the reload store still works", complaints == 1
            and cvars.rikuiStore_account ~= nil)
        check("macro failure remains visible", core.Store.MacroStatus().failure ~= nil
            and core.Store.BackupIssue() == "Restart backup needs attention")
        full = false
        core.Store.FlushMacros()
        check("macro retry clears failure", core.Store.MacroStatus().failure == nil)

        -- A whole layout is thirty-five positions. It is kept as the preset it started from plus the
        -- frames that were moved, which is what it almost always is.
        local savedWidth, savedHeight = UIParent.GetWidth, UIParent.GetHeight
        UIParent.GetWidth, UIParent.GetHeight = function() return 1365 end, function() return 768 end
        files, macros = WITH_LAYOUT, {}
        core = restart()
        local classic = core.Layout.PresetPositions("classic")
        for key, position in pairs(classic) do core.Profile.positions[key] = position end
        core.Profile.positions.player = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 40, y = -40 }
        core.Profile.positions.tot = nil
        tick()
        check("a whole layout with one frame moved and one left at its default fits in a single macro", count(macros) == 1,
            tostring(count(macros)))
        core = restart()
        local back = core.Profile.positions
        check("and comes back exactly: the preset's places, the moved frame, and the frame that had none",
            back.target ~= nil and back.target.x == classic.target.x and back.target.point == classic.target.point
            and back.player.x == 40 and back.tot == nil and back.chat.x == classic.chat.x
            and rawget(core.Profile, "layoutPacked") == nil)
        core.Profile.positions = { chat = { point = "CENTER", relativePoint = "BOTTOMLEFT", x = 219, y = 107 } }
        tick()
        core = restart()
        check("a few positions with no preset behind them are kept as they are", core.Profile.positions.chat.x == 219
            and core.Profile.positions.player == nil)
        UIParent.GetWidth, UIParent.GetHeight = savedWidth, savedHeight
        files = { "src/core/core.lua", "src/persistence/store.lua", "src/persistence/store-macros.lua" }

        -- Large learned data must never crowd out user settings or another character.
        macros={};character="Peepee Jameson";core=restart()
        local identity="forever:test:enUS:Player-test"
        local learned={version=1,identity=identity,models={big={values={1},mean=1,samples=1,context=string.rep("x",4000)}},
            order={"big"},recent={},completed={101,102},visits={},failures={},places={}}
        core.CharDB.questPlanMemory=learned
        core.CharDB.questPolicy={flavor="Explorer",skips={[96408]=true},arrow=false}
        core.Profile.scale=.93
        tick()
        check("large learning fits a restart backup without dropping settings",count(macros)>0
            and core.Store.MacroStatus().learningReduced==1 and not printed("too large")
            and core.CharDB.questPlanMemory==learned and #learned.models.big.context==4000)
        check("reload store retains full learning",core.Store.Load(core.Store.CharacterKey()).questPlanMemory.models.big.context==learned.models.big.context)
        core=restart()
        check("restart preserves exact quest preferences and completion history",core.Profile.scale==.93
            and core.CharDB.questPolicy.flavor=="Explorer" and core.CharDB.questPolicy.skips[96408]
            and core.CharDB.questPolicy.arrow==false and core.CharDB.questPlanMemory.completed[2]==102
            and #core.CharDB.questPlanMemory.order==0 and type(core.CharDB.questPlanMemory.recent)=="table")
        character="Fat Franky";core=restart()
        core.CharDB.questPolicy={flavor="Challenge",pins={[7]=true}}
        core.CharDB.questPlanMemory=learned
        tick();character="Peepee Jameson";core=restart()
        check("saving another large learner preserves the first character",core.CharDB.questPolicy.skips[96408]
            and core.CharDB.questPlanMemory.completed[1]==101)
        local before=writes;local previous=macros["RikUI data 1"]
        core.Profile.largeUserSetting=string.rep("u",4000)
        tick()
        check("settings-only overflow leaves previous backup intact",writes==before and macros["RikUI data 1"]==previous
            and printed("too large"))
        core.Profile.largeUserSetting=nil;core.Profile.scale=.92;tick()
        check("macro save recovers after oversized setting removed",writes>before)
        core.CharDB.questPlanMemory={version=1,identity=identity,models={},order={},recent={},completed={103}}
        tick();core=restart()
        check("small learning preserves its empty schema tables",core.CharDB.questPlanMemory
            and type(core.CharDB.questPlanMemory.order)=="table" and core.CharDB.questPlanMemory.completed[1]==103)

        macros = {}; core = restart()
        core.DB.profiles.Empty = {}
        core.DB.profiles.DefaultsOnly = { scale = 1, modules = { bags = true } }
        core.DB.profiles.Custom = { scale = 0.8 }
        core.Store.FlushMacros()
        core = restart()
        check("restart retains inactive empty and default-only profile identities",
            type(core.DB.profiles.Empty) == "table" and type(core.DB.profiles.DefaultsOnly) == "table")
        check("restored profiles receive independent defaults", core.DB.profiles.Empty
            and core.DB.profiles.Empty.scale == 1 and core.DB.profiles.Empty ~= core.DB.profiles.DefaultsOnly
            and core.DB.profiles.Custom.scale == 0.8)
        core.DB.profiles.Invalid = false
        local beforeInvalid = writes
        core.Store.FlushMacros()
        check("malformed profile does not silently become a default profile",
            writes == beforeInvalid and core.Store.MacroStatus().failure ~= nil)

        macros = {}; core = restart()
        core.Profile.scale = 0.8; core.CharDB.askRole = false
        core.Store.FlushMacros()
        cvars = {}
        core = boot(false, { profiles = { Default = { scale = 1.2 } } })
        check("loaded account keeps precedence while missing character recovers", core.Profile.scale == 1.2
            and core.CharDB.askRole == false and core.Store.MacroStatus().restored)
        cvars = {}
        core = boot(false, nil, { askRole = true, wizardDone = true })
        check("loaded character keeps precedence while missing account recovers", core.Profile.scale == 0.8
            and core.CharDB.askRole == true and core.CharDB.wizardDone == true)
        cvars = {}
        core = boot(false, { profiles = { Default = { scale = 1.3 } } }, { askRole = true })
        check("complete saved variables are never overlaid by macros", core.Profile.scale == 1.3
            and core.CharDB.askRole and not core.Store.MacroStatus().restored)
        cvars = {}
        core.Store.Save("account", { profiles = { Default = { scale = 1.1 } } })
        core = boot()
        check("CVar account permits missing character macro recovery", core.Profile.scale == 1.1
            and core.CharDB.askRole == false)
        cvars = {}
        core.Store.Save(core.Store.CharacterKey(), { askRole = true, wizardDone = true })
        core = boot()
        check("CVar character permits missing account macro recovery", core.Profile.scale == 0.8
            and core.CharDB.askRole and core.CharDB.wizardDone)
        cvars = {}
        core.Store.Save("account", false)
        core.Store.Save(core.Store.CharacterKey(), 42)
        core = boot()
        check("scalar CVar records do not block valid restart backups", core.Profile.scale == 0.8
            and core.CharDB.askRole == false)

        macros = {}; core = restart()
        local createMacro, editMacro = CreateMacro, EditMacro
        CreateMacro = function() return 1 end
        core.Profile.scale = 0.9
        core.Store.FlushMacros()
        check("unretained successful macro creation is detected", core.Store.MacroStatus().failure ~= nil
            and core.Store.BackupIssue() == "Restart backup needs attention")
        CreateMacro = createMacro
        core.Store.FlushMacros()
        check("unchanged settings retry failed creation", macros["RikUI data 1"] ~= nil
            and core.Store.MacroStatus().failure == nil)
        EditMacro = function(name, _, _, text) macros[name] = text:sub(1, -2); return 1 end
        core.Profile.scale = 0.7
        core.Store.FlushMacros()
        check("truncated macro edits are detected", core.Store.MacroStatus().failure ~= nil)
        EditMacro = editMacro
        core.Store.FlushMacros()
        core = restart()
        check("unchanged settings retry truncated edits and survive restart", core.Profile.scale == 0.7
            and core.Store.MacroStatus().failure == nil)

        macros = {}; core = restart()
        core.DB.community.Travel = { class = "WARRIOR", version = 1,
            roles = { travel = { slots = {}, macros = { test = "#showtooltip\n/say Ready" } } } }
        core.Store.FlushMacros()
        core = restart()
        local imported = core.DB.community.Travel
        check("restart retains imported preset definitions", imported and imported.roles.travel.macros.test
            == "#showtooltip\n/say Ready" and type(imported.roles.travel.slots) == "table")
        local previous, before = macros["RikUI data 1"], writes
        core.DB.community.TooLarge = { body = string.rep("x", 4000) }
        core.Store.FlushMacros()
        check("oversized imported presets preserve previous restart backup", writes == before
            and macros["RikUI data 1"] == previous and core.Store.MacroStatus().failure ~= nil)
        core.DB.community.TooLarge = nil
        core.DB.community.Cycle = core.DB.community
        core.Store.FlushMacros()
        check("cyclic preset library cannot partially write", writes == before)
        core.DB.community.Cycle = nil
        core.Store.FlushMacros()
        check("preset backup recovers without changing definitions", core.Store.MacroStatus().failure == nil)

        macros = {}; core = restart()
        local initialSummary = core.Store.BackupSummary and core.Store.BackupSummary()
        check("never-saved backup state is explicit", initialSummary and initialSummary:find("no verified snapshot", 1, true))
        core.Profile.scale = 0.8
        core.Store.FlushMacros()
        local capacity = core.Store.MacroStatus()
        check("restart status reports verified payload and budget", capacity.limit == 12 and capacity.capacity
            and capacity.bytes and capacity.bytes > 0 and capacity.bytes <= capacity.capacity
            and capacity.requiredBytes == capacity.bytes and capacity.used == count(macros))
        local beforeStatus = writes
        local encoder = core.Store.Encode
        core.Store.Encode = function() error("status must not serialize") end
        local statusOK, summary = pcall(function() return core.Store.BackupSummary() end)
        core.Store.Encode = encoder
        check("status is read-only and describes verified usage", statusOK and writes == beforeStatus
            and summary:find("Last verified restart snapshot:", 1, true)
            and summary:find("/12 macros", 1, true) and summary:find("bytes", 1, true))
        core.DB.community.Large = { body = string.rep("x", 4000) }
        core.Store.FlushMacros()
        local overflow = core.Store.MacroStatus()
        local warning = core.Store.BackupSummary and core.Store.BackupSummary()
        check("overflow retains verified usage and reports required capacity", overflow.bytes == capacity.bytes
            and overflow.requiredBytes and overflow.requiredBytes > overflow.capacity and writes == beforeStatus
            and warning and warning:find("Remove unused profiles or imported presets", 1, true))
        core.DB.community.Large = nil
        core.Store.FlushMacros()
        core = restart()
        check("readback restores verified usage after restart", core.Store.MacroStatus().bytes == capacity.bytes
            and core.Store.MacroStatus().failure == nil)
        SlashCmdList.RIKUI("store")
        check("store command includes the capacity summary", printed("Last verified restart snapshot:"))

        local function brokenSnapshot(data)
            local text = core.Store.Encode(data)
            local a, b = 1, 0
            for i = 1, #text do a = (a + text:byte(i)) % 65521; b = (b + a) % 65521 end
            macros = { ["RikUI data 1"] = "#rikui 1/1 " .. (b * 65536 + a) .. " " .. text }
            return restart()
        end
        local malformed = {
            { account = { profiles = false } },
            { account = { profiles = { Default = false } } },
            { account = { profiles = { Default = { scale = 0.4,
                layoutPacked = { base = "classic", moved = false } } } } },
            { account = { profiles = { Default = { scale = 0.4 } } }, characters = false },
            { account = { community = false } },
            { characters = { broken = false } },
        }
        for index, data in ipairs(malformed) do
            core = brokenSnapshot(data)
            check("malformed restart snapshot is rejected before overlay " .. index, core.Profile.scale == 1
                and core.Runtime.loggedIn and not core.Store.MacroStatus().restored
                and core.Store.MacroStatus().failure ~= nil and not printed("Settings RestoreLate:"))
        end
        macros = {}; core = restart()
        local macroReader = GetMacroInfo
        GetMacroInfo = function() error("read unavailable") end
        local safeRead, restored = pcall(core.Store.RestoreLate)
        check("macro read exceptions become explicit recovery failures", safeRead and not restored
            and core.Store.MacroStatus().failure ~= nil)
        GetMacroInfo = macroReader

        macros = {}; core = restart()
        core.Profile.customPayload = string.rep("old", 250)
        core.Store.FlushMacros()
        local prior = {}
        for name, value in pairs(macros) do prior[name] = value end
        core.Profile.customPayload = string.rep("new", 250)
        local editMacro, rejected = EditMacro, false
        EditMacro = function(name, ...)
            if name == "RikUI data 2" and not rejected then rejected = true; return nil end
            return editMacro(name, ...)
        end
        core.Store.FlushMacros()
        EditMacro = editMacro
        local intact = true
        for name, value in pairs(prior) do if macros[name] ~= value then intact = false end end
        check("partial macro overwrite rolls back prior snapshot", intact and core.Store.MacroStatus().failure ~= nil)
        core = restart()
        check("rolled back restart snapshot remains readable", core.Profile.customPayload == string.rep("old", 250))
        core.Profile.customPayload = string.rep("new", 250)
        core.Store.FlushMacros()
        check("macro retry after rollback succeeds", core.Store.MacroStatus().failure == nil)

        local deleteMacro = DeleteMacro
        core.Profile.customPayload = nil
        local deleteRejected = false
        DeleteMacro = function(name)
            if not deleteRejected then deleteRejected = true; return end
            return deleteMacro(name)
        end
        local beforeShrink = macros["RikUI data 1"]
        core.Store.FlushMacros()
        DeleteMacro = deleteMacro
        check("cleanup failure rolls back prior header", macros["RikUI data 1"] == beforeShrink
            and core.Store.MacroStatus().failure ~= nil)
        macros = {}; core = restart()
        core.Profile.customPayload = string.rep("first", 150)
        local createMacro = CreateMacro
        CreateMacro = function(name, ...)
            if name == "RikUI data 2" then return nil end
            return createMacro(name, ...)
        end
        core.Store.FlushMacros()
        CreateMacro = createMacro
        check("failed first save removes partial created macros", next(macros) == nil
            and core.Store.MacroStatus().failure ~= nil)
        core.Store.FlushMacros()
        core.Profile.customPayload = string.rep("changed", 120)
        local failures = 0
        EditMacro = function(name, ...)
            failures = failures + 1
            if failures >= 2 then return nil end
            return editMacro(name, ...)
        end
        core.Store.FlushMacros()
        EditMacro = editMacro
        check("rollback failure is explicit", core.Store.MacroStatus().failure
            and core.Store.MacroStatus().failure:find("could not be fully restored", 1, true))

        macros = { ["RikUI data 1"] = "/say my macro" }; core = restart()
        local collisionWrites = writes
        core.Store.FlushMacros()
        check("same-name user macro is never overwritten", macros["RikUI data 1"] == "/say my macro"
            and writes == collisionWrites and core.Store.MacroStatus().failure ~= nil)
        macros = {}; core = restart()
        core.Profile.customPayload = string.rep("a", 600)
        macros["RikUI data 2"] = "/say later collision"
        collisionWrites = writes
        core.Store.FlushMacros()
        check("later macro collision prevents all earlier writes", writes == collisionWrites
            and macros["RikUI data 1"] == nil and macros["RikUI data 2"] == "/say later collision")
        macros["RikUI data 2"] = nil
        core.Store.FlushMacros()
        check("macro save recovers after collision removed", core.Store.MacroStatus().failure == nil and writes > collisionWrites)
        macros["RikUI data 2"] = "/say replaced old backup"
        core.Profile.customPayload = nil
        collisionWrites = writes
        core.Store.FlushMacros()
        check("shrinking backup cannot delete user replacement", macros["RikUI data 2"] == "/say replaced old backup"
            and writes == collisionWrites)

        GetMacroInfo, CreateMacro, EditMacro, DeleteMacro = nil, nil, nil, nil
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        RikUI, RikUIDB, RikUICharDB = nil, nil, nil
        for _, file in ipairs({ "src/core/core.lua", "src/persistence/store.lua", "src/persistence/store-macros.lua" }) do assert(loadfile(file))("RikUI", {}) end
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        check("a client without the macro API keeps working without the second tier", RikUI.Profile ~= nil
            and RikUI.Store.MacrosAvailable() == false)
        check("missing macro API is explicit in summary", RikUI.Store.BackupSummary
            and RikUI.Store.BackupSummary():find("Restart backup unavailable", 1, true))
    end)
    for _, name in ipairs(NAMES) do _G[name] = saved[name] end
    env.inCombat = false
    check("store macros suite completes", ok, reason)
end
