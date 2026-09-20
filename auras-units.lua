-- Target, pet and focus aura containers under the RikUI unit frames, built on the shared factory in
-- auras.lua. Filter strings split the player's own auras (full size) from other casters'
-- (small and dim); the containers read and redraw in secure code, this file only asks them
-- to refresh when the unit behind a token changes.
local core, auras, unitframes = RikUI, RikUI.Auras, RikUI.UnitFrames
local unitauras = { Containers = {} }
core.UnitAuras = unitauras

local LARGE, MEDIUM, SMALL, GAP, FOCUS_GAP = 30, 26, 22, 4, 30
-- Rows fill left-to-right and upward from the frame's top left corner.
local FLOW = { anchor = "BOTTOMLEFT", horizontal = "Right", vertical = "Up" }
local GROUPS = {
    owndebuffs = { filter = "HARMFUL|PLAYER", large = true, harmful = true },
    debuffs = { filter = "HARMFUL|!PLAYER", harmful = true, dim = true },
    ownbuffs = { filter = "HELPFUL|PLAYER", newLine = true },
    buffs = { filter = "HELPFUL|!PLAYER", dim = true },
}
-- width: the unit frame's width, so each line fills the frame; large: the own-debuff size.
local UNITS = {
    { key = "target", frame = "target", unit = "target", width = 220, large = LARGE,
        groups = { { "owndebuffs", 12 }, { "debuffs", 12 }, { "ownbuffs", 16 }, { "buffs", 16 } } },
    { key = "pet", frame = "petframe", unit = "pet", width = 110, large = SMALL,
        groups = { { "owndebuffs", 8 }, { "debuffs", 8 } } },
    -- The focus cast bar sits in the 4 + 22 pixels above the focus frame, so this row starts above it.
    { key = "focus", frame = "focus", unit = "focus", width = 160, large = MEDIUM, gap = FOCUS_GAP,
        groups = { { "owndebuffs", 8 }, { "debuffs", 8 }, { "buffs", 8 } } },
}
local warnings = {}

function unitauras.Warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Unit auras " .. operation .. ": " .. tostring(reason))
end

local function addGroups(container, unit)
    for _, entry in ipairs(unit.groups) do
        local key, maxFrames = entry[1], entry[2]
        local group = GROUPS[key]
        local spec = { size = group.large and unit.large or SMALL, harmful = group.harmful, dim = group.dim }
        container:AddAuraGroup(key, group.filter, auras.GroupOptions(spec, maxFrames, group.newLine))
    end
end

-- Containers are children of the secure unit button: they hide with its visibility driver,
-- inherit its layout scale and are sized by the secure flow layout.
local function createContainer(unit, frame)
    local flow = { anchor = FLOW.anchor, horizontal = FLOW.horizontal, vertical = FLOW.vertical, lineSize = unit.width }
    local container = auras.CreateContainer(unit.key, frame, unit.unit, flow)
    if not container or not auras.Populate(container, addGroups, unit) then return nil end
    container:SetPoint(FLOW.anchor, frame, "TOPLEFT", 0, unit.gap or GAP)
    unitauras.Containers[unit.key] = container
    return container
end

local function createContainers()
    for _, unit in ipairs(UNITS) do
        local frame = unitframes.Frames[unit.frame]
        if frame and not unitauras.Containers[unit.key] then createContainer(unit, frame) end
    end
    if next(unitauras.Containers) == nil and next(unitframes.Frames) == nil then
        unitauras.Warn("attach", "no unit frames to attach to")
    end
end

-- UNIT_AURA for a token reaches the container itself; a token that now names a different
-- unit needs an explicit full refresh, as Blizzard's target frame does.
local function refresh(key)
    local container = unitauras.Containers[key]
    if not container then return end
    local ok, reason = pcall(container.UpdateAllAuras, container)
    if not ok then unitauras.Warn("refresh", reason) end
end

local function registerEvents()
    core:RegisterEvent("PLAYER_TARGET_CHANGED", function() refresh("target") end)
    core:RegisterEvent("PLAYER_FOCUS_CHANGED", function() refresh("focus") end)
    core:RegisterEvent("UNIT_PET", function(_, unit)
        if core.Secret.IsSecret(unit) or unit == "player" then refresh("pet") end
    end)
end

function unitauras:OnEnable()
    core.Combat.Queue(createContainers)
    registerEvents()
end

function unitauras:Debug(sample)
    core:Print("Unit auras containers=" .. auras.Count(unitauras.Containers))
    sample("GetAuraDataByIndex(target,1,HARMFUL)", auras.Api("C_UnitAuras", "GetAuraDataByIndex"), "target", 1, "HARMFUL")
end

core:RegisterModule("unitauras", unitauras)
