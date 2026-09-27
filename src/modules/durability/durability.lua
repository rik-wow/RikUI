-- A flat alert pill replacing DurabilityFrame's armoured figure. The client raises
-- UPDATE_INVENTORY_ALERTS and answers GetInventoryAlertStatus per slot: 1 worn, 2 broken. That is
-- inventory state, not a unit value, so it is counted; the reads still run under pcall.
local core, media, layout, ui, motion = RikUI, RikUI.Media, RikUI.Layout, RikUI.UI, RikUI.Motion
local durability = {}
core.Durability = durability

local FRAME_NAME, KEY = "RikUIDurability", "durability"
local WIDTH, HEIGHT, EDGE = 132, 18, 1
local DEFAULTS = { point = "TOP", relativePoint = "TOP", x = 0, y = -94 }
local BACKGROUND, BORDER = { 0.06, 0.07, 0.09, 0.9 }, { 0.25, 0.28, 0.32, 1 }
local HEALTHY_COLOR = { 0.5, 0.8, 0.7 }
local WORN_COLOR, BROKEN_COLOR, WHITE = { 1, 0.82, 0.18 }, { 0.93, 0.07, 0.07 }, { 1, 1, 1 }
local FLAT = "Interface\\BUTTONS\\WHITE8X8"
local FADE_SECONDS, PULSE_SECONDS, PULSE_ALPHA = 0.15, 0.5, 0.35
local WORN, BROKEN = 1, 2
-- Blizzard's INVENTORY_ALERT_STATUS_SLOTS order, with the inventory slot behind each entry.
local SLOTS = {
    { label = "Head", slot = 1 }, { label = "Shoulders", slot = 3 }, { label = "Chest", slot = 5 },
    { label = "Waist", slot = 6 }, { label = "Legs", slot = 7 }, { label = "Feet", slot = 8 },
    { label = "Wrists", slot = 9 }, { label = "Hands", slot = 10 }, { label = "Main hand", slot = 16 },
    { label = "Off hand", slot = 17 }, { label = "Ranged", slot = 18 },
}
local STOCK = "DurabilityFrame"
local pill, warnings, counts = nil, {}, { worn = 0, broken = 0 }

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Durability " .. operation .. ": " .. tostring(reason))
end

local function isFrame(value)
    local kind = type(value)
    return (kind == "table" or kind == "userdata") and type(value.SetParent) == "function"
end

local function readStatuses()
    local statuses = {}
    for index in ipairs(SLOTS) do
        local ok, value = pcall(GetInventoryAlertStatus, index)
        if not ok then warn("status", value) end
        statuses[index] = ok and not core.Secret.IsSecret(value) and (value == WORN or value == BROKEN) and value or 0
    end
    return statuses
end

local function readRepairDisabled()
    return C_GameRules.IsGameRuleActive(Enum.GameRule.RepairArmorDisabled) == true
end

local function repairDisabled()
    if type(C_GameRules) ~= "table" or type(Enum.GameRule) ~= "table" then return false end
    local ok, disabled = pcall(readRepairDisabled)
    return ok and disabled
end

local function count(statuses)
    local worn, broken = 0, 0
    for _, status in ipairs(statuses) do
        if status == BROKEN then broken = broken + 1 elseif status == WORN then worn = worn + 1 end
    end
    return worn, broken
end

local function describe(worn, broken)
    local parts = {}
    if broken > 0 then parts[#parts + 1] = broken .. " broken" end
    if worn > 0 then parts[#parts + 1] = worn .. " worn" end
    return table.concat(parts, ", ")
end

local function setPulsing(pulsing)
    if durability.pulsing == pulsing then return end
    durability.pulsing = pulsing
    if pulsing then motion.Play(durability.Pulse) return end
    motion.Stop(durability.Pulse)
    pill.alert:SetAlpha(0)
end

local function showPercent()
    local settings = core.Profile and core.Profile.durability
    return type(settings) == "table" and settings.showPercent == true
end

local function percent(slot)
    local ok, current, maximum = pcall(GetInventoryItemDurability, slot)
    if not ok or core.Secret.IsSecret(current) or core.Secret.IsSecret(maximum) then return end
    if type(current) ~= "number" or type(maximum) ~= "number" or current ~= current or maximum ~= maximum
        or maximum <= 0 or maximum == math.huge or current < 0 or current > maximum then return end
    return math.floor(current / maximum * 100 + 0.5)
end

local function lowestPercent()
    local lowest
    for _, info in ipairs(SLOTS) do
        local value = percent(info.slot)
        if value then lowest = math.min(lowest or value, value) end
    end
    return lowest
end

-- The pill is unprotected, so it shows and hides in combat.
local function show(worn, broken)
    local visible = pill:IsShown()
    counts.worn, counts.broken = worn, broken
    local minimum = showPercent() and not repairDisabled() and lowestPercent() or nil
    pill:SetShown(worn + broken > 0 or minimum ~= nil)
    setPulsing(broken > 0)
    if worn + broken == 0 and minimum == nil then return end
    pill.label:SetText(worn + broken > 0 and describe(worn, broken) or (minimum .. "% durability"))
    local color = broken > 0 and BROKEN_COLOR or worn > 0 and WORN_COLOR or HEALTHY_COLOR
    pill.label:SetTextColor(unpack(color))
    pill.severity:SetVertexColor(unpack(color))
    pill.icon:SetVertexColor(unpack(color))
    if not visible then motion.Play(durability.Fade) end
end

function durability.Refresh()
    if not pill then return end
    durability.Statuses = {}
    if repairDisabled() then show(0, 0) return end
    local ok, statuses = pcall(readStatuses)
    if not ok then warn("status", statuses); show(0, 0) return end
    durability.Statuses = statuses
    show(count(statuses))
end

local function slotLine(info, status)
    local value = percent(info.slot)
    local state = status == BROKEN and "broken" or status == WORN and "worn" or ""
    return info.label .. (value and "  " .. value .. "%" or "") .. "  " .. state
end

local function showTooltip(frame)
    GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Durability")
    for index, status in ipairs(durability.Statuses or {}) do
        if status == WORN or status == BROKEN or (showPercent() and percent(SLOTS[index].slot)) then
            local color = status == BROKEN and BROKEN_COLOR or WORN_COLOR
            GameTooltip:AddLine(slotLine(SLOTS[index], status), unpack(color))
        end
    end
    GameTooltip:Show()
end

local function hideTooltip() GameTooltip:Hide() end

local function severityChrome()
    pill.severity = pill:CreateTexture(nil, "OVERLAY")
    pill.severity:SetTexture(FLAT)
    pill.severity:SetPoint("TOPLEFT", pill, "TOPLEFT", 1, -1)
    pill.severity:SetPoint("BOTTOMLEFT", pill, "BOTTOMLEFT", 1, 1)
    pill.severity:SetWidth(2)
    pill.icon = media.Icon(pill, "profession", 12, "OVERLAY")
    pill.icon:SetPoint("LEFT", pill, "LEFT", 7, 0)
end

local function decorate()
    severityChrome()
    local background = pill:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(pill)
    background:SetTexture(FLAT)
    background:SetVertexColor(unpack(BACKGROUND))
    pill.rikBorder = ui.Edges(pill, EDGE, "BORDER")
    for _, line in ipairs(pill.rikBorder) do line:SetVertexColor(unpack(BORDER)) end
    pill.alert = pill:CreateTexture(nil, "ARTWORK")
    pill.alert:SetAllPoints(pill)
    pill.alert:SetTexture(FLAT)
    pill.alert:SetVertexColor(unpack(BROKEN_COLOR))
    pill.alert:SetAlpha(0)
    pill.label = pill:CreateFontString(nil, "OVERLAY")
    media.Font(pill.label, "small")
    pill.label:SetPoint("LEFT", pill, "LEFT", 24, 0)
    pill.label:SetPoint("RIGHT", pill, "RIGHT", -5, 0)
    pill.label:SetJustifyH("LEFT")
    pill.label:SetWordWrap(false)
    pill.label:SetTextColor(unpack(WHITE))
end

local function build()
    pill = CreateFrame("Frame", FRAME_NAME, UIParent)
    pill:SetSize(WIDTH, HEIGHT)
    decorate()
    durability.Fade = motion.Tween(pill, 0, 1, FADE_SECONDS)
    durability.Pulse = motion.Pulse(pill.alert, 0, PULSE_ALPHA, PULSE_SECONDS)
    pill:EnableMouse(true)
    pill:SetScript("OnEnter", showTooltip)
    pill:SetScript("OnLeave", hideTooltip)
    pill:Hide()
    layout.Register(pill, KEY, DEFAULTS)
    durability.Pill = pill
    durability.Refresh()
    if isFrame(_G[STOCK]) then core.Hide.Frame(_G[STOCK], false) end
end

function durability:OnEnable()
    if type(GetInventoryAlertStatus) ~= "function" then return end
    core.Combat.Queue(build)
    core:RegisterEvent("UPDATE_INVENTORY_ALERTS", durability.Refresh)
    core:RegisterEvent("PLAYER_ENTERING_WORLD", durability.Refresh)
end

function durability:Debug()
    core:Print("Durability pill=" .. tostring(pill ~= nil) .. " worn=" .. counts.worn .. " broken=" .. counts.broken)
end

durability.Options = { title = "Durability", settings = {
    { type = "checkbox", key = "showPercent", label = "Show lowest gear durability",
        description = "Keep the lowest readable gear percentage visible before a worn or broken alert.",
        get = showPercent, set = function(value)
            core.Profile.durability = core.Profile.durability or {}
            core.Profile.durability.showPercent = value == true
            durability.Refresh()
        end },
} }

core:RegisterModule("durability", durability)
