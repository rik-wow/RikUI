-- The flat look around Blizzard's chat windows: one bordered panel behind each window, flat tab
-- boxes with a gold border on the selected tab, and Blizzard's own window background and rounded
-- border gone. Everything draws from chat.Colors through chat.Flat, the same fill and one-pixel
-- border as the bags, the tooltip and the minimap. Nothing here is protected.
local core = RikUI
local chat = core.Chat

-- The window part of CHAT_FRAME_TEXTURES. FCF_FadeInChatFrame fades every listed texture that is
-- shown back in on hover, so an alpha write would not last; a hidden texture is skipped.
local FRAME_ART = { "Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
    "LeftTexture", "RightTexture", "BottomTexture", "TopTexture" }
local PANEL_PAD = 4
-- ChatTabTemplate is 32 high with its label in the lower half; the box frames the label.
local TAB_LEFT, TAB_RIGHT, TAB_TOP, TAB_BOTTOM = 2, -2, -11, 2
local COLOR_HOOK = "FCFTab_UpdateColors"
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
    if chat.Settings().panel == false then panel:Hide() end
    frame.rikPanel = panel
end

local function tintTab(tab, selected)
    local color = selected and chat.Colors.selected or chat.Colors.border
    for _, line in ipairs(tab.rikBorder) do line:SetVertexColor(color[1], color[2], color[3], 1) end
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
