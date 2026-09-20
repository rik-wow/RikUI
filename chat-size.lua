-- Resizing the main chat window without Edit Mode. On 69913 the default chat frame's size belongs
-- to Edit Mode: Blizzard hides its ResizeButton and FCF_UpdateResizeButton never shows it again, and
-- Edit Mode writes its stored size back on every layout apply, which editmode.lua answers.
-- RikUI adds its own corner grip, visible while the window is unlocked with the padlock. The window
-- is centred on the move holder, and sizing from one corner shifts that centre, so after a drag
-- the holder is re-placed on the window and the drop saved (chat.AdoptCurrent). The size lives in
-- the profile next to the position; /rik chat reset forgets both. Nothing here is protected.
local core = RikUI
local chat = core.Chat

local MAIN = "ChatFrame1"
local GRIP_SIZE, GRIP_INSET, DOT, DOT_STEP = 14, 1, 2, 4
local MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT = 250, 120, 1200, 800
local CORNER = "BOTTOMRIGHT"
-- Three rows of dots stepping down to the corner, the usual grip shape.
local DOTS = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 1, 1 }, { 2, 1 }, { 2, 2 } }
local SETTERS = { "SetSize", "SetWidth", "SetHeight" }
local grip, sizing, applying, guarded, answered = nil, false, false, false, 0

local function validSize(size)
    if type(size) ~= "table" then return false end
    local width, height = size.width, size.height
    return type(width) == "number" and type(height) == "number" and width >= MIN_WIDTH and width <= MAX_WIDTH
        and height >= MIN_HEIGHT and height <= MAX_HEIGHT
end

function chat.ApplySize()
    local size = chat.Settings().size
    if not validSize(size) then return end
    applying = true
    local ok, reason = pcall(_G[MAIN].SetSize, _G[MAIN], size.width, size.height)
    applying = false
    if not ok then chat.Warn("size", reason) end
end

local function differs(size)
    local width, height = _G[MAIN]:GetSize()
    if type(width) ~= "number" or type(height) ~= "number" then return true end
    return math.abs(width - size.width) > 0.5 or math.abs(height - size.height) > 0.5
end

-- Whoever writes the window's size, by whatever route, is answered with the saved size. This is the
-- mechanism that keeps the window's place (chat-move.lua hooks SetPoint the same way). RikUI's own
-- write and a drag of the grip are left alone; a size set while Edit Mode is open is adopted instead.
-- A size chosen inside Edit Mode (its resize handle or its width and height sliders) is the player's
-- choice, so it becomes the saved size. Edit Mode throws an unsaved change away when it closes, and a
-- Blizzard preset layout cannot be changed at all; the revert is then answered like any other write.
local function adoptEditModeSize()
    local width, height = _G[MAIN]:GetSize()
    local size = { width = width, height = height }
    if validSize(size) then chat.Settings().size = size end
end

local function onNativeSize()
    if applying or sizing then return end
    if core.EditMode.IsActive() then return adoptEditModeSize() end
    local size = chat.Settings().size
    if not validSize(size) or not differs(size) then return end
    answered = answered + 1
    chat.ApplySize()
end

local function sizeText(width, height)
    if type(width) ~= "number" or type(height) ~= "number" then return "none" end
    return string.format("%dx%d", width, height)
end

function chat.SizeDebug()
    local size = chat.Settings().size
    local saved = validSize(size) and sizeText(size.width, size.height) or "none"
    core:Print("Chat size saved=" .. saved .. " now=" .. sizeText(_G[MAIN]:GetSize()) .. " guarded=" .. tostring(guarded)
        .. " answered=" .. answered)
end

local function start()
    if sizing or chat.Settings().locked ~= false then return end
    local frame = _G[MAIN]
    sizing = true
    frame:SetResizable(true)
    frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    frame:StartSizing(CORNER)
end

local function stop()
    if not sizing then return end
    sizing = false
    local frame = _G[MAIN]
    frame:StopMovingOrSizing()
    local width, height = frame:GetSize()
    local size = { width = width, height = height }
    if validSize(size) then chat.Settings().size = size end
    if not chat.AdoptCurrent() then chat.Warn("size", "chat window position unavailable") end
end

function chat.RefreshGrip()
    if grip then grip:SetShown(chat.Settings().locked == false) end
end

local function createGrip()
    local frame = _G[MAIN]
    grip = CreateFrame("Button", nil, frame)
    grip:SetSize(GRIP_SIZE, GRIP_SIZE)
    grip:SetPoint(CORNER, frame, CORNER, -GRIP_INSET, GRIP_INSET)
    for _, dot in ipairs(DOTS) do
        local texture = grip:CreateTexture(nil, "ARTWORK")
        texture:SetTexture(core.Media.border)
        texture:SetVertexColor(unpack(chat.Colors.selected))
        texture:SetSize(DOT, DOT)
        texture:SetPoint(CORNER, grip, CORNER, -(2 - dot[1]) * DOT_STEP, dot[2] * DOT_STEP)
    end
    grip:SetScript("OnMouseDown", start)
    grip:SetScript("OnMouseUp", stop)
    grip:SetScript("OnHide", stop)
    frame.rikGrip = grip
    chat.RefreshGrip()
end

function chat.EnableSize()
    if not chat.IsFrame(_G[MAIN]) or type(chat.AdoptCurrent) ~= "function" then return end
    createGrip()
    chat.ApplySize()
    -- The window is an Edit Mode system: every layout apply writes the size stored in the Edit Mode
    -- layout (login, a spec change, a layout switch, leaving Edit Mode). The saved size goes back
    -- after each one.
    guarded = core.EditMode.Guard(_G[MAIN], "chat size", chat.ApplySize)
    for _, setter in ipairs(SETTERS) do
        if type(_G[MAIN][setter]) == "function" then hooksecurefunc(_G[MAIN], setter, onNativeSize) end
    end
    core:RegisterEvent("PLAYER_ENTERING_WORLD", chat.ApplySize)
end
