-- Finding your way in the scrollback. A flat button fades in at a window's bottom-right corner as
-- soon as it is scrolled up and counts the lines that arrive meanwhile; a click returns to the
-- newest line. Blizzard's wheel handler only scrolls one line, so Ctrl-wheel (jump to either end)
-- and Shift-wheel (page) are added beside it. Every scroll and every new line marks the window's
-- display dirty, and the window calls its display-refreshed callbacks after redrawing, so one such
-- callback keeps the button in step with key bindings and Blizzard's buttons too. The window's own
-- methods are never hooked: on 69977 that left them nil for Blizzard's callers.
local core, media, motion = RikUI, RikUI.Media, RikUI.Motion
local chat = core.Chat

local HEIGHT, MIN_WIDTH, INSET, PAD = 18, 22, 4, 6
local ICON, ICON_SIZE, ICON_GAP, FADE_SECONDS = "chevron-down", 10, 3, 0.15
local unread, seen = {}, {}

local function enabled() return chat.Settings().jumpButton ~= false end

local function atBottom(frame)
    if type(frame.AtBottom) ~= "function" then return true end
    local ok, bottom = pcall(frame.AtBottom, frame)
    return not ok or bottom ~= false
end

-- The count can reach three digits; the button grows with its text.
local function label(frame)
    local button, count = frame.rikJump, unread[frame] or 0
    button.label:SetText(count > 0 and tostring(count) or "")
    local width = type(button.label.GetStringWidth) == "function" and button.label:GetStringWidth() or nil
    local text = count > 0 and (type(width) == "number" and width or 0) + ICON_GAP or 0
    button:SetWidth(math.max(MIN_WIDTH, ICON_SIZE + text + 2 * PAD))
end

local function refresh(frame)
    local button = frame.rikJump
    if not button then return end
    local wanted = enabled() and not atBottom(frame)
    if not wanted then unread[frame] = 0 end
    label(frame)
    if wanted == button:IsShown() then return end
    button:SetShown(wanted)
    if wanted then motion.Play(button.fade) end
end

-- Lines that arrived since the last redraw count as unread while the window is scrolled up.
local function onRefreshed(frame)
    local count, newest = chat.NewLines(frame, seen[frame])
    seen[frame] = newest
    if count > 0 and frame.rikJump and not atBottom(frame) then unread[frame] = (unread[frame] or 0) + count end
    refresh(frame)
end

local function onWheel(frame, delta)
    if type(delta) ~= "number" then return end
    local up = delta > 0
    if type(IsControlKeyDown) == "function" and IsControlKeyDown() then
        if up then frame:ScrollToTop() else frame:ScrollToBottom() end
    elseif IsShiftKeyDown() then
        if up then frame:PageUp() else frame:PageDown() end
    end
end

local function createButton(frame)
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(MIN_WIDTH, HEIGHT)
    button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -INSET, INSET)
    chat.Flat(button, chat.Colors.field)
    button.icon = media.Icon(button, ICON, ICON_SIZE, "OVERLAY")
    button.icon:SetPoint("LEFT", button, "LEFT", PAD, 0)
    button.label = button:CreateFontString(nil, "OVERLAY")
    media.Font(button.label, "small")
    button.label:SetPoint("LEFT", button.icon, "RIGHT", ICON_GAP, 0)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(button)
    highlight:SetTexture(media.highlight)
    button.fade = motion.Tween(button, 0, 1, FADE_SECONDS)
    button:SetScript("OnClick", function() frame:ScrollToBottom() end)
    button:Hide()
    frame.rikJump = button
end

local function hookFrame(frame)
    createButton(frame)
    seen[frame] = select(2, chat.NewLines(frame, nil))
    if type(frame.AddOnDisplayRefreshedCallback) == "function" then
        frame:AddOnDisplayRefreshedCallback(onRefreshed)
    else
        chat.Warn("scroll", "display refresh callbacks unavailable on this client")
    end
    core.Hooks.Script(frame, "OnMouseWheel", onWheel)
    refresh(frame)
end

function chat.SetJumpButton(value)
    chat.Settings().jumpButton = value == true
    for frame in pairs(chat.Frames) do refresh(frame) end
    return true
end

function chat.EnableScroll()
    for frame in pairs(chat.Frames) do hookFrame(frame) end
end

table.insert(chat.Options.settings, { type = "checkbox", key = "jumpButton", label = "Jump-to-newest button when scrolled up",
    get = enabled, set = chat.SetJumpButton })
