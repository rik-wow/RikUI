-- The main chat window is a member of RikUI's arrangement system like every other frame. On 69913
-- ChatFrame1 is an Edit Mode system (its tab's drag handler returns early, "Default frame is managed
-- via edit mode"), so RikUI takes the window over from the first login: it is centred on a holder of
-- its own size, the holder is a layout group under the key chat, and the window gets the lock tag,
-- the overlay, the drag engine and the resize grip of the arrangement system. The padlock on the
-- window and dragging its first tab are shortcuts onto the same unlock state and the same drag.
-- Edit Mode re-anchoring the window is answered by putting it back on the holder. Nothing here is
-- protected.
local core, layout = RikUI, RikUI.Layout
local chat = core.Chat

local HOLDER_NAME, KEY = "RikUIChatHolder", "chat"
local MAIN, TAB = "ChatFrame1", "ChatFrame1Tab"
local USAGE = "Usage: /rik chat lock|unlock|reset"
local UNLOCKED = "Chat unlocked: drag it by its overlay, its first tab or the padlock; resize it by the corner grip. "
    .. "Click the padlock to lock."
local RESET = "Chat window back at its default place and size."
local TIP_LOCKED, TIP_UNLOCKED = "Click to unlock the chat window", "Drag to move the chat window. Click to lock."
-- The copy button takes the corner (16 wide, inset 2); the padlock sits two pixels left of it.
local LOCK_SIZE, LOCK_OFFSET, LOCK_INSET, LOCK_ALPHA, SHACKLE_SWING = 16, 20, 2, 0.35, 3
local LOCKED_COLOR, UNLOCKED_COLOR = { 1, 1, 1 }, { 1, 0.78, 0.3 }
-- The overlay of an unlocked group is a DIALOG frame over the whole window; the open padlock sits above it.
local OPEN_STRATA = "FULLSCREEN_DIALOG"
local HOVER_FADE = 0.12
local holder, lockButton, anchoring, dragging = nil, nil, false, false

local function isLocked() return not (layout.IsUnlocked and layout.IsUnlocked(KEY)) end

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
    if holder and not anchoring then anchor() end
end

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
    lockButton:SetFrameStrata(locked and lockButton.homeStrata or OPEN_STRATA)
end

-- A new character's chat starts with the size a whole-screen layout gives it; without the layouts
-- (or a screen size) the window keeps the size it has.
local function firstSize()
    if chat.SavedSize and chat.SavedSize() then return end
    local fitted = layout.ChatSize and layout.Screen and layout.Screen() and layout.ChatSize(layout.Screen()) or nil
    local width, height = _G[MAIN]:GetSize()
    if fitted then width, height = fitted.width, fitted.height end
    if chat.SetSize then chat.SetSize(width, height) end
end

local function holderSize()
    local size = chat.SavedSize and chat.SavedSize()
    if size then return size.width, size.height end
    return _G[MAIN]:GetSize()
end

local function createHolder()
    holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    chat.Holder = holder
    firstSize()
    local width, height = holderSize()
    if type(width) == "number" and type(height) == "number" then holder:SetSize(width, height) end
    local bounds = chat.SizeBounds or {}
    layout.Register(holder, KEY, nil, { label = "Chat", onUnlock = refreshLock,
        resize = chat.SetSize and { minWidth = bounds.minWidth, minHeight = bounds.minHeight, maxWidth = bounds.maxWidth,
            maxHeight = bounds.maxHeight, apply = chat.SetSize } or nil })
    hooksecurefunc(_G[MAIN], "SetPoint", onNativePoint)
end

-- The layout places the holder through the combat queue; the window follows once it is placed.
local function adopt()
    if not holder then createHolder() end
    core.Combat.Queue(anchor)
end

-- A whole-screen layout or a reset changed the saved place or size: the window follows.
function chat.Restore()
    adopt()
    if chat.ApplySize then chat.ApplySize() end
end

local function dragStart()
    if dragging or isLocked() or not layout.BeginDrag then return end
    dragging = layout.BeginDrag(KEY) == true
end

local function dragStop()
    if not dragging then return end
    dragging = false
    layout.EndDrag()
end

function chat.SetLocked(locked)
    if not layout.SetUnlocked then return nil, "The frame arrangement is unavailable." end
    if locked == true then dragStop() end
    if not layout.SetUnlocked(KEY, locked ~= true) then return nil, "Cannot unlock the chat window in combat." end
    if locked ~= true then core:Print(UNLOCKED) end
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
    if self.rest < 1 and core.Motion then core.Motion.Play(self.rikHoverFade) end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(isLocked() and TIP_LOCKED or TIP_UNLOCKED)
    GameTooltip:Show()
end

local function createLockButton()
    lockButton = CreateFrame("Button", nil, _G[MAIN])
    lockButton:SetSize(LOCK_SIZE, LOCK_SIZE)
    lockButton:SetPoint("TOPRIGHT", _G[MAIN], "TOPRIGHT", -LOCK_OFFSET, -LOCK_INSET)
    chat.Flat(lockButton, chat.Colors.field)
    lockButton.body, lockButton.shackle = lockPart(8, 5), lockPart(4, 4)
    lockButton.body:SetPoint("BOTTOM", lockButton, "BOTTOM", 0, 3)
    lockButton:RegisterForDrag("LeftButton")
    lockButton:SetScript("OnClick", function()
        local ok, reason = chat.SetLocked(not isLocked())
        if not ok and reason then core:Print(reason) end
    end)
    lockButton:SetScript("OnDragStart", dragStart)
    lockButton:SetScript("OnDragStop", dragStop)
    lockButton:SetScript("OnEnter", showLockTip)
    lockButton:SetScript("OnLeave", function(self) self:SetAlpha(self.rest); GameTooltip:Hide() end)
    _G[MAIN].rikLock = lockButton
    lockButton.rikHoverFade = core.Motion and core.Motion.Tween(lockButton, LOCK_ALPHA, 1, HOVER_FADE) or nil
    local strata = lockButton:GetFrameStrata()
    lockButton.homeStrata = type(strata) == "string" and strata or "LOW"
    refreshLock()
end

-- Forgets the saved place and size; the window goes to the default layout's place and fitted size.
function chat.ResetPosition()
    dragStop()
    core.Profile.positions[KEY] = nil
    chat.Settings().size = nil
    firstSize()
    chat.Restore()
    layout.Apply()
    core:Print(RESET)
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
    adopt()
end

core:RegisterCommand("chat", function(args)
    if not core.Profile then core:Print("Still loading."); return end
    if not chat.enabled then core:Print("The chat module is disabled."); return end
    local action = args:lower()
    local ok, reason = true, nil
    if action == "lock" then ok, reason = chat.SetLocked(true)
    elseif action == "unlock" then ok, reason = chat.SetLocked(false)
    elseif action == "reset" then chat.ResetPosition()
    else core:Print(USAGE); return end
    if not ok and reason then core:Print(reason) elseif action == "lock" then core:Print("Chat locked.") end
end, "Lock, unlock or reset the main chat window: /rik chat lock|unlock|reset")

table.insert(chat.Options.settings, { type = "checkbox", key = "locked", label = "Lock the main chat window",
    get = isLocked, set = chat.SetLocked })
