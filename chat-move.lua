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
local LOCK_SIZE, LOCK_OFFSET, LOCK_INSET, LOCK_ALPHA, LOCK_ICON = 16, 20, 2, 0.35, 10
local LOCKED_COLOR, UNLOCKED_COLOR = { 1, 1, 1 }, { 1, 0.78, 0.3 }
-- The overlay of an unlocked group is a DIALOG frame over the whole window; the open padlock sits above it.
local OPEN_STRATA = "FULLSCREEN_DIALOG"
local HOVER_FADE = 0.12
local holder, lockButton, anchoring, dragging, clamping = nil, nil, false, false, false

local NO_FOOTPRINT = { left = 0, right = 0, top = 0, bottom = 0 }

local function isLocked() return not (layout.IsUnlocked and layout.IsUnlocked(KEY)) end

-- What surrounds the message area: the panel's border, the tabs above, the channel strip and the input
-- bar below. The layouts data holds the numbers, because it places the chat by its whole rectangle.
function chat.Footprint()
    return core.Layouts and core.Layouts.ChatFootprint or NO_FOOTPRINT
end

-- The holder's size for a window of this size.
function chat.HolderSize(width, height)
    local foot = chat.Footprint()
    return width + foot.left + foot.right, height + foot.top + foot.bottom
end

local function anchor()
    local frame = _G[MAIN]
    anchoring = true
    local ok, reason = pcall(function()
        local foot = chat.Footprint()
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", holder, "TOPLEFT", foot.left, -foot.top)
    end)
    anchoring = false
    if not ok then chat.Warn("move", reason) end
end

-- Edit Mode re-anchors its systems whenever a layout is applied; the window goes back on the holder.
local function onNativePoint()
    if holder and not anchoring then anchor() end
end

-- Edit Mode sets the window's screen clamp from its selection box (EditModeSystemMixin:UpdateClampOffsets),
-- which is larger than the window: it reserves the button column on the left, the tabs and the edit box.
-- The client then keeps the window that far from the screen edge, so it cannot be moved there and no
-- longer stands where its holder and overlay are. The layout engine keeps the chat on screen itself.
local function freeClamp()
    local frame = _G[MAIN]
    if clamping then return end
    clamping = true
    local ok, reason = pcall(function()
        if type(frame.SetClampRectInsets) == "function" then frame:SetClampRectInsets(0, 0, 0, 0) end
        -- Zero insets were not enough in game: after a reload the window still stood away from a holder
        -- that was flush in the corner. The layout engine keeps the chat on screen, so the client's own
        -- clamping is switched off altogether.
        if type(frame.SetClampedToScreen) == "function" then frame:SetClampedToScreen(false) end
    end)
    clamping = false
    if not ok then chat.Warn("clamp", reason) end
end

local function number(value) return type(value) == "number" and string.format("%d", math.floor(value + 0.5)) or "?" end

-- Where the holder and the window really stand; the offset between them should be the footprint.
function chat.PlaceDebug()
    local frame, saved = _G[MAIN], core.Profile.positions[KEY]
    if not holder then return core:Print("Chat place holder=none") end
    local left, bottom, windowLeft, windowBottom = holder:GetLeft(), holder:GetBottom(), frame:GetLeft(), frame:GetBottom()
    local both = type(left) == "number" and type(windowLeft) == "number" and type(bottom) == "number"
        and type(windowBottom) == "number"
    local insets = type(frame.GetClampRectInsets) == "function" and { frame:GetClampRectInsets() } or {}
    core:Print("Chat place holder=" .. number(left) .. "," .. number(bottom) .. " window=" .. number(windowLeft) .. ","
        .. number(windowBottom) .. " offset=" .. (both and number(windowLeft - left) .. "," .. number(windowBottom - bottom) or "?")
        .. " saved=" .. (type(saved) == "table" and saved.point .. " " .. number(saved.x) .. "," .. number(saved.y) or "none")
        .. " clamped=" .. tostring(type(frame.IsClampedToScreen) == "function" and frame:IsClampedToScreen())
        .. " insets=" .. number(insets[1]) .. "," .. number(insets[2]) .. "," .. number(insets[3]) .. "," .. number(insets[4]))
end

-- The padlock icon: closed and white when locked, open and gold when unlocked.
local function refreshLock()
    if not lockButton then return end
    local locked = isLocked()
    local color = locked and LOCKED_COLOR or UNLOCKED_COLOR
    core.Media.SetIcon(lockButton.icon, locked and "lock" or "lock-open")
    lockButton.icon:SetVertexColor(color[1], color[2], color[3])
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

-- The arrangement system resizes the whole rectangle; the window takes what is left inside it.
local function resizeOption()
    local bounds, foot = chat.SizeBounds or {}, chat.Footprint()
    local wide, tall = foot.left + foot.right, foot.top + foot.bottom
    return { minWidth = bounds.minWidth + wide, minHeight = bounds.minHeight + tall, maxWidth = bounds.maxWidth + wide,
        maxHeight = bounds.maxHeight + tall, apply = function(width, height) return chat.SetSize(width - wide, height - tall) end }
end

local function createHolder()
    holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    chat.Holder = holder
    firstSize()
    local width, height = holderSize()
    if type(width) == "number" and type(height) == "number" then holder:SetSize(chat.HolderSize(width, height)) end
    layout.Register(holder, KEY, nil, { label = "Chat", onUnlock = refreshLock, resize = chat.SetSize and resizeOption() or nil })
    hooksecurefunc(_G[MAIN], "SetPoint", onNativePoint)
    for _, method in ipairs({ "SetClampRectInsets", "SetClampedToScreen" }) do
        if type(_G[MAIN][method]) == "function" then hooksecurefunc(_G[MAIN], method, freeClamp) end
    end
    freeClamp()
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
    lockButton.icon = core.Media.Icon(lockButton, "lock", LOCK_ICON, "ARTWORK")
    lockButton.icon:SetPoint("CENTER", lockButton, "CENTER", 0, 0)
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
    core:Changed()
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
