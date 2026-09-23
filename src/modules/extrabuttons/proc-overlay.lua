-- Native pool and animations own proc lifetime; RikUI replaces only artwork.
local core, skin = RikUI, RikUI.Skin
local proc = { Regions = setmetatable({}, { __mode = "k" }) }
core.ProcOverlay = proc
local hooked = setmetatable({}, { __mode = "k" })
local LENGTH, THICKNESS = 54, 4
local warned = false

local function decorate(overlay)
    if not skin.IsRegion(overlay.texture) then return end
    local art = proc.Regions[overlay]
    if not art then
        art = overlay:CreateTexture(nil, "OVERLAY")
        art:SetTexture(skin.FLAT)
        art:SetVertexColor(1, 0.78, 0.3)
        art:SetPoint("CENTER", overlay, "CENTER")
        proc.Regions[overlay] = art
    end
    local location = type(Enum) == "table" and Enum.ScreenLocationType
    local position = overlay.position
    local vertical = location and not core.Secret.IsSecret(position)
        and (position == location.Left or position == location.Right
            or position == location.LeftOutside or position == location.RightOutside)
    art:SetSize(vertical and THICKNESS or LENGTH, vertical and LENGTH or THICKNESS)
    overlay.texture:SetTexture(nil)
end

local function refresh(frame)
    if type(frame.overlaysInUse) ~= "table" then return end
    for _, list in pairs(frame.overlaysInUse) do
        for _, overlay in pairs(list) do
            local ok, reason = pcall(decorate, overlay)
            if not ok and not warned then warned = true; core:Print("Proc overlay: " .. tostring(reason)) end
        end
    end
end

local function attach()
    local frame = SpellActivationOverlayFrame
    if not skin.IsRegion(frame) or hooked[frame] then return end
    hooked[frame] = core.Hooks.Script(frame, "OnEvent", function(self, event)
        if event == "SPELL_ACTIVATION_OVERLAY_SHOW" then refresh(self) end
    end)
    refresh(frame)
end

function proc:OnEnable()
    attach()
    core:RegisterEvent("ADDON_LOADED", attach, proc)
end

core:RegisterModule("procoverlay", proc)

