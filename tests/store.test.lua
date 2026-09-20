local loadfile = dofile("tests/load_addon.lua").Loadfile
-- The CVar store: RikUI's settings survive a reload on a client that writes saved variables and never
-- reads them back (seen on 69913, 2026-09-20). The CVar API is faked with a table that outlives the
-- "reload"; whether a custom CVar survives a full client restart needs a beta check.
return function(check)
    local env = require("wow_stub")
    local saved = { C_CVar = C_CVar, UnitName = UnitName, GetRealmName = GetRealmName, C_Timer = C_Timer }
    local cvars, limit, registered, bare = {}, nil, {}, false
    local function fakeCVars()
        C_CVar = {
            RegisterCVar = function(name, value)
                registered[name] = true
                if cvars[name] == nil then cvars[name] = value or "" end
            end,
            GetCVar = function(name) return cvars[name] end,
            SetCVar = function(name, value)
                assert(registered[name], "SetCVar on an unregistered CVar: " .. tostring(name))
                cvars[name] = limit and value:sub(1, limit) or value
                return true
            end,
        }
    end
    local tickers, timers = {}, {}
    local function boot(db, charDB, withStore)
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        registered, tickers, timers = {}, {}, {}
        if bare then C_CVar = { GetCVar = function() end, SetCVar = function() end } else fakeCVars() end
        C_Timer = { NewTicker = function(seconds, callback) tickers[#tickers + 1] = callback; return {} end,
            After = function(seconds, callback) timers[#timers + 1] = { seconds = seconds, run = callback } end }
        UnitName, GetRealmName = function() return "Peepee Jameson" end, function() return "Classic Beta PvE" end
        RikUI, RikUIDB, RikUICharDB = nil, db, charDB
        assert(loadfile("src/core/core.lua"))("RikUI", {})
        if withStore ~= false then assert(loadfile("src/persistence/store.lua"))("RikUI", {}) end
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        return RikUI
    end
    local function printed(text)
        for _, line in ipairs(env.printed) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end

    local ok, reason = pcall(function()
        local core = boot()
        local store = core.Store
        local sample = { scale = 0.85, on = true, off = false, name = "a;b{c}:|\"\n", list = { 1, 2, { deep = "x" } },
            note = string.rep("long enough to need more than one CVar ", 12),
            positions = { chat = { point = "CENTER", relativePoint = "BOTTOMLEFT", x = 219, y = 107.0000076293945 } } }
        local text = store.Encode(sample)
        local back = store.Decode(text)
        check("a settings table survives encoding: numbers, booleans, awkward strings and nesting", type(back) == "table"
            and back.scale == 0.85 and back.on == true and back.off == false and back.name == sample.name
            and back.list[3].deep == "x" and back.positions.chat.y == 107.0000076293945 and back.positions.chat.point == "CENTER")
        check("the encoded text uses only letters, digits and underscore, which a CVar and a macro hold safely",
            text:match("^[%w_]+$") ~= nil)
        local place = store.Encode({ point = "CENTER", relativePoint = "BOTTOMLEFT", x = 219, y = 107 })
        check("a saved position is short: the words every position repeats are two-character codes", #place <= 32, place)
        check("functions and frames are left out instead of breaking the save",
            store.Decode(store.Encode({ keep = 1, skip = function() end })).skip == nil)
        check("damaged text is refused, not half decoded", store.Decode(text:sub(1, #text - 7)) == nil
            and store.Decode("zzz") == nil and store.Decode("") == nil)


        local cycle = {}; cycle.self = cycle
        local safe, encoded, encodeReason = pcall(store.Encode, cycle)
        check("cyclic settings fail safely", safe and encoded == nil and type(encodeReason) == "string")
        check("non-finite settings cannot be encoded", store.Encode({ n = math.huge }) == nil
            and store.Encode({ n = -math.huge }) == nil and store.Encode({ n = 0 / 0 }) == nil)
        local shared = { x = 1 }
        local alias = store.Decode(store.Encode({ a = shared, b = shared }))
        check("shared acyclic tables remain supported", alias and alias.a.x == 1 and alias.b.x == 1)
        local deep = string.rep("Ts1za", 40) .. "t" .. string.rep("E", 40)
        check("excessive stored nesting is rejected", store.Decode(deep) == nil)
        check("invalid keys and duplicate stored entries are rejected", store.Decode("TttE") == nil
            and store.Decode("TTEtE") == nil and store.Decode("Ts1zats1zafE") == nil)
        check("non-finite values and invalid string lengths are rejected", store.Decode("n1e309z") == nil
            and store.Decode("s1e1zabcdefghij") == nil)
        check("incomplete escapes are rejected", store.Decode("s1z_") == nil and store.Decode("s3z_zz") == nil)
        check("oversized input is rejected", store.Decode(string.rep("t", 21601)) == nil)


        local get, chunkReads = C_CVar.GetCVar, 0
        C_CVar.GetCVar = function(name)
            if name:match("^rikuiStore_invalid_%d+$") then chunkReads = chunkReads + 1 end
            return get(name)
        end
        cvars.rikuiStore_invalid = "v2x999999999x1x1"
        check("unbounded header count is rejected before chunk reads", store.Load("invalid") == nil and chunkReads == 0)
        cvars.rikuiStore_invalid = "v2x2x1x1"
        check("inconsistent header length is rejected before chunk reads", store.Load("invalid") == nil and chunkReads == 0)
        C_CVar.GetCVar = get
        local register = C_CVar.RegisterCVar
        C_CVar.RegisterCVar = function() error("register failed") end
        local safeSave, saved = pcall(store.Save, "failure", {})
        local safeLoad, loaded = pcall(store.Load, "failure")
        check("CVar API exceptions become explicit store failures", safeSave and saved == false and safeLoad and loaded == nil)
        C_CVar.RegisterCVar = register
        check("cyclic settings do not write a header", store.Save("cycle", cycle) == false and cvars.rikuiStore_cycle == nil)
        check("v2 dictionary remains byte compatible", store.Encode({ point = "CENTER", x = 219 }) == "Tk01k05k03n219zE")

        check("the store is available when the client can register CVars", store.Available() == true)
        local wrote, chunks = store.Save("account", sample)
        check("a long value is split over several CVars under one header", wrote == true and chunks > 1
            and cvars.rikuiStore_account ~= nil and cvars.rikuiStore_account_1 ~= nil)
        check("and loads back whole", store.Load("account").positions.chat.x == 219)
        cvars.rikuiStore_account_1 = cvars.rikuiStore_account_1:sub(1, -3) .. "xx"
        local broken, why = store.Load("account")
        check("a chunk that came back changed is caught by the checksum", broken == nil and why:find("checksum", 1, true) ~= nil)
        limit = 40
        local short, shortWhy = store.Save("account", sample)
        check("a client that truncates CVar values is noticed at once, by reading back", short == false
            and shortWhy:find("truncated", 1, true) ~= nil)
        limit = nil
        check("nothing stored means nothing loaded", store.Load("nonsense") == nil)

        -- The real case: saved variables are written but do not load.
        cvars = {}
        core = boot()
        core.Profile.positions.chat = { point = "CENTER", relativePoint = "BOTTOMLEFT", x = 219, y = 107 }
        core.Profile.scale = 0.9
        core.CharDB.wizardDone = true
        core.CharDB.chatHistory = { { { text = "a long line" } } }
        env.fire("PLAYER_LOGOUT")
        check("logging out writes the account and the character settings to the store",
            cvars.rikuiStore_account ~= nil and next(cvars) ~= nil and core.Store.Status().saves >= 2)
        core = boot(nil, nil)
        check("on a login where saved variables did not load, the settings come back from the store",
            core.Profile.positions.chat ~= nil and core.Profile.positions.chat.x == 219 and core.Profile.scale == 0.9
            and core.CharDB.wizardDone == true and printed("restored"))
        check("the chat history is not kept in the store: it is large and only a convenience", core.CharDB.chatHistory == nil)

        core = boot({ version = 1, profiles = { Default = { scale = 1.2 } }, community = {} }, { profile = "Default" })
        check("saved variables that did load win over the store", core.Profile.scale == 1.2 and not printed("restored"))

        core = boot()

        local encode, encodes = core.Store.Encode, 0
        core.Store.Encode = function(value) encodes = encodes + 1; return encode(value) end
        core.Store.Flush()
        check("flush serializes each database only once", encodes == 2)
        core.Store.Encode = encode
        core.Profile.scale = 1.1
        check("a ticker is started after login", #tickers == 1)
        tickers[1]()
        local saves = core.Store.Status().saves
        tickers[1]()
        check("the ticker writes only when something changed", core.Store.Status().saves == saves)
        core.Profile.scale = 1.3
        tickers[1]()
        check("and writes again after a change", core.Store.Status().saves > saves)
        -- Nobody should have to wait for the ticker: a change asks for a save at once.
        core.Profile.scale = 0.75
        saves = core.Store.Status().saves
        core:Changed()
        core:Changed()
        core:Changed()
        check("a change asks for one save a moment later, however often it is reported", #timers == 1
            and timers[1].seconds <= 0.25 and core.Store.Status().saves == saves)
        timers[1].run()
        check("and that save happens without the ticker", core.Store.Status().saves > saves
            and core.Store.Load("account").profiles.Default.scale == 0.75)
        core:Changed()
        check("a later change asks again", #timers == 2)
        env.printed = {}
        SlashCmdList.RIKUI("store")
        check("/rik store reports the store's state", printed("Store available=true") and printed("chunks="))

        bare = true
        core = boot()
        check("a client without RegisterCVar has no store and nothing breaks", core.Store.Available() == false
            and core.Profile ~= nil and core.Store.Save("account", {}) == false)
        bare = false
        core = boot(nil, nil, false)
        check("the core starts without the store file", core.Profile ~= nil and core.Store == nil)
    end)
    for name, value in pairs(saved) do _G[name] = value end
    env.inCombat = false
    check("store suite completes", ok, reason)
end
