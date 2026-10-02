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

-- A copy of the exact proposed key assignments, shared with the setup preview.
function bindings.Preview(opts) return resolveOptions(opts) end

local function captureCommand(snapshot, command)
    local ok, keys = pcall(function() return { GetBindingKey(command) } end)
    if not ok then return nil, "GetBindingKey failed for " .. command end
    for _, key in ipairs(keys) do
        if type(key) ~= "string" or key == "" then return nil, "invalid key for " .. command end
        local readable, owner = pcall(GetBindingAction, key)
        if not readable or owner ~= command then return nil, "inconsistent binding for " .. key end
        snapshot.keys[key] = owner
    end
    snapshot.commands[command] = keys
    return true
end

local function verifySnapshot(snapshot)
    local captured = {}
    for command, keys in pairs(snapshot.commands) do
        for _, key in ipairs(keys) do captured[key] = command end
    end
    for key, command in pairs(snapshot.keys) do
        if command ~= "" and captured[key] ~= command then
            return nil, "incomplete binding snapshot for " .. key
        end
    end
    return snapshot
end

local function captureSnapshot(resolved)
    local reason
    for _, name in ipairs({ "GetCurrentBindingSet", "GetBindingAction", "GetBindingKey" }) do
        if type(_G[name]) ~= "function" then return nil, name .. " unavailable" end
    end
    local ok, bindingSet = pcall(GetCurrentBindingSet)
    if not ok or (bindingSet ~= ACCOUNT_BINDINGS and bindingSet ~= CHARACTER_BINDINGS) then
        return nil, "GetCurrentBindingSet failed"
    end
    local snapshot, commands = { bindingSet = bindingSet, keys = {}, commands = {} }, {}
    for command in pairs(resolved) do commands[command] = true end
    for _, key in ipairs(touchedKeys) do
        local readable, command = pcall(GetBindingAction, key)
        if not readable or type(command) ~= "string" then return nil, "GetBindingAction failed for " .. key end
        snapshot.keys[key] = command
        if command ~= "" then commands[command] = true end
    end
    for _, command in ipairs(sortedKeys(commands)) do
        ok, reason = captureCommand(snapshot, command)
        if not ok then return nil, reason end
    end
    return verifySnapshot(snapshot)
end

function bindings.Snapshot(opts)
    local resolved, reason = resolveOptions(opts)
    if not resolved then return nil, reason end
    return captureSnapshot(resolved)
end

local function setKey(key, command)
    if command == "" then command = nil end
    local ok, accepted = pcall(SetBinding, key, command)
    if not ok or not accepted then return nil, "SetBinding failed for " .. key end
    return true
end

local function matchesSnapshot(snapshot)
    for key, command in pairs(snapshot.keys) do
        local ok, actual = pcall(GetBindingAction, key)
        if not ok or actual ~= command then return false end
    end
    for command, keys in pairs(snapshot.commands) do
        local ok, actual = pcall(function() return { GetBindingKey(command) } end)
        if not ok or #actual ~= #keys then return false end
        for index, key in ipairs(keys) do
            if actual[index] ~= key then return false end
        end
    end
    return true
end

-- Failure cleanup restores ordering as well as ownership, including old owners
-- of keys reassigned by the scheme. Public/persistent undo belongs to setup.
local function restore(snapshot)
    local restored = true
    for _, key in ipairs(sortedKeys(snapshot.keys)) do
        if not setKey(key) then restored = false end
    end
    for _, command in ipairs(sortedKeys(snapshot.commands)) do
        for _, key in ipairs(snapshot.commands[command]) do
            if not setKey(key, command) then restored = false end
        end
    end
    return matchesSnapshot(snapshot) and restored
end

local function validateStoredBindings(snapshot)
    if type(snapshot) ~= "table" or type(snapshot.keys) ~= "table" or type(snapshot.commands) ~= "table" then
        return nil, "invalid binding snapshot"
    end
    for key, command in pairs(snapshot.keys) do
        if type(key) ~= "string" or key == "" or type(command) ~= "string" then return nil, "invalid binding entry" end
    end
    for command, keys in pairs(snapshot.commands) do
        if type(command) ~= "string" or command == "" or type(keys) ~= "table" then return nil, "invalid binding order" end
        local count, seen = 0, {}
        for index, key in pairs(keys) do
            if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #keys
                or type(key) ~= "string" or key == "" or seen[key] then return nil, "invalid binding key list" end
            seen[key], count = true, count + 1
            if snapshot.keys[key] ~= command then return nil, "inconsistent binding order" end
        end
        if count ~= #keys then return nil, "incomplete binding key list" end
    end
    if not verifySnapshot(snapshot) then return nil, "incomplete binding snapshot" end
    return true
end

function bindings.ValidateSnapshot(snapshot)
    local ok, reason = validateStoredBindings(snapshot)
    if not ok then return nil, reason end
    if snapshot.restore ~= nil then return validateStoredBindings(snapshot.restore) end
    return true
end

local function restoreTarget(snapshot)
    local target = snapshot.restore
    if not target then
        target = { keys = {}, commands = {} }
        for key, command in pairs(snapshot.keys) do target.keys[key] = command end
        for command, keys in pairs(snapshot.commands) do
            target.commands[command] = {}
            for _, key in ipairs(keys) do table.insert(target.commands[command], key) end
        end
    end
    for command, keys in pairs(target.commands) do
        local ok, current = pcall(function() return { GetBindingKey(command) } end)
        if not ok then return nil, "GetBindingKey failed for " .. command end
        for _, key in ipairs(current) do
            if target.keys[key] == nil then
                local readable, owner = pcall(GetBindingAction, key)
                if not readable or owner ~= command then return nil, "inconsistent binding for " .. tostring(key) end
                target.keys[key] = command
                keys[#keys + 1] = key
            end
        end
    end
    -- Journal later aliases before temporarily clearing them to restore primaries.
    snapshot.restore = target
    return target
end

-- Setup owns queuing; restore refuses direct combat calls.
function bindings.Restore(snapshot)
    if InCombatLockdown() then return nil, "binding restore requires leaving combat" end
    local valid, reason = bindings.ValidateSnapshot(snapshot)
    if not valid then return nil, reason end
    local target
    target, reason = restoreTarget(snapshot)
    if not target then return nil, reason end
    if not restore(target) then return nil, "binding restore readback failed" end
    local ok, saved = pcall(SaveBindings, CHARACTER_BINDINGS)
    if not ok or saved == false then return nil, "SaveBindings failed" end
    return true
end

local function keysToClear(resolved, snapshot)
    local keys = {}
    for _, key in ipairs(touchedKeys) do keys[key] = true end
    for command in pairs(resolved) do
        for _, key in ipairs(snapshot.commands[command]) do keys[key] = true end
    end
    return sortedKeys(keys)
end

local function assignPrimary(command, primary, aliases)
    local ok, reason = setKey(primary, command)
    if not ok then return nil, reason end
    for _, key in ipairs(aliases) do
        -- Scheme keys may now belong to a different command; never steal them back.
        if not touched[key] then
            ok, reason = setKey(key, command)
            if not ok then return nil, reason end
        end
    end
    return true
end

local function verifyBindings(resolved, snapshot)
    for command, primary in pairs(resolved) do
        local ok, actual = pcall(GetBindingKey, command)
        if not ok or actual ~= primary then return nil, "primary binding mismatch for " .. command end
    end
    for key, previous in pairs(snapshot.keys) do
        if not touched[key] then
            local ok, actual = pcall(GetBindingAction, key)
            if not ok or actual ~= previous then return nil, "alternate binding mismatch for " .. key end
        end
    end
    return true
end

local function writeBindings(resolved, commands, snapshot)
    for _, key in ipairs(keysToClear(resolved, snapshot)) do
        local ok, reason = setKey(key)
        if not ok then return nil, reason end
    end
    for _, command in ipairs(commands) do
        local ok, reason = assignPrimary(command, resolved[command], snapshot.commands[command])
        if not ok then return nil, reason end
    end
    local verified, reason = verifyBindings(resolved, snapshot)
    if not verified then return nil, reason end
    local ok, saved = pcall(SaveBindings, CHARACTER_BINDINGS)
    -- SaveBindings has no success return; an explicit false still means failure.
    if not ok or saved == false then return nil, "SaveBindings failed" end
    return true
end

local function applyNow(resolved, opts)
    if type(SetBinding) ~= "function" then return reject("SetBinding unavailable", opts) end
    if type(SaveBindings) ~= "function" then return reject("SaveBindings unavailable", opts) end
    local snapshot, reason = captureSnapshot(resolved)
    if not snapshot then return reject(reason, opts) end
    local commands = sortedKeys(resolved)
    local ok
    ok, reason = writeBindings(resolved, commands, snapshot)
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


-- Setup Packs adopt only the keys explicitly selected in the review.
function bindings.CaptureSelected(selected)
    if InCombatLockdown() then return nil,"Binding review requires leaving combat" end
    if type(selected)~="table" then return nil,"Expected selected bindings" end
    local count=0;local resolved={}
    for key,command in pairs(selected) do
        count=count+1
        local slot=type(command)=="string" and tonumber(command:match("^ACTIONBUTTON(%d+)$"))
        if count>24 or type(key)~="string" or not key:match("^[%w%-]+$") or not slot or slot<1 or slot>12 then return nil,"Unsupported selected binding" end
        resolved[command]=key
    end
    local snapshot,reason=captureSnapshot(resolved);if not snapshot then return nil,reason end
    for key in pairs(selected) do
        local ok,command=pcall(GetBindingAction,key);if not ok or type(command)~="string" then return nil,"Binding owner unavailable" end
        snapshot.keys[key]=command
        if command~="" then local captured,problem=captureCommand(snapshot,command);if not captured then return nil,problem end end
    end
    return verifySnapshot(snapshot)
end
function bindings.ApplySelected(selected,snapshot)
    if InCombatLockdown() then return nil,"Binding apply requires leaving combat" end
    local valid,reason=bindings.CaptureSelected(selected);if not valid then return nil,reason end
    if not snapshot or not matchesSnapshot(snapshot) then return nil,"Bindings changed after review; review again" end
    local result,failure,finished
    local queued=core.Combat.Queue(function()
        local function rollback(problem)
            if not restore(snapshot) then problem=problem.."; runtime rollback incomplete" end
            failure=problem;finished=true
        end
        for _,key in ipairs(sortedKeys(selected)) do
            local ok,problem=setKey(key,selected[key])
            if not ok then rollback(problem);return end
            local read,actual=pcall(GetBindingAction,key)
            if not read or actual~=selected[key] then rollback("Binding readback failed");return end
        end
        local saved,accepted=pcall(SaveBindings,CHARACTER_BINDINGS)
        if not saved or accepted==false then rollback("Selected binding save failed");return end
        result,finished=true,true
    end)
    if not queued or not finished then return nil,"Binding queue did not finish" end
    return result,failure
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
