-- Plate layout and the health bar. Blizzard calls SetValue without interpolation, so each plate
-- gets an own StatusBar over Blizzard's bar, fed reader-to-sink with the client's easing; Blizzard's
-- fill is faded. A child frame draws above its parent's regions, which is why Blizzard's health
-- text moves onto the overlay and the bar's RikUI regions live on it. The name sits in its own
-- plaque on top of the bar.
-- UpdateAnchors resets fonts, anchors, sizes and atlases on each layout pass; Apply runs after it.
local core, media, unitframes = RikUI, RikUI.Media, RikUI.UnitFrames
local nameplates = core.Nameplates
local skin = {}
nameplates.Skin = skin

local isRegion, font, flat = nameplates.IsRegion, nameplates.Font, nameplates.Flat
local BAR_HEIGHT, LEVEL_GAP, MARKER_GAP = 14, 2, 16
local NAME_GAP, PLAQUE_PAD_X, PLAQUE_PAD_Y = 3, 5, 2
local BACKING, LINE, WHITE = { 0.06, 0.07, 0.09, 0.9 }, { 0.25, 0.28, 0.32, 1 }, { 1, 1, 1, 1 }
local LEVEL_ART = { "playerLevelDiffIcon", "selectedBorder" }
local CAST_ART = { "Border", "BorderShield" }
local ICON_CROP = 0.08
local FADE_SECONDS, FLASH_SECONDS, FLASH_ALPHA = 0.15, 0.25, 0.5
-- Camelot switches Blizzard's classification art off; these glyphs take its place.
local MARKERS = { elite = { "+", { 1, 0.82, 0 } }, worldboss = { "B", { 1, 0.3, 0.2 } },
    rare = { "R", { 0.75, 0.78, 0.85 } }, rareelite = { "R+", { 0.75, 0.78, 0.85 } } }
local warnings = {}

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Nameplates " .. operation .. ": " .. tostring(reason))
end

local function interpolation(name)
    local enum = type(Enum) == "table" and Enum.StatusBarInterpolation
    return type(enum) == "table" and enum[name] or nil
end

-- One alpha tween on a region or frame; nil where the client has no animation groups.
local function tween(owner, from, to, seconds)
    local group = type(owner.CreateAnimationGroup) == "function" and owner:CreateAnimationGroup() or nil
    if not group then return nil end
    local alpha = group:CreateAnimation("Alpha")
    alpha:SetFromAlpha(from)
    alpha:SetToAlpha(to)
    alpha:SetDuration(seconds)
    return group
end
skin.Tween = tween

local function play(group)
    if not group then return end
    group:Stop()
    group:Play()
end
skin.Play = play

local function createOverlay(bar)
    local own = CreateFrame("StatusBar", nil, bar)
    own:SetAllPoints(bar)
    own:SetStatusBarTexture(media.statusbar)
    own.flash = nameplates.Block(own, "OVERLAY", WHITE)
    own.flash:SetAllPoints(own)
    own.flash:SetAlpha(0)
    own.flashAnim = tween(own.flash, FLASH_ALPHA, 0, FLASH_SECONDS)
    own.marker = own:CreateFontString(nil, "OVERLAY")
    font(own.marker, "small")
    own.marker:SetPoint("RIGHT", own, "LEFT", -MARKER_GAP, 0)
    return own
end

-- The level badge loses its gold frame and selection glow; the number keeps Blizzard's
-- difficulty colour and the skull for high-level units stays.
local function createLevel(parts, level)
    if not isRegion(level) then return end
    for _, key in ipairs(LEVEL_ART) do
        if isRegion(level[key]) then level[key]:SetAlpha(0) end
    end
    parts.levelBox = nameplates.Block(level, "BACKGROUND", BACKING)
    parts.levelBorder = nameplates.Outline(level, parts.levelBox, LINE)
end

-- The name's own box: same backing and edge as the bar and the level box, sized to the text.
-- Blizzard hides the name on some plates, and the box follows it.
local function createPlaque(parts, frame)
    local name = frame.name
    if not isRegion(name) then return end
    parts.plaque = nameplates.Block(frame, "BACKGROUND", BACKING)
    parts.plaqueBorder = nameplates.Outline(frame, parts.plaque, LINE)
    local function sync() skin.SyncPlaque(frame) end
    for _, method in ipairs({ "SetShown", "Show", "Hide" }) do
        if type(name[method]) == "function" then hooksecurefunc(name, method, sync) end
    end
end

function skin.SyncPlaque(frame)
    local parts = nameplates.Parts[frame]
    if not parts or not parts.plaque then return end
    local nameOnly = type(frame.IsShowOnlyName) == "function" and frame:IsShowOnlyName() == true
    local shown = not nameOnly and frame.name:IsShown() == true
    parts.plaque:SetShown(shown)
    for _, line in ipairs(parts.plaqueBorder) do line:SetShown(shown) end
end

local function createCast(parts, castBar)
    if not isRegion(castBar) then return end
    parts.castBorder = nameplates.Outline(castBar, castBar, LINE)
end

function skin.Ensure(frame)
    local parts = nameplates.Parts[frame]
    if parts then return parts end
    parts = { bar = createOverlay(frame.HealthBarsContainer.healthBar) }
    nameplates.Parts[frame] = parts
    parts.fade = tween(frame, 0, 1, FADE_SECONDS)
    createLevel(parts, frame.PlayerLevelDiffFrame)
    createPlaque(parts, frame)
    createCast(parts, isRegion(frame.CastBarsContainer) and frame.CastBarsContainer.castBar or nil)
    nameplates.Target.Build(frame, parts)
    hooksecurefunc(frame, "UpdateAnchors", skin.Apply)
    return parts
end

local function applyBar(frame, parts, size)
    local bar = frame.HealthBarsContainer.healthBar
    frame.HealthBarsContainer:SetHeight(BAR_HEIGHT)
    bar.barTexture:SetAlpha(0)
    local backing = bar.bgTexture
    backing:SetTexture(flat)
    backing:SetVertexColor(unpack(BACKING))
    backing:ClearAllPoints()
    backing:SetPoint("TOPLEFT", bar, "TOPLEFT", -size, size)
    backing:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", size, -size)
end

-- TextStatusBar puts the percent in Text, LeftText or RightText depending on the display mode,
-- so all three are centred in the bar; only one is filled at a time.
local function applyHealthText(bar, own)
    for _, key in ipairs({ "Text", "LeftText", "RightText" }) do
        local region = bar[key]
        if isRegion(region) then
            region:SetParent(own)
            font(region, "small")
            region:ClearAllPoints()
            region:SetPoint("CENTER", own, "CENTER", 0, 0)
        end
    end
end

-- Percent inside the bar, name in its plaque on top. One anchor and no width lets the name take
-- whatever length it has. A name-only plate keeps Blizzard's name placement and gets no plaque.
local function applyText(frame, parts, size)
    local name = frame.name
    applyHealthText(frame.HealthBarsContainer.healthBar, parts.bar)
    if not isRegion(name) then return end
    font(name, "small")
    skin.SyncPlaque(frame)
    if type(frame.IsShowOnlyName) == "function" and frame:IsShowOnlyName() == true then return end
    name:ClearAllPoints()
    name:SetJustifyH("CENTER")
    name:SetPoint("BOTTOM", frame.HealthBarsContainer, "TOP", 0, NAME_GAP)
    if not parts.plaque then return end
    parts.plaque:ClearAllPoints()
    parts.plaque:SetPoint("TOPLEFT", name, "TOPLEFT", -PLAQUE_PAD_X, PLAQUE_PAD_Y)
    parts.plaque:SetPoint("BOTTOMRIGHT", name, "BOTTOMRIGHT", PLAQUE_PAD_X, -PLAQUE_PAD_Y)
    nameplates.Resize(parts.plaqueBorder, size)
end

-- The box takes Blizzard's width for the badge and the bar's exact height, outer edge included.
local function applyLevel(frame, parts, size)
    local level, box = frame.PlayerLevelDiffFrame, parts.levelBox
    if not box then return end
    local bar = frame.HealthBarsContainer.healthBar
    box:ClearAllPoints()
    box:SetPoint("LEFT", level, "LEFT", LEVEL_GAP, 0)
    box:SetPoint("RIGHT", level, "RIGHT", 0, 0)
    box:SetPoint("TOP", bar, "TOP", 0, size)
    box:SetPoint("BOTTOM", bar, "BOTTOM", 0, -size)
    nameplates.Resize(parts.levelBorder, size)
    local number = level.playerLevelDiffText
    if not isRegion(number) then return end
    font(number, "small")
    number:ClearAllPoints()
    number:SetPoint("CENTER", box, "CENTER", 0, 0)
end

-- CastingBarMixin swaps the fill atlas per cast type, which carries the uninterruptible colour,
-- so the fill is left alone and only the frame around it goes flat.
local function applyCast(frame, parts, size)
    if not parts.castBorder then return end
    local castBar = frame.CastBarsContainer.castBar
    for _, key in ipairs(CAST_ART) do
        if isRegion(castBar[key]) then castBar[key]:SetAlpha(0) end
    end
    if isRegion(castBar.Background) then
        castBar.Background:SetTexture(flat)
        castBar.Background:SetVertexColor(unpack(BACKING))
    end
    if isRegion(castBar.Icon) then castBar.Icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP) end
    font(castBar.Text, "small")
    font(castBar.CastTargetNameText, "small")
    nameplates.Resize(parts.castBorder, size)
end

function skin.Apply(frame)
    local parts = nameplates.Parts[frame]
    if not parts then return end
    local size = nameplates.Pixel(parts.bar)
    applyBar(frame, parts, size)
    applyText(frame, parts, size)
    applyLevel(frame, parts, size)
    applyCast(frame, parts, size)
    nameplates.Target.Resize(frame, parts, size)
end

local function readHealth(unit) return UnitHealth(unit), UnitHealthMax(unit) end

local function feed(parts, unit, easing)
    local own = parts.bar
    local ok, reason = core.Secret.Apply(function(current, maximum)
        own:SetMinMaxValues(0, maximum)
        own:SetValue(current, easing)
    end, readHealth, unit)
    if not ok then warn("health", reason) end
end

function skin.Health(frame, unit)
    local parts = nameplates.Parts[frame]
    if parts then feed(parts, unit, interpolation("ExponentialEaseOut")) end
end

-- UNIT_HEALTH is the trigger; the value itself is never looked at.
function skin.Damaged(frame, unit)
    local parts = nameplates.Parts[frame]
    if not parts then return end
    feed(parts, unit, interpolation("ExponentialEaseOut"))
    play(parts.bar.flashAnim)
end

function skin.Color(frame, unit)
    local parts = nameplates.Parts[frame]
    if not parts then return end
    local color = unitframes.HealthColor(unit)
    parts.bar:SetStatusBarColor(color.r, color.g, color.b)
end

function skin.Marker(frame, unit)
    local parts = nameplates.Parts[frame]
    if not parts then return end
    local ok, classification = core.Secret.Read(UnitClassification, unit)
    if not ok then warn("classification", classification) end
    local readable = ok and not core.Secret.IsSecret(classification) and type(classification) == "string"
    local marker = readable and MARKERS[classification] or nil
    parts.bar.marker:SetText(marker and marker[1] or "")
    if marker then parts.bar.marker:SetTextColor(unpack(marker[2])) end
end

-- A pooled frame arrives showing the previous unit's health, so the first fill does not ease.
function skin.SetUnit(frame, unit)
    local parts = nameplates.Parts[frame]
    if not parts then return end
    feed(parts, unit, interpolation("Immediate"))
    skin.Color(frame, unit)
    skin.Marker(frame, unit)
    play(parts.fade)
end
