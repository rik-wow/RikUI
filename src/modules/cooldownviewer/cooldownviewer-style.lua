-- Owned decoration only; no pooled native fields, item animations or cooldown state.
local viewer, skin, motion = RikUI.CooldownViewer, RikUI.Skin, RikUI.Motion
local ACCENT, LIGHT, SHADOW = { 0.3, 0.75, 1, 0.85 }, { 1, 1, 1, 0.12 }, { 0, 0, 0, 0.65 }
local decorated = setmetatable({}, { __mode = "k" })

function viewer.Rule(owner, target, color, top, inset)
    local line = owner:CreateTexture(nil, "OVERLAY")
    line:SetTexture(skin.FLAT)
    line:SetVertexColor(unpack(color))
    local point = top and "TOP" or "BOTTOM"
    line:SetPoint(point .. "LEFT", target, point .. "LEFT", inset or 0, 0)
    line:SetPoint(point .. "RIGHT", target, point .. "RIGHT", -(inset or 0), 0)
    line:SetHeight(1)
    return line
end

function viewer.DecorateItem(item, owner, icon, isBar)
    if decorated[item] then return end
    local shadow = skin.Outline(owner, SHADOW, -2, icon)
    viewer.Rule(owner, icon, LIGHT, true)
    local accent = viewer.Rule(owner, icon, ACCENT, false)
    local fade = motion.Tween(accent, 0, 0.85, skin.FADE_SECONDS)
    motion.Play(fade)
    if isBar and skin.IsRegion(item.Bar) then
        skin.Outline(item.Bar, skin.LINE, -1)
        viewer.Rule(item.Bar, item.Bar, LIGHT, true)
    end
    decorated[item] = { shadow = shadow, fade = fade }
end
