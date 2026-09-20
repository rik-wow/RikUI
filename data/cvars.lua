-- Labelled setup settings. See docs/core.md for selection and snapshot contracts.
local core = RikUI
local cvars = {}
core.CVars = cvars

cvars.List = {
    { name = "cameraDistanceMaxZoomFactor", value = 2.6, label = "Maximum camera zoom" },
    { name = "cameraSmoothStyle", value = 0, label = "Disable camera following" },
    { name = "nameplateShowEnemies", value = 1, label = "Show enemy nameplates" },
    { name = "nameplateShowFriendlyPlayers", value = 0, label = "Hide friendly player nameplates" },
    { name = "nameplateShowFriendlyNpcs", value = 0, label = "Hide friendly NPC nameplates" },
    -- NamePlateStackType: enemy bit 1, friendly bit 2. The CVar is an encoded bitfield.
    { name = "nameplateStackingTypes", value = 1, bits = { 1, 2 }, label = "Stack nameplates" },
    { name = "autoLootDefault", value = 1, label = "Enable auto loot" },
    { name = "SpellQueueWindow", value = 400, label = "Spell queue window (400 ms)" },
    { name = "floatingCombatTextCombatDamage_v2", value = 1, label = "Show floating damage" },
    { name = "floatingCombatTextCombatHealing_v2", value = 1, label = "Show floating healing" },
    { name = "showTimestamps", value = "%H:%M ", label = "Show chat timestamps (24-hour)" },
    { name = "chatBubbles", value = 1, label = "Show chat bubbles" },
    { name = "chatBubblesParty", value = 0, label = "Hide party chat bubbles" },
    { name = "screenshotQuality", value = 10, label = "Maximum screenshot quality" },
    -- Off by default on 69913; Blizzard hides the whole meter while it is off.
    { name = "damageMeterEnabled", value = 1, label = "Enable the built-in damage meter" },
}

local function skip(name, reason, opts)
    if not (opts and opts.quiet) then core:Print("Skipped " .. name .. ": " .. reason) end
end

local function readCurrent(name)
    if not C_CVar or type(C_CVar.GetCVarInfo) ~= "function" then
        return nil, "CVar lookup unavailable"
    end
    local ok, value = pcall(C_CVar.GetCVarInfo, name)
    if not ok then return nil, "CVar lookup failed" end
    if value == nil then return nil, "unknown CVar" end
    return value
end

local function capture(selection, opts)
    local prior, stats = {}, { placed = 0, skipped = 0, edited = 0 }
    for _, entry in ipairs(cvars.List) do
        if selection == nil or selection[entry.name] == true then
            local value, reason = readCurrent(entry.name)
            prior[entry.name] = value
            if value == nil then
                skip(entry.name, reason, opts)
                stats.skipped = stats.skipped + 1
                if reason ~= "unknown CVar" then stats.error = entry.name .. ": " .. reason end
            end
        end
    end
    return prior, stats
end

local function writeValue(name, value, index)
    local setter = C_CVar and C_CVar[index and "SetCVarBitfield" or "SetCVar"]
    if type(setter) ~= "function" then return nil, "CVar setter unavailable" end
    local ok, accepted
    if index then ok, accepted = pcall(setter, name, index, value == 1)
    else ok, accepted = pcall(setter, name, tostring(value)) end
    if not ok then return nil, "CVar write failed" end
    if accepted ~= true then return nil, "CVar write rejected" end
    return true
end

local function applyEntry(entry, opts)
    if entry.bits then
        for _, index in ipairs(entry.bits) do
            local ok, reason = writeValue(entry.name, entry.value, index)
            if not ok then return nil, reason .. " at bit " .. index end
        end
    else
        local ok, reason = writeValue(entry.name, entry.value)
        if not ok then return nil, reason end
    end
    if not (opts and opts.quiet) then core:Print("Applied " .. entry.name .. " = " .. tostring(entry.value)) end
    return true
end

function cvars.Snapshot(selection, opts)
    return capture(selection, opts)
end

function cvars.Restore(name, value)
    if InCombatLockdown() then return nil, "CVar restore requires leaving combat" end
    if type(value) ~= "string" then return nil, "invalid CVar snapshot for " .. tostring(name) end
    local ok, reason = applyEntry({ name = name, value = value }, { quiet = true })
    if not ok then return nil, name .. ": " .. reason end
    local actual = readCurrent(name)
    if actual ~= value then return nil, name .. ": CVar restore readback failed" end
    return true
end

function cvars.Apply(selection, opts)
    assert(selection == nil or type(selection) == "table", "CVars.Apply needs a selection table or nil")
    -- Finish the snapshot before SetCVar can trigger changes to other settings.
    local prior, stats = capture(selection, opts)
    for _, entry in ipairs(cvars.List) do
        if prior[entry.name] ~= nil then
            local ok, reason = applyEntry(entry, opts)
            if ok then
                stats.placed = stats.placed + 1
            else
                stats.skipped = stats.skipped + 1
                stats.error = entry.name .. ": " .. reason
                skip(entry.name, reason, opts)
            end
        end
    end
    return prior, stats
end

core:RegisterCommand("cvars", function() cvars.Apply() end, "Apply the recommended game settings")
