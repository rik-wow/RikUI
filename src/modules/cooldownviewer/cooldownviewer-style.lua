-- Owned decoration only; no pooled native fields, item animations or cooldown state.
local core, viewer, skin, media, motion = RikUI, RikUI.CooldownViewer, RikUI.Skin, RikUI.Media, RikUI.Motion
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

function viewer.DecoratePanel(holder, title)
    skin.Fill(holder, SHADOW, -2)
    holder.fill = skin.Fill(holder, { 0.035, 0.045, 0.065, 0.88 })
    holder.edge = skin.Outline(holder, skin.LINE)
    viewer.Rule(holder, holder, ACCENT, true, 1)
    holder.title = holder:CreateFontString(nil, "OVERLAY")
    media.Font(holder.title, "small")
    holder.title:SetTextColor(0.65, 0.82, 0.94)
    holder.title:SetPoint("TOPLEFT", holder, "TOPLEFT", 8, -6)
    holder.title:SetText(title)
    holder.fade = motion.Tween(holder, 0, 1, skin.FADE_SECONDS)
    holder:SetScript("OnShow", function() motion.Play(holder.fade) end)
end
