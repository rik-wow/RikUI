-- Assemble the enabled write set before Apply mutates any native state.
local core, setup = RikUI, RikUI.Setup
local SNAPSHOT_VERSION = 1
setup.UndoVersion = SNAPSHOT_VERSION

local function captureAction(slot)
    local kind, id = GetActionInfo(slot)
    if kind == nil then return {} end
    if kind ~= "spell" and kind ~= "item" and kind ~= "macro" then
        return nil, "unsupported action in slot " .. slot .. ": " .. tostring(kind)
    end
    if type(id) ~= "number" or id <= 0 then return nil, "unreadable action in slot " .. slot end
    local action = { kind = kind, id = id }
    if kind == "macro" then
        local pool, reason = core.Macros.Snapshot()
        if not pool then return nil, reason end
        action.macro, reason = core.Macros.CaptureIdentity(id, pool)
        if not action.macro then return nil, reason end
    end
    return action
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

local function captureLayout(preset, profile)
    local layout = {}
    for name in pairs(preset.positions or setup.DefaultPositions) do
        layout[name] = { value = setup.CopyState(profile.positions[name]) }
    end
    return layout
end

function setup.CaptureSnapshot(preset, opts, profile, charDB, profileName)
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
    if opts.layout ~= false then snapshot.layout = captureLayout(preset, profile) end
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
