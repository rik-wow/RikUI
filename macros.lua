-- Preset macro storage for Forever's 120 account / 18 character target.
-- See docs/macros.md for queue results, snapshot identity and beta limitations.
local core = RikUI
local macros = {}
core.Macros = macros

local ACCOUNT_LIMIT, CHARACTER_LIMIT = 120, 18
local FIRST_CHARACTER, LAST_CHARACTER = ACCOUNT_LIMIT + 1, ACCOUNT_LIMIT + CHARACTER_LIMIT
local NAME_LIMIT, BODY_LIMIT = 16, 255

local function reject(name, reason, opts)
    local label = type(name) == "string" and name or "<invalid name>"
    if not (opts and opts.quiet) then core:Print("Macro " .. label .. ": " .. reason) end
    return nil, reason
end

local function letterCount(text)
    -- Lua's # counts bytes. Count UTF-8 leading bytes, including whitespace.
    local _, count = text:gsub("[^\128-\191]", "")
    return count
end

local function validate(name, icon, body, scope)
    if type(name) ~= "string" or name == "" then return "name must be a nonempty string" end
    if letterCount(name) > NAME_LIMIT then return "name exceeds 16 characters" end
    if type(body) ~= "string" then return "body must be a string" end
    if letterCount(body) > BODY_LIMIT then return "body exceeds 255 characters" end
    if scope ~= nil and scope ~= "character" and scope ~= "account" then return "unknown scope" end
    if type(icon) == "number" and icon > 0 and icon % 1 == 0 then return end
    if type(icon) == "string" and icon ~= "" then return end
    return "icon must be a texture ID or path"
end

local function capturePool(snapshot, first, last, scope)
    for index = first, last do
        local ok, name, icon, body = pcall(GetMacroInfo, index)
        if not ok then return nil, "GetMacroInfo failed at slot " .. index end
        if name ~= nil then
            if type(name) ~= "string" or type(body) ~= "string" then
                return nil, "invalid macro data at slot " .. index
            end
            snapshot[index] = { name = name, icon = icon, body = body, scope = scope }
        end
    end
    return true
end

function macros.Snapshot()
    if type(GetMacroInfo) ~= "function" then return nil, "GetMacroInfo unavailable" end
    local snapshot = {}
    local ok, reason = capturePool(snapshot, 1, ACCOUNT_LIMIT, "account")
    if not ok then return nil, reason end
    ok, reason = capturePool(snapshot, FIRST_CHARACTER, LAST_CHARACTER, "character")
    if not ok then return nil, reason end
    return snapshot
end

local function findInPool(snapshot, name, first, last)
    for index = first, last do
        if snapshot[index] and snapshot[index].name == name then return index end
    end
end

local function findInSnapshot(snapshot, name)
    return findInPool(snapshot, name, FIRST_CHARACTER, LAST_CHARACTER)
        or findInPool(snapshot, name, 1, ACCOUNT_LIMIT)
end

function macros.Find(name)
    if type(name) ~= "string" or name == "" then return nil, "name must be a nonempty string" end
    local snapshot, reason = macros.Snapshot()
    if not snapshot then return nil, reason end
    return findInSnapshot(snapshot, name)
end

local function hasSpace(snapshot, first, last)
    for index = first, last do
        if not snapshot[index] then return true end
    end
    return false
end

local function create(snapshot, name, icon, body, scope)
    local character = hasSpace(snapshot, FIRST_CHARACTER, LAST_CHARACTER)
    if not character and scope ~= "account" then return nil, "character macro pool is full" end
    if not character and not hasSpace(snapshot, 1, ACCOUNT_LIMIT) then return nil, "account macro pool is full" end
    if type(CreateMacro) ~= "function" then return nil, "CreateMacro unavailable" end
    local ok, index = pcall(CreateMacro, name, icon, body, character)
    if not ok then return nil, "CreateMacro failed" end
    return index
end

local function edit(index, name, icon, body)
    if type(EditMacro) ~= "function" then return nil, "EditMacro unavailable" end
    local ok, result = pcall(EditMacro, index, name, icon, body)
    if not ok then return nil, "EditMacro failed" end
    return result
end

local function ensureNow(name, icon, body, scope, opts)
    local snapshot, reason = macros.Snapshot()
    if not snapshot then return reject(name, reason, opts) end
    local index = findInSnapshot(snapshot, name)
    local disposition = index and "edited" or "placed"
    if index then
        index, reason = edit(index, name, icon, body)
    else
        index, reason = create(snapshot, name, icon, body, scope)
    end
    if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > LAST_CHARACTER then
        return reject(name, reason or "macro write rejected", opts)
    end
    return index, nil, disposition
end

function macros.Ensure(name, icon, body, scope, opts)
    opts = opts or {}
    local invalid = validate(name, icon, body, scope)
    if invalid then
        if opts.onComplete then opts.onComplete(nil, invalid) end
        return reject(name, invalid, opts)
    end
    local finished, index, reason, disposition = false, nil, nil, nil
    local accepted = core.Combat.Queue(function()
        index, reason, disposition = ensureNow(name, icon, body, scope, opts)
        finished = true
        if opts.onComplete then opts.onComplete(index, reason, disposition) end
    end)
    if not accepted then return reject(name, "combat queue failed", opts) end
    if not finished then return nil, "queued" end
    return index, reason
end
