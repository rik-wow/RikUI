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
    local function boot(combat)
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        tickers = {}
        fakeClient()
        RikUI, RikUIDB, RikUICharDB = nil, nil, nil
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
            and core.CharDB.applied.role == "dps" and printed("restored from RikUI's macros"))
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
        full = false

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

        GetMacroInfo, CreateMacro, EditMacro, DeleteMacro = nil, nil, nil, nil
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        RikUI, RikUIDB, RikUICharDB = nil, nil, nil
        for _, file in ipairs({ "src/core/core.lua", "src/persistence/store.lua", "src/persistence/store-macros.lua" }) do assert(loadfile(file))("RikUI", {}) end
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        check("a client without the macro API keeps working without the second tier", RikUI.Profile ~= nil
            and RikUI.Store.MacrosAvailable() == false)
    end)
    for _, name in ipairs(NAMES) do _G[name] = saved[name] end
    env.inCombat = false
    check("store macros suite completes", ok, reason)
end
