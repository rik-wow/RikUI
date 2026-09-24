-- Keep applied spell slots current without replacing the player's other actions.
local core, setup = RikUI, RikUI.Setup
local pending, reportedMarker
local reported = {}

local function appliedState()
    local marker = core.CharDB and core.CharDB.applied
    local _, class = UnitClass("player")
    if type(marker) == "table" and marker.class == class and type(marker.role) == "string" then
        return marker
    end
end

local function busy()
    local snapshot = core.CharDB and core.CharDB.undo
    local progress = type(snapshot) == "table" and snapshot.progress
    -- A failed/reloaded Undo retains completed entries that must stay restored.
    local undoStarted = type(progress) == "table" and next(progress) ~= nil
    return setup.IsApplying() or setup.IsUndoing() or undoStarted
end

local function rankOf(name, id)
    local entry = core.Spells.Entry(name)
    for rank, spellID in ipairs(entry and entry.ranks or {}) do
        if spellID == id then return rank end
    end
end

local function spellName(id)
    for name in pairs(core.Spells.Catalog()) do
        if rankOf(name, id) then return name end
    end
end

local function reportSkip(context, job, reason)
    local message = job.name .. " skipped at slot " .. job.slot .. ": " .. reason
    if context.manual or reported[job.slot] ~= message then core:Print(message) end
    reported[job.slot] = message
    context.result.skipped = context.result.skipped + 1
end

local function reportOccupied(context, job, kind)
    reportSkip(context, job, "occupied by a different " .. tostring(kind) .. " action")
end

local function placeAction(context, job, kind, id)
    if GetCursorInfo() ~= nil then reportSkip(context, job, "cursor is holding an action; retry /rik resync"); return end
    local stats, failure = setup.RestoreSlot(job.slot, { kind = kind, id = id })
    if not stats then reportSkip(context, job, failure); return end
    reported[job.slot] = nil
    context.result.placed = context.result.placed + stats.placed
    context.result.edited = context.result.edited + stats.edited
end

local function placeSpell(context, job)
    local id, reason, rank = core.Spells.HighestKnownRank(job.name)
    if reason then reportSkip(context, job, reason); return end
    if not id then return end -- Never clear a slot for an unknown or unlearned spell.
    local kind, currentID = GetActionInfo(job.slot)
    if kind == "spell" and currentID == id then reported[job.slot] = nil; return end
    if kind then
        local currentRank = kind == "spell" and rankOf(job.name, currentID)
        if not currentRank then reportOccupied(context, job, kind); return end
        if not rank or currentRank >= rank then return end
    end
    placeAction(context, job, "spell", id)
end

local function placeMacro(context, job)
    local usable, reason = setup.MacroKnown(job.macro)
    if reason then reportSkip(context, job, reason); return end
    if not usable then return end -- The slot waits until one of the macro's attacks is learned.
    local index
    index, reason = core.Macros.Find(job.name)
    if reason then reportSkip(context, job, reason); return end
    if not index then reportSkip(context, job, "macro is missing; run /rik apply"); return end
    -- Compared by name: a macro slot does not report the macro's index on 69913.
    if setup.SlotHolds(job.slot, "macro", index) then reported[job.slot] = nil; return end
    local kind = GetActionInfo(job.slot)
    if kind then reportOccupied(context, job, kind); return end
    placeAction(context, job, "macro", index)
end

local function jobFor(preset, entry, slot)
    if entry.spell then return { name = entry.spell, spells = { entry.spell }, slot = slot } end
    local macro = entry.macro and preset.macros[entry.macro]
    -- Macros without a spells list are placed by Apply alone.
    if type(macro) ~= "table" or type(macro.spells) ~= "table" or #macro.spells == 0 then return end
    return { name = entry.macro, spells = macro.spells, slot = slot, macro = macro }
end

local function jobsFor(preset)
    local jobs = {}
    for _, page in ipairs(setup.PageOrder) do
        for _, index in ipairs(setup.StateKeys(preset.bars[page])) do
            local job = jobFor(preset, preset.bars[page][index], setup.SlotToAction(page, index))
            if job then jobs[#jobs + 1] = job end
        end
    end
    return jobs
end

local function wanted(context, job)
    if context.all then return true end
    for _, name in ipairs(job.spells) do
        if context.names[name] then return true end
    end
    return false
end

local function finish(context, status, reason)
    if pending == context then pending = nil end
    context.result.status, context.result.error = status, reason
    if reason then
        core:Print("Resync " .. status .. ": " .. reason)
    elseif context.manual and status == "complete" then
        core:Print(string.format("Resync complete: placed=%d, skipped=%d, edited=%d",
            context.result.placed, context.result.skipped, context.result.edited))
    end
end

local function stillCurrent(context)
    local marker = appliedState()
    return marker == context.marker and marker.class == context.class and marker.role == context.role
        and not busy() and (context.manual or core.CharDB.autoPlacement ~= false)
end

local run
local function enqueue(context)
    context.result.status = "queued"
    if InCombatLockdown() and not context.queueReported then
        core:Print("Resync queued until combat ends.")
        context.queueReported = true
    end
    core.Combat.Queue(function()
        local ok, reason = pcall(run, context)
        if not ok then finish(context, "failed", tostring(reason)) end
    end)
end

run = function(context)
    if not stillCurrent(context) then
        finish(context, "cancelled", context.manual and "applied preset changed or another Setup operation is pending" or nil)
        return
    end
    if InCombatLockdown() then enqueue(context); return end
    if not context.jobs then
        local preset, reason = setup.Resolve(context.class, context.role)
        if not preset then finish(context, "failed", reason); return end
        context.jobs, context.index = jobsFor(preset), 1
    end
    context.result.status = "running"
    while context.jobs[context.index] do
        if InCombatLockdown() then enqueue(context); return end
        if not stillCurrent(context) then finish(context, "cancelled"); return end
        local job = context.jobs[context.index]
        context.index = context.index + 1
        -- A synchronous spell event during placement may reset index to 1.
        if wanted(context, job) then
            if job.macro then placeMacro(context, job) else placeSpell(context, job) end
        end
    end
    finish(context, "complete")
end

local function request(name, manual)
    if not manual and core.CharDB and core.CharDB.autoPlacement == false then return end
    local marker = appliedState()
    local reason = not marker and "no applied preset for this class" or busy() and "another Setup operation is pending"
    if reason then
        if manual then core:Print("Resync: " .. reason) end
        return nil, reason
    end
    if marker ~= reportedMarker then reported, reportedMarker = {}, marker end
    if pending and pending.marker == marker then
        pending.all, pending.manual = pending.all or not name, pending.manual or manual
        if name then pending.names[name] = true end
        -- Revisit earlier slots if a new spell was learned during a combat pause.
        pending.index = 1
        return pending.result
    end
    local context = { marker = marker, class = marker.class, role = marker.role,
        all = not name, names = {}, manual = manual,
        result = { status = "queued", placed = 0, edited = 0, skipped = 0 } }
    if name then context.names[name] = true end
    pending = context
    enqueue(context)
    return context.result
end

function setup.Resync() return request(nil, true) end

core:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE", function(_, id)
    -- Unknown/missing payloads use the same full scan as the fallback.
    request(spellName(id), false)
end)
core:RegisterEvent("SPELLS_CHANGED", function() request(nil, false) end)
core:RegisterCommand("resync", function(args)
    if args ~= "" then core:Print("Usage: /rik resync"); return end
    setup.Resync()
end, "Fill empty preset spell and macro slots and upgrade older ranks: /rik resync")
