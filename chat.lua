-- Chat cleanup: the RikUI font on every chat frame and edit box, Blizzard's side buttons and scroll
-- controls parked through the shared hide helper, a flat edit box docked under the frame, the
-- showTimestamps setting owned by a profile flag, tabs faded until hovered and a copy button per
-- frame. chat-copy.lua owns the copy window and the address links. Only the parent writes are
-- protected, and those run through the hide helper's combat queue.
local core, media, unitframes = RikUI, RikUI.Media, RikUI.UnitFrames
local chat = { Parked = {}, Frames = {}, Options = { title = "Chat", settings = {} } }
core.Chat = chat

local MAX_WINDOWS, FONT_FLAGS, SHADOW = 10, "", { 0, 0, 0, 1 }
local SIZE_MIN, SIZE_MAX, SIZE_FUNCTION = 10, 24, "FCF_SetChatWindowFontSize"
local EDIT_HEIGHT, EDIT_GAP, PANEL_GAP, EDGE = 24, 4, 2, 1
-- The one palette every chat piece draws from: panel fill, control fill, border, selected border.
chat.Colors = { background = { 0.055, 0.065, 0.08, 0.95 }, field = { 0.1, 0.11, 0.13, 1 },
    border = { 0.25, 0.28, 0.32, 1 }, selected = { 1, 0.78, 0.3, 1 } }
local COPY_SIZE, COPY_GLYPH, COPY_GLYPH_INSET, COPY_INSET, COPY_ALPHA = 16, 7, 3, 2, 0.35
local TIMESTAMP_CVAR, TIMESTAMP_FORMAT, TIMESTAMP_OFF = "showTimestamps", "%H:%M ", "none"
-- FCFTab_UpdateAlpha reads these globals on every refresh; alerting tabs keep their own alpha.
local NO_MOUSE_ALPHAS = { "CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA", "CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA" }
local SIDE_BUTTONS = { "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
    "TextToSpeechButtonFrame", "QuickJoinToastButton" }
-- parentKeys of FloatingChatFrameTemplate on 69913; ChatFrameMenuButton lives inside ChatFrame1's buttonFrame.
local FRAME_CONTROLS = { "buttonFrame", "ScrollBar", "ScrollToBottomButton" }
local EDIT_ART, EDIT_FOCUS = { "Left", "Mid", "Right" }, { "focusLeft", "focusMid", "focusRight" }
local TAB_ART = { "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight",
    "HighlightLeft", "HighlightMiddle", "HighlightRight" }
-- The other chat files, in the order they start. History comes first: raising the scrollback
-- clears a window, and restored lines must land before the line and scroll hooks exist.
local ENABLERS = { "EnableLinks", "EnableMove", "EnableHistory", "EnableLines", "EnableScroll", "EnableSize", "EnableInput" }
local warnings = {}

function chat.Warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Chat " .. operation .. ": " .. tostring(reason))
end

local function hasMethod(value, method)
    local kind = type(value)
    return (kind == "table" or kind == "userdata") and type(value[method]) == "function"
end

function chat.IsFrame(value) return hasMethod(value, "SetParent") end

function chat.Settings() return core.Profile.chat end

-- Blizzard toggles the focus art with SetShown, so alpha is the write that lasts.
local function fade(region)
    if hasMethod(region, "SetAlpha") then region:SetAlpha(0) end
end

-- Flat fill and one-pixel border, the look of every RikUI window and control.
function chat.Flat(frame, fill)
    frame.rikBackground = frame:CreateTexture(nil, "BACKGROUND")
    frame.rikBackground:SetAllPoints()
    frame.rikBackground:SetColorTexture(unpack(fill))
    frame.rikBorder = unitframes.Edges(frame, EDGE, "BORDER")
    for _, line in ipairs(frame.rikBorder) do line:SetVertexColor(unpack(chat.Colors.border)) end
end

local function applyFont(target)
    if not hasMethod(target, "SetFont") then return end
    target:SetFont(media.font, chat.Settings().fontSize, FONT_FLAGS)
    target:SetShadowColor(unpack(SHADOW))
    target:SetShadowOffset(1, -1)
end

function chat.ApplyFonts()
    applyFont(ChatFontNormal) -- the edit box header and prompt inherit this object
    for frame in pairs(chat.Frames) do
        applyFont(frame)
        applyFont(frame.editBox)
    end
end

local function validSize(size)
    return type(size) == "number" and size >= SIZE_MIN and size <= SIZE_MAX
end

-- Blizzard's function also saves the size with the chat window settings.
function chat.SetFontSize(size)
    if not validSize(size) then return nil, "Chat font size must be between " .. SIZE_MIN .. " and " .. SIZE_MAX .. "." end
    chat.Settings().fontSize = size
    local native = _G[SIZE_FUNCTION]
    for frame in pairs(chat.Frames) do
        if type(native) == "function" then pcall(native, nil, frame, size) end
    end
    chat.ApplyFonts()
    return true
end

-- Post-hook: Blizzard has kept the font file and changed the size, from its tab menu or from us.
local function rememberSize(_, frame, size)
    if not chat.Frames[frame] or not validSize(size) then return end
    chat.Settings().fontSize = size
    applyFont(frame)
end

local function park(frame)
    if chat.IsFrame(frame) and core.Hide.Frame(frame, false) then chat.Parked[#chat.Parked + 1] = frame end
end

local function flattenEditBox(frame)
    local box = frame.editBox
    if not chat.IsFrame(box) then return end
    local name = box:GetName()
    for _, key in ipairs(EDIT_ART) do fade(name and _G[name .. key]) end
    for _, key in ipairs(EDIT_FOCUS) do fade(box[key]) end
    chat.Flat(box, chat.Colors.background)
    -- Under the window's panel when the skin file made one, so both share their left and right edge.
    local anchor, gap = frame.rikPanel or frame, frame.rikPanel and PANEL_GAP or EDIT_GAP
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
    box:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -gap)
    box:SetHeight(EDIT_HEIGHT)
end

local function skinTab(frame)
    local tab = _G[frame:GetName() .. "Tab"]
    if not chat.IsFrame(tab) then return end
    for _, key in ipairs(TAB_ART) do fade(tab[key]) end
    if hasMethod(tab.Text, "SetFont") then media.Font(tab.Text, "small") end
end

local function fadeTabs()
    for _, name in ipairs(NO_MOUSE_ALPHAS) do _G[name] = 0 end
    if type(FCFTab_UpdateAlpha) ~= "function" then return end
    for frame in pairs(chat.Frames) do
        local ok, reason = pcall(FCFTab_UpdateAlpha, frame)
        if not ok then chat.Warn("tabs", reason) end
    end
end

-- Two offset squares: the usual copy glyph without shipping another texture.
local function copyGlyph(button, point)
    local square = button:CreateTexture(nil, "ARTWORK")
    square:SetTexture(media.border)
    local inset = point == "TOPLEFT" and COPY_GLYPH_INSET or -COPY_GLYPH_INSET
    square:SetSize(COPY_GLYPH, COPY_GLYPH)
    square:SetPoint(point, button, point, inset, -inset)
    return square
end

local function addCopyButton(frame)
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(COPY_SIZE, COPY_SIZE)
    button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -COPY_INSET, -COPY_INSET)
    chat.Flat(button, chat.Colors.field)
    button:SetAlpha(COPY_ALPHA)
    button.back, button.front = copyGlyph(button, "TOPLEFT"), copyGlyph(button, "BOTTOMRIGHT")
    button:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    button:SetScript("OnLeave", function(self) self:SetAlpha(COPY_ALPHA) end)
    button:SetScript("OnClick", function() chat.OpenCopy(frame) end)
    frame.rikCopy = button
end

local function readTimestamps()
    if type(C_CVar) ~= "table" or type(C_CVar.GetCVar) ~= "function" then return nil end
    local ok, value = pcall(C_CVar.GetCVar, TIMESTAMP_CVAR)
    if not ok or type(value) ~= "string" then return nil end
    return value
end

-- A format the player picked in Blizzard's options counts as "on" and is left alone.
function chat.ApplyTimestamps()
    local wanted, current = chat.Settings().timestamps ~= false, readTimestamps()
    if current == nil or type(C_CVar.SetCVar) ~= "function" then
        chat.Warn("timestamps", TIMESTAMP_CVAR .. " unavailable on this client")
        return
    end
    if wanted == (current ~= TIMESTAMP_OFF) then return end
    local ok, accepted = pcall(C_CVar.SetCVar, TIMESTAMP_CVAR, wanted and TIMESTAMP_FORMAT or TIMESTAMP_OFF)
    if not ok or accepted == false then chat.Warn("timestamps", ok and "setting rejected" or accepted) end
end

function chat.SetTimestamps(enabled)
    chat.Settings().timestamps = enabled == true
    chat.ApplyTimestamps()
    return true
end

local function setupFrame(frame)
    chat.Frames[frame] = true
    if chat.SkinFrame then chat.SkinFrame(frame) end
    for _, key in ipairs(FRAME_CONTROLS) do park(frame[key]) end
    flattenEditBox(frame)
    skinTab(frame)
    addCopyButton(frame)
end

function chat:OnEnable()
    if not chat.IsFrame(ChatFrame1) then
        chat.Warn("frames", "ChatFrame1 unavailable on this client")
        return
    end
    for id = 1, NUM_CHAT_WINDOWS or MAX_WINDOWS do
        local frame = _G["ChatFrame" .. id]
        if chat.IsFrame(frame) then setupFrame(frame) end
    end
    for _, name in ipairs(SIDE_BUTTONS) do park(_G[name]) end
    chat.ApplyFonts()
    fadeTabs()
    chat.ApplyTimestamps()
    if type(_G[SIZE_FUNCTION]) == "function" then hooksecurefunc(SIZE_FUNCTION, rememberSize) end
    for _, name in ipairs(ENABLERS) do
        if chat[name] then chat[name]() end
    end
end

local function frameCount()
    local total = 0
    for _ in pairs(chat.Frames) do total = total + 1 end
    return total
end

function chat:Debug(sample)
    core:Print("Chat frames=" .. frameCount() .. " parked=" .. #chat.Parked .. " links=" .. tostring(chat.LinksReady == true))
    sample("GetCVar(" .. TIMESTAMP_CVAR .. ")", function() return C_CVar.GetCVar(TIMESTAMP_CVAR) end)
end

table.insert(chat.Options.settings, { type = "slider", key = "fontSize", label = "Font size",
    min = SIZE_MIN, max = SIZE_MAX, step = 1,
    get = function() return chat.Settings().fontSize end, set = chat.SetFontSize })
table.insert(chat.Options.settings, { type = "checkbox", key = "timestamps", label = "Timestamps on chat lines",
    get = function() return chat.Settings().timestamps ~= false end, set = chat.SetTimestamps })

core:RegisterModule("chat", chat)
