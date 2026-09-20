-- The flat look around Blizzard's chat windows: one bordered panel behind each window, flat tab
-- boxes with a gold border on the selected tab, and Blizzard's own window background and rounded
-- border gone. Everything draws from chat.Colors through chat.Flat, the same fill and one-pixel
-- border as the bags, the tooltip and the minimap. Motion is only ever put on RikUI's own regions:
-- the panel fades in at login, a tab's highlight fades in under the cursor, and the selected tab gets
-- a gold underline that fades in. Blizzard fades the tabs and its own textures itself. Colours are
-- written with three components, because the fourth component of SetVertexColor is the alpha here.
-- Nothing here is protected.
local core, media, motion = RikUI, RikUI.Media, RikUI.Motion
local chat = core.Chat

-- The window part of CHAT_FRAME_TEXTURES. FCF_FadeInChatFrame fades every listed texture that is
-- shown back in on hover, so an alpha write would not last; a hidden texture is skipped.
local FRAME_ART = { "Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
    "LeftTexture", "RightTexture", "BottomTexture", "TopTexture" }
local PANEL_PAD = 4
-- ChatTabTemplate is 32 high with its label in the lower half; the box frames the label.
local TAB_LEFT, TAB_RIGHT, TAB_TOP, TAB_BOTTOM = 2, -2, -11, 2
local COLOR_HOOK = "FCFTab_UpdateColors"
local FLAT = "Interface\\BUTTONS\\WHITE8X8"
local PANEL_FADE, HOVER_FADE, HOVER_TINT, HOVER_ALPHA = 0.25, 0.12, { 0.3, 0.75, 1 }, 0.35
local UNDERLINE_HEIGHT, UNDERLINE_INSET = 2, 1
local tabs, hooked = {}, false

local function hideArt(frame)
    local name = frame:GetName()
    if not name then return end
    for _, key in ipairs(FRAME_ART) do
        local art = _G[name .. key]
        if type(art) == "table" and type(art.Hide) == "function" then art:Hide() end
    end
end

local function createPanel(frame)
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", -PANEL_PAD, PANEL_PAD)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", PANEL_PAD, -PANEL_PAD)
    panel:SetFrameLevel(math.max(0, (frame:GetFrameLevel() or 1) - 1))
    chat.Flat(panel, chat.Colors.background)
    panel.fade = motion.Tween(panel, 0, 1, PANEL_FADE)
    if chat.Settings().panel == false then panel:Hide() else motion.Play(panel.fade) end
    frame.rikPanel = panel
end

-- The underline fades in when the tab becomes the selected one, not on every colour refresh.
local function underline(tab, selected)
    local line = tab.rikUnderline
    if not line or (tab.rikSelected == true) == selected then return end
    tab.rikSelected = selected
    line:SetAlpha(selected and 1 or 0)
    if selected then motion.Play(line.fade) end
end

local function tintTab(tab, selected)
    local color = selected and chat.Colors.selected or chat.Colors.border
    for _, line in ipairs(tab.rikBorder) do line:SetVertexColor(color[1], color[2], color[3]) end
    underline(tab, selected)
end

local function addHover(tab, box)
    local hover = box:CreateTexture(nil, "ARTWORK")
    hover:SetAllPoints(box)
    hover:SetTexture(media.highlight)
    hover:SetVertexColor(HOVER_TINT[1], HOVER_TINT[2], HOVER_TINT[3])
    hover:SetAlpha(0)
    hover.fade = motion.Tween(hover, 0, HOVER_ALPHA, HOVER_FADE)
    tab.rikHover = hover
    tab:HookScript("OnEnter", function()
        hover:SetAlpha(HOVER_ALPHA)
        motion.Play(hover.fade)
    end)
    tab:HookScript("OnLeave", function() hover:SetAlpha(0) end)
end

local function addUnderline(tab, box)
    local line, gold = box:CreateTexture(nil, "OVERLAY"), chat.Colors.selected
    line:SetTexture(FLAT)
    line:SetVertexColor(gold[1], gold[2], gold[3])
    line:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", UNDERLINE_INSET, UNDERLINE_INSET)
    line:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -UNDERLINE_INSET, UNDERLINE_INSET)
    line:SetHeight(UNDERLINE_HEIGHT)
    line:SetAlpha(0)
    line.fade = motion.Tween(line, 0, 1, PANEL_FADE)
    tab.rikUnderline = line
end

-- Blizzard recolours a tab whenever the selection changes; the border follows.
local function onTabColors(tab, selected)
    if tabs[tab] then tintTab(tab, selected == true) end
end

local function skinTab(frame)
    local tab = _G[frame:GetName() .. "Tab"]
    if not chat.IsFrame(tab) or tabs[tab] then return end
    local box = CreateFrame("Frame", nil, tab)
    box:SetPoint("TOPLEFT", tab, "TOPLEFT", TAB_LEFT, TAB_TOP)
    box:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", TAB_RIGHT, TAB_BOTTOM)
    box:SetFrameLevel(math.max(0, (tab:GetFrameLevel() or 1) - 1))
    chat.Flat(box, chat.Colors.field)
    tab.rikBox, tab.rikBorder, tabs[tab] = box, box.rikBorder, true
    addHover(tab, box)
    addUnderline(tab, box)
    local label = tab.Text
    if type(label) == "table" and type(label.SetPoint) == "function" then
        label:ClearAllPoints()
        label:SetPoint("CENTER", box, "CENTER", 0, 0)
    end
end

function chat.SkinFrame(frame)
    hideArt(frame)
    createPanel(frame)
    skinTab(frame)
    if hooked or type(_G[COLOR_HOOK]) ~= "function" then return end
    hooked = true
    hooksecurefunc(COLOR_HOOK, onTabColors)
end

function chat.SetPanel(shown)
    chat.Settings().panel = shown == true
    for frame in pairs(chat.Frames) do
        local panel = frame.rikPanel
        if panel then
            if shown == true then panel:Show() else panel:Hide() end
        end
    end
    return true
end

table.insert(chat.Options.settings, { type = "checkbox", key = "panel", label = "Panel behind the chat window",
    get = function() return chat.Settings().panel ~= false end, set = chat.SetPanel })
