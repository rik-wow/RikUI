-- A second home for RikUI's settings. On 69913 the client was seen (2026-09-20) writing saved variables
-- at logout and never reading them back, so every reload started from nothing. RikProbe showed that a
-- CVar an addon registers does survive a reload, so the settings are also kept there: encoded to
-- letters, digits and underscore, split over numbered CVars under one header that carries the chunk
-- count, the length and a checksum. src/core/core.lua loads from here only when saved variables did not load;
-- saved variables that loaded always win. Writes happen at logout and from a ticker that only writes
-- when the encoded text changed. The chat history is left out: it is large and only a convenience.
local core = RikUI
local store = {}
core.Store = store
store.Encode, store.Decode = core.Codec.Encode, core.Codec.Decode

local PREFIX, VERSION, CHUNK, MAX_CHUNKS, TICK_SECONDS, TOUCH_SECONDS = "rikuiStore_", "v2", 180, 120, 5, 0.2
local status = { saves = 0, chunks = 0, bytes = 0, restored = {}, failure = nil }
local lastText, failures = {}, {}

function store.Available()
    return type(C_CVar) == "table" and type(C_CVar.RegisterCVar) == "function" and type(C_CVar.GetCVar) == "function"
        and type(C_CVar.SetCVar) == "function"
end

local function checksum(text)
    local a, b = 1, 0
    for index = 1, #text do
        a = (a + text:byte(index)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

local function validName(name)
    return type(name) == "string" and name:match("^[%w_]+$") ~= nil
end

local function get(name)
    local registered, reason = pcall(C_CVar.RegisterCVar, name, "")
    if not registered then return nil, tostring(reason) end
    local ok, value = pcall(C_CVar.GetCVar, name)
    if not ok then return nil, tostring(value) end
    return value or ""
end

local function put(name, value)
    local previous, reason = get(name)
    if previous == nil then return false, reason end
    local ok, written = pcall(C_CVar.SetCVar, name, value)
    if not ok then return false, tostring(written) end
    if written == false then return false, "CVar write rejected" end
    local back, failure = get(name)
    if back == nil then return false, failure end
    if back ~= value then return false, "value truncated at " .. #tostring(back) end
    return true
end

local function saveText(name, text)
    if not store.Available() then return false, "no CVar registration on this client" end
    if not validName(name) then return false, "invalid store name" end
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

function store.Save(name, value)
    local text, reason = store.Encode(value)
    if not text then return false, reason end
    return saveText(name, text)
end

local function parseHeader(header)
    if type(header) ~= "string" then return nil, "invalid store header" end
    local version, chunks, length, sum = header:match("^(%w+)x(%d+)x(%d+)x(%d+)$")
    if version ~= VERSION then return nil, "nothing stored" end
    chunks, length, sum = tonumber(chunks), tonumber(length), tonumber(sum)
    if not chunks or chunks < 1 or chunks > MAX_CHUNKS or not length or length < 1
        or length > CHUNK * MAX_CHUNKS or chunks ~= math.ceil(length / CHUNK)
        or not sum or sum < 0 or sum >= 4294967296 then return nil, "invalid store header" end
    return { chunks = chunks, length = length, checksum = sum }
end

function store.Load(name)
    if not store.Available() then return nil, "no CVar registration on this client" end
    if not validName(name) then return nil, "invalid store name" end
    local header, reason = get(PREFIX .. name)
    if header == nil then return nil, reason end
    local info, failure = parseHeader(header)
    if not info then return nil, failure end
    local parts = {}
    for index = 1, info.chunks do
        local part, problem = get(PREFIX .. name .. "_" .. index)
        if part == nil then return nil, problem end
        local length = index < info.chunks and CHUNK or info.length - (index - 1) * CHUNK
        if type(part) ~= "string" or #part ~= length then return nil, "checksum mismatch in stored settings: chunk length" end
        parts[index] = part
    end
    local text = table.concat(parts)
    if checksum(text) ~= info.checksum then return nil, "checksum mismatch in stored settings" end
    return store.Decode(text)
end

-- A character's settings are kept under a number made from its name and realm: CVar names are ASCII.
function store.CharacterKey()
    local name = type(UnitName) == "function" and UnitName("player") or nil
    local realm = type(GetRealmName) == "function" and GetRealmName() or nil
    return "char" .. checksum(tostring(name) .. "-" .. tostring(realm))
end

-- Called by src/core/core.lua before defaults are merged. Saved variables that loaded are never replaced.
function store.Restore()
    status.loadedAccount, status.loadedCharacter = type(RikUIDB) == "table", type(RikUICharDB) == "table"
    status.loaded = status.loadedAccount or status.loadedCharacter
    if not store.Available() then return end
    if not status.loadedAccount then
        local loaded = store.Load("account")
        RikUIDB = type(loaded) == "table" and loaded or nil
        status.restored.account = RikUIDB ~= nil
    end
    if not status.loadedCharacter then
        local loaded = store.Load(store.CharacterKey())
        RikUICharDB = type(loaded) == "table" and loaded or nil
        status.restored.character = RikUICharDB ~= nil
    end
end

function store.Status() return status end

function store.BackupIssue()
    if not store.Available() then return "Reload backup unavailable" end
    if status.failure then return "Reload backup needs attention" end
    if store.MacroStatus and store.MacroStatus().failure then return "Restart backup needs attention" end
    return nil
end

-- Cached usage only: opening settings must never serialize or write a backup.
function store.BackupSummary()
    local lines = {}
    if not store.Available() then lines[#lines + 1] = "Reload backup unavailable."
    elseif status.failure then lines[#lines + 1] = "Reload backup needs attention: " .. status.failure
    else lines[#lines + 1] = "Reload backup available." end
    if not (store.MacrosAvailable and store.MacrosAvailable() and store.MacroStatus) then
        lines[#lines + 1] = "Restart backup unavailable."
    else
        local macro = store.MacroStatus()
        local limits = macro.limit .. " macros; " .. macro.capacity .. " bytes"
        if macro.bytes then
            lines[#lines + 1] = "Last verified restart snapshot: " .. macro.used .. "/" .. macro.limit
                .. " macros; " .. macro.bytes .. "/" .. macro.capacity .. " bytes."
        else lines[#lines + 1] = "Restart backup: no verified snapshot yet (limit " .. limits .. ")." end
        if macro.failure then lines[#lines + 1] = "Restart backup needs attention: " .. macro.failure end
        if macro.requiredBytes and macro.requiredBytes > macro.capacity then
            lines[#lines + 1] = "Latest settings need " .. macro.requiredBytes
                .. " bytes. Remove unused profiles or imported presets, keep portable exports, then choose Save now."
        elseif macro.failure then lines[#lines + 1] = "Choose Save now to retry outside combat." end
        if macro.learningReduced > 0 then
            lines[#lines + 1] = "Restart backup keeps reduced learning for " .. macro.learningReduced .. " character(s)."
        end
    end
    return table.concat(lines, "\n")
end

local function flushOne(name, value)
    if type(value) ~= "table" then return end
    local text, reason = store.Encode(value)
    if text and lastText[name] == text and not failures[name] then return end
    local ok = false
    if text then ok, reason = saveText(name, text) end
    if ok then lastText[name], failures[name] = text, nil
    else
        if failures[name] ~= reason then core:Print("Settings store: " .. name .. ": " .. tostring(reason)) end
        failures[name] = reason
    end
    status.failure = failures.account or failures[store.CharacterKey()]
end

function store.Flush()
    if not store.Available() then return end
    if type(core.DB)=="table" then
        local account={}
        for key,value in pairs(core.DB) do
            if key~="blockedActions" and key~="planSwitches" then account[key]=value end
        end
        flushOne("account", account)
    end
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
    if store.Available() and type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
        C_Timer.NewTicker(TICK_SECONDS, store.Flush)
    end
end)
core:RegisterEvent("PLAYER_LOGOUT", store.Flush)

core:RegisterCommand("store", function()
    core:Print(store.BackupSummary())
    core:Print("Store available=" .. tostring(store.Available()) .. " saves=" .. status.saves .. " chunks=" .. status.chunks
        .. " characters=" .. status.bytes .. " restored account=" .. tostring(status.restored.account == true)
        .. " character=" .. tostring(status.restored.character == true)
        .. (status.failure and " last failure: " .. status.failure or ""))
    if store.MacroStatus then
        local macro=store.MacroStatus()
        core:Print("Restart backup macros=" .. macro.used .. " restored=" .. tostring(macro.restored)
            .. " compacted learning=" .. macro.learningReduced
            .. (macro.failure and " last failure: " .. macro.failure or ""))
    end
end, "Show the state of RikUI's own settings store")
