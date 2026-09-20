-- Ordered setup orchestration. The returned result also tracks deferred work.
local core, setup = RikUI, RikUI.Setup
local STEP_ORDER = { "macros", "bars", "binds", "cvars", "layout" }
local active

function setup.IsApplying() return active ~= nil end

setup.DefaultPositions = {
    main = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 40 },
    bar2 = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 82 },
    bar3 = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 124 },
    bar4 = { point = "RIGHT", relativePoint = "RIGHT", x = -40, y = -90 },
    bar5 = { point = "RIGHT", relativePoint = "RIGHT", x = -82, y = -90 },
    stance = { point = "BOTTOMLEFT", relativePoint = "BOTTOM", x = -249, y = 166 },
    pet = { point = "BOTTOMLEFT", relativePoint = "BOTTOM", x = -249, y = 202 },
}

local copy, sortedKeys = setup.CopyState, setup.StateKeys

local function counts()
    return { placed = 0, skipped = 0, edited = 0 }
end

local function summarize(name, stats, suffix)
    core:Print(string.format("Setup %s: placed=%d, skipped=%d, edited=%d%s",
        name, stats.placed, stats.skipped, stats.edited, suffix or ""))
end

local function reportMissing()
    local names = sortedKeys(setup.Missing)
    if #names == 0 then return end
    core:Print("Setup spells: not in your spellbook although your level allows them: " .. table.concat(names, ", ")
        .. ". Check one with /rik spells <name>.")
end

-- The snapshot leaves out a setting the client does not know, so Apply never visits it. Without
-- this it would vanish from the summary instead of showing as skipped.
local function reportUnknownSettings(context, stats)
    local wanted, unknown = context.opts.cvarSelection, {}
    for _, entry in ipairs(core.CVars.List) do
        local selected = wanted == nil or wanted[entry.name] == true
        if selected and context.snapshot.cvars[entry.name] == nil then unknown[#unknown + 1] = entry.name end
    end
    if #unknown == 0 then return end
    stats.skipped = stats.skipped + #unknown
    core:Print("Setup settings: unknown on this client, skipped: " .. table.concat(unknown, ", "))
end

local function macroOperations(context)
    local preset = context.preset
    local operations = {}
    for _, name in ipairs(sortedKeys(preset.macros)) do
        local macro = preset.macros[name]
        operations[#operations + 1] = function(done)
            core.Macros.Ensure(name, macro.icon, macro.body, macro.scope, {
                quiet = true,
                beforeWrite = function(index, pool, scope)
                    return core.Macros.PrepareUndo(context.snapshot.macros[name], index, pool, scope)
                end,
                onComplete = function(index, reason, disposition)
                    if not index then done(nil, name .. ": " .. tostring(reason)); return end
                    local saved, failure = core.Macros.RecordUndo(context.snapshot.macros[name], index)
                    if not saved then done(nil, failure); return end
                    local stats = counts()
                    stats[disposition] = 1
                    done(stats)
                end,
            })
        end
    end
    return operations
end

local function barOperations(preset)
    local operations = {}
    for _, page in ipairs(setup.PageOrder) do
        for _, index in ipairs(sortedKeys(preset.bars[page] or {})) do
            local slot, entry = setup.SlotToAction(page, index), preset.bars[page][index]
            operations[#operations + 1] = function(done) done(setup.WriteSlot(slot, entry, preset)) end
        end
    end
    return operations
end

-- Defaults, then the chosen whole-screen layout, then the class preset's own positions.
function setup.LayoutPositions(preset, layoutName)
    local positions = copy(setup.DefaultPositions)
    local chosen = layoutName and core.Layout and core.Layout.PresetPositions and core.Layout.PresetPositions(layoutName)
    for key, value in pairs(chosen or {}) do positions[key] = value end
    for key, value in pairs(preset.positions or {}) do positions[key] = copy(value) end
    return positions
end

local function writeLayout(positions, profile)
    local stats = counts()
    for name, position in pairs(positions) do
        local category = profile.positions[name] and "edited" or "placed"
        profile.positions[name] = copy(position)
        stats[category] = stats[category] + 1
    end
    if core.Layout then core.Layout.Apply()
    elseif core.Bars then core.Bars.ApplyLayout() end
    return stats
end

local function operationsFor(name, context)
    local preset, opts = context.preset, context.opts
    if name == "macros" then return macroOperations(context) end
    if name == "bars" then return barOperations(preset) end
    if name == "binds" then
        return { function(done)
            core.Bindings.Apply({ strafe = opts.strafe, mouse45 = opts.mouse45, quiet = true,
                onComplete = function(snapshot, reason, count)
                    if not snapshot then done(nil, reason); return end
                    done({ placed = count, skipped = 0, edited = 0 })
                end })
        end }
    end
    if name == "cvars" then
        return { function(done)
            local selection = {}
            for cvar in pairs(context.snapshot.cvars) do selection[cvar] = true end
            local _, stats = core.CVars.Apply(selection, { quiet = true })
            reportUnknownSettings(context, stats)
            done(stats, stats.error)
        end }
    end
    return { function(done) done(writeLayout(context.layout, context.profile)) end }
end

-- The wizard waits on this: Apply runs through the combat queue and ends some time after it returns.
local function notify(context)
    local callback = context.onComplete
    if type(callback) ~= "function" then return end
    local ok, reason = pcall(callback, context.result)
    if not ok then core:Print("Setup completion: " .. tostring(reason)) end
end

local function fail(context, name, reason)
    if context.result.status == "failed" then return end
    context.result.status, context.result.error = "failed", tostring(reason)
    summarize(name, context.result.steps[name], "; failed: " .. tostring(reason))
    active = nil
    notify(context)
end

local function queueOperation(context, name, operation, done)
    if InCombatLockdown() then
        context.result.status = "queued"
        if not context.queueReported then
            core:Print("Setup queued until combat ends.")
            context.queueReported = true
        end
    end
    core.Combat.Queue(function()
        if context.result.status == "failed" then return end
        context.result.status = "running"
        local ok, reason = pcall(operation, done)
        if not ok then fail(context, name, reason) end
    end)
end

local runStep
local function runOperations(context, name, operations, index, nextStep)
    local operation = operations[index]
    if not operation then
        summarize(name, context.result.steps[name])
        if name == "bars" then reportMissing() end
        runStep(context, nextStep)
        return
    end
    queueOperation(context, name, operation, function(delta, reason)
        local stats = context.result.steps[name]
        if delta then
            for _, field in ipairs({ "placed", "skipped", "edited" }) do stats[field] = stats[field] + delta[field] end
        end
        if reason or not delta then fail(context, name, reason or "write failed"); return end
        runOperations(context, name, operations, index + 1, nextStep)
    end)
end

runStep = function(context, index)
    local name = STEP_ORDER[index]
    if not name then
        -- A class without a preset gets binds, settings and layout; nothing is recorded as applied,
        -- so level-up placement has no preset to look for.
        if not context.preset.empty then
            context.charDB.applied = { class = context.preset.class, role = context.preset.role,
                at = time(), presetVersion = context.preset.version or 1 }
        end
        context.result.status, active = "applied", nil
        core:Print("Setup complete; type /rik undo to revert.")
        notify(context)
        return
    end
    context.result.steps[name] = counts()
    if context.opts[name] == false then
        context.result.steps[name].skipped = 1
        summarize(name, context.result.steps[name], "; disabled")
        runStep(context, index + 1)
        return
    end
    runOperations(context, name, operationsFor(name, context), 1, index + 1)
end

local function reject(reason)
    core:Print("Setup: " .. reason)
    return nil, reason
end

function setup.ValidateOptions(opts)
    if type(opts) ~= "table" then return "options must be a table" end
    for _, name in ipairs({ "macros", "bars", "binds", "cvars", "layout", "strafe", "mouse45", "allowEmpty" }) do
        if opts[name] ~= nil and type(opts[name]) ~= "boolean" then return name .. " must be a boolean" end
    end
    if opts.cvarSelection ~= nil and type(opts.cvarSelection) ~= "table" then return "cvarSelection must be a table" end
    if opts.onComplete ~= nil and type(opts.onComplete) ~= "function" then return "onComplete must be a function" end
    if opts.layoutPreset ~= nil then
        local presets = core.Layout and core.Layout.PresetPositions
        if not presets or not presets(opts.layoutPreset) then return "layoutPreset must name a layout" end
    end
end

function setup.Apply(class, role, opts)
    if active or setup.IsUndoing() then return reject("another Setup operation is pending") end
    if not core.CharDB or not core.Profile then return reject("Still loading") end
    if opts == nil then opts = {} end
    local reason = setup.ValidateOptions(opts)
    if reason then return reject(reason) end
    local preset
    preset, reason = setup.Resolve(class, role)
    if not preset and opts.allowEmpty and not core.Presets[class] then preset = setup.EmptyPreset(class) end
    if not preset then return reject(reason) end
    local result = { status = "running", steps = {}, class = class, role = preset.role }
    local context = { preset = preset, opts = copy(opts), result = result, onComplete = opts.onComplete,
        charDB = core.CharDB, profile = core.Profile, profileName = core.CharDB.profile }
    active = context
    setup.Missing = {}
    context.result.steps.snapshot = counts()
    queueOperation(context, "snapshot", function()
        if context.opts.layout ~= false then
            context.layout = setup.LayoutPositions(context.preset, context.opts.layoutPreset)
        end
        local snapshot, failure = setup.CaptureSnapshot(context.preset, context.opts,
            context.profile, context.charDB, context.profileName, context.layout)
        if not snapshot then fail(context, "snapshot", failure); return end
        context.snapshot, context.charDB.undo = snapshot, snapshot
        runStep(context, 1)
    end)
    return result
end

core:RegisterCommand("apply", function(args)
    if args:find("%s") then core:Print("Usage: /rik apply [role]"); return end
    local _, class = UnitClass("player")
    setup.Apply(class, args ~= "" and args:lower() or nil)
end, "Apply the class preset: /rik apply [role]")
