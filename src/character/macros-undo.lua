-- Persistent macro identities and the journal used by Setup undo.
local macros = RikUI.Macros

function macros.FindScoped(identity, pool)
    local reason
    if not pool then pool, reason = macros.Snapshot() end
    if not pool then return nil, reason end
    local found
    for index, value in pairs(pool) do
        if value.name == identity.name and value.scope == identity.scope then
            if found then return nil, "ambiguous macro: " .. identity.name end
            found = index
        end
    end
    return found
end

function macros.CaptureIdentity(index, pool)
    local value = pool[index]
    if not value then return nil, "macro missing at index " .. tostring(index) end
    local found, reason = macros.FindScoped(value, pool)
    if not found then return nil, reason end
    local icon = value.icon
    if C_Macro and type(C_Macro.GetSelectedMacroIcon) == "function" then
        local ok
        ok, icon = pcall(C_Macro.GetSelectedMacroIcon, index)
        if not ok or icon == nil then return nil, "selected macro icon unavailable: " .. value.name end
    end
    if type(icon) ~= "number" and type(icon) ~= "string" then return nil, "invalid macro icon: " .. value.name end
    return { name = value.name, scope = value.scope, body = value.body, icon = icon }
end

function macros.SnapshotChanges(definitions)
    local pool, reason = macros.Snapshot()
    if not pool then return nil, reason end
    local changes = {}
    for name, definition in pairs(definitions) do
        local index
        index, reason = macros.Find(name)
        if reason then return nil, reason end
        local before = false
        if index then
            before, reason = macros.CaptureIdentity(index, pool)
            if not before then return nil, reason end
        end
        changes[name] = { name = name, before = before,
            body = definition.body, icon = definition.icon }
    end
    return changes
end

-- Runs inside Ensure's queued callback immediately before its native mutation.
function macros.PrepareUndo(change, index, pool, scope)
    if change.before then
        local current, reason
        if index then current, reason = macros.CaptureIdentity(index, pool) end
        if not current or current.scope ~= change.before.scope or current.body ~= change.before.body
            or current.icon ~= change.before.icon then
            return nil, reason or "macro changed since snapshot: " .. change.name
        end
    elseif index then
        return nil, "macro appeared since snapshot: " .. change.name
    end
    change.scope, change.started = scope, true
    return true
end

function macros.RecordUndo(change, index)
    local pool, reason = macros.Snapshot()
    if not pool then return nil, reason end
    local identity
    identity, reason = macros.CaptureIdentity(index, pool)
    if not identity then return nil, reason end
    if identity.name ~= change.name or identity.scope ~= change.scope then return nil, "macro write identity changed" end
    change.after = identity
    return true
end

local function currentIdentity(change)
    local pool, reason = macros.Snapshot()
    if not pool then return nil, nil, reason end
    local index
    index, reason = macros.FindScoped(change, pool)
    if not index then return nil, nil, reason end
    local identity
    identity, reason = macros.CaptureIdentity(index, pool)
    return index, identity, reason
end

local function deleteCreated(change, index, current)
    local expected = change.after or change
    if current.body ~= expected.body or current.icon ~= expected.icon then
        return nil, "created macro was changed: " .. change.name
    end
    local ok, result = pcall(DeleteMacro, index)
    if not ok or result == false then return nil, "DeleteMacro failed: " .. change.name end
    local remaining, _, reason = currentIdentity(change)
    if reason then return nil, reason end
    if remaining then return nil, "macro deletion readback failed: " .. change.name end
    return true
end

function macros.RestoreChange(change)
    if InCombatLockdown() then return nil, "macro restore requires leaving combat" end
    if not change.started then return true end
    local index, current, reason = currentIdentity(change)
    if reason then return nil, reason end
    if not change.before then
        if not index then return true end
        return deleteCreated(change, index, current)
    end
    if not index then return nil, "original macro is missing: " .. change.name end
    local before = change.before
    if current.body == before.body and current.icon == before.icon then return true end
    local ok, result = pcall(EditMacro, index, before.name, before.icon, before.body)
    if not ok or type(result) ~= "number" then return nil, "EditMacro failed: " .. change.name end
    index, current, reason = currentIdentity(change)
    if reason then return nil, reason end
    if not index or current.body ~= before.body or current.icon ~= before.icon then
        return nil, "macro restoration readback failed: " .. change.name
    end
    return true
end
