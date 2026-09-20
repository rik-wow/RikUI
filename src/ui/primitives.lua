-- Shared drawing primitives do not depend on a feature being enabled.
local core = RikUI

local function edge(frame, first, second, horizontal, thickness, layer)
    local texture = frame:CreateTexture(nil, layer)
    texture:SetTexture(core.Media.border)
    texture:SetPoint(first, frame, first, 0, 0)
    texture:SetPoint(second, frame, second, 0, 0)
    if horizontal then texture:SetHeight(thickness) else texture:SetWidth(thickness) end
    return texture
end

function core.UI.Edges(frame, thickness, layer)
    return {
        edge(frame, "TOPLEFT", "TOPRIGHT", true, thickness, layer),
        edge(frame, "BOTTOMLEFT", "BOTTOMRIGHT", true, thickness, layer),
        edge(frame, "TOPLEFT", "BOTTOMLEFT", false, thickness, layer),
        edge(frame, "TOPRIGHT", "BOTTOMRIGHT", false, thickness, layer),
    }
end
