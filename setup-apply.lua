-- Ordered setup orchestration. The returned result also tracks deferred work.
local core, setup = RikUI, RikUI.Setup
local STEP_ORDER = { "macros", "bars", "binds", "cvars", "layout" }
local active

setup.DefaultPositions = {
    main = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 40 },
    bar2 = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 82 },
    bar3 = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 124 },
    bar4 = { point = "RIGHT", relativePoint = "RIGHT", x = -40, y = 0 },
    bar5 = { point = "RIGHT", relativePoint = "RIGHT", x = -82, y = 0 },
}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = copy(entry) end
    return result
end

local function sortedKeys(values)
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function counts()
    return { placed = 0, skipped = 0, edited = 0 }
end

local function summarize(name, stats, suffix)
    core:Print(string.format("Setup %s: placed=%d, skipped=%d, edited=%d%s",
        name, stats.placed, stats.skipped, stats.edited, suffix or ""))
end

local function macroOperations(preset)
    local operations = {}
    for _, name in ipairs(sortedKeys(preset.macros)) do
        local macro = preset.macros[name]
        operations[#operations + 1] = function(done)
            core.Macros.Ensure(name, macro.icon, macro.body, macro.scope, {
                quiet = true,
                onComplete = function(index, reason, disposition)
                    if not index then done(nil, name .. ": " .. tostring(reason)); return end
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
            operations[#operations + 1] = function(done) done(setup.WriteSlot(slot, entry)) end
        end
    end
    return operations
end

local function writeLayout(preset, profile)
    local stats = counts()
    for name, position in pairs(preset.positions or setup.DefaultPositions) do
        local category = profile.positions[name] and "edited" or "placed"
        profile.positions[name] = copy(position)
        stats[category] = stats[category] + 1
    end
    return stats
end

local function operationsFor(name, context)
    local preset, opts = context.preset, context.opts
    if name == "macros" then return macroOperations(preset) end
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
            local _, stats = core.CVars.Apply(opts.cvarSelection, { quiet = true })
            done(stats, stats.error)
        end }
    end
    return { function(done) done(writeLayout(preset, context.profile)) end }
end

local function fail(context, name, reason)
    if context.result.status == "failed" then return end
    context.result.status, context.result.error = "failed", tostring(reason)
    summarize(name, context.result.steps[name], "; failed: " .. tostring(reason))
    active = nil
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
        context.charDB.applied = { class = context.preset.class, role = context.preset.role,
            at = time(), presetVersion = context.preset.version or 1 }
        context.result.status, active = "applied", nil
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

local function validateOptions(opts)
    if type(opts) ~= "table" then return "options must be a table" end
    for _, name in ipairs({ "macros", "bars", "binds", "cvars", "layout", "strafe", "mouse45" }) do
        if opts[name] ~= nil and type(opts[name]) ~= "boolean" then return name .. " must be a boolean" end
    end
    if opts.cvarSelection ~= nil and type(opts.cvarSelection) ~= "table" then return "cvarSelection must be a table" end
end

function setup.Apply(class, role, opts)
    if active then return reject("an Apply is already pending") end
    if not core.CharDB or not core.Profile then return reject("Still loading") end
    if opts == nil then opts = {} end
    local reason = validateOptions(opts)
    if reason then return reject(reason) end
    local preset
    preset, reason = setup.Resolve(class, role)
    if not preset then return reject(reason) end
    local result = { status = "running", steps = {}, class = class, role = preset.role }
    local context = { preset = preset, opts = copy(opts), result = result,
        charDB = core.CharDB, profile = core.Profile }
    active = context
    local ok
    ok, reason = pcall(runStep, context, 1)
    if not ok then
        local name = STEP_ORDER[1]
        for _, step in ipairs(STEP_ORDER) do if result.steps[step] then name = step end end
        fail(context, name, reason)
    end
    return result
end

core:RegisterCommand("apply", function(args)
    if args:find("%s") then core:Print("Usage: /rik apply [role]"); return end
    local _, class = UnitClass("player")
    setup.Apply(class, args ~= "" and args:lower() or nil)
end, "Apply the class preset: /rik apply [role]")
