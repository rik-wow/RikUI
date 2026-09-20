-- Assemble the enabled write set before Apply mutates any native state.
local core, setup = RikUI, RikUI.Setup
local SNAPSHOT_VERSION = 1
setup.UndoVersion = SNAPSHOT_VERSION

-- The macro pool index behind a macro slot. On 69913 GetActionInfo answers with the ID of the spell
-- the macro casts, so the slot's macro is found by the name GetActionText returns; the reported id
-- is only trusted when that macro carries the same name. The lowest index wins a name clash.
local function macroIndexInSlot(slot, id, pool)
    local name = setup.MacroNameInSlot(slot)
    if not name then return id end
    if pool[id] and pool[id].name == name then return id end
    local found
    for index, value in pairs(pool) do
        if value.name == name and (not found or index < found) then found = index end
    end
    return found
end

local function captureMacro(slot, id)
    local pool, reason = core.Macros.Snapshot()
    if not pool then return nil, reason end
    local index = macroIndexInSlot(slot, id, pool)
    -- A slot naming a macro that no longer exists has nothing Undo could put back.
    if not index then return {} end
    local identity
    identity, reason = core.Macros.CaptureIdentity(index, pool)
    if not identity then return nil, reason end
    return { kind = "macro", id = index, macro = identity }
end

local function captureAction(slot)
    local kind, id = GetActionInfo(slot)
    if kind == nil then return {} end
    if kind ~= "spell" and kind ~= "item" and kind ~= "macro" then
        return nil, "unsupported action in slot " .. slot .. ": " .. tostring(kind)
    end
    if type(id) ~= "number" or id <= 0 then return nil, "unreadable action in slot " .. slot end
    if kind == "macro" then return captureMacro(slot, id) end
    return { kind = kind, id = id }
end

local function captureBars(preset)
    local bars = {}
    for _, page in ipairs(setup.PageOrder) do
        for _, index in ipairs(setup.StateKeys(preset.bars[page])) do
            local slot = setup.SlotToAction(page, index)
            local action, reason = captureAction(slot)
            if not action then return nil, reason end
            bars[slot] = action
        end
    end
    return bars
end

local function captureLayout(preset, profile, positions)
    local layout = {}
    for name in pairs(positions or setup.LayoutPositions(preset)) do
        layout[name] = { value = setup.CopyState(profile.positions[name]) }
    end
    return layout
end

function setup.CaptureSnapshot(preset, opts, profile, charDB, profileName, positions)
    local snapshot = { version = SNAPSHOT_VERSION, profile = profileName or charDB.profile,
        applied = setup.CopyState(charDB.applied), progress = {} }
    local reason
    if opts.macros ~= false then
        snapshot.macros, reason = core.Macros.SnapshotChanges(preset.macros)
        if not snapshot.macros then return nil, reason end
    end
    if opts.bars ~= false then
        snapshot.bars, reason = captureBars(preset)
        if not snapshot.bars then return nil, reason end
    end
    if opts.binds ~= false then
        snapshot.binds, reason = core.Bindings.Snapshot(opts)
        if not snapshot.binds then return nil, reason end
    end
    if opts.cvars ~= false then
        local stats
        snapshot.cvars, stats = core.CVars.Snapshot(opts.cvarSelection, { quiet = true })
        if stats.error then return nil, stats.error end
    end
    if opts.layout ~= false then snapshot.layout = captureLayout(preset, profile, positions) end
    return snapshot
end

-- Read-only preview; Apply persists its own capture at actual execution time.
function setup.Snapshot(class, role, opts)
    if not core.CharDB or not core.Profile then return nil, "Still loading" end
    if InCombatLockdown() then return nil, "snapshot requires leaving combat" end
    if class == nil then class = select(2, UnitClass("player")) end
    if opts == nil then opts = {} end
    local reason = setup.ValidateOptions(opts)
    if reason then return nil, reason end
    local preset
    preset, reason = setup.Resolve(class, role)
    if not preset then return nil, reason end
    local ok, snapshot
    ok, snapshot, reason = pcall(setup.CaptureSnapshot, preset, opts, core.Profile, core.CharDB)
    if not ok then return nil, tostring(snapshot) end
    return snapshot, reason
end
