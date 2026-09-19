-- Reverse the saved Setup transaction, retaining progress after any failure.
local core, setup = RikUI, RikUI.Setup
-- Macro deletion can renumber indices: finish macros before re-placing slots.
local STEP_ORDER = { "layout", "cvars", "binds", "macros", "bars" }
local active

function setup.IsUndoing() return active ~= nil end

local function reject(reason)
    core:Print("Undo: " .. reason)
    return nil, reason
end

local function restoreBar(slot, action)
    local restored = { kind = action.kind, id = action.id }
    if action.kind == "macro" then
        local reason
        restored.id, reason = core.Macros.FindScoped(action.macro)
        if not restored.id then return nil, reason or "original slot macro is missing" end
    end
    return setup.RestoreSlot(slot, restored)
end

local function restoreEntry(context, name, key)
    local saved = context.snapshot[name]
    if name == "layout" then
        context.profile.positions[key] = setup.CopyState(saved[key].value)
        if core.Bars then core.Bars.ApplyLayout() end
        return true
    end
    if name == "cvars" then return core.CVars.Restore(key, saved[key]) end
    if name == "binds" then return core.Bindings.Restore(saved) end
    if name == "macros" then return core.Macros.RestoreChange(saved[key]) end
    return restoreBar(key, saved[key])
end

local function fail(context, name, reason)
    context.result.status, context.result.error = "failed", tostring(reason)
    core:Print("Undo " .. name .. ": failed: " .. tostring(reason) .. "; snapshot kept; retry /rik undo.")
    active = nil
end

local function enqueue(context, callback)
    if InCombatLockdown() then
        context.result.status = "queued"
        if not context.queueReported then
            core:Print("Undo cannot run in combat; queued until combat ends.")
            context.queueReported = true
        end
    end
    core.Combat.Queue(function()
        local ok, reason = pcall(callback)
        if not ok then fail(context, "snapshot", reason) end
    end)
end

local runStep
local function runEntries(context, name, keys, index, nextStep)
    local key = keys[index]
    if not key then
        core:Print("Undo " .. name .. ": restored=" .. #keys .. (context.snapshot[name] and "" or "; disabled"))
        runStep(context, nextStep)
        return
    end
    local progress = context.snapshot.progress[name]
    if progress[key] then runEntries(context, name, keys, index + 1, nextStep); return end
    enqueue(context, function()
        context.result.status = "running"
        if context.charDB.undo ~= context.snapshot then fail(context, name, "snapshot changed"); return end
        local ok, restored, reason = pcall(restoreEntry, context, name, key)
        if not ok or not restored then fail(context, name, ok and reason or restored); return end
        progress[key] = true
        runEntries(context, name, keys, index + 1, nextStep)
    end)
end

runStep = function(context, index)
    local name = STEP_ORDER[index]
    if not name then
        context.charDB.applied = setup.CopyState(context.snapshot.applied)
        context.charDB.undo = nil
        context.result.status, active = "undone", nil
        core:Print("Undo complete.")
        return
    end
    context.snapshot.progress[name] = context.snapshot.progress[name] or {}
    local keys = setup.StateKeys(context.snapshot[name])
    if name == "binds" then keys = context.snapshot.binds and { "bindings" } or {} end
    local reversed = {}
    for i = #keys, 1, -1 do reversed[#reversed + 1] = keys[i] end
    runEntries(context, name, reversed, 1, index + 1)
end

local function validIdentity(value)
    return type(value) == "table" and type(value.name) == "string" and value.name ~= ""
        and (value.scope == "account" or value.scope == "character") and type(value.body) == "string"
        and (type(value.icon) == "number" or type(value.icon) == "string")
end

local function validAction(slot, action)
    if type(slot) ~= "number" or slot % 1 ~= 0 or type(action) ~= "table" then return false end
    local inPage = false
    for _, page in ipairs(setup.PageOrder) do
        if slot >= setup.SlotToAction(page, 1) and slot <= setup.SlotToAction(page, 12) then inPage = true end
    end
    if not inPage then return false end
    if action.kind == nil then return action.id == nil and action.macro == nil end
    if action.kind ~= "spell" and action.kind ~= "item" and action.kind ~= "macro" then return false end
    if type(action.id) ~= "number" or action.id <= 0 or action.id % 1 ~= 0 then return false end
    return action.kind ~= "macro" or validIdentity(action.macro)
end

local function validateRecords(snapshot)
    for slot, action in pairs(snapshot.bars or {}) do
        if not validAction(slot, action) then return "invalid undo action" end
    end
    for name, value in pairs(snapshot.cvars or {}) do
        if type(name) ~= "string" or type(value) ~= "string" then return "invalid undo CVar" end
    end
    for name, entry in pairs(snapshot.layout or {}) do
        if type(name) ~= "string" or type(entry) ~= "table"
            or (entry.value ~= nil and type(entry.value) ~= "table") then return "invalid undo position" end
    end
    for name, change in pairs(snapshot.macros or {}) do
        if type(change) ~= "table" or name ~= change.name or type(name) ~= "string"
            or (change.before ~= false and not validIdentity(change.before))
            or (change.started and change.scope ~= "account" and change.scope ~= "character")
            or (change.after ~= nil and not validIdentity(change.after)) then return "invalid undo macro" end
    end
    if snapshot.binds then
        local valid, reason = core.Bindings.ValidateSnapshot(snapshot.binds)
        if not valid then return reason end
    end
end

local function validateSnapshot(snapshot)
    if type(snapshot) ~= "table" or snapshot.version ~= setup.UndoVersion
        or type(snapshot.progress) ~= "table" or type(snapshot.profile) ~= "string" then
        return "unsupported or invalid undo snapshot"
    end
    for _, name in ipairs(STEP_ORDER) do
        if snapshot[name] ~= nil and type(snapshot[name]) ~= "table" then return "invalid undo " .. name end
        if snapshot.progress[name] ~= nil and type(snapshot.progress[name]) ~= "table" then
            return "invalid undo progress"
        end
    end
    return validateRecords(snapshot)
end

function setup.Undo()
    if active or setup.IsApplying() then return reject("another Setup operation is pending") end
    if not core.CharDB or not core.DB then return reject("Still loading") end
    local snapshot = core.CharDB.undo
    if snapshot == nil then return reject("nothing to undo") end
    local reason = validateSnapshot(snapshot)
    if reason then return reject(reason) end
    local profile = core.DB.profiles[snapshot.profile]
    if not profile or type(profile.positions) ~= "table" then return reject("original profile is unavailable") end
    local context = { snapshot = snapshot, charDB = core.CharDB, profile = profile,
        result = { status = "running" } }
    active = context
    enqueue(context, function()
        local ok, failure = pcall(runStep, context, 1)
        if not ok then fail(context, "snapshot", failure) end
    end)
    return context.result
end

core:RegisterCommand("undo", function(args)
    if args ~= "" then core:Print("Usage: /rik undo"); return end
    setup.Undo()
end, "Restore the state before the last Apply: /rik undo")
