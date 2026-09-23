-- The main chat window's size belongs to RikUI. On 69913 the default chat frame is an Edit Mode
-- system: Edit Mode writes its stored size on every layout apply. RikUI keeps the size in the profile,
-- resizes through the arrangement system's grip (src/layout/layout-resize.lua calls chat.SetSize) and answers
-- every foreign write of the window's size with the saved one. The move holder (src/modules/chat/chat-move.lua) is
-- kept the same size as the window, so the layout sees the chat's real rectangle. Nothing here is
-- protected.
local core = RikUI
local chat = core.Chat

local MAIN = "ChatFrame1"
chat.SizeBounds = { minWidth = 250, minHeight = 120, maxWidth = 1200, maxHeight = 800 }
local bounds = chat.SizeBounds
local applying, guarded, answered = false, false, 0

local function validSize(size)
    if type(size) ~= "table" then return false end
    local width, height = size.width, size.height
    return type(width) == "number" and type(height) == "number" and width >= bounds.minWidth
        and width <= bounds.maxWidth and height >= bounds.minHeight and height <= bounds.maxHeight
end

-- The saved size, or nil when none was chosen yet.
function chat.SavedSize()
    local size = chat.Settings().size
    return validSize(size) and size or nil
end

function chat.ApplySize()
    local size = chat.SavedSize()
    if not size then return end
    applying = true
    local ok, reason = pcall(_G[MAIN].SetSize, _G[MAIN], size.width, size.height)
    applying = false
    if not ok then chat.Warn("size", reason) end
    if not chat.Holder then return end
    if chat.HolderSize then chat.Holder:SetSize(chat.HolderSize(size.width, size.height))
    else chat.Holder:SetSize(size.width, size.height) end
end

-- The arrangement system's grip and the whole-screen layouts set the size through here.
function chat.SetSize(width, height)
    local size = { width = width, height = height }
    if not validSize(size) then return false end
    chat.Settings().size = size
    chat.ApplySize()
    core:Changed()
    return true
end

local function differs(size)
    local width, height = _G[MAIN]:GetSize()
    if type(width) ~= "number" or type(height) ~= "number" then return true end
    return math.abs(width - size.width) > 0.5 or math.abs(height - size.height) > 0.5
end

-- A size chosen inside Edit Mode (its resize handle or its sliders) is still the player's choice, so
-- it becomes the saved size instead of being fought. Edit Mode throws an unsaved change away when it
-- closes; that revert is then answered like any other foreign write.
local function adoptEditModeSize()
    local width, height = _G[MAIN]:GetSize()
    if chat.SetSize(width, height) and core.Layout.Settle then core.Layout.Settle("chat") end
end

-- Whoever writes the window's size, by whatever route, is answered with the saved size.
local function onNativeSize()
    if applying then return end
    if core.EditMode.IsActive() then return adoptEditModeSize() end
    local size = chat.SavedSize()
    if not size or not differs(size) then return end
    answered = answered + 1
    chat.ApplySize()
end

local function sizeText(width, height)
    if type(width) ~= "number" or type(height) ~= "number" then return "none" end
    return string.format("%dx%d", width, height)
end

function chat.SizeDebug()
    local size = chat.SavedSize()
    core:Print("Chat size saved=" .. (size and sizeText(size.width, size.height) or "none") .. " now="
        .. sizeText(_G[MAIN]:GetSize()) .. " guarded=" .. tostring(guarded) .. " answered=" .. answered)
end

-- Size writes are seen through OnSizeChanged, never through hooks on the window's setters: on 69977
-- a method hook on a Blizzard frame left the method nil for Blizzard's own callers.
function chat.EnableSize()
    if not chat.IsFrame(_G[MAIN]) then return end
    chat.ApplySize()
    guarded = core.EditMode.Guard(_G[MAIN], "chat size", chat.ApplySize)
    core.Hooks.Script(_G[MAIN], "OnSizeChanged", onNativeSize)
    core:RegisterEvent("PLAYER_ENTERING_WORLD", chat.ApplySize)
end
