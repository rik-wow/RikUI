-- A flat totem row. Blizzard's TotemFrame is a child of PlayerFrame, which RikUI parks, so without
-- this a shaman sees no totems. The slots are unprotected and show and hide in combat, which is
-- when totems drop. Whether GetTotemInfo hands out secrets on 69913 is unverified: readable values
-- decide presence the way Blizzard does, secret values cannot be compared and go straight to the
-- widgets. The cooldown widget draws the sweep and the countdown, so no time is worked out here.
-- Display only: DestroyTotem is called from secure code in the stock button and is left alone.
local core, layout, skin, motion = RikUI, RikUI.Layout, RikUI.Skin, RikUI.Motion
local totems = { Slots = {} }
core.Totems = totems

local HOLDER_NAME, KEY = "RikUITotems", "totems"
local SIZE, GAP, DEFAULT_SLOTS = 28, 3, 4
local DEFAULTS = { point = "BOTTOM", relativePoint = "BOTTOM", x = -140, y = 238 }
local holder, warnings = nil, {}

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Totems " .. operation .. ": " .. tostring(reason))
end

-- Shown slots pack from the left in slot order.
local function arrange()
    local offset = 0
    for _, button in ipairs(totems.Slots) do
        if button:IsShown() then
            button:ClearAllPoints()
            button:SetPoint("LEFT", holder, "LEFT", offset, 0)
            offset = offset + SIZE + GAP
        end
    end
end

local function hide(button)
    button.cooldown:Clear()
    button:Hide()
end

local function show(button, start, duration, icon)
    local wasShown = button:IsShown()
    button.icon:SetTexture(icon)
    button.cooldown:SetCooldown(start, duration)
    button:Show()
    if not wasShown then motion.Play(button.fade) end
end

local function isUp(haveTotem, duration) return haveTotem == true and duration > 0 end

local function feed(button, haveTotem, _, start, duration, icon)
    local secret = core.Secret.IsSecret(haveTotem) or core.Secret.IsSecret(duration)
    if secret or isUp(haveTotem, duration) then show(button, start, duration, icon) else hide(button) end
end

local function readTotem(slot) return GetTotemInfo(slot) end

local function refreshSlot(button)
    local ok, reason = core.Secret.Apply(button.sink, readTotem, button.slot)
    if ok then return end
    warn("read", reason)
    hide(button)
end

function totems.Refresh()
    if not holder then return end
    for _, button in ipairs(totems.Slots) do refreshSlot(button) end
    arrange()
end

local function showTooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:SetTotem(button.slot)
end

local function hideTooltip() GameTooltip:Hide() end

local function cooldown(button)
    local widget = CreateFrame("Cooldown", nil, button)
    widget:SetAllPoints(button)
    widget:EnableMouse(false)
    widget:SetDrawEdge(false)
    widget:SetDrawBling(false)
    widget:SetReverse(true)
    widget:SetHideCountdownNumbers(false)
    widget:SetCountdownFont("NumberFontNormal")
    widget:SetSwipeColor(0, 0, 0, 0.8)
    return widget
end

local function createSlot(slot)
    local button = CreateFrame("Frame", nil, holder)
    button:SetSize(SIZE, SIZE)
    button.slot = slot
    button.rikFill = skin.Fill(button, skin.BACKING)
    button.rikBorder = skin.Outline(button)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    skin.CropIcon(button.icon)
    button.cooldown = cooldown(button)
    button.fade = motion.Tween(button, 0, 1, skin.FADE_SECONDS)
    button.sink = function(...) feed(button, ...) end
    button:EnableMouse(true)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", hideTooltip)
    button:Hide()
    totems.Slots[slot] = button
end

local function build()
    local slots = type(MAX_TOTEMS) == "number" and MAX_TOTEMS or DEFAULT_SLOTS
    holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    holder:SetSize(slots * SIZE + (slots - 1) * GAP, SIZE)
    for slot = 1, slots do createSlot(slot) end
    layout.Register(holder, KEY, DEFAULTS)
    totems.Holder = holder
    totems.Refresh()
end

function totems:OnEnable()
    if type(GetTotemInfo) ~= "function" then return end
    core.Combat.Queue(build)
    core:RegisterEvent("PLAYER_TOTEM_UPDATE", totems.Refresh)
    core:RegisterEvent("PLAYER_ENTERING_WORLD", totems.Refresh)
end

function totems:Debug()
    local shown = 0
    for _, button in ipairs(totems.Slots) do
        if button:IsShown() then shown = shown + 1 end
    end
    core:Print("Totems holder=" .. tostring(holder ~= nil) .. " shown=" .. shown)
end

core:RegisterModule("totems", totems)
