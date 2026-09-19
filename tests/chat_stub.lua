-- Fake of the 69913 chat surface RikUI touches. Blizzard_ChatFrameBase builds ChatFrame1..N from
-- FloatingChatFrameTemplate: each frame carries a ScrollBar, a ScrollToBottomButton, a buttonFrame
-- (ChatFrameNButtonFrame) and an editBox (ChatFrameNEditBox with Left/Mid/Right art plus the focus
-- textures), and a tab (ChatFrameNTab) with its own art. The side buttons, ChatFontNormal, the
-- font-size and tab-alpha functions, the message filter registry (which skips secret arguments the
-- way Blizzard's canaccessvalue wrapper does), EventRegistry, SetItemRef with the "addon" link
-- route and the showTimestamps cvar are recorded so a test can read them.
local stub = { WINDOWS = 3, TAB_ART = { "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight",
    "HighlightLeft", "HighlightMiddle", "HighlightRight" } }

-- CHAT_FRAME_TEXTURES' window part: Blizzard fades these in on hover unless they are hidden.
stub.FRAME_ART = { "Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
    "LeftTexture", "RightTexture", "BottomTexture", "TopTexture" }

local function installFrameArt(frame, name)
    for _, key in ipairs(stub.FRAME_ART) do
        local art = frame:CreateTexture()
        art.shown = true
        _G[name .. key] = art
    end
end

local function installEditBox(frame, name)
    local box = CreateFrame("EditBox", name .. "EditBox", frame)
    frame.editBox = box
    for _, key in ipairs({ "Left", "Mid", "Right" }) do _G[name .. "EditBox" .. key] = box:CreateTexture() end
    box.focusLeft, box.focusMid, box.focusRight = box:CreateTexture(), box:CreateTexture(), box:CreateTexture()
    box.header = box:CreateFontString()
    return box
end

local function installTab(name, id)
    local tab = CreateFrame("Button", name .. "Tab", UIParent)
    tab.id = id
    for _, key in ipairs(stub.TAB_ART) do tab[key] = tab:CreateTexture() end
    tab.glow = tab:CreateTexture()
    tab.Text = tab:CreateFontString()
    tab.Text:SetText("Window " .. id)
    return tab
end

local function installFrame(id)
    local name = "ChatFrame" .. id
    local frame = CreateFrame("ScrollingMessageFrame", name, UIParent)
    frame.fontPath, frame.fontSize, frame.fontFlags = "Fonts\\FRIZQT__.TTF", 18, ""
    frame.messages = {}
    function frame:GetID() return id end
    function frame:AddMessage(text, r, g, b) table.insert(self.messages, { text = text, r = r, g = g, b = b }) end
    function frame:GetNumMessages() return #self.messages end
    function frame:GetMessageInfo(index)
        if stub.messageError then error(stub.messageError) end
        local line = self.messages[index]
        if not line then return nil end
        return line.text, line.r, line.g, line.b
    end
    frame.ScrollBar = CreateFrame("EventFrame", nil, frame)
    frame.ScrollToBottomButton = CreateFrame("Button", nil, frame)
    frame.buttonFrame = CreateFrame("Frame", name .. "ButtonFrame", frame)
    installFrameArt(frame, name)
    installEditBox(frame, name)
    installTab(name, id)
    table.insert(CHAT_FRAMES, name)
    return frame
end

local function installButtons()
    ChatFrameMenuButton = CreateFrame("DropdownButton", "ChatFrameMenuButton", ChatFrame1ButtonFrame)
    ChatFrameChannelButton = CreateFrame("Button", "ChatFrameChannelButton", UIParent)
    ChatFrameToggleVoiceDeafenButton = CreateFrame("Button", "ChatFrameToggleVoiceDeafenButton", UIParent)
    ChatFrameToggleVoiceMuteButton = CreateFrame("Button", "ChatFrameToggleVoiceMuteButton", UIParent)
    TextToSpeechButtonFrame = CreateFrame("Frame", "TextToSpeechButtonFrame", UIParent)
    QuickJoinToastButton = CreateFrame("Button", "QuickJoinToastButton", UIParent)
    GeneralDockManager = CreateFrame("Frame", "GeneralDockManager", UIParent)
end

local function fontObject()
    local object = {}
    function object:SetFont(path, size, flags) self.fontPath, self.fontSize, self.fontFlags = path, size, flags; return true end
    function object:SetShadowColor(...) self.shadow = { ... } end
    function object:SetShadowOffset(...) self.offset = { ... } end
    return object
end

-- Blizzard changes only the size and keeps whatever file the frame already uses.
local function installFontFunctions()
    ChatFontNormal = fontObject()
    function FCF_SetChatWindowFontSize(_, chatFrame, fontSize)
        local file, _, flags = chatFrame:GetFont()
        chatFrame:SetFont(file, fontSize, flags)
        stub.sizeWrites[#stub.sizeWrites + 1] = { chatFrame, fontSize }
    end
    CHAT_FRAME_TAB_SELECTED_MOUSEOVER_ALPHA, CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA = 1, 0.4
    CHAT_FRAME_TAB_NORMAL_MOUSEOVER_ALPHA, CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA = 0.6, 0.2
    CHAT_FRAME_TAB_ALERTING_MOUSEOVER_ALPHA, CHAT_FRAME_TAB_ALERTING_NOMOUSE_ALPHA = 1, 1
    function FCFTab_UpdateColors() end
    function FCFTab_UpdateAlpha(chatFrame)
        local tab = _G[chatFrame:GetName() .. "Tab"]
        local selected = chatFrame:GetID() == 1
        tab:SetAlpha(selected and CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA or CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA)
        stub.alphaUpdates[#stub.alphaUpdates + 1] = chatFrame
    end
end

-- The 69913 registry: callbacks never see secret arguments; a truthy second return replaces the
-- whole argument list, a nil one keeps it.
local function pack(...) return { n = select("#", ...), ... } end

local function anySecret(args)
    for index = 1, args.n do
        if issecretvalue(args[index]) then return true end
    end
    return false
end

local function installFilters()
    local filters = {}
    ChatFrameUtil = { Filters = filters }
    function ChatFrameUtil.AddMessageEventFilter(event, callback)
        filters[event] = filters[event] or {}
        table.insert(filters[event], callback)
    end
    function ChatFrameUtil.ProcessMessageEventFilters(chatFrame, event, ...)
        local args = pack(...)
        for _, callback in ipairs(filters[event] or {}) do
            if not anySecret(args) then
                local results = pack(callback(chatFrame, event, unpack(args, 1, args.n)))
                if results[1] then return true end
                if results[2] then args = pack(unpack(results, 2, results.n)) end
            end
        end
        return false, unpack(args, 1, args.n)
    end
end

local function installLinks()
    EventRegistry = { callbacks = {} }
    function EventRegistry:RegisterCallback(event, callback, owner)
        self.callbacks[event] = self.callbacks[event] or {}
        table.insert(self.callbacks[event], { callback = callback, owner = owner })
    end
    function EventRegistry:TriggerEvent(event, ...)
        for _, entry in ipairs(self.callbacks[event] or {}) do entry.callback(entry.owner, ...) end
    end
    ItemRefTooltip = CreateFrame("GameTooltip", "ItemRefTooltip", UIParent)
    ItemRefTooltip.shown = false
    function ItemRefTooltip:SetHyperlink(link) self.link = link; self.shown = true end
    -- SetItemRef: LinkUtil.ProcessLink hands "addon" links to EventRegistry and stops there.
    function SetItemRef(link, text, button, frame)
        if link:match("^addon:") then EventRegistry:TriggerEvent("SetItemRef", link, text, button, frame) return end
        ItemRefTooltip:SetHyperlink(link)
    end
end

local function installCVars()
    stub.cvars = { showTimestamps = "none" }
    C_CVar.GetCVar = function(name) return stub.cvars[name] end
    C_CVar.SetCVar = function(name, value)
        stub.cvars[name] = value
        stub.cvarWrites[#stub.cvarWrites + 1] = { name, value }
        return true
    end
end

-- Fresh frames, globals and recorders; call again for every scenario that reloads the addon.
function stub.install(env)
    stub.env = env
    stub.sizeWrites, stub.alphaUpdates, stub.cvarWrites, stub.messageError = {}, {}, {}, nil
    CHAT_FRAMES, NUM_CHAT_WINDOWS = {}, stub.WINDOWS
    for id = 1, stub.WINDOWS do installFrame(id) end
    installButtons()
    installFontFunctions()
    installFilters()
    installLinks()
    installCVars()
end

return stub
