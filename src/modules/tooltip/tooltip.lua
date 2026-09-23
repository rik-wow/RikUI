-- Tooltip anchor, flat skin and fonts. Lines, colours and the unit health bar live in
-- src/modules/tooltip/tooltip-data.lua. Nothing here is protected, so every write also runs in combat.
local core, media, layout, ui = RikUI, RikUI.Media, RikUI.Layout, RikUI.UI
local tooltip = { Skinned = {}, Options = { title = "Tooltips", settings = {} } }
core.Tooltip = tooltip

local ANCHOR_NAME, ANCHOR_KEY = "RikUITooltipAnchor", "tooltip"
local ANCHOR_WIDTH, ANCHOR_HEIGHT = 250, 150 -- GameTooltipDefaultContainer's footprint
-- Bottom right, above the space the micro menu and bag strip will take.
local DEFAULTS = { point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT", x = -16, y = 180 }
-- Every named GameTooltip instance on 69913 that floats. ItemSocketingDescription is left out: it is
-- a description area pinned inside the socketing window.
local TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "EmbeddedItemTooltip", "GameNoHeaderTooltip",
    "GameSmallHeaderTooltip", "BuffFrameTooltip", "AuraButtonTooltip", "PrivateAurasTooltip",
    "LootHistoryExtraTooltip", "QuickKeybindTooltip", "SettingsTooltip" }
local FONT_OBJECTS = { GameTooltipHeaderText = "label", GameTooltipText = "label", GameTooltipTextSmall = "small" }
local ANCHOR_FUNCTION, BACKDROP_FUNCTION = "GameTooltip_SetDefaultAnchor", "SharedTooltip_SetBackdropStyle"
local EDGE = 1
local BACKGROUND, BORDER = { 0.055, 0.065, 0.08, 0.95 }, { 0.25, 0.28, 0.32, 1 }
local warnings = {}

function tooltip.Warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Tooltip " .. operation .. ": " .. tostring(reason))
end

-- A frame-valued field, or nil: the real client has none of RikUI's names on its frames.
function tooltip.Child(frame, key)
    local value = frame[key]
    local kind = type(value)
    if kind == "table" or kind == "userdata" then return value end
    return nil
end

function tooltip.HideInCombat()
    local settings = core.Profile and core.Profile.tooltip
    return type(settings) == "table" and settings.hideInCombat == true
end

local function createAnchor()
    local frame = CreateFrame("Frame", ANCHOR_NAME, UIParent)
    frame:SetSize(ANCHOR_WIDTH, ANCHOR_HEIGHT)
    -- A place tooltips float over, not a frame: it neither blocks other groups nor is blocked.
    layout.Register(frame, ANCHOR_KEY, DEFAULTS, { label = "Tooltip", floating = true })
    tooltip.Anchor = frame
    return frame
end

-- Post-hook: Blizzard has already set the owner and its own corner anchor.
local function anchorTooltip(frame)
    if not tooltip.enabled or not tooltip.Anchor then return end
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMRIGHT", tooltip.Anchor, "BOTTOMRIGHT", 0, 0)
end

-- The default style re-applies the NineSlice on every hide; keep it hidden on skinned tooltips.
function tooltip.HideBackdrop(frame)
    if not tooltip.enabled or not tooltip.Skinned[frame] then return end
    local nineSlice = tooltip.Child(frame, "NineSlice")
    if nineSlice then nineSlice:Hide() end
end

local function skin(frame)
    if tooltip.Skinned[frame] then return end
    frame.rikBackground = frame:CreateTexture(nil, "BACKGROUND")
    frame.rikBackground:SetAllPoints()
    frame.rikBackground:SetColorTexture(unpack(BACKGROUND))
    frame.rikBorder = ui.Edges(frame, EDGE, "BORDER")
    for _, line in ipairs(frame.rikBorder) do line:SetVertexColor(unpack(BORDER)) end
    core.Motion.BindEntrance(frame)
    tooltip.Skinned[frame] = true
    tooltip.HideBackdrop(frame)
end

local function skinAll()
    for _, name in ipairs(TOOLTIPS) do
        local frame = _G[name]
        if frame then skin(frame) end
    end
end

local function applyFonts()
    for name, role in pairs(FONT_OBJECTS) do
        local object = _G[name]
        if object then
            local ok, reason = pcall(media.Font, object, role)
            if not ok then tooltip.Warn("font", reason) end
        end
    end
end

local function hook(name, callback)
    if type(_G[name]) ~= "function" then tooltip.Warn(name, "unavailable on this client"); return false end
    core.Hooks.Function(name, callback)
    return true
end

function tooltip:OnEnable()
    createAnchor()
    skinAll()
    applyFonts()
    hook(ANCHOR_FUNCTION, anchorTooltip)
    hook(BACKDROP_FUNCTION, tooltip.HideBackdrop)
    -- A tooltip that lives in a load-on-demand add-on arrives after login.
    core:RegisterEvent("ADDON_LOADED", skinAll)
    if tooltip.RegisterData then tooltip.RegisterData() end
end

local function skinnedCount()
    local total = 0
    for _ in pairs(tooltip.Skinned) do total = total + 1 end
    return total
end

function tooltip:Debug(sample)
    core:Print("Tooltip anchor=" .. tostring(tooltip.Anchor ~= nil) .. " skinned=" .. skinnedCount()
        .. " processor=" .. tostring(tooltip.DataReady == true))
    sample("UnitTokenFromGUID(player)", function() return UnitTokenFromGUID(UnitGUID("player")) end)
    sample("GetDetailedItemLevelInfo(6948)", function() return C_Item.GetDetailedItemLevelInfo(6948) end)
end

table.insert(tooltip.Options.settings, { type = "checkbox", key = "hideInCombat", label = "Hide unit tooltips in combat",
    get = tooltip.HideInCombat,
    set = function(value) core.Profile.tooltip.hideInCombat = value == true end })

core:RegisterModule("tooltip", tooltip)
