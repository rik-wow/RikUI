-- One-click channel switching and an edit box that shows where you are typing. The strip replaces
-- the chat menu button RikUI parks. A click goes through Blizzard's own entry points: OpenChat
-- with no text activates the right edit box and leaves what is typed alone, then the edit box's
-- SetChatType, SetChannelTarget and UpdateHeader do the switch; reply is ReplyTell. Nothing is
-- ever sent. UpdateHeader is the one place the active channel changes, so a post-hook on it drives
-- the edit box colour and the selected mark. Docked windows hide each other, so the strip belongs
-- to the screen and is only anchored to the main window; nothing here is protected.
local core, media = RikUI, RikUI.Media
local chat = core.Chat
chat.Strip = { Buttons = {} }

local MAIN, HOLDER_NAME = "ChatFrame1", "RikUIChatStrip"
local HEIGHT, BUTTON_WIDTH, GAP, PANEL_GAP, EDIT_GAP = 18, 20, 2, 2, 2
local REST_ALPHA = 0.75
local REPLY, CHANNEL = "REPLY", "CHANNEL"
local REFRESH_EVENTS = { "GROUP_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "CHAT_MSG_CHANNEL_NOTICE", "PLAYER_ENTERING_WORLD" }
local holder, pool, hooked, activeBox = nil, {}, {}, nil

local function ask(name)
    local reader = _G[name]
    if type(reader) ~= "function" then return false end
    local ok, value = pcall(reader)
    return ok and value == true
end

local function isOfficer()
    local info = C_GuildInfo
    if not ask("IsInGuild") or type(info) ~= "table" or type(info.IsGuildOfficer) ~= "function" then return false end
    local ok, value = pcall(info.IsGuildOfficer)
    return ok and value == true
end

local ENTRIES = {
    { key = "SAY", label = "S" }, { key = "YELL", label = "Y" },
    { key = "PARTY", label = "P", usable = function() return ask("IsInGroup") end },
    { key = "RAID", label = "R", usable = function() return ask("IsInRaid") end },
    { key = "GUILD", label = "G", usable = function() return ask("IsInGuild") end },
    { key = "OFFICER", label = "O", usable = isOfficer },
    { key = REPLY, label = "W", color = "WHISPER" },
}

local function stripOn() return chat.Settings().channelStrip ~= false end
local function colorOn() return chat.Settings().editColor ~= false end

-- GetChannelList returns id, name, disabled triples.
local function joinedChannels()
    local entries = {}
    if type(GetChannelList) ~= "function" then return entries end
    local list = { pcall(GetChannelList) }
    if not list[1] then return entries end
    for index = 2, #list, 3 do
        local id = list[index]
        if type(id) == "number" and list[index + 2] ~= true then
            entries[#entries + 1] = { key = CHANNEL, target = id, label = tostring(id), color = CHANNEL .. id }
        end
    end
    return entries
end

local function wantedEntries()
    local entries = {}
    for _, entry in ipairs(ENTRIES) do
        if not entry.usable or entry.usable() then entries[#entries + 1] = entry end
    end
    for _, entry in ipairs(joinedChannels()) do entries[#entries + 1] = entry end
    return entries
end

local function typeInfo(name)
    local info = type(ChatTypeInfo) == "table" and ChatTypeInfo[name] or nil
    return type(info) == "table" and type(info.r) == "number" and info or nil
end

local function selectedWindow()
    if type(FCFDock_GetSelectedWindow) == "function" and GENERAL_CHAT_DOCK then
        local ok, frame = pcall(FCFDock_GetSelectedWindow, GENERAL_CHAT_DOCK)
        if ok and chat.IsFrame(frame) then return frame end
    end
    return _G[MAIN]
end

local onHeader

local function switch(entry, frame)
    local ok, box = pcall(ChatFrameUtil.OpenChat, nil, frame)
    if not ok or not chat.IsFrame(box) then return chat.Warn("strip", ok and "no edit box" or box) end
    box:SetChatType(entry.key)
    if entry.target then box:SetChannelTarget(entry.target) end
    box:UpdateHeader()
    onHeader(box)
end

local function onClick(button)
    local entry, frame = button.entry, selectedWindow()
    if entry.key ~= REPLY then return switch(entry, frame) end
    if type(ChatFrameUtil.ReplyTell) == "function" then pcall(ChatFrameUtil.ReplyTell, frame) end
end

local function createButton()
    local button = CreateFrame("Button", nil, holder)
    button:SetSize(BUTTON_WIDTH, HEIGHT)
    chat.Flat(button, chat.Colors.field)
    button.label = button:CreateFontString(nil, "OVERLAY")
    media.Font(button.label, "small")
    button.label:SetPoint("CENTER", button, "CENTER", 0, 0)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(button)
    highlight:SetTexture(media.highlight)
    button:SetScript("OnClick", onClick)
    return button
end

local function matches(entry, kind, target)
    if entry.key ~= kind then return false end
    return kind ~= CHANNEL or tostring(entry.target) == tostring(target)
end

local function markActive()
    local kind, target
    if activeBox then kind, target = activeBox:GetChatType(), activeBox:GetChannelTarget() end
    for _, button in ipairs(chat.Strip.Buttons) do
        local color = matches(button.entry, kind, target) and chat.Colors.selected or chat.Colors.border
        for _, line in ipairs(button.rikBorder) do line:SetVertexColor(color[1], color[2], color[3], 1) end
    end
end

local function dress(button, entry, index)
    local info = typeInfo(entry.color or entry.key)
    button.entry = entry
    button.label:SetText(entry.label)
    if info then button.label:SetTextColor(info.r, info.g, info.b, 1) end
    button:ClearAllPoints()
    button:SetPoint("LEFT", holder, "LEFT", (index - 1) * (BUTTON_WIDTH + GAP), 0)
    button:SetAlpha(REST_ALPHA)
    button:Show()
end

function chat.RefreshStrip()
    if not holder then return end
    local entries, visible = wantedEntries(), {}
    for index, entry in ipairs(entries) do
        pool[index] = pool[index] or createButton()
        dress(pool[index], entry, index)
        visible[index] = pool[index]
    end
    for index = #entries + 1, #pool do pool[index]:Hide() end
    chat.Strip.Buttons = visible
    markActive()
end

local function boxInfo(box)
    local kind = box:GetChatType()
    if type(kind) ~= "string" then return nil end
    if kind ~= CHANNEL then return typeInfo(kind), kind end
    local target = box:GetChannelTarget()
    return typeInfo(CHANNEL .. tostring(target)) or typeInfo(CHANNEL), kind .. tostring(target)
end

-- The box's look is src/modules/chat/chat-editbox.lua's; this file only says which channel it is on.
local function paint(box, animate)
    local info, key = boxInfo(box)
    if not colorOn() or not info then return chat.PaintEditBox(box, nil, nil, false) end
    chat.PaintEditBox(box, { info.r, info.g, info.b }, key, animate)
end

function onHeader(box)
    activeBox = box
    paint(box, true)
    markActive()
end

-- The edit box's methods are not hooked: on 1.60.1.69977 hooking UpdateHeader on the box left it
-- nil for Blizzard's own callers. Script hooks see every channel change a player can make: the
-- box shows or gains focus when chat opens, and its text changes when a slash command switches.
local function hookBox(frame)
    local box = frame.editBox
    if hooked[box] or not chat.IsFrame(box) or type(box.HookScript) ~= "function" then return end
    hooked[box] = true
    chat.DressEditBox(box)
    for _, script in ipairs({ "OnShow", "OnEditFocusGained", "OnTextChanged" }) do
        box:HookScript(script, function(self)
            if script == "OnShow" then chat.RefreshInputLayout() end
            onHeader(self)
        end)
    end
    paint(box, false)
end

local function sharesStrip(frame) return frame == _G[MAIN] or frame.isDocked == true end

function chat.RefreshInputLayout()
    if InCombatLockdown() then core.Combat.Queue(chat.RefreshInputLayout, "chat:input"); return end
    if holder then holder:SetScale(core.Layout.GetScale()) end
    for frame in pairs(chat.Frames) do
        if chat.IsFrame(frame.editBox) then
            if holder and stripOn() and sharesStrip(frame) then
                chat.AnchorEditBox(frame, holder, EDIT_GAP)
            else
                chat.DockEditBox(frame)
            end
        end
    end
end

local function createHolder()
    local main = _G[MAIN]
    local anchor = main.rikPanel or main
    holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    holder:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -PANEL_GAP)
    holder:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -PANEL_GAP)
    holder:SetHeight(HEIGHT)
    chat.Strip.Holder = holder
end

function chat.SetChannelStrip(value)
    chat.Settings().channelStrip = value == true
    if holder then holder:SetShown(value == true) end
    chat.RefreshInputLayout()
    return true
end

function chat.SetEditColor(value)
    chat.Settings().editColor = value == true
    for box in pairs(hooked) do paint(box, false) end
    return true
end

local function canSwitch()
    return chat.IsFrame(_G[MAIN]) and type(ChatFrameUtil) == "table" and type(ChatFrameUtil.OpenChat) == "function"
end

function chat.EnableStrip()
    for frame in pairs(chat.Frames) do hookBox(frame) end
    if not canSwitch() then return end
    createHolder()
    holder:SetShown(stripOn())
    chat.RefreshStrip()
    chat.RefreshInputLayout()
    for _, event in ipairs(REFRESH_EVENTS) do core:RegisterEvent(event, chat.RefreshStrip) end
end

table.insert(chat.Options.settings, { type = "checkbox", key = "channelStrip", label = "Channel buttons under the chat window",
    get = stripOn, set = chat.SetChannelStrip })
table.insert(chat.Options.settings, { type = "checkbox", key = "editColor", label = "Edit box border in the channel's colour",
    get = colorOn, set = chat.SetEditColor })
