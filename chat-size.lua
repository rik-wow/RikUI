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
local grip, sizing = nil, false

local function validSize(size)
    if type(size) ~= "table" then return false end
    local width, height = size.width, size.height
    return type(width) == "number" and type(height) == "number" and width >= MIN_WIDTH and width <= MAX_WIDTH
        and height >= MIN_HEIGHT and height <= MAX_HEIGHT
end

function chat.ApplySize()
    local size = chat.Settings().size
    if not validSize(size) then return end
    local ok, reason = pcall(_G[MAIN].SetSize, _G[MAIN], size.width, size.height)
    if not ok then chat.Warn("size", reason) end
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
    core.EditMode.Guard(_G[MAIN], "chat size", chat.ApplySize)
    core:RegisterEvent("PLAYER_ENTERING_WORLD", chat.ApplySize)
end
