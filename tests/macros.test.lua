local loadfile = dofile("tests/load_addon.lua").Loadfile
-- Macro service contracts; run through tests/run_tests.lua.
return function(check)
    local env = require("wow_stub")
    local originalInfo, originalCreate, originalEdit = GetMacroInfo, CreateMacro, EditMacro
    local slots, writes, behavior, queueDepth, queuedCalls, macros
    local function contains(text)
        for _, line in ipairs(env.printed) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end
    local function sortPool(character, target)
        local first, last = character and 121 or 1, character and 138 or 120
        local records = {}
        for index = first, last do
            if slots[index] then records[#records + 1] = slots[index] end
            slots[index] = nil
        end
        table.sort(records, function(a, b) return a.name < b.name end)
        local result
        for position, record in ipairs(records) do
            local index = first + position - 1
            slots[index] = record
            if record == target then result = index end
        end
        return result
    end
    local function recordWrite(kind)
        assert(not env.inCombat, "macro write during combat")
        assert(queueDepth > 0, "macro write bypassed Combat.Queue")
        writes[#writes + 1] = kind
        if behavior[kind] == "throw" then error(kind .. " failed") end
        return behavior[kind] ~= "reject"
    end
    local function reset()
        slots, writes, behavior, queueDepth, queuedCalls = {}, {}, {}, 0, 0
        env.frames, env.printed, env.inCombat = {}, {}, false
        RikUI, RikUIDB, RikUICharDB = nil, nil, nil
        GetMacroInfo = function(index)
            if behavior.read == "throw" then error("macro read failed") end
            local record = slots[index]
            if record then return record.name, record.icon, record.body end
        end
        CreateMacro = function(name, icon, body, character)
            if not recordWrite("create") then return nil end
            local first, last = character and 121 or 1, character and 138 or 120
            local record = { name = name, icon = icon, body = body }
            for index = first, last do
                if not slots[index] then
                    slots[index] = record
                    return sortPool(character, record)
                end
            end
            error("full pool")
        end
        EditMacro = function(index, name, icon, body)
            if not recordWrite("edit") then return nil end
            local record = assert(slots[index], "missing macro")
            record.name, record.icon, record.body = name, icon, body
            return sortPool(index > 120, record)
        end
        assert(loadfile("src/core/core.lua"))("RikUI", {})
        assert(loadfile("src/character/macros.lua"))("RikUI", {})
        local queue = RikUI.Combat.Queue
        RikUI.Combat.Queue = function(callback)
            queuedCalls = queuedCalls + 1
            return queue(function()
                queueDepth = queueDepth + 1
                callback()
                queueDepth = queueDepth - 1
            end)
        end
        macros = RikUI.Macros
    end
    local function fill(first, last)
        for index = first, last do
            slots[index] = { name = "Existing" .. index, icon = index, body = "/say old" }
        end
    end

    reset()
    check("macro service is exposed without writing at load", type(macros) == "table" and #writes == 0)
    assert(macros, "Macro API missing")
    slots[120] = { name = "Account", icon = 1, body = "" }
    slots[138] = { name = "Character", icon = 2, body = "/say character" }
    check("Find covers final slots in both pools", macros.Find("Account") == 120 and macros.Find("Character") == 138)
    check("Find uses exact case-sensitive names", macros.Find("account") == nil and macros.Find("Char") == nil)
    check("Find returns nil for an absent name", macros.Find("Missing") == nil)
    slots[1], slots[121] = { name = "Duplicate", icon = 1, body = "account" }, { name = "Duplicate", icon = 2, body = "character" }
    check("duplicate names prefer character pool", macros.Find("Duplicate") == 121)

    reset()
    local index, reason = macros.Ensure("Zeta", 123, "/say first")
    check("new macro prefers character pool", index == 121 and reason == nil and slots[121].body == "/say first")
    index = macros.Ensure("Alpha", 456, "/say second", "account")
    check("account scope still prefers free character slot and returns sorted index",
        index == 121 and slots[121].name == "Alpha" and slots[122].name == "Zeta" and slots[1] == nil)
    index = macros.Ensure("Zeta", 789, "/say updated")
    check("Ensure edits same-name macro rather than duplicating", index == 122 and #writes == 3
        and writes[3] == "edit" and slots[122].icon == 789 and slots[122].body == "/say updated")
    check("every immediate write uses Combat.Queue", queuedCalls == 3)
    reset()
    slots[1] = { name = "Shared", icon = 1, body = "/say old" }
    index = macros.Ensure("Shared", 2, "/say new")
    check("existing account macro is edited in its original pool", index == 1 and writes[1] == "edit"
        and slots[121] == nil and slots[1].body == "/say new")

    reset()
    fill(121, 138)
    index, reason = macros.Ensure("New", 1, "/say new")
    check("full character pool returns nil and reason without spilling", index == nil and type(reason) == "string"
        and #writes == 0 and contains("New"))
    index = macros.Ensure("New", 1, "/say new", "account")
    check("explicit account scope permits spill when character pool is full", index == 1 and slots[1].name == "New")
    fill(1, 120)
    local before = #writes
    index, reason = macros.Ensure("NoRoom", 1, "", "account")
    check("both pools full return a reason without native write", index == nil and type(reason) == "string" and #writes == before)
    index = macros.Ensure("Existing138", 5, "updated", "account")
    check("full pools do not prevent editing an existing macro", index ~= nil and writes[#writes] == "edit")
    reset()
    fill(1, 120)
    check("full account pool does not block a free character slot", macros.Ensure("Local", 1, "", "account") == 121)

    reset()
    local longName = string.rep("N", 17)
    index, reason = macros.Ensure(longName, 1, "")
    check("overlong names are rejected and named in chat", index == nil and type(reason) == "string" and contains(longName) and #writes == 0)
    index, reason = macros.Ensure("LongBody", 1, string.rep("b", 256))
    check("overlong bodies are rejected and macro is named in chat", index == nil and type(reason) == "string"
        and contains("LongBody") and #writes == 0)
    index = macros.Ensure(string.rep("N", 16), 1, string.rep("b", 255))
    check("exact name and body length boundaries are accepted", index == 121)
    reset()
    index = macros.Ensure(string.rep("é", 16), 1, string.rep("é", 255))
    check("UTF-8 name and body boundaries count letters rather than bytes", index == 121)
    before = #writes
    index, reason = macros.Ensure(string.rep("é", 17), 1, "")
    check("UTF-8 names beyond 16 letters are rejected", index == nil and reason ~= nil and #writes == before)
    index, reason = macros.Ensure("UnicodeBody", 1, string.rep("é", 256))
    check("UTF-8 bodies beyond 255 letters are rejected", index == nil and reason ~= nil and #writes == before)
    index, reason = macros.Ensure("Whitespace", 1, string.rep("\n", 256))
    check("invisible body characters count towards the limit", index == nil and reason ~= nil and #writes == before)
    for _, args in ipairs({
        { "", 1, "" }, { false, 1, "" }, { "BadBody", 1, false },
        { "BadScope", 1, "", "shared" }, { "BadIcon", false, "" },
    }) do
        before = #writes
        local ok, value, detail = pcall(macros.Ensure, unpack(args))
        check("invalid macro input is rejected without throwing: " .. tostring(args[1]),
            ok and value == nil and type(detail) == "string" and #writes == before)
    end

    reset()
    env.inCombat = true
    index, reason = macros.Ensure("Deferred", 1, "first")
    macros.Ensure("Deferred", 2, "second")
    check("combat writes defer with an explicit queued result", index == nil and reason == "queued" and #writes == 0)
    env.fire("PLAYER_REGEN_ENABLED")
    check("macro queue never writes while combat persists", #writes == 0)
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("queued same-name requests create once then edit", #writes == 2 and writes[1] == "create"
        and writes[2] == "edit" and slots[121].body == "second" and slots[122] == nil)
    env.fire("PLAYER_REGEN_ENABLED")
    check("deferred macro writes run once", #writes == 2)

    reset()
    slots[121] = { name = "Moved", icon = 1, body = "old" }
    env.inCombat = true
    macros.Ensure("Moved", 2, "new")
    slots[122], slots[121] = slots[121], { name = "Earlier", icon = 3, body = "untouched" }
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("queued edit resolves the current index after pool changes", slots[121].body == "untouched"
        and slots[122].body == "new")
    reset()
    env.inCombat = true
    macros.Ensure("Late", 1, "")
    fill(121, 138)
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("queued creation rechecks capacity and reports failure", #writes == 0 and contains("Late"))

    reset()
    env.inCombat = true
    RikUI.Combat.Queue(function()
        index, reason = macros.Ensure("Nested", 1, "queued while draining")
    end)
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("Ensure nested inside queue drain reports queued then executes", index == nil and reason == "queued"
        and slots[121].body == "queued while draining" and #writes == 1)

    reset()
    slots[1] = { name = "Shared", icon = 7, body = "#showtooltip\n/cast Attack" }
    slots[138] = { name = "Personal", icon = "path", body = "" }
    local snapshot = macros.Snapshot()
    check("snapshot preserves index, name, icon, body and pool for undo", snapshot[1].name == "Shared"
        and snapshot[1].icon == 7 and snapshot[1].body == "#showtooltip\n/cast Attack"
        and snapshot[1].scope == "account" and snapshot[138].scope == "character" and snapshot[138].body == "")
    check("snapshot has no writes and no invented empty slots", #writes == 0 and snapshot[2] == nil)
    slots[1].body = "changed"
    snapshot[138].body = "modified snapshot"
    check("snapshot is independent of later macro and caller changes", snapshot[1].body == "#showtooltip\n/cast Attack"
        and slots[138].body == "" and macros.Snapshot()[1].body == "changed")
    reset()
    check("empty macro pools produce an empty snapshot", next(macros.Snapshot()) == nil)
    behavior.read = "throw"
    index, reason = macros.Ensure("Unreadable", 1, "")
    check("lookup failure cannot create an accidental duplicate", index == nil and type(reason) == "string" and #writes == 0)
    snapshot, reason = macros.Snapshot()
    check("snapshot read failure is explicit rather than partial", snapshot == nil and type(reason) == "string")
    GetMacroInfo = nil
    index, reason = macros.Find("Unavailable")
    check("missing lookup API returns a reason", index == nil and type(reason) == "string")

    for _, kind in ipairs({ "create", "edit" }) do
        for _, mode in ipairs({ "throw", "reject", "missing" }) do
            reset()
            if kind == "edit" then slots[121] = { name = "Failure", icon = 1, body = "old" } end
            behavior[kind] = mode
            if mode == "missing" then
                if kind == "create" then CreateMacro = nil else EditMacro = nil end
            end
            local ok, value, detail = pcall(macros.Ensure, "Failure", 2, "new")
            check(kind .. " " .. mode .. " is returned and reported", ok and value == nil
                and type(detail) == "string" and contains("Failure"))
        end
    end
    reset()
    env.inCombat = true
    macros.Ensure("AllowedSpill", 1, "new", "account")
    fill(121, 138)
    env.inCombat = false
    env.fire("PLAYER_REGEN_ENABLED")
    check("queued account opt-in permits spill after capacity changes", slots[1].name == "AllowedSpill" and #writes == 1)

    reset()
    CreateMacro = function() return 0 end
    index, reason = macros.Ensure("ZeroIndex", 1, "")
    check("zero native index is rejected rather than reporting success", index == nil and reason ~= nil)
    slots[121] = { name = "FractionIndex", icon = 1, body = "" }
    EditMacro = function() return 121.5 end
    index, reason = macros.Ensure("FractionIndex", 1, "")
    check("fractional native index is rejected", index == nil and reason ~= nil)

    reset()
    fill(1, 120)
    slots[138] = { name = "Broken", icon = 1 }
    snapshot, reason = macros.Snapshot()
    check("late malformed snapshot data discards all earlier records", snapshot == nil and reason ~= nil)
    GetMacroInfo, CreateMacro, EditMacro = originalInfo, originalCreate, originalEdit
end
