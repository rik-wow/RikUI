-- Flat skin over Blizzard's nameplates. The client keeps drawing and driving the plates: health,
-- colour and target state are computed in Blizzard's secure code and this file only writes
-- textures, fonts and alpha. UpdateAnchors puts the stock atlases back on every layout pass, so
-- the skin is reapplied from a post-hook. Own debuffs come from a Blizzard aura container per
-- unit frame; forbidden plates are never touched.
local core, media, unitframes, auras = RikUI, RikUI.Media, RikUI.UnitFrames, RikUI.Auras
local nameplates = { Active = {}, Containers = setmetatable({}, { __mode = "k" }) }
core.Nameplates = nameplates

local FLAT, EDGE = "Interface\\BUTTONS\\WHITE8X8", 1
local BACKING, HIGHLIGHT = { 0.06, 0.07, 0.09, 0.9 }, { 1, 1, 1, 1 }
local LEVEL_ART, LEVEL_BORDER = { "playerLevelDiffIcon", "selectedBorder" }, { 0.25, 0.28, 0.32, 1 }
local AURA_SIZE, AURA_MAX, AURA_LINE, AURA_GAP = 18, 6, 140, 2
local AURA_GROUP, AURA_FILTER = "owndebuffs", "HARMFUL|PLAYER"
local FLOW = { anchor = "BOTTOMLEFT", horizontal = "Right", vertical = "Up", lineSize = AURA_LINE }
local skinned, skinnedCount, containerCount, containerUnavailable = setmetatable({}, { __mode = "k" }), 0, 0, false

local function isRegion(value)
    local kind = type(value)
    return (kind == "table" or kind == "userdata") and type(value.SetAlpha) == "function"
end

-- Plates carry their own scale, so a fixed thickness of 1 draws two screen pixels or more.
local function pixel(frame)
    if type(PixelUtil) ~= "table" or type(PixelUtil.GetNearestPixelSize) ~= "function" then return EDGE end
    local ok, size = pcall(PixelUtil.GetNearestPixelSize, 1, frame:GetEffectiveScale(), 1)
    if ok and type(size) == "number" and size > 0 then return size end
    return EDGE
end

-- unitframes.Edges order: top, bottom, left, right.
local function resize(lines, size)
    if type(lines) ~= "table" then return end
    for index, line in ipairs(lines) do
        if index <= 2 then line:SetHeight(size) else line:SetWidth(size) end
    end
end

local function font(region, role)
    if isRegion(region) then region:SetFont(media.font, media.sizes[role], "OUTLINE") end
end

-- Everything Blizzard's layout pass resets.
local function applySkin(frame)
    local bar = frame.HealthBarsContainer.healthBar
    local size = pixel(bar)
    bar.barTexture:SetTexture(media.statusbar)
    local backing = bar.bgTexture
    backing:SetTexture(FLAT)
    backing:SetVertexColor(unpack(BACKING))
    backing:ClearAllPoints()
    backing:SetPoint("TOPLEFT", bar, "TOPLEFT", -size, size)
    backing:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", size, -size)
    resize(bar.rikHighlight, size)
    font(frame.name, "small")
    local level = frame.PlayerLevelDiffFrame
    if isRegion(level) then
        font(level.playerLevelDiffText, "small")
        resize(level.rikBorder, size)
    end
end

-- The level badge loses its gold frame and selection glow; the number keeps Blizzard's
-- difficulty colour and the skull for high-level units stays.
local function skinLevel(level)
    if not isRegion(level) then return end
    for _, key in ipairs(LEVEL_ART) do
        if isRegion(level[key]) then level[key]:SetAlpha(0) end
    end
    local backing = level:CreateTexture(nil, "BACKGROUND")
    backing:SetAllPoints(level)
    backing:SetTexture(FLAT)
    backing:SetVertexColor(unpack(BACKING))
    level.rikBorder = unitframes.Edges(level, EDGE, "BORDER")
    for _, line in ipairs(level.rikBorder) do line:SetVertexColor(unpack(LEVEL_BORDER)) end
end

-- Blizzard decides target and focus and shows its selection art; the flat border copies that state.
local function followSelection(bar)
    local border = bar.selectedBorder
    border:SetAlpha(0)
    bar.rikHighlight = unitframes.Edges(bar, EDGE, "OVERLAY")
    local function sync()
        local shown = border:IsShown() == true
        for _, line in ipairs(bar.rikHighlight) do line:SetShown(shown) end
    end
    for _, line in ipairs(bar.rikHighlight) do line:SetVertexColor(unpack(HIGHLIGHT)) end
    hooksecurefunc(border, "SetShown", sync)
    hooksecurefunc(border, "Hide", sync)
    sync()
end

local function skin(frame)
    if skinned[frame] then applySkin(frame) return end
    skinned[frame], skinnedCount = true, skinnedCount + 1
    followSelection(frame.HealthBarsContainer.healthBar)
    skinLevel(frame.PlayerLevelDiffFrame)
    applySkin(frame)
    hooksecurefunc(frame, "UpdateAnchors", applySkin)
end

local function addGroup(container)
    local spec = { size = AURA_SIZE, harmful = true }
    container:AddAuraGroup(AURA_GROUP, AURA_FILTER, auras.GroupOptions(spec, AURA_MAX))
end

-- Blizzard's debuff list fades only where ours exists, so a refused container costs nothing.
local function createContainer(frame, unit)
    containerCount = containerCount + 1
    local container = auras.CreateContainer("Nameplate" .. containerCount, frame, unit, FLOW)
    if not container or not auras.Populate(container, addGroup) then
        containerUnavailable = true
        return nil
    end
    -- Above the name: anything under the plate covers the creature.
    local anchor = isRegion(frame.name) and frame.name or frame.HealthBarsContainer
    container:SetPoint("BOTTOM", anchor, "TOP", 0, AURA_GAP)
    nameplates.Containers[frame] = container
    local stock = isRegion(frame.AurasFrame) and frame.AurasFrame.DebuffListFrame
    if isRegion(stock) then stock:SetAlpha(0) end
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
    skin(frame)
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

function nameplates:OnEnable()
    if type(C_NamePlate) ~= "table" or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then
        core:Print("Nameplates: C_NamePlate unavailable on this client")
        return
    end
    core:RegisterEvent("NAME_PLATE_UNIT_ADDED", nameplates.Added)
    core:RegisterEvent("NAME_PLATE_UNIT_REMOVED", nameplates.Removed)
    core:RegisterEvent("PLAYER_REGEN_ENABLED", nameplates.LeftCombat)
end

function nameplates:Debug()
    core:Print("Nameplates skinned=" .. skinnedCount .. " active=" .. auras.Count(nameplates.Active)
        .. " containers=" .. auras.Count(nameplates.Containers))
end

core:RegisterModule("nameplates", nameplates)
