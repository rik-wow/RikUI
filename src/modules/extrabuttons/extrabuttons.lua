-- Bar look for the action buttons that live outside RikUI's bars: the extra action button, the zone
-- ability buttons and the spell flyout. These are Blizzard's secure buttons, so only regions are
-- written (alpha, crop, mask, fonts, new textures). No attribute, parent, position or script is
-- written, and nothing is stored on a button: skinned buttons are remembered in weak tables, so no
-- RikUI key ends up on a table Blizzard's action code reads.
local core, skin, motion = RikUI, RikUI.Skin, RikUI.Motion
local weak = { __mode = "k" }
local extras = { Edges = setmetatable({}, weak), Fades = setmetatable({}, weak) }
core.ExtraButtons = extras

local BUTTON_ART = { "style", "Style", "Border", "SlotArt", "SlotBackground", "NormalTexture" }
local FLYOUT_ART = { "End", "HorizontalMiddle", "VerticalMiddle", "Start" }
local ICON_KEYS, FONT_KEYS = { "icon", "Icon" }, { HotKey = "hotkey", Count = "count" }
-- The edge sits one pixel outside the icon: it is drawn in a lower layer and the icon would cover it.
local EDGE_INSET = -1
local OVERRIDE_KEY, OVERRIDE_BUTTONS = "SpellButton", 6
local failed, warnings = setmetatable({}, weak), {}
local counts = { hooked = 0, skinned = 0, failed = 0 }

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("ExtraButtons " .. operation .. ": " .. tostring(reason))
end

local function iconOf(button)
    for _, key in ipairs(ICON_KEYS) do
        if skin.IsRegion(button[key]) then return button[key] end
    end
    return nil
end

-- The bars' border colour setting, so these buttons match the user's bars.
local function borderColor()
    local bars = core.Bars
    local color = bars and type(bars.BorderColor) == "function" and bars.BorderColor() or skin.LINE
    return { color[1], color[2], color[3], 1 }
end

local function unmask(button, icon)
    local mask = button.IconMask
    if skin.IsRegion(mask) and type(icon.RemoveMaskTexture) == "function" then icon:RemoveMaskTexture(mask) end
end

-- The art goes first: if the client refuses that write nothing else has been added.
local function apply(button, icon)
    skin.Strip(button, BUTTON_ART)
    local normal = type(button.GetNormalTexture) == "function" and button:GetNormalTexture() or nil
    if skin.IsRegion(normal) then normal:SetAlpha(0) end
    unmask(button, icon)
    skin.CropIcon(icon)
    for key, role in pairs(FONT_KEYS) do skin.Font(button[key], role) end
    local edge = skin.Outline(button, borderColor(), EDGE_INSET, icon)
    extras.Edges[button] = edge
    local fade = { groups = {}, plays = 0 }
    for index, line in ipairs(edge) do fade.groups[index] = motion.Tween(line, 0, 1, skin.FADE_SECONDS) end
    extras.Fades[button] = fade
end

-- One record stands for the four lines' tweens, with a single play count.
local function playFade(button)
    local fade = extras.Fades[button]
    if not fade then return end
    fade.plays = fade.plays + 1
    for _, group in ipairs(fade.groups) do motion.Play(group) end
end

-- A failed button is not retried: half a skin applied twice is worse than half a skin.
local function skinButton(button)
    local icon = skin.IsRegion(button) and iconOf(button) or nil
    if not icon or failed[button] then return end
    if not extras.Edges[button] then
        local ok, reason = pcall(apply, button, icon)
        if not ok then
            failed[button], counts.failed = true, counts.failed + 1
            return warn("skin", reason)
        end
        counts.skinned = counts.skinned + 1
    end
    playFade(button)
end

local function skinChildren(holder)
    if not skin.IsRegion(holder) or type(holder.GetChildren) ~= "function" then return end
    for _, child in ipairs({ holder:GetChildren() }) do skinButton(child) end
end

local function hook(name, onShow)
    local frame = _G[name]
    if not skin.IsRegion(frame) or type(frame.HookScript) ~= "function" then return nil end
    counts.hooked = counts.hooked + 1
    frame:HookScript("OnShow", onShow)
    if frame:IsShown() then onShow(frame) end
    return frame
end

local function zoneAbilities(frame)
    skin.Strip(frame, { "Style" })
    skinChildren(frame.SpellButtonContainer)
end

local function flyout(frame)
    if skin.IsRegion(frame.Background) then skin.Strip(frame.Background, FLYOUT_ART) end
    skinChildren(frame)
end

-- Possess buttons retain native actions. Vehicle artwork is reapplied after texture-kit changes.
local function possessBar(frame)
    if type(frame.actionButtons) ~= "table" then return end
    for _, button in ipairs(frame.actionButtons) do skinButton(button) end
end

local vehicleArt = {
    "EndCapL", "EndCapR", "Divider1", "Divider2", "Divider3", "_BG", "_Border",
    "MicroBGL", "_MicroBGMid", "MicroBGR", "ButtonBGL", "_ButtonBGMid", "ButtonBGR",
    "PitchOverlay", "PitchButtonBG", "PitchBG", "ExitBG", "HealthBarBG",
    "HealthBarOverlay", "PowerBarBG", "PowerBarOverlay",
}
local vehicleRegions, vehicleHooks = setmetatable({}, weak), setmetatable({}, weak)

local function flatSurface(frame)
    if not skin.IsRegion(frame) or vehicleRegions[frame] then return end
    vehicleRegions[frame] = { skin.Fill(frame, skin.BACKING, 1), skin.Outline(frame) }
end

local function vehicleControl(button, label)
    if not skin.IsRegion(button) then return end
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
        local region = type(button[getter]) == "function" and button[getter](button)
        if skin.IsRegion(region) then
            region:SetTexture(core.Media.highlight)
            region:SetTexCoord(0, 1, 0, 1)
        end
    end
    if vehicleRegions[button] then return end
    flatSurface(button)
    local text = button:CreateFontString(nil, "OVERLAY")
    core.Media.Font(text, "label")
    text:SetPoint("CENTER", button, "CENTER")
    text:SetText(label)
end

local function vehicleStatus(bar)
    if not skin.IsRegion(bar) then return end
    skin.Strip(bar, { "HealthBarBG", "HealthBarOverlay", "PowerBarBG", "PowerBarOverlay", "XpMid", "XpL", "XpR" })
    local fill = type(bar.GetStatusBarTexture) == "function" and bar:GetStatusBarTexture()
    if skin.IsRegion(fill) then fill:SetTexture(core.Media.statusbar) end
    skin.Font(bar.text, "small")
    flatSurface(bar)
end

local function vehicleSkin(frame)
    skin.Strip(frame, vehicleArt)
    flatSurface(frame)
    vehicleControl(frame.LeaveButton, "X")
    vehicleControl(frame.PitchUpButton, "+")
    vehicleControl(frame.PitchDownButton, "-")
    if skin.IsRegion(frame.PitchMarker) then
        frame.PitchMarker:SetTexture(skin.FLAT)
        frame.PitchMarker:SetVertexColor(1, 0.78, 0.3)
    end
    vehicleStatus(frame.healthBar)
    vehicleStatus(frame.powerBar)
    vehicleStatus(frame.xpBar)
    if skin.IsRegion(frame.xpBar) then
        for index = 1, 19 do skin.Strip(frame.xpBar, { "XpDiv" .. index }) end
    end
end

local function overrideBar(frame)
    vehicleSkin(frame)
    for index = 1, OVERRIDE_BUTTONS do skinButton(frame[OVERRIDE_KEY .. index]) end
end

local function attachVehicle()
    local frame = OverrideActionBar
    if not skin.IsRegion(frame) or vehicleHooks[frame] then return end
    vehicleHooks[frame] = true
    hook("OverrideActionBar", overrideBar)
    core.Hooks.Script(frame, "OnEvent", function(self) vehicleSkin(self) end)
end


function extras:OnEnable()
    hook("PossessActionBar", possessBar)
    attachVehicle()
    core:RegisterEvent("ADDON_LOADED", attachVehicle, extras)
    hook("ExtraActionBarFrame", function(frame) skinButton(frame.button) end)
    hook("SpellFlyout", flyout)
    local zone = hook("ZoneAbilityFrame", zoneAbilities)
    -- The pool hands out buttons on every update, which can come after the frame's show. The frame's
    -- methods are not hooked (on 1.60.1.69977 that left UpdateDisplayedZoneAbilities nil for
    -- Blizzard's updater); the container's show and spell changes re-skin instead.
    if zone and skin.IsRegion(zone.SpellButtonContainer) then
        zone.SpellButtonContainer:HookScript("OnShow", function() zoneAbilities(zone) end)
        core:RegisterEvent("SPELLS_CHANGED", function() if zone:IsShown() then zoneAbilities(zone) end end, extras)
    end
end

function extras:Debug()
    core:Print("ExtraButtons hooked=" .. counts.hooked .. " skinned=" .. counts.skinned .. " failed=" .. counts.failed)
end

core:RegisterModule("extrabuttons", extras)
