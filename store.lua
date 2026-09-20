-- A second home for RikUI's settings. On 69913 the client was seen (2026-09-20) writing saved variables
-- at logout and never reading them back, so every reload started from nothing. RikProbe showed that a
-- CVar an addon registers does survive a reload, so the settings are also kept there: encoded to
-- letters, digits and underscore, split over numbered CVars under one header that carries the chunk
-- count, the length and a checksum. core.lua loads from here only when saved variables did not load;
-- saved variables that loaded always win. Writes happen at logout and from a ticker that only writes
-- when the encoded text changed. The chat history is left out: it is large and only a convenience.
local core = RikUI
local store = {}
core.Store = store

local PREFIX, VERSION, CHUNK, MAX_CHUNKS, TICK_SECONDS = "rikuiStore_", "v1", 180, 120, 5
local SKIP_KEYS = { chatHistory = true }
local status = { saves = 0, chunks = 0, bytes = 0, restored = {}, failure = nil }
local lastText = {}

function store.Available()
    return type(C_CVar) == "table" and type(C_CVar.RegisterCVar) == "function" and type(C_CVar.GetCVar) == "function"
        and type(C_CVar.SetCVar) == "function"
end

-- value := n<number>; | s<length>:<bytes> | t | f | {<key><value>...}
local function write(value, out, top)
    local kind = type(value)
    if kind == "number" then out[#out + 1] = "n" .. string.format("%.17g", value) .. ";"
    elseif kind == "string" then out[#out + 1] = "s" .. #value .. ":" .. value
    elseif kind == "boolean" then out[#out + 1] = value and "t" or "f"
    elseif kind == "table" then
        out[#out + 1] = "{"
        for key, entry in pairs(value) do
            local keyKind, entryKind = type(key), type(entry)
            local storable = (keyKind == "string" or keyKind == "number")
                and (entryKind == "number" or entryKind == "string" or entryKind == "boolean" or entryKind == "table")
            if storable and not (top and SKIP_KEYS[key]) then
                write(key, out)
                write(entry, out)
            end
        end
        out[#out + 1] = "}"
    end
end

local function armour(text)
    return (text:gsub("[^%w]", function(char) return string.format("_%02x", char:byte()) end))
end

local function unarmour(text)
    return (text:gsub("_(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

function store.Encode(value)
    local out = {}
    write(value, out, true)
    return armour(table.concat(out))
end

local read

local function readTable(text, at)
    local result = {}
    while text:sub(at, at) ~= "}" do
        if at > #text then return nil end
        local key, value
        key, at = read(text, at)
        if key == nil then return nil end
        value, at = read(text, at)
        if value == nil then return nil end
        result[key] = value
    end
    return result, at + 1
end

read = function(text, at)
    local tag = text:sub(at, at)
    if tag == "t" then return true, at + 1 end
    if tag == "f" then return false, at + 1 end
    if tag == "{" then return readTable(text, at + 1) end
    if tag == "n" then
        local stop = text:find(";", at, true)
        local number = stop and tonumber(text:sub(at + 1, stop - 1))
        if number == nil then return nil end
        return number, stop + 1
    end
    if tag == "s" then
        local colon = text:find(":", at, true)
        local length = colon and tonumber(text:sub(at + 1, colon - 1))
        if not length or colon + length > #text then return nil end
        return text:sub(colon + 1, colon + length), colon + length + 1
    end
    return nil
end

-- false is a legal value, so failure is nil plus a reason.
function store.Decode(text)
    if type(text) ~= "string" or text == "" or not text:match("^[%w_]+$") then return nil, "not store text" end
    local plain = unarmour(text)
    local ok, value, stop = pcall(read, plain, 1)
    if not ok or value == nil or stop ~= #plain + 1 then return nil, "damaged store text" end
    return value
end

local function checksum(text)
    local a, b = 1, 0
    for index = 1, #text do
        a = (a + text:byte(index)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

local function cvar(name)
    C_CVar.RegisterCVar(name, "")
    return name
end

-- Every write is read back: a client that truncates a value must be noticed now, not at the next login.
local function put(name, value)
    local ok, reason = pcall(C_CVar.SetCVar, cvar(name), value)
    if not ok then return false, tostring(reason) end
    if C_CVar.GetCVar(name) ~= value then return false, "value truncated at " .. #tostring(C_CVar.GetCVar(name) or "") end
    return true
end

function store.Save(name, value)
    if not store.Available() then return false, "no CVar registration on this client" end
    local text = store.Encode(value)
    local chunks = math.ceil(#text / CHUNK)
    if chunks > MAX_CHUNKS then return false, "settings too large for the store: " .. #text .. " characters" end
    for index = 1, chunks do
        local ok, reason = put(PREFIX .. name .. "_" .. index, text:sub((index - 1) * CHUNK + 1, index * CHUNK))
        if not ok then return false, reason end
    end
    local ok, reason = put(PREFIX .. name, table.concat({ VERSION, chunks, #text, checksum(text) }, "x"))
    if not ok then return false, reason end
    status.saves, status.chunks, status.bytes = status.saves + 1, chunks, #text
    return true, chunks
end

function store.Load(name)
    if not store.Available() then return nil, "no CVar registration on this client" end
    local header = C_CVar.GetCVar(cvar(PREFIX .. name))
    local version, chunks, length, sum = tostring(header or ""):match("^(%w+)x(%d+)x(%d+)x(%d+)$")
    if version ~= VERSION then return nil, "nothing stored" end
    local parts = {}
    for index = 1, tonumber(chunks) do parts[index] = C_CVar.GetCVar(cvar(PREFIX .. name .. "_" .. index)) or "" end
    local text = table.concat(parts)
    if #text ~= tonumber(length) or checksum(text) ~= tonumber(sum) then return nil, "checksum mismatch in stored settings" end
    return store.Decode(text)
end

-- A character's settings are kept under a number made from its name and realm: CVar names are ASCII.
function store.CharacterKey()
    local name = type(UnitName) == "function" and UnitName("player") or nil
    local realm = type(GetRealmName) == "function" and GetRealmName() or nil
    return "char" .. checksum(tostring(name) .. "-" .. tostring(realm))
end

-- Called by core.lua before defaults are merged. Saved variables that loaded are never replaced.
function store.Restore()
    if not store.Available() then return end
    if RikUIDB == nil then
        RikUIDB = store.Load("account")
        status.restored.account = RikUIDB ~= nil
    end
    if RikUICharDB == nil then
        RikUICharDB = store.Load(store.CharacterKey())
        status.restored.character = RikUICharDB ~= nil
    end
end

function store.Status() return status end

local function flushOne(name, value)
    if type(value) ~= "table" then return end
    local text = store.Encode(value)
    if lastText[name] == text then return end
    local ok, reason = store.Save(name, value)
    if ok then lastText[name], status.failure = text, nil
    elseif status.failure ~= reason then
        status.failure = reason
        core:Print("Settings store: " .. tostring(reason))
    end
end

function store.Flush()
    if not store.Available() then return end
    flushOne("account", core.DB)
    flushOne(store.CharacterKey(), core.CharDB)
end

core:RegisterEvent("PLAYER_LOGIN", function()
    if status.restored.account or status.restored.character then
        core:Print("Saved variables did not load on this client; settings were restored from RikUI's own store.")
    end
    if store.Available() and type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
        C_Timer.NewTicker(TICK_SECONDS, store.Flush)
    end
end)
core:RegisterEvent("PLAYER_LOGOUT", store.Flush)

core:RegisterCommand("store", function()
    core:Print("Store available=" .. tostring(store.Available()) .. " saves=" .. status.saves .. " chunks=" .. status.chunks
        .. " characters=" .. status.bytes .. " restored account=" .. tostring(status.restored.account == true)
        .. " character=" .. tostring(status.restored.character == true)
        .. (status.failure and " last failure: " .. status.failure or ""))
end, "Show the state of RikUI's own settings store")
