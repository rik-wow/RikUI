-- Target and pet aura rows attached above their RikUI unit frames. The rows come from the
-- shared factory in auras.lua and refresh through auras-status.lua; this file owns the row
-- specs, the anchoring and the unit events. Auras another caster applied shrink and dim.
local core, auras, unitframes = RikUI, RikUI.Auras, RikUI.UnitFrames
local unitauras = { Rows = {}, blocked = false }
core.UnitAuras = unitauras

local LARGE, SMALL, GAP, ORIGIN = 30, 22, 4, "BOTTOMLEFT"
-- Debuffs sit directly above the frame and buffs above the debuffs. The target frame is 220
-- wide and the pet frame 110, so each per-line count fills its frame's width.
local ROWS = {
    { key = "targetdebuffs", frame = "target", unit = "target", filter = "HARMFUL", slots = 12, size = LARGE,
        perLine = 6 },
    { key = "targetbuffs", frame = "target", unit = "target", filter = "HELPFUL", slots = 16, size = SMALL,
        perLine = 8, above = "targetdebuffs" },
    { key = "petdebuffs", frame = "petframe", unit = "pet", filter = "HARMFUL", slots = 8, size = SMALL,
        perLine = 4 },
}
for _, spec in ipairs(ROWS) do spec.origin, spec.emphasis = ORIGIN, true end
local warnings = {}

function unitauras.Warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Unit auras " .. operation .. ": " .. tostring(reason))
end

-- Rows are plain children of the secure unit button: they hide with its visibility driver,
-- inherit its layout scale and stay writable in combat.
local function createRow(spec, frame)
    local row = auras.CreateRow(spec, frame, unitauras)
    local below = spec.above and unitauras.Rows[spec.above] or frame
    row:SetPoint(ORIGIN, below, "TOPLEFT", 0, GAP)
    return row
end

local function createRows()
    for _, spec in ipairs(ROWS) do
        local frame = unitframes.Frames[spec.frame]
        if frame and not unitauras.Rows[spec.key] then auras.RefreshRow(createRow(spec, frame)) end
    end
    if next(unitauras.Rows) == nil then unitauras.Warn("attach", "no unit frames to attach to") end
end

local function eachRow(callback, unit)
    if core.Secret.IsSecret(unit) then unit = nil end
    for _, spec in ipairs(ROWS) do
        local row = unitauras.Rows[spec.key]
        if row and (not unit or unit == spec.unit) then callback(row) end
    end
end

function unitauras.Refresh(unit)
    eachRow(auras.RefreshRow, unit)
end

-- A blocked combat read keeps the last display, so a unit change clears first: the new
-- target or pet never wears the previous one's auras.
local function reset(unit)
    eachRow(auras.ClearRow, unit)
    unitauras.Refresh(unit)
end

local function onUnitAura(_, unit)
    if core.Secret.IsSecret(unit) or unit == "target" or unit == "pet" then unitauras.Refresh(unit) end
end

local function registerEvents()
    core:RegisterEvent("UNIT_AURA", onUnitAura)
    core:RegisterEvent("PLAYER_TARGET_CHANGED", function() reset("target") end)
    core:RegisterEvent("UNIT_PET", function(_, unit)
        if core.Secret.IsSecret(unit) or unit == "player" then reset("pet") end
    end)
    core:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if unitauras.blocked then unitauras.Refresh() end
    end)
    core:RegisterEvent("PLAYER_ENTERING_WORLD", function() unitauras.Refresh() end)
end

function unitauras:OnEnable()
    core.Combat.Queue(createRows)
    registerEvents()
end

local function rowCount()
    local total = 0
    for _ in pairs(unitauras.Rows) do total = total + 1 end
    return total
end

function unitauras:Debug(sample)
    core:Print("Unit auras blocked=" .. tostring(unitauras.blocked) .. " rows=" .. rowCount())
    sample("GetAuraDataByIndex(target,1,HARMFUL)", auras.Api("C_UnitAuras", "GetAuraDataByIndex"), "target", 1, "HARMFUL")
    local id = auras.FirstAuraInstance("target", "HARMFUL")
    if id ~= nil then
        sample("GetAuraDuration(target, first debuff)", auras.Api("C_UnitAuras", "GetAuraDuration"), "target", id)
    end
end

core:RegisterModule("unitauras", unitauras)
