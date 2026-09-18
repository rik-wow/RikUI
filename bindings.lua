-- Native key scheme and guarded writes; see docs/bindings.md for contracts.
local core = RikUI
local bindings = { Scheme = {} }
core.Bindings = bindings
local ACCOUNT_BINDINGS, CHARACTER_BINDINGS = 1, 2
local scheme = bindings.Scheme

local function addTier(prefix, keys)
    for index, key in ipairs(keys) do scheme[prefix .. index] = key end
end

addTier("ACTIONBUTTON", { "1", "2", "3", "4", "5", "Q", "E", "R", "F", "T", "G" })
addTier("MULTIACTIONBAR1BUTTON", {
    "SHIFT-1", "SHIFT-2", "SHIFT-3", "SHIFT-4", "SHIFT-5", "SHIFT-Q",
    "SHIFT-E", "SHIFT-R", "SHIFT-F", "BUTTON4", "BUTTON5", "SHIFT-T",
})
addTier("MULTIACTIONBAR2BUTTON", {
    "CTRL-1", "CTRL-2", "CTRL-3", "CTRL-4", "CTRL-5", "CTRL-F",
    "CTRL-T", "CTRL-G", "CTRL-Z", "CTRL-X", "CTRL-C", "CTRL-V",
})
addTier("SHAPESHIFTBUTTON", { "CTRL-Q", "CTRL-E", "CTRL-R" })
addTier("BONUSACTIONBUTTON", { "SHIFT-G", "CTRL-B", "CTRL-N" })
scheme.STRAFELEFT, scheme.STRAFERIGHT = "A", "D"

local function sortedKeys(values)
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local touched = { ["CTRL-6"] = true }
for _, key in pairs(scheme) do touched[key] = true end
local touchedKeys = sortedKeys(touched)

local function reject(reason, opts)
    if not (opts and opts.quiet) then core:Print("Bindings: " .. reason) end
    return nil, reason
end

local function resolveOptions(opts)
    if opts == nil then opts = {} end
    if type(opts) ~= "table" then return nil, "options must be a table" end
    for _, name in ipairs({ "strafe", "mouse45" }) do
        if opts[name] ~= nil and type(opts[name]) ~= "boolean" then
            return nil, name .. " must be a boolean"
        end
    end
    local resolved = {}
    for command, key in pairs(scheme) do resolved[command] = key end
    if opts.strafe == false then
        resolved.STRAFELEFT, resolved.STRAFERIGHT = nil, nil
        resolved.TURNLEFT, resolved.TURNRIGHT = "A", "D"
    end
    if opts.mouse45 == false then
        resolved.BONUSACTIONBUTTON1, resolved.MULTIACTIONBAR2BUTTON8 = nil, nil
        resolved.MULTIACTIONBAR1BUTTON10 = "SHIFT-G"
        resolved.MULTIACTIONBAR1BUTTON11 = "CTRL-G"
    end
    return resolved
end

function bindings.Snapshot()
    if type(GetCurrentBindingSet) ~= "function" then return nil, "GetCurrentBindingSet unavailable" end
    if type(GetBindingAction) ~= "function" then return nil, "GetBindingAction unavailable" end
    local ok, bindingSet = pcall(GetCurrentBindingSet)
    if not ok or (bindingSet ~= ACCOUNT_BINDINGS and bindingSet ~= CHARACTER_BINDINGS) then
        return nil, "GetCurrentBindingSet failed"
    end
    local snapshot = { bindingSet = bindingSet, keys = {} }
    for _, key in ipairs(touchedKeys) do
        local readable, command = pcall(GetBindingAction, key)
        if not readable or type(command) ~= "string" then return nil, "GetBindingAction failed for " .. key end
        snapshot.keys[key] = command
    end
    return snapshot
end

local function setKey(key, command)
    if command == "" then command = nil end
    local ok, accepted = pcall(SetBinding, key, command)
    if not ok or not accepted then return nil, "SetBinding failed for " .. key end
    return true
end

-- Failure cleanup only. Public/persistent undo belongs to the setup module.
local function restore(snapshot)
    local restored = true
    for _, key in ipairs(touchedKeys) do
        if not setKey(key) then restored = false end
    end
    for _, key in ipairs(touchedKeys) do
        local command = snapshot.keys[key]
        if command ~= "" and not setKey(key, command) then restored = false end
    end
    return restored
end

local function writeBindings(resolved, commands)
    for _, key in ipairs(touchedKeys) do
        local ok, reason = setKey(key)
        if not ok then return nil, reason end
    end
    for _, command in ipairs(commands) do
        local ok, reason = setKey(resolved[command], command)
        if not ok then return nil, reason end
    end
    local ok, saved = pcall(SaveBindings, CHARACTER_BINDINGS)
    -- SaveBindings has no success return; an explicit false still means failure.
    if not ok or saved == false then return nil, "SaveBindings failed" end
    return true
end

local function applyNow(resolved, opts)
    if type(SetBinding) ~= "function" then return reject("SetBinding unavailable", opts) end
    if type(SaveBindings) ~= "function" then return reject("SaveBindings unavailable", opts) end
    local snapshot, reason = bindings.Snapshot()
    if not snapshot then return reject(reason, opts) end
    local commands = sortedKeys(resolved)
    local ok
    ok, reason = writeBindings(resolved, commands)
    if not ok then
        if not restore(snapshot) then reason = reason .. "; runtime rollback incomplete" end
        return reject(reason, opts)
    end
    if not opts.quiet then
        for _, command in ipairs(commands) do core:Print(resolved[command] .. " -> " .. command) end
    end
    return snapshot, nil, #commands
end

function bindings.Apply(opts)
    local resolved, reason = resolveOptions(opts)
    if not resolved then
        if type(opts) == "table" and opts.onComplete then opts.onComplete(nil, reason) end
        return reject(reason, type(opts) == "table" and opts or nil)
    end
    opts = opts or {}
    local finished, snapshot, count = false, nil, nil
    local accepted = core.Combat.Queue(function()
        snapshot, reason, count = applyNow(resolved, opts)
        finished = true
        if opts.onComplete then opts.onComplete(snapshot, reason, count) end
    end)
    if not accepted then return reject("combat queue failed", opts) end
    if not finished then return nil, "queued" end
    return snapshot, reason
end

local FALLBACK_KEYS = { MULTIACTIONBAR1BUTTON10 = "SHIFT-G", MULTIACTIONBAR1BUTTON11 = "CTRL-G" }

local function preferredKey(command, ...)
    local primary = ...
    local fallback
    for index = 1, select("#", ...) do
        local key = select(index, ...)
        if key == scheme[command] and key ~= nil then return key end
        if key == FALLBACK_KEYS[command] then fallback = key end
    end
    return fallback or primary
end

function bindings.Label(command)
    if type(command) ~= "string" or command == "" or type(GetBindingKey) ~= "function" then return "" end
    local key
    local ok = pcall(function() key = preferredKey(command, GetBindingKey(command)) end)
    if not ok or type(key) ~= "string" then return "" end
    local label = key:gsub("SHIFT%-", "s"):gsub("CTRL%-", "c"):gsub("ALT%-", "a"):gsub("BUTTON", "M")
    return label
end

core:RegisterCommand("binds", function()
    local _, reason = bindings.Apply()
    if reason == "queued" then core:Print("Bindings queued until combat ends.") end
end, "Apply the character keybind scheme")
