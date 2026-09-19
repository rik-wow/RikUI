-- Moving the main chat window without Edit Mode or /rik move. On 69913 ChatFrame1 is an Edit Mode
-- system: its tab's drag handler returns early ("Default frame is managed via edit mode"), while
-- undocked windows still lock, unlock and drag from their own tab menu. RikUI adds the missing
-- piece: with the window unlocked, dragging the ChatFrame1 tab moves a small holder the window is
-- centred on. Docked tabs and the edit box follow the window. The drop is saved under the layout
-- key chat, and the window is only ever touched once a position has been saved. Nothing here is
-- protected, so it also works in combat.
local core, layout = RikUI, RikUI.Layout
local chat = core.Chat

local HOLDER_NAME, KEY, HOLDER_SIZE = "RikUIChatHolder", "chat", 2
local MAIN, TAB = "ChatFrame1", "ChatFrame1Tab"
local USAGE = "Usage: /rik chat lock|unlock|reset"
local UNLOCKED = "Chat unlocked: drag the padlock button or the first chat tab, then click the padlock to lock."
local RESET = "Chat position forgotten; reload to hand the window back to Blizzard's layout."
local TIP_LOCKED, TIP_UNLOCKED = "Click to unlock the chat window", "Drag to move the chat window. Click to lock."
-- The copy button takes the corner (14 wide, inset 2); the padlock sits four pixels left of it.
local LOCK_SIZE, LOCK_OFFSET, LOCK_INSET, LOCK_ALPHA, SHACKLE_SWING = 14, 20, 2, 0.35, 4
local LOCKED_COLOR, UNLOCKED_COLOR = { 1, 1, 1 }, { 1, 0.78, 0.3 }
local holder, lockButton, adopted, anchoring, dragging = nil, nil, false, false, false

local function anchor()
    local frame = _G[MAIN]
    anchoring = true
    local ok, reason = pcall(function()
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", holder, "CENTER", 0, 0)
    end)
    anchoring = false
    if not ok then chat.Warn("move", reason) end
end

-- Edit Mode re-anchors its systems whenever a layout is applied; the window goes back on the holder.
local function onNativePoint()
    if adopted and not anchoring then anchor() end
end

local function ensureHolder()
    if holder then return end
    holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    holder:SetSize(HOLDER_SIZE, HOLDER_SIZE)
    holder:SetMovable(true)
    chat.Holder = holder
    hooksecurefunc(_G[MAIN], "SetPoint", onNativePoint)
end

-- First move only: the holder starts on the window's centre, wherever Edit Mode put it.
local function placeOnWindow()
    local x, y = _G[MAIN]:GetCenter()
    if not x or not y then return false end
    local ratio = _G[MAIN]:GetEffectiveScale() / holder:GetEffectiveScale()
    holder:ClearAllPoints()
    holder:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * ratio, y * ratio)
    return true
end

local function adopt()
    if adopted then return true end
    ensureHolder()
    if not placeOnWindow() then return false end
    adopted = true
    anchor()
    return true
end

local function dragStart()
    if dragging or chat.Settings().locked ~= false then return end
    if not adopt() then
        chat.Warn("move", "chat window position unavailable")
        return
    end
    dragging = true
    holder:StartMoving()
end

local function dragStop()
    if not dragging then return end
    dragging = false
    holder:StopMovingOrSizing()
    if not layout.SaveCenter(KEY, holder, core.Profile) then
        chat.Warn("move", "drop position unavailable")
        return
    end
    layout.Register(holder, KEY, core.Profile.positions[KEY])
    layout.Apply()
end

local function isLocked() return chat.Settings().locked ~= false end

-- Padlock glyph: the shackle sits over the body when locked and swings right, in gold, when open.
local function refreshLock()
    if not lockButton then return end
    local locked = isLocked()
    local color = locked and LOCKED_COLOR or UNLOCKED_COLOR
    lockButton.shackle:SetPoint("BOTTOM", lockButton.body, "TOP", locked and 0 or SHACKLE_SWING, 0)
    lockButton.shackle:SetVertexColor(color[1], color[2], color[3], 1)
    lockButton.body:SetVertexColor(color[1], color[2], color[3], 1)
    lockButton.rest = locked and LOCK_ALPHA or 1
    lockButton:SetAlpha(lockButton.rest)
end

function chat.SetLocked(locked)
    chat.Settings().locked = locked == true
    if locked == true then dragStop() else core:Print(UNLOCKED) end
    refreshLock()
    return true
end

local function lockPart(width, height)
    local part = lockButton:CreateTexture(nil, "ARTWORK")
    part:SetTexture(core.Media.border)
    part:SetSize(width, height)
    return part
end

local function showLockTip(self)
    self:SetAlpha(1)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(isLocked() and TIP_LOCKED or TIP_UNLOCKED)
    GameTooltip:Show()
end

local function createLockButton()
    lockButton = CreateFrame("Button", nil, _G[MAIN])
    lockButton:SetSize(LOCK_SIZE, LOCK_SIZE)
    lockButton:SetPoint("TOPRIGHT", _G[MAIN], "TOPRIGHT", -LOCK_OFFSET, -LOCK_INSET)
    lockButton.body, lockButton.shackle = lockPart(10, 7), lockPart(6, 5)
    lockButton.body:SetPoint("BOTTOM", lockButton, "BOTTOM", 0, 1)
    lockButton:RegisterForDrag("LeftButton")
    lockButton:SetScript("OnClick", function() chat.SetLocked(not isLocked()) end)
    lockButton:SetScript("OnDragStart", dragStart)
    lockButton:SetScript("OnDragStop", dragStop)
    lockButton:SetScript("OnEnter", showLockTip)
    lockButton:SetScript("OnLeave", function(self) self:SetAlpha(self.rest); GameTooltip:Hide() end)
    _G[MAIN].rikLock = lockButton
    refreshLock()
end

function chat.ResetPosition()
    dragStop()
    core.Profile.positions[KEY] = nil
    adopted = false
    core:Print(RESET)
end

-- The layout places the holder through the combat queue; the window follows once it is placed.
local function restore()
    if type(core.Profile.positions[KEY]) ~= "table" then return end
    ensureHolder()
    layout.Register(holder, KEY, core.Profile.positions[KEY])
    core.Combat.Queue(function()
        adopted = true
        anchor()
    end)
end

function chat.EnableMove()
    local tab = _G[TAB]
    if not chat.IsFrame(tab) or type(tab.HookScript) ~= "function" then
        chat.Warn("move", TAB .. " unavailable on this client")
        return
    end
    tab:HookScript("OnDragStart", dragStart)
    tab:HookScript("OnDragStop", dragStop)
    createLockButton()
    restore()
end

core:RegisterCommand("chat", function(args)
    if not core.Profile then core:Print("Still loading."); return end
    if not chat.enabled then core:Print("The chat module is disabled."); return end
    local action = args:lower()
    if action == "lock" then chat.SetLocked(true); core:Print("Chat locked.")
    elseif action == "unlock" then chat.SetLocked(false)
    elseif action == "reset" then chat.ResetPosition()
    else core:Print(USAGE) end
end, "Lock, unlock or reset the main chat window: /rik chat lock|unlock|reset")

table.insert(chat.Options.settings, { type = "checkbox", key = "locked", label = "Lock the main chat window",
    get = function() return chat.Settings().locked ~= false end, set = chat.SetLocked })
