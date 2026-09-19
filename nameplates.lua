-- Flat nameplates on top of Blizzard's. The client keeps creating, placing and driving the plates;
-- this file owns the events, the pooled per-frame parts and the own-debuff containers.
-- nameplates-skin.lua lays a plate out and feeds its bar, nameplates-target.lua draws the target
-- and threat indicators and sets the client's target scale and alpha. Unit values only travel
-- reader-to-sink through core.Secret; forbidden plates are never touched.
local core, media, auras = RikUI, RikUI.Media, RikUI.Auras
local weak = { __mode = "k" }
local nameplates = { Active = {}, Containers = setmetatable({}, weak), Parts = setmetatable({}, weak) }
core.Nameplates = nameplates

local FLAT, EDGE = "Interface\\BUTTONS\\WHITE8X8", 1
local AURA_SIZE, AURA_MAX, AURA_LINE, AURA_GAP = 18, 6, 140, 2
local AURA_GROUP, AURA_FILTER = "owndebuffs", "HARMFUL|PLAYER"
local FLOW = { anchor = "BOTTOMLEFT", horizontal = "Right", vertical = "Up", lineSize = AURA_LINE }
local OUTLINE = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
    { "TOPRIGHT", "BOTTOMRIGHT" } }
local UNIT_EVENTS = { UNIT_HEALTH = "Damaged", UNIT_MAXHEALTH = "Health", UNIT_FACTION = "Color",
    UNIT_NAME_UPDATE = "Color", UNIT_CLASSIFICATION_CHANGED = "Marker" }
local containerCount, containerUnavailable = 0, false
nameplates.Flat = FLAT

function nameplates.IsRegion(value)
    local kind = type(value)
    return (kind == "table" or kind == "userdata") and type(value.SetAlpha) == "function"
end
local isRegion = nameplates.IsRegion

-- Plates carry their own scale, so a fixed thickness of 1 draws two screen pixels or more.
function nameplates.Pixel(frame)
    if type(PixelUtil) ~= "table" or type(PixelUtil.GetNearestPixelSize) ~= "function" then return EDGE end
    local ok, size = pcall(PixelUtil.GetNearestPixelSize, 1, frame:GetEffectiveScale(), 1)
    if ok and type(size) == "number" and size > 0 then return size end
    return EDGE
end

-- A flat line or block. Plates move in fractions of a pixel, and snapped lines then change
-- thickness from side to side.
function nameplates.Block(owner, layer, color)
    local texture = owner:CreateTexture(nil, layer)
    texture:SetTexture(FLAT)
    texture:SetVertexColor(unpack(color))
    texture:SetSnapToPixelGrid(false)
    texture:SetTexelSnappingBias(0)
    return texture
end

-- Four lines along the inside of a region's edge: top, bottom, left, right.
function nameplates.Outline(owner, target, color)
    local lines = {}
    for index, points in ipairs(OUTLINE) do
        local line = nameplates.Block(owner, "OVERLAY", color)
        line:SetPoint(points[1], target, points[1], 0, 0)
        line:SetPoint(points[2], target, points[2], 0, 0)
        lines[index] = line
    end
    return lines
end

function nameplates.Resize(lines, size)
    if type(lines) ~= "table" then return end
    for index, line in ipairs(lines) do
        if index <= 2 then line:SetHeight(size) else line:SetWidth(size) end
    end
end

function nameplates.Font(region, role)
    if isRegion(region) then region:SetFont(media.font, media.sizes[role], "OUTLINE") end
end

local function addGroup(container)
    local spec = { size = AURA_SIZE, harmful = true }
    container:AddAuraGroup(AURA_GROUP, AURA_FILTER, auras.GroupOptions(spec, AURA_MAX))
end

-- NamePlateAurasMixin shows its debuff list with SetShown on every aura display update, so the
-- list is hidden again from a post-hook. Alpha alone left both rows on screen.
local function hideStockDebuffs(frame)
    local stock = isRegion(frame.AurasFrame) and frame.AurasFrame.DebuffListFrame
    if not isRegion(stock) then return end
    stock:SetAlpha(0)
    stock:Hide()
    hooksecurefunc(stock, "SetShown", function(self, shown) if shown then self:Hide() end end)
end

-- Blizzard's debuff list goes only where ours exists, so a refused container costs nothing.
local function createContainer(frame, unit)
    containerCount = containerCount + 1
    local container = auras.CreateContainer("Nameplate" .. containerCount, frame, unit, FLOW)
    if not container or not auras.Populate(container, addGroup) then
        containerUnavailable = true
        return nil
    end
    -- Above the name plaque: anything under the plate covers the creature.
    local parts = nameplates.Parts[frame]
    container:SetPoint("BOTTOM", parts and parts.plaque or frame.HealthBarsContainer, "TOP", 0, AURA_GAP)
    nameplates.Containers[frame] = container
    hideStockDebuffs(frame)
    return container
end

local function retarget(container, unit)
    container:SetUnit(unit)
    container:Show()
    container:UpdateAllAuras()
end

-- Unit frames are pooled, so a frame's container is kept and pointed at the new token.
local function attachAuras(frame, unit)
    local container = nameplates.Containers[frame]
    if container then
        local ok, reason = pcall(retarget, container, unit)
        if not ok then auras.Warn("nameplate", reason) end
        return
    end
    if containerUnavailable or InCombatLockdown() then return end
    createContainer(frame, unit)
end

local function unitFrameFor(unit)
    if core.Secret.IsSecret(unit) or type(unit) ~= "string" then return nil end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or plate:IsForbidden() then return nil end
    local frame = plate.UnitFrame
    if not isRegion(frame) or not isRegion(frame.HealthBarsContainer) then return nil end
    return isRegion(frame.HealthBarsContainer.healthBar) and frame or nil
end

function nameplates.Added(_, unit)
    local ok, frame = pcall(unitFrameFor, unit)
    if not ok then auras.Warn("nameplate", frame) return end
    if not frame then return end
    nameplates.Active[unit] = frame
    nameplates.Skin.Ensure(frame)
    nameplates.Skin.Apply(frame)
    nameplates.Skin.SetUnit(frame, unit)
    attachAuras(frame, unit)
end

function nameplates.Removed(_, unit)
    if core.Secret.IsSecret(unit) then return end
    local frame = nameplates.Active[unit]
    nameplates.Active[unit] = nil
    local container = frame and nameplates.Containers[frame]
    if container then container:Hide() end
end

-- Plates that appeared in combat get their container now.
function nameplates.LeftCombat()
    for unit, frame in pairs(nameplates.Active) do
        if not nameplates.Containers[frame] then attachAuras(frame, unit) end
    end
end

local function unitEvent(event, unit)
    if core.Secret.IsSecret(unit) or type(unit) ~= "string" then return end
    local frame = nameplates.Active[unit]
    if frame then nameplates.Skin[UNIT_EVENTS[event]](frame, unit) end
end

function nameplates:OnEnable()
    if type(C_NamePlate) ~= "table" or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then
        core:Print("Nameplates: C_NamePlate unavailable on this client")
        return
    end
    core:RegisterEvent("NAME_PLATE_UNIT_ADDED", nameplates.Added)
    core:RegisterEvent("NAME_PLATE_UNIT_REMOVED", nameplates.Removed)
    core:RegisterEvent("PLAYER_REGEN_ENABLED", nameplates.LeftCombat)
    for event in pairs(UNIT_EVENTS) do core:RegisterEvent(event, unitEvent) end
    nameplates.Target.ApplyCVars()
end

function nameplates:Debug()
    core:Print("Nameplates skinned=" .. auras.Count(nameplates.Parts) .. " active=" .. auras.Count(nameplates.Active)
        .. " containers=" .. auras.Count(nameplates.Containers))
end

core:RegisterModule("nameplates", nameplates)
