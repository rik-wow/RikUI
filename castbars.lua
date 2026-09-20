-- Player, target, focus and pet castbars. Cast values only reach sinks (castbars-status.lua); this
-- file owns frames, layout, events and the stock casting bar.
local core, media, layout, unitframes = RikUI, RikUI.Media, RikUI.Layout, RikUI.UnitFrames
local castbars = { Bars = {} }
core.CastBars = castbars

local HEIGHT, EDGE, TEXT_INSET, ICON_CROP = 22, 1, 4, 0.08
-- width is the matching unit frame's width.
local UNITS = {
    { key = "castplayer", unit = "player", width = 220, shield = false },
    { key = "casttarget", unit = "target", width = 220, shield = true },
    { key = "castfocus", unit = "focus", width = 160, shield = true },
    { key = "castpet", unit = "pet", width = 110, shield = false },
}
-- Directly under the player, target and pet frames, which sit at y=300. The focus bar goes above its
-- frame (y=340, 36 high): under it the pet frame is in the way. The focus aura row starts above it.
local DEFAULTS = {
    castplayer = { point = "BOTTOM", relativePoint = "BOTTOM", x = -140, y = 272 },
    casttarget = { point = "BOTTOM", relativePoint = "BOTTOM", x = 140, y = 272 },
    castfocus = { point = "BOTTOM", relativePoint = "BOTTOM", x = -340, y = 380 },
    castpet = { point = "BOTTOM", relativePoint = "BOTTOM", x = -313, y = 272 },
}
-- PetCastingBarFrame hangs off UIParent, so parking PetFrame leaves it; the focus spell bar is a
-- child of the parked FocusFrame.
local STOCK_FRAMES = { "PlayerCastingBarFrame", "CastingBarFrame", "PetCastingBarFrame" }
local BACKGROUND, BORDER, SHIELD = { 0.055, 0.065, 0.08, 0.95 }, { 0.25, 0.28, 0.32, 1 }, { 0.75, 0.8, 0.9, 0.9 }
local FRAME_PREFIX = "RikUICast_"
local stockPending = false

local function icon(frame)
    local texture = frame:CreateTexture(nil, "ARTWORK")
    texture:SetPoint("TOPLEFT", frame, "TOPLEFT", EDGE, -EDGE)
    texture:SetSize(HEIGHT - 2 * EDGE, HEIGHT - 2 * EDGE)
    texture:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    return texture
end

-- The shield is an overlay on the icon; its alpha is the only thing a secret flag drives.
local function shield(frame)
    local texture = frame:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints(frame.icon)
    texture:SetTexture(media.border)
    texture:SetVertexColor(unpack(SHIELD))
    texture:SetAlphaFromBoolean(false, 1, 0)
    return texture
end

local function text(parent, point, x)
    local region = parent:CreateFontString(nil, "OVERLAY")
    media.Font(region, "small")
    region:SetPoint(point, parent, point, x, 0)
    return region
end

local function statusBar(frame)
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetStatusBarTexture(media.statusbar)
    bar:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", EDGE, 0)
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -EDGE, EDGE)
    bar.background = bar:CreateTexture(nil, "BACKGROUND")
    bar.background:SetAllPoints()
    bar.background:SetColorTexture(0, 0, 0, 0.4)
    bar.text = text(bar, "LEFT", TEXT_INSET)
    bar.time = text(bar, "RIGHT", -TEXT_INSET)
    return bar
end

local function decorate(frame)
    frame.background = frame:CreateTexture(nil, "BACKGROUND")
    frame.background:SetAllPoints()
    frame.background:SetColorTexture(unpack(BACKGROUND))
    frame.border = unitframes.Edges(frame, EDGE, "BORDER")
    for _, line in ipairs(frame.border) do line:SetVertexColor(unpack(BORDER)) end
    frame.icon = icon(frame)
    frame.bar = statusBar(frame)
    frame.time = frame.bar.time
end

local function createBar(spec)
    local frame = CreateFrame("Frame", FRAME_PREFIX .. spec.unit, UIParent)
    frame.key, frame.unit = spec.key, spec.unit
    frame:SetSize(spec.width, HEIGHT)
    decorate(frame)
    if spec.shield then frame.shield = shield(frame) end
    frame:SetScript("OnUpdate", function(self) castbars.Tick(self) end)
    frame:Hide()
    layout.Register(frame, spec.key, DEFAULTS[spec.key])
    castbars.Bars[spec.key] = frame
    return frame
end

local function replacementsReady()
    for _, spec in ipairs(UNITS) do
        if not castbars.Bars[spec.key] then return false end
    end
    return true
end

local function hideStock()
    stockPending = false
    if not castbars.enabled or not replacementsReady() then return end
    for _, name in ipairs(STOCK_FRAMES) do
        local frame = _G[name]
        -- No native handler must keep running: the RikUI bars own these casts now.
        if frame then core.Hide.Frame(frame, false) end
    end
end

function castbars.UpdateStockVisibility()
    if stockPending then return end
    stockPending = true
    core.Combat.Queue(hideStock)
end

local function eachBar(callback, unit)
    for _, spec in ipairs(UNITS) do
        local frame = castbars.Bars[spec.key]
        if frame and (not unit or unit == spec.unit) then callback(frame) end
    end
end

function castbars.Refresh(unit)
    eachBar(castbars.Sync, unit)
end

-- A secret unit token cannot be matched, so every bar re-reads its own cast instead.
local function onCastEvent(handler)
    return function(_, unit, ...)
        if core.Secret.IsSecret(unit) then castbars.Refresh(); return end
        for _, spec in ipairs(UNITS) do
            local frame = castbars.Bars[spec.key]
            if frame and unit == spec.unit then handler(frame, ...) end
        end
    end
end

local HANDLERS = {
    UNIT_SPELLCAST_START = function(frame) castbars.Begin(frame, false) end,
    UNIT_SPELLCAST_CHANNEL_START = function(frame) castbars.Begin(frame, true) end,
    UNIT_SPELLCAST_STOP = function(frame, castID) castbars.Stop(frame, castID) end,
    UNIT_SPELLCAST_CHANNEL_STOP = function(frame, _, _, interruptedBy) castbars.StopChannel(frame, interruptedBy) end,
    UNIT_SPELLCAST_FAILED = function(frame, castID) castbars.Fail(frame, castID) end,
    UNIT_SPELLCAST_INTERRUPTED = function(frame, castID) castbars.Interrupt(frame, castID) end,
    UNIT_SPELLCAST_DELAYED = function(frame) castbars.Refill(frame) end,
    UNIT_SPELLCAST_CHANNEL_UPDATE = function(frame) castbars.Refill(frame) end,
    UNIT_SPELLCAST_INTERRUPTIBLE = function(frame) castbars.SetShield(frame, false) end,
    UNIT_SPELLCAST_NOT_INTERRUPTIBLE = function(frame) castbars.SetShield(frame, true) end,
}

local function registerEvents()
    for event, handler in pairs(HANDLERS) do core:RegisterEvent(event, onCastEvent(handler)) end
    core:RegisterEvent("PLAYER_TARGET_CHANGED", function() castbars.Refresh("target") end)
    core:RegisterEvent("PLAYER_FOCUS_CHANGED", function() castbars.Refresh("focus") end)
    core:RegisterEvent("UNIT_PET", function(_, unit)
        if core.Secret.IsSecret(unit) or unit == "player" then castbars.Refresh("pet") end
    end)
    core:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        castbars.Refresh()
        castbars.UpdateStockVisibility()
    end)
end

function castbars:OnEnable()
    core.Combat.Queue(function()
        for _, spec in ipairs(UNITS) do
            if not castbars.Bars[spec.key] then castbars.Sync(createBar(spec)) end
        end
        castbars.UpdateStockVisibility()
    end)
    registerEvents()
end

function castbars:Debug(sample)
    sample("UnitCastingInfo(player)", UnitCastingInfo, "player")
    sample("UnitCastingInfo(target)", UnitCastingInfo, "target")
    sample("UnitCastingDuration(target)", UnitCastingDuration, "target")
end

core:RegisterModule("castbars", castbars)
