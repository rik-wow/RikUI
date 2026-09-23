-- Flat cosmetic regions only; secure actions and visibility belong to src/modules/bars/bars.lua.
local core, bars, media = RikUI, RikUI.Bars, RikUI.Media
local ICON_MIN, ICON_MAX, EDGE = 0.07, 0.93, 1
local GRYPHON = "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf"
local GRYPHON_SIZE, GRYPHON_OVERLAP = 96, 8
local DEFAULT_BORDER = { 0.25, 0.28, 0.32 }
local decorated = setmetatable({}, { __mode = "k" })

local function channel(value)
    return type(value) == "number" and value >= 0 and value <= 1
end

function bars.BorderColor()
    local saved = core.Profile and core.Profile.borderColor
    if type(saved) == "table" and channel(saved[1]) and channel(saved[2]) and channel(saved[3]) then return saved end
    return DEFAULT_BORDER
end

local function tintBorder(button)
    local color = bars.BorderColor()
    for _, edge in ipairs(button.border) do edge:SetVertexColor(color[1], color[2], color[3], 1) end
end

-- Cosmetic only: retinting existing textures needs no protected write.
function bars.ApplySkin()
    for button in pairs(decorated) do tintBorder(button) end
end

local function borderEdge(button, first, second, horizontal)
    local edge = button:CreateTexture(nil, "OVERLAY")
    edge:SetTexture(media.border)
    edge:SetPoint(first, button, first, 0, 0)
    edge:SetPoint(second, button, second, 0, 0)
    if horizontal then edge:SetHeight(EDGE) else edge:SetWidth(EDGE) end
    return edge
end

local function motionRegion(button, color)
    local region = button:CreateTexture(nil, "OVERLAY")
    region:SetAllPoints(button)
    region:SetTexture(media.highlight)
    region:SetVertexColor(unpack(color))
    region:SetAlpha(0)
    return region
end

local function decorateMotion(button)
    local motion = core.Motion
    if not motion then return end
    local hover = motionRegion(button, { 0.5, 0.75, 1 })
    local flash = motionRegion(button, { 1, 1, 1 })
    local ready = motionRegion(button, { 0.4, 1, 0.7 })
    local fx = {
        hover = hover, flash = flash, ready = ready,
        hoverIn = motion.Tween(hover, 0, 0.3, 0.12),
        hoverOut = motion.Tween(hover, 0.3, 0, 0.16),
        press = motion.Tween(flash, 0.5, 0, 0.18),
        done = motion.Tween(ready, 0.5, 0, 0.3),
        entry = motion.Tween(button.icon, 0, 1, 0.16),
    }
    button.motion = fx
    if fx.hoverIn then fx.hoverIn:SetScript("OnFinished", function() hover:SetAlpha(0.3) end) end
    button:HookScript("OnEnter", function() motion.Stop(fx.hoverOut); motion.Play(fx.hoverIn) end)
    button:HookScript("OnLeave", function()
        motion.Stop(fx.hoverIn); hover:SetAlpha(0); motion.Play(fx.hoverOut)
    end)
    button:HookScript("OnMouseDown", function() motion.Play(fx.press) end)
    button:HookScript("OnShow", function() motion.Play(fx.entry) end)
    button:HookScript("OnHide", function()
        for _, key in ipairs({ "hoverIn", "hoverOut", "press", "done", "entry" }) do motion.Stop(fx[key]) end
        hover:SetAlpha(0)
    end)
end

function bars.PlayButtonMotion(button, key)
    if button.motion then core.Motion.Play(button.motion[key]) end
end

function bars.AttachCooldownMotion(button, cooldown)
    if not button.motion then return end
    cooldown:HookScript("OnCooldownDone", function()
        if button.stateOccupied and button:IsVisible() then bars.PlayButtonMotion(button, "done") end
    end)
end

function bars.DecorateButton(button)
    button:ClearNormalTexture()
    button.empty = button:CreateTexture(nil, "BACKGROUND")
    button.empty:SetAllPoints()
    button.empty:SetColorTexture(0.055, 0.065, 0.08, 0.95)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", EDGE, -EDGE)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -EDGE, EDGE)
    button.icon:SetTexCoord(ICON_MIN, ICON_MAX, ICON_MIN, ICON_MAX)
    button.border = {
        borderEdge(button, "TOPLEFT", "TOPRIGHT", true),
        borderEdge(button, "BOTTOMLEFT", "BOTTOMRIGHT", true),
        borderEdge(button, "TOPLEFT", "BOTTOMLEFT", false),
        borderEdge(button, "TOPRIGHT", "BOTTOMRIGHT", false),
    }
    decorated[button] = true
    tintBorder(button)
    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -2, 2)
    media.Font(button.count, "count")
    button:SetHighlightTexture(media.highlight, "ADD")
    button:SetPushedTexture(media.highlight, "ADD")
    decorateMotion(button)
end

function bars.CreateActiveTexture(parent)
    local texture = parent:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    texture:SetTexture(media.checked)
    texture:SetVertexColor(1, 0.78, 0.3, 1)
    texture:SetAlphaFromBoolean(false, 1, 0)
    return texture
end

function bars.SkinButtonState(button)
    media.Font(button.hotkey, "hotkey")
    media.Font(button.cooldown:GetCountdownFontString(), "cooldown")
    media.Font(button.chargeCooldown:GetCountdownFontString(), "charge")
    for _, edge in ipairs(button.border) do edge:SetParent(button.stateOverlay) end
    button.current = bars.CreateActiveTexture(button.stateOverlay)
    button.repeating = bars.CreateActiveTexture(button.stateOverlay)
end

local function gryphon(bar, right)
    local art = bar:CreateTexture(nil, "BACKGROUND")
    art:SetTexture(GRYPHON)
    art:SetSize(GRYPHON_SIZE, GRYPHON_SIZE)
    art:SetPoint(right and "BOTTOMLEFT" or "BOTTOMRIGHT", bar,
        right and "BOTTOMRIGHT" or "BOTTOMLEFT", right and -GRYPHON_OVERLAP or GRYPHON_OVERLAP, -12)
    if right then art:SetTexCoord(1, 0, 0, 1) end
    return art
end

function bars.UpdateGryphons(bar)
    if (bar.positionKey or bar.key) ~= "main" then return end
    if not bar.gryphons then bar.gryphons = { gryphon(bar, false), gryphon(bar, true) } end
    for _, art in ipairs(bar.gryphons) do art:SetShown(core.Profile.gryphons == true) end
end

local function setGryphons(shown)
    core.Profile.gryphons = shown == true
    bars.ApplyLayout()
end

core:RegisterCommand("gryphons", function(args)
    if not core.Profile then core:Print("Still loading."); return end
    if args ~= "on" and args ~= "off" then core:Print("Usage: /rik gryphons on|off"); return end
    setGryphons(args == "on")
end, "Show or hide main-bar gryphon end caps")

table.insert(bars.Options.settings, { type = "checkbox", key = "gryphons", label = "Gryphon end caps",
    get = function() return core.Profile.gryphons == true end, set = setGryphons })
table.insert(bars.Options.settings, { type = "colour", key = "borderColor", label = "Button border colour",
    get = bars.BorderColor,
    set = function(value)
        core.Profile.borderColor = { value[1], value[2], value[3] }
        bars.ApplySkin()
    end })
