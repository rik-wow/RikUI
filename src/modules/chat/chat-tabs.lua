-- Tabs that stay visible, with an unread dot. src/modules/chat/chat.lua zeroes the no-mouse tab alphas so tabs fade
-- out with the window; with this option on they are set to 1 (selected) and 0.6 instead, and back
-- to zero when it is switched off. A docked window that receives a line while another tab is shown
-- gets a gold dot on its tab, pulsing when the line was a whisper, cleared when the window shows.
-- The combat log window receives lines all the time and gets no dot.
local core, media, motion = RikUI, RikUI.Media, RikUI.Motion
local chat = core.Chat

local SELECTED_ALPHA, NORMAL_ALPHA, HIDDEN_ALPHA = 1, 0.6, 0
local ALPHA_GLOBALS = { CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA = SELECTED_ALPHA, CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA = NORMAL_ALPHA }
local DOT_SIZE, DOT_INSET, PULSE_LOW, PULSE_SECONDS, COMBAT_LOG_ID = 5, 3, 0.25, 0.6, 2
local WHISPERS = { CHAT_MSG_WHISPER = true, CHAT_MSG_BN_WHISPER = true }
local tabs = {}

local function enabled() return chat.Settings().tabsVisible ~= false end

local function applyAlphas()
    local visible = enabled()
    for name, alpha in pairs(ALPHA_GLOBALS) do _G[name] = visible and alpha or HIDDEN_ALPHA end
    if type(FCFTab_UpdateAlpha) ~= "function" then return end
    for frame in pairs(chat.Frames) do
        local ok, reason = pcall(FCFTab_UpdateAlpha, frame)
        if not ok then chat.Warn("tabs", reason) end
    end
end

local function clear(frame)
    local tab = tabs[frame]
    if not tab then return end
    motion.Stop(tab.rikPulse)
    tab.rikDot:Hide()
end

local function onMessage(frame, _, _, _, _, _, _, _, event)
    local tab = tabs[frame]
    if not tab or not enabled() or frame:IsShown() then return end
    tab.rikDot:Show()
    if WHISPERS[event] and not (tab.rikPulse and tab.rikPulse:IsPlaying()) then motion.Play(tab.rikPulse) end
end

local function addDot(frame)
    local tab = _G[frame:GetName() .. "Tab"]
    if not chat.IsFrame(tab) or frame:GetID() == COMBAT_LOG_ID then return end
    local anchor = tab.rikBox or tab
    tab.rikDot = tab:CreateTexture(nil, "OVERLAY")
    tab.rikDot:SetTexture(media.border)
    tab.rikDot:SetVertexColor(unpack(chat.Colors.selected))
    tab.rikDot:SetSize(DOT_SIZE, DOT_SIZE)
    tab.rikDot:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -DOT_INSET, -DOT_INSET)
    tab.rikDot:Hide()
    tab.rikPulse = motion.Pulse(tab.rikDot, 1, PULSE_LOW, PULSE_SECONDS)
    tabs[frame] = tab
    if type(frame.AddMessage) == "function" then hooksecurefunc(frame, "AddMessage", onMessage) end
    frame:HookScript("OnShow", clear)
end

function chat.SetTabsVisible(value)
    chat.Settings().tabsVisible = value == true
    applyAlphas()
    if value ~= true then
        for frame in pairs(tabs) do clear(frame) end
    end
    return true
end

function chat.EnableTabs()
    for frame in pairs(chat.Frames) do addDot(frame) end
    applyAlphas()
end

table.insert(chat.Options.settings, { type = "checkbox", key = "tabsVisible", label = "Keep tabs visible, with unread dots",
    get = enabled, set = chat.SetTabsVisible })
