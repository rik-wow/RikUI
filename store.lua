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

local PREFIX, VERSION, CHUNK, MAX_CHUNKS, TICK_SECONDS, TOUCH_SECONDS = "rikuiStore_", "v2", 180, 120, 5, 0.2
local SKIP_KEYS = { chatHistory = true }
local status = { saves = 0, chunks = 0, bytes = 0, restored = {}, failure = nil }
local lastText = {}

function store.Available()
    return type(C_CVar) == "table" and type(C_CVar.RegisterCVar) == "function" and type(C_CVar.GetCVar) == "function"
        and type(C_CVar.SetCVar) == "function"
end

-- Keys in a fixed order: the same settings always encode to the same text, whatever order the table
-- was built in, so "did anything change" is a string comparison.
local function sortedKeys(value)
    local keys = {}
    for key in pairs(value) do
        if type(key) == "string" or type(key) == "number" then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) == "number" end
        return a < b
    end)
    return keys
end

-- Words that repeat in every saved position and setting get a two-character code. APPEND ONLY: a code
-- is the word's place in this list, and stored text outlives the addon version that wrote it.
local WORDS = { "point", "relativePoint", "x", "y", "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT", "TOPLEFT", "TOPRIGHT",
    "BOTTOMLEFT", "BOTTOMRIGHT", "positions", "profiles", "Default", "modules", "chat", "size", "width", "height",
    "scale", "characters", "account", "wizardDone", "applied", "askRole", "profile", "class", "role", "at",
    "presetVersion", "version", "community", "layout", "base", "moved", "locked", "fontSize", "gryphons", "tooltip",
    "questtracker", "collapsed", "main", "bar2", "bar3", "bar4", "bar5", "stance", "pet", "xpbar", "player", "target",
    "focus", "tot", "petframe", "party", "raid", "castplayer", "casttarget", "castfocus", "castpet", "buffs", "debuffs",
    "minimap", "micromenu", "durability", "mirrortimers", "swingtimer", "combopoints", "totems", "questtimers", "loot",
    "bags", "damagemeter", "WARRIOR", "dps", "tank", "nameplateCVars" }
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local CODES = {}
for index, word in ipairs(WORDS) do
    local high, low = math.floor(index / 36), index % 36
    CODES[word] = DIGITS:sub(high + 1, high + 1) .. DIGITS:sub(low + 1, low + 1)
end

local function armour(text)
    return (text:gsub("[^%w]", function(char) return string.format("_%02x", char:byte()) end))
end

local function unarmour(text)
    return (text:gsub("_(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

-- The shortest text that reads back as the same number.
local function numberText(value)
    local short = tostring(value)
    return tonumber(short) == value and short or string.format("%.17g", value)
end

-- The text is letters, digits and underscore throughout, so a CVar and a macro both hold it as it is:
-- value := n<number>z | s<length>z<armoured bytes> | k<two-character word code> | t | f | T<key><value>...E
local function write(value, out, top)
    local kind = type(value)
    if kind == "number" then out[#out + 1] = "n" .. armour(numberText(value)) .. "z"
    elseif kind == "string" then
        local safe = armour(value)
        out[#out + 1] = CODES[value] and "k" .. CODES[value] or "s" .. #safe .. "z" .. safe
    elseif kind == "boolean" then out[#out + 1] = value and "t" or "f"
    elseif kind == "table" then
        out[#out + 1] = "T"
        for _, key in ipairs(sortedKeys(value)) do
            local entryKind = type(value[key])
            local storable = entryKind == "number" or entryKind == "string" or entryKind == "boolean" or entryKind == "table"
            if storable and not (top and SKIP_KEYS[key]) then
                write(key, out)
                write(value[key], out)
            end
        end
        out[#out + 1] = "E"
    end
end

function store.Encode(value)
    local out = {}
    write(value, out, true)
    return table.concat(out)
end

local read

local function readTable(text, at)
    local result = {}
    while text:sub(at, at) ~= "E" do
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

local function readWord(text, at)
    local high, low = DIGITS:find(text:sub(at + 1, at + 1), 1, true), DIGITS:find(text:sub(at + 2, at + 2), 1, true)
    local word = high and low and #text >= at + 2 and WORDS[(high - 1) * 36 + low - 1] or nil
    if word == nil then return nil end
    return word, at + 3
end

read = function(text, at)
    local tag = text:sub(at, at)
    if tag == "t" then return true, at + 1 end
    if tag == "f" then return false, at + 1 end
    if tag == "T" then return readTable(text, at + 1) end
    if tag == "k" then return readWord(text, at) end
    local stop = (tag == "n" or tag == "s") and text:find("z", at + 1, true) or nil
    if not stop then return nil end
    if tag == "n" then
        local number = tonumber((unarmour(text:sub(at + 1, stop - 1))))
        if number == nil then return nil end
        return number, stop + 1
    end
    local length = tonumber(text:sub(at + 1, stop - 1))
    if not length or stop + length > #text then return nil end
    return unarmour(text:sub(stop + 1, stop + length)), stop + length + 1
end

-- false is a legal value, so failure is nil plus a reason.
function store.Decode(text)
    if type(text) ~= "string" or text == "" or not text:match("^[%w_]+$") then return nil, "not store text" end
    local ok, value, stop = pcall(read, text, 1)
    if not ok or value == nil or stop ~= #text + 1 then return nil, "damaged store text" end
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
    status.loaded = RikUIDB ~= nil or RikUICharDB ~= nil
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

-- core:Changed() lands here. One save a moment later covers a burst of changes (a drag reports its
-- place on every frame); without a timer API the save happens at once.
local touched = false
function store.Touch()
    if touched then return end
    local function save()
        touched = false
        store.Flush()
        if store.FlushMacros then store.FlushMacros() end
    end
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return save() end
    touched = true
    C_Timer.After(TOUCH_SECONDS, save)
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
