-- Decorates Blizzard CustomAuraButton frames for the aura containers. Every region is a
-- descendant of the button and is handed to the button's own API once, inside the container's
-- initializeFrame call; the button then drives icon, count, border colour, cooldown, tooltip
-- and right-click cancel in secure code and RikUI never touches it again.
local core, media, ui, auras = RikUI, RikUI.Media, RikUI.UI, RikUI.Auras
local EDGE, ICON_CROP, COUNT_INSET = 1, 0.07, 2
local BACKGROUND = { 0.055, 0.065, 0.08, 0.95 }
local PRESERVE_ASSET_STYLE = 3 -- Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset on 69913
local CANCEL_CLICKS = "RightButtonUp"
local colors = { buff = { 0.25, 0.28, 0.32 } }
auras.Colors = colors
-- Auras another caster applied are drawn at this alpha.
auras.DimAlpha = 0.5

local function enumValue(group, name, fallback)
    local values = type(Enum) == "table" and Enum[group]
    if type(values) == "table" and values[name] ~= nil then return values[name] end
    return fallback
end

-- PreserveAsset keeps our edge texture and only recolours it with the client's dispel colours.
local function dispelOptions()
    return {
        style = enumValue("CustomAuraButtonDispelTypeTextureStyle", "PreserveAsset", PRESERVE_ASSET_STYLE),
        showAlways = false, showWhenHarmful = true, showWhenHelpful = false, showWithoutDispelType = true,
    }
end

local function background(button)
    local texture = button:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(unpack(BACKGROUND))
    return texture
end

local function icon(button)
    local texture = button:CreateTexture(nil, "ARTWORK")
    texture:SetPoint("TOPLEFT", button, "TOPLEFT", EDGE, -EDGE)
    texture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -EDGE, EDGE)
    texture:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    return texture
end

local function cooldown(button)
    local widget = CreateFrame("Cooldown", nil, button)
    widget:SetAllPoints(button)
    widget:EnableMouse(false)
    widget:SetDrawEdge(false)
    widget:SetDrawBling(false)
    widget:SetHideCountdownNumbers(false)
    widget:SetCountdownFont("NumberFontNormal")
    widget:SetSwipeColor(0, 0, 0, 0.8)
    return widget
end

-- The count sits on a frame above the cooldown so the swipe never covers it.
local function countText(button, swipe)
    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints(button)
    overlay:EnableMouse(false)
    overlay:SetFrameLevel(swipe:GetFrameLevel() + 1)
    local region = overlay:CreateFontString(nil, "OVERLAY")
    media.Font(region, "count")
    region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -COUNT_INSET, COUNT_INSET)
    return region
end

local function border(button, harmful)
    local lines = ui.Edges(button, EDGE, "OVERLAY")
    for _, line in ipairs(lines) do
        if harmful then
            button:AddDispelTypeTexture(line, dispelOptions())
        else
            line:SetVertexColor(colors.buff[1], colors.buff[2], colors.buff[3], 1)
        end
    end
    return lines
end

-- The secure container owns playback, expiry timing and recycling. Never install scripts
-- on AuraButton or read cooldown/aura durations to decide when to animate.
local function registerMotion(button)
    local motion = core.Motion
    if not motion then return end
    if type(button.AddAuraShownAnimation) == "function" then
        local fade = motion.Tween(button.icon, 0, 1, 0.16)
        if fade then button:AddAuraShownAnimation(fade) end
    end
    if type(button.AddPandemicRegion) ~= "function"
        or type(button.AddPandemicActiveAnimation) ~= "function" then return end
    local cue = button:CreateTexture(nil, "OVERLAY")
    cue:SetAllPoints(button)
    cue:SetTexture(media.border)
    cue:SetVertexColor(1, 0.72, 0.2)
    cue:Hide()
    local pulse = motion.Pulse(cue, 0.25, 0.85, 0.4)
    if not pulse then return end
    button:AddPandemicRegion(cue)
    button:AddPandemicActiveAnimation(pulse)
end

-- spec: size (px), harmful (dispel-coloured border), cancel (right-click cancels), dim (alpha).
local function decorate(button, spec)
    button:SetSize(spec.size, spec.size)
    if spec.dim then button:SetAlpha(auras.DimAlpha) end
    button.background = background(button)
    button.icon = icon(button)
    registerMotion(button)
    button:SetIcon(button.icon)
    button.border = border(button, spec.harmful)
    button.cooldown = cooldown(button)
    button:SetDurationCooldown(button.cooldown)
    button.count = countText(button, button.cooldown)
    button:SetApplicationCount(button.count)
    if spec.cancel then button:SetCancelAuraButtons(CANCEL_CLICKS) end
end

-- The container calls this once per button it creates, possibly in combat, before the
-- post-login access restriction applies to the new button.
function auras.Decorator(spec)
    return function(button)
        local ok, reason = pcall(decorate, button, spec)
        if not ok then auras.Warn("button", reason) end
    end
end

function auras.GroupLayout(size, newLine)
    local gap = auras.Gap
    return { elementSpacing = gap, lineSpacing = gap, groupSpacing = gap, elementWidth = size, elementHeight = size,
        forceNewLine = newLine == true }
end

function auras.GroupOptions(spec, maxFrames, newLine)
    return { maxFrameCount = maxFrames, initializeFrame = auras.Decorator(spec), layout = auras.GroupLayout(spec.size, newLine) }
end
