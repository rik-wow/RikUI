-- Only parent writes on Blizzard frames are protected and they run through the hide helper's
-- combat queue; the rendered edit box, tab fade timing and copy window need a beta check.
return function(check)
    local env = require("wow_stub")
    local stub = require("chat_stub")
    local originalCreate = CreateFrame
    local API = { "CHAT_FRAMES", "NUM_CHAT_WINDOWS", "ChatFrameUtil", "EventRegistry", "SetItemRef", "ChatFontNormal",
        "FCF_SetChatWindowFontSize", "FCFTab_UpdateAlpha", "CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA",
        "CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA", "CHAT_FRAME_TAB_ALERTING_NOMOUSE_ALPHA", "ItemRefTooltip", "RikUIChatCopy" }
    local FILES = { "core.lua", "hide.lua", "media.lua", "setup.lua", "setup-apply.lua", "layout.lua",
        "layout-movers.lua", "unitframes.lua", "unitframes-status.lua", "chat.lua", "chat-copy.lua", "chat-move.lua" }
    local STOCK_FONT, URL = "Fonts\\FRIZQT__.TTF", "https://example.com/a?b=1"
    local saved, savedGet, savedSet = {}, C_CVar.GetCVar, C_CVar.SetCVar
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local savedCenter, savedScale = rawget(UIParent, "GetCenter"), rawget(UIParent, "GetEffectiveScale")
    function UIParent:GetCenter() return 400, 300 end
    function UIParent:GetEffectiveScale() return 1 end
    local function upperOnly(value)
        local methods = getmetatable(value).__index
        setmetatable(value, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
    end
    local function region(value)
        upperOnly(value)
        function value:SetTexture(texture) self.texture = texture end
        function value:SetVertexColor(...) self.color = { ... } end
        function value:SetColorTexture(...) self.color = { ... } end
        function value:SetTextColor(...) self.color = { ... } end
        function value:SetPoint(...) self.point = { ... } end
        function value:SetAlpha(alpha) self.alpha = alpha end
        function value:SetFont(path, size, flags) self.fontPath, self.fontSize, self.fontFlags = path, size, flags; return true end
        return value
    end
    CreateFrame = function(kind, name, parent, template)
        local frame = originalCreate(kind, name, parent, template)
        upperOnly(frame)
        function frame:SetParent(value) assert(not InCombatLockdown(), "frame reparented in combat"); self.parent = value end
        function frame:GetParent() return self.parent end
        function frame:SetSize(w, h) self.width, self.height = w, h end
        function frame:SetHeight(h) self.height = h end
        function frame:SetPoint(...) self.points = self.points or {}; table.insert(self.points, { ... }) end
        function frame:ClearAllPoints() self.points = nil end
        function frame:SetAlpha(alpha) self.alpha = alpha end
        function frame:SetFont(path, size, flags) self.fontPath, self.fontSize, self.fontFlags = path, size, flags; return true end
        function frame:GetFont() return self.fontPath, self.fontSize, self.fontFlags end
        function frame:HighlightText() self.highlighted = true end
        function frame:SetMovable(flag) self.movable = flag end
        function frame:StartMoving() self.moving = true end
        function frame:StopMovingOrSizing() self.moving = false end
        function frame:GetCenter() return self.centerX, self.centerY end
        function frame:GetEffectiveScale() return 1 end
        local texture, font = frame.CreateTexture, frame.CreateFontString
        function frame:CreateTexture(...) return region(texture(self, ...)) end
        function frame:CreateFontString(...) return region(font(self, ...)) end
        return frame
    end
    local function printedContains(text)
        for _, line in ipairs(env.printed) do
            if line:find(text, 1, true) then return true end
        end
        return false
    end
    local function parked(frame) return frame and frame.parent == RikUIHiddenFrames and RikUI.Hide.IsHidden(frame) end
    local function allFrames(predicate)
        for id = 1, stub.WINDOWS do
            if not predicate(_G["ChatFrame" .. id], "ChatFrame" .. id) then return false end
        end
        return true
    end
    local function load(profile, combat, prepare)
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        RikUIChatCopy = nil
        stub.install(env)
        if prepare then prepare() end
        profile = profile or {}
        profile.modules = profile.modules or {}
        profile.modules.unitframes = false
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = profile } }, nil
        for _, file in ipairs(FILES) do assert(loadfile(file))("RikUI", {}) end
        env.fire("ADDON_LOADED", "RikUI")
        env.inCombat = combat == true
        env.fire("PLAYER_LOGIN")
        return RikUI.Chat
    end
    local function fontChecks(module)
        local media = RikUI.Media
        check("every chat frame uses the media font at the profile size without an outline", allFrames(function(frame)
            return frame.fontPath == media.font and frame.fontSize == 14 and frame.fontFlags == ""
        end) and RikUI.Profile.chat.fontSize == 14)
        check("the edit boxes and ChatFontNormal use the media font", ChatFrame1EditBox.fontPath == media.font
            and ChatFrame1EditBox.fontSize == 14 and ChatFontNormal.fontPath == media.font)
        FCF_SetChatWindowFontSize(nil, ChatFrame2, 16)
        check("a Blizzard size change keeps the media font and lands in the profile", ChatFrame2.fontPath == media.font
            and ChatFrame2.fontSize == 16 and RikUI.Profile.chat.fontSize == 16)
        stub.sizeWrites = {}
        check("SetFontSize routes through Blizzard's size function for every frame", module.SetFontSize(12) == true
            and #stub.sizeWrites == stub.WINDOWS and RikUI.Profile.chat.fontSize == 12 and allFrames(function(frame)
                return frame.fontSize == 12 and frame.fontPath == media.font
            end) and ChatFrame1EditBox.fontSize == 12)
        check("SetFontSize refuses values outside the slider range", module.SetFontSize(4) == nil
            and module.SetFontSize("big") == nil and RikUI.Profile.chat.fontSize == 12)
    end
    local function hideChecks(module)
        check("button frames, scroll bars and scroll-to-bottom buttons are parked on every frame", allFrames(function(frame)
            return parked(frame.buttonFrame) and parked(frame.ScrollBar) and parked(frame.ScrollToBottomButton)
        end))
        check("channel, voice, text-to-speech and quick-join buttons are parked", parked(ChatFrameChannelButton)
            and parked(ChatFrameToggleVoiceDeafenButton) and parked(ChatFrameToggleVoiceMuteButton)
            and parked(TextToSpeechButtonFrame) and parked(QuickJoinToastButton) and #module.Parked == 14)
        check("the menu button goes with its button frame; chat frames and the dock stay", ChatFrameMenuButton.parent
            == ChatFrame1ButtonFrame and not RikUI.Hide.IsHidden(ChatFrame1) and not RikUI.Hide.IsHidden(GeneralDockManager)
            and ChatFrame1.parent == UIParent)
    end
    local function editBoxChecks()
        local box = ChatFrame1EditBox
        check("edit box art and focus art are invisible", ChatFrame1EditBoxLeft.alpha == 0 and ChatFrame1EditBoxMid.alpha == 0
            and ChatFrame1EditBoxRight.alpha == 0 and box.focusLeft.alpha == 0 and box.focusMid.alpha == 0
            and box.focusRight.alpha == 0)
        check("the edit box is flat with a RikUI background and border", type(rawget(box, "rikBackground")) == "table"
            and type(rawget(box, "rikBorder")) == "table" and #box.rikBorder == 4
            and box.rikBorder[1].texture == RikUI.Media.border)
        check("the edit box docks under its chat frame across the full width", #box.points == 2
            and box.points[1][1] == "TOPLEFT" and box.points[1][2] == ChatFrame1 and box.points[1][3] == "BOTTOMLEFT"
            and box.points[2][1] == "TOPRIGHT" and box.points[2][3] == "BOTTOMRIGHT" and box.points[1][5] < 0
            and box.height == 24)
    end
    local function tabChecks()
        check("the selected and normal no-mouse tab alphas are zero; alerting tabs stay visible",
            CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA == 0 and CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA == 0
            and CHAT_FRAME_TAB_ALERTING_NOMOUSE_ALPHA == 1)
        check("every tab is refreshed through FCFTab_UpdateAlpha and fades out", #stub.alphaUpdates == stub.WINDOWS
            and ChatFrame1Tab.alpha == 0 and ChatFrame3Tab.alpha == 0)
        local artHidden = true
        for _, key in ipairs(stub.TAB_ART) do artHidden = artHidden and ChatFrame2Tab[key].alpha == 0 end
        check("tab art is invisible, the new-message glow is kept and the label uses the media font", artHidden
            and ChatFrame2Tab.glow.alpha == nil and ChatFrame2Tab.Text.fontPath == RikUI.Media.font)
    end
    local function copyChecks(module)
        local button = rawget(ChatFrame1, "rikCopy")
        check("each frame has a small copy button in its top-right corner", allFrames(function(frame)
            local copy = rawget(frame, "rikCopy")
            return copy and copy.parent == frame and copy.points[1][1] == "TOPRIGHT" and copy.width <= 16
        end) and RikUIChatCopy == nil)
        ChatFrame1:AddMessage("|cff00ff00|Hplayer:Bob|h[Bob]|h|r: hello |Tfoo.blp:0|t world")
        ChatFrame1:AddMessage("plain line")
        ChatFrame1:AddMessage(env.SECRET)
        ChatFrame1:AddMessage("|Hitem:123|h[Sword]|h")
        ChatFrame2:AddMessage("other window")
        env.click(button)
        local window = RikUIChatCopy
        check("the copy button opens a window with that frame's lines as plain text", window and window:IsShown()
            and window.edit.text == "[Bob]: hello  world\nplain line\n[Sword]" and window == module.Window)
        check("the text is selected and the title names the window", window.edit.highlighted == true
            and window.title.text == "Chat copy: Window 1" and #env.printed == 0)
        env.runScript(window.edit, "OnEscapePressed")
        check("Escape closes the copy window", not window:IsShown())
        env.click(rawget(ChatFrame2, "rikCopy"))
        check("another frame's button shows that frame's lines in the same window", RikUIChatCopy == window
            and window:IsShown() and window.edit.text == "other window")
        env.click(window.close)
        check("the close button hides the window", not window:IsShown())
        stub.messageError = "messages unavailable"
        env.click(button)
        env.click(button)
        check("a failing message read is reported once and leaves an empty box", printedContains("Chat copy")
            and #env.printed == 1 and window.edit.text == "")
        stub.messageError, env.printed = nil, {}
        module.CloseCopy()
    end
    local function linkChecks(module)
        local link = "|cff4e96f7|Haddon:RikUI:" .. URL .. "|h[" .. URL .. "]|h|r"
        check("Linkify wraps http and www addresses and leaves trailing punctuation outside",
            module.Linkify("see " .. URL .. ", ok") == "see " .. link .. ", ok"
            and module.Linkify("www.wowhead.com.") == "|cff4e96f7|Haddon:RikUI:www.wowhead.com|h[www.wowhead.com]|h|r.")
        check("Linkify leaves existing hyperlinks and plain text alone",
            module.Linkify("|Hitem:1|h[http://x.example]|h and text") == "|Hitem:1|h[http://x.example]|h and text"
            and module.Linkify("no address here") == "no address here")
        local filters = ChatFrameUtil.Filters
        check("the filter is registered once for the chat message events", #filters.CHAT_MSG_SAY == 1
            and #filters.CHAT_MSG_WHISPER == 1 and #filters.CHAT_MSG_CHANNEL == 1 and #filters.CHAT_MSG_GUILD == 1
            and #filters.CHAT_MSG_SYSTEM == 1 and #filters.CHAT_MSG_BN_WHISPER == 1)
        local discard, message, author, extra = ChatFrameUtil.ProcessMessageEventFilters(ChatFrame1, "CHAT_MSG_SAY",
            "go " .. URL, "Bob", "Common")
        check("a filtered message carries the link and every other argument unchanged", discard == false
            and message == "go " .. link and author == "Bob" and extra == "Common")
        discard, message, author = ChatFrameUtil.ProcessMessageEventFilters(ChatFrame1, "CHAT_MSG_SAY", "hello", "Bob")
        check("a message without an address passes through untouched", discard == false and message == "hello"
            and author == "Bob")
        discard, message = ChatFrameUtil.ProcessMessageEventFilters(ChatFrame1, "CHAT_MSG_WHISPER", env.SECRET, "Bob")
        check("a secret message is never rewritten", discard == false and message == env.SECRET and #env.printed == 0)
        local callback = filters.CHAT_MSG_SAY[1]
        check("the filter itself declines secret and non-string messages", callback(ChatFrame1, "CHAT_MSG_SAY", env.SECRET) == false
            and select("#", callback(ChatFrame1, "CHAT_MSG_SAY", 42)) == 1)

        SetItemRef("addon:RikUI:" .. URL, "[" .. URL .. "]", "LeftButton", ChatFrame1)
        local window = RikUIChatCopy
        check("clicking an address link opens the box with the address selected", window:IsShown()
            and window.edit.text == URL and window.edit.highlighted == true and window.title.text == "Link"
            and ItemRefTooltip.shown == false)
        module.CloseCopy()
        SetItemRef("addon:Other:data", "[x]", "LeftButton", ChatFrame1)
        SetItemRef("addon:RikUI", "[x]", "LeftButton", ChatFrame1)
        check("other addons' links are ignored", not window:IsShown())
        SetItemRef("item:123", "[Sword]", "LeftButton", ChatFrame1)
        check("Blizzard links still reach the item tooltip", ItemRefTooltip.shown == true and not window:IsShown())
    end
    local function timestampChecks(module)
        check("timestamps are switched on with the 24-hour format when they were off",
            stub.cvars.showTimestamps == "%H:%M " and #stub.cvarWrites == 1)
        check("the timestamps option switches the setting off and back on", module.SetTimestamps(false) == true
            and stub.cvars.showTimestamps == "none" and RikUI.Profile.chat.timestamps == false
            and module.SetTimestamps(true) == true and stub.cvars.showTimestamps == "%H:%M ")
    end
    local ok, reason = pcall(function()
        local module = load()
        timestampChecks(module)
        fontChecks(module)
        hideChecks(module)
        editBoxChecks()
        tabChecks()
        copyChecks(module)
        linkChecks(module)
        check("the options page offers the font size and timestamps", module.Options.title == "Chat"
            and module.Options.settings[1].type == "slider" and module.Options.settings[1].get() == 12
            and module.Options.settings[2].type == "checkbox" and module.Options.settings[2].get() == true)
        env.printed = {}
        SlashCmdList.RIKUI("debug")
        check("debug reports the chat state and samples the timestamp setting",
            printedContains("Chat frames=3 parked=14 links=true") and printedContains("chat.GetCVar(showTimestamps)"))

        module = load({ chat = { fontSize = 18, timestamps = true } }, false, function()
            stub.cvars.showTimestamps = "%I:%M:%S %p "
        end)
        check("a saved size is applied and a player's own timestamp format is left alone", ChatFrame1.fontSize == 18
            and stub.cvars.showTimestamps == "%I:%M:%S %p " and #stub.cvarWrites == 0)

        module = load(nil, true)
        check("a combat login applies fonts at once and queues every parent write",
            ChatFrame1.fontPath == RikUI.Media.font and ChatFrame1ButtonFrame.parent == ChatFrame1
            and ChatFrameChannelButton.parent == UIParent and ChatFrame1EditBoxLeft.alpha == 0)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat parks the queued frames", parked(ChatFrame1ButtonFrame) and parked(ChatFrameChannelButton)
            and parked(ChatFrame1.ScrollBar))

        module = load(nil, false, function()
            ChatFrameUtil, EventRegistry, FCF_SetChatWindowFontSize, FCFTab_UpdateAlpha = nil, nil, nil, nil
            TextToSpeechButtonFrame, QuickJoinToastButton = nil, nil
        end)
        check("missing link APIs print one line each and the rest still applies", printedContains("Chat links")
            and printedContains("Chat clicks") and #env.printed == 2 and ChatFrame1.fontPath == RikUI.Media.font
            and #module.Parked == 12 and #env.hooks == stub.WINDOWS * 3 + 3)
        check("without Blizzard's size function SetFontSize writes the fonts itself", module.SetFontSize(15) == true
            and ChatFrame3.fontSize == 15 and ChatFrame3EditBox.fontSize == 15)

        module = load(nil, false, function() ChatFrame1 = nil end)
        check("a client without ChatFrame1 prints one line and touches nothing", printedContains("Chat frames")
            and #env.printed == 1 and ChatFrame2.fontPath == STOCK_FONT and #module.Parked == 0)

        module = load()
        local tab = ChatFrame1Tab
        ChatFrame1.centerX, ChatFrame1.centerY = 200, 150
        check("the main chat window starts locked and untouched", RikUI.Profile.chat.locked == true
            and ChatFrame1.points == nil and module.Holder == nil and RikUI.Layout.Groups.chat == nil)
        env.runScript(tab, "OnDragStart")
        check("dragging the tab of a locked window does nothing", module.Holder == nil and ChatFrame1.points == nil)
        env.printed = {}
        SlashCmdList.RIKUI("chat unlock")
        check("/rik chat unlock saves the flag and says how to drag", RikUI.Profile.chat.locked == false
            and printedContains("drag") and not RikUI.Layout.IsMoving())
        env.runScript(tab, "OnDragStart")
        local holder = module.Holder
        check("an unlocked tab drag puts a holder on the window's centre and moves it", holder ~= nil
            and holder.moving == true and holder.movable == true and ChatFrame1.points[1][1] == "CENTER"
            and ChatFrame1.points[1][2] == holder and #ChatFrame1.points == 1)
        holder.centerX, holder.centerY = 500, 380
        env.runScript(tab, "OnDragStop")
        local dropped = RikUIDB.profiles.Default.positions.chat
        check("the drop is saved in the profile and registered with the layout", holder.moving == false
            and type(dropped) == "table" and dropped.point == "CENTER" and dropped.x == 100 and dropped.y == 80
            and RikUI.Layout.Groups.chat.frames[1] == holder and holder.points[1][4] == 100)
        ChatFrame1:ClearAllPoints()
        ChatFrame1:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 32, 95)
        check("an Edit Mode re-anchor is answered by putting the window back on the holder",
            #ChatFrame1.points == 1 and ChatFrame1.points[1][2] == holder)
        SlashCmdList.RIKUI("chat lock")
        env.runScript(tab, "OnDragStart")
        check("/rik chat lock stops further drags", RikUI.Profile.chat.locked == true and holder.moving == false)
        SlashCmdList.RIKUI("chat reset")
        check("/rik chat reset forgets the position", RikUIDB.profiles.Default.positions.chat == nil
            and printedContains("reload"))
        SlashCmdList.RIKUI("chat sideways")
        check("an unknown chat argument prints the usage", printedContains("Usage: /rik chat"))

        module = load({ positions = { chat = { point = "CENTER", relativePoint = "CENTER", x = 100, y = 80 } } })
        check("a saved position is applied at the next login", module.Holder ~= nil
            and module.Holder.points[1][4] == 100 and module.Holder.points[1][5] == 80
            and ChatFrame1.points[1][2] == module.Holder)
        module = load({ positions = { chat = { point = "CENTER", relativePoint = "CENTER", x = 100, y = 80 } } }, true)
        check("a combat login leaves the window alone until the holder is placed", ChatFrame1.points == nil)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat places the holder, then the window", module.Holder.points[1][4] == 100
            and ChatFrame1.points[1][2] == module.Holder)

        module = load({ modules = { chat = false } })
        env.runScript(ChatFrame1Tab, "OnDragStart")
        check("a disabled module never moves the chat window", ChatFrame1.points == nil and module.Holder == nil)
        check("a disabled module leaves fonts, buttons, tabs, timestamps, filters and hooks untouched",
            ChatFrame1.fontPath == STOCK_FONT and ChatFontNormal.fontPath == nil
            and ChatFrame1ButtonFrame.parent == ChatFrame1 and ChatFrame1EditBoxLeft.alpha == nil
            and rawget(ChatFrame1, "rikCopy") == nil and CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA == 0.4
            and stub.cvars.showTimestamps == "none" and next(ChatFrameUtil.Filters) == nil
            and next(EventRegistry.callbacks) == nil and #env.hooks == 0 and #module.Parked == 0)
    end)
    CreateFrame = originalCreate
    C_CVar.GetCVar, C_CVar.SetCVar = savedGet, savedSet
    UIParent.GetCenter, UIParent.GetEffectiveScale = savedCenter, savedScale
    for _, name in ipairs(API) do _G[name] = saved[name] end
    env.inCombat = false
    check("chat suite completes", ok, reason)
end
