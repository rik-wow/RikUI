local loadfile = dofile("tests/load_addon.lua").Loadfile
-- Only parent writes on Blizzard frames are protected and they run through the hide helper's
-- combat queue; the rendered edit box, tab fade timing and copy window need a beta check.
return function(check)
    local env = require("wow_stub")
    local stub = require("chat_stub")
    local originalCreate = CreateFrame
    local API = { "CHAT_FRAMES", "NUM_CHAT_WINDOWS", "ChatFrameUtil", "EventRegistry", "SetItemRef", "ChatFontNormal",
        "FCF_SetChatWindowFontSize", "FCFTab_UpdateAlpha", "FCFTab_UpdateColors", "CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA",
        "CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA", "CHAT_FRAME_TAB_ALERTING_NOMOUSE_ALPHA", "ItemRefTooltip", "RikUIChatCopy" }
    local FILES = { "src/core/core.lua", "src/platform/hide.lua", "src/ui/media.lua", "src/setup/setup.lua", "src/setup/setup-apply.lua", "src/layout/layout-geometry.lua", "src/layout/layout.lua", "src/layout/layout-rects.lua",
        "src/ui/motion.lua", "src/ui/skin.lua", "src/layout/layout-unlock.lua", "src/layout/layout-drag.lua", "src/modules/unitframes/unitframes.lua", "src/modules/unitframes/unitframes-status.lua", "src/layout/layout-resize.lua", "src/platform/editmode.lua", "src/modules/chat/chat.lua", "src/modules/chat/chat-skin.lua", "src/modules/chat/chat-copy.lua", "src/modules/chat/chat-move.lua", "src/modules/chat/chat-size.lua" }
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
        function frame:SetWidth(w) self.width = w end
        function frame:SetFrameStrata(strata) self.strata = strata end
        function frame:SetClampRectInsets(...) self.clamp = { ... } end
        function frame:GetClampRectInsets() return unpack(self.clamp or { 0, 0, 0, 0 }) end
        function frame:SetClampedToScreen(clamped) self.clamped = clamped end
        function frame:IsClampedToScreen() return self.clamped == true end
        function frame:GetLeft() return self.left end
        function frame:GetBottom() return self.bottom end
        function frame:GetFrameStrata() return self.strata or "LOW" end
        function frame:GetSize() return self.width, self.height end
        function frame:GetWidth() return self.width end
        function frame:GetHeight() return self.height end
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
    local function load(profile, combat, prepare, configure)
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        RikUIChatCopy = nil
        stub.install(env)
        if prepare then prepare() end
        profile = profile or {}
        profile.modules = profile.modules or {}
        profile.modules.unitframes = false
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = profile } }, nil
        for _, file in ipairs(FILES) do assert(loadfile(file))("RikUI", {}) end
        if configure then configure() end
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
            and box.points[1][1] == "TOPLEFT" and box.points[1][2] == ChatFrame1.rikPanel and box.points[1][3] == "BOTTOMLEFT"
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
            and #module.Parked == 12 and #env.hooks == stub.WINDOWS * 3 + 10)
        check("without Blizzard's size function SetFontSize writes the fonts itself", module.SetFontSize(15) == true
            and ChatFrame3.fontSize == 15 and ChatFrame3EditBox.fontSize == 15)

        module = load(nil, false, function() ChatFrame1 = nil end)
        check("a client without ChatFrame1 prints one line and touches nothing", printedContains("Chat frames")
            and #env.printed == 1 and ChatFrame2.fontPath == STOCK_FONT and #module.Parked == 0)

        module = load()
        local panel, skinnedTab = rawget(ChatFrame1, "rikPanel"), ChatFrame2Tab
        check("every chat window sits on a flat bordered panel a few pixels larger than itself", allFrames(function(frame)
            local back = rawget(frame, "rikPanel")
            return back and back.parent == frame and #back.rikBorder == 4 and back.rikBorder[1].texture == RikUI.Media.border
                and back.points[1][4] < 0 and back.points[2][4] > 0
        end) and panel.rikBackground.color[4] == 0.95)
        check("Blizzard's window background and rounded border are hidden, not faded", allFrames(function(_, name)
            for _, key in ipairs(stub.FRAME_ART) do
                if _G[name .. key]:IsShown() then return false end
            end
            return true
        end))
        check("tabs are flat boxes with the label centred in them", #skinnedTab.rikBorder == 4
            and skinnedTab.rikBox ~= nil and skinnedTab.Text.point[2] == skinnedTab.rikBox)
        FCFTab_UpdateColors(skinnedTab, true)
        check("the selected tab gets the gold border", skinnedTab.rikBorder[1].color[1] == 1
            and skinnedTab.rikBorder[1].color[3] < 0.5)
        FCFTab_UpdateColors(skinnedTab, false)
        check("an unselected tab goes back to the neutral border", skinnedTab.rikBorder[1].color[1] == 0.25)
        local copyButton, lockButton = rawget(ChatFrame1, "rikCopy"), rawget(ChatFrame1, "rikLock")
        check("the copy and lock buttons share the flat button skin and size", #copyButton.rikBorder == 4
            and #lockButton.rikBorder == 4 and copyButton.width == 16 and lockButton.width == 16
            and copyButton.rikBackground.color[1] == lockButton.rikBackground.color[1])
        check("the panel setting hides and shows every panel", module.SetPanel(false) == true
            and RikUI.Profile.chat.panel == false and not panel:IsShown() and module.SetPanel(true) == true
            and panel:IsShown())
        module = load({ chat = { panel = false } })
        check("a profile without the panel still loses Blizzard's art", not ChatFrame1.rikPanel:IsShown()
            and not ChatFrame1Background:IsShown())

        -- The main window is a layout group from login on. UIParent is 1365x768; the window is 430x180.
        local savedWidth, savedHeight, savedCursor = UIParent.GetWidth, UIParent.GetHeight, GetCursorPosition
        UIParent.GetWidth, UIParent.GetHeight = function() return 1365 end, function() return 768 end
        local cursor = { 0, 0 }
        GetCursorPosition = function() return cursor[1], cursor[2] end
        local function sized() ChatFrame1.width, ChatFrame1.height = 430, 180 end
        local function tick() env.runScript(RikUI.Layout.DragDriver, "OnUpdate", 0.016) end
        module = load(nil, false, sized)
        env.fire("PLAYER_ENTERING_WORLD")
        local tab, holder, layout = ChatFrame1Tab, module.Holder, RikUI.Layout
        local group = layout.Groups.chat
        check("the main chat window is a layout group from the first login, with the window's own size", holder ~= nil
            and group ~= nil and group.frames[1] == holder and group.label == "Chat" and holder.width == 430
            and holder.height == 180 and RikUI.Profile.chat.size.width == 430)
        check("the window hangs on its holder by one point", #ChatFrame1.points == 1 and ChatFrame1.points[1][1] == "TOPLEFT"
            and ChatFrame1.points[1][2] == holder and ChatFrame1.points[1][4] == 0 and ChatFrame1.points[1][5] == 0)
        -- Edit Mode clamps the window by its selection box, which reserves room for the button column,
        -- the tabs and the edit box: the client then keeps the window away from the screen edge and the
        -- window no longer stands where its holder and overlay are.
        local function freed()
            local clamp = ChatFrame1.clamp
            return clamp ~= nil and clamp[1] == 0 and clamp[2] == 0 and clamp[3] == 0 and clamp[4] == 0
        end
        check("the window's screen clamp has no insets, so it can reach every edge the layout allows", freed())
        ChatFrame1:SetClampRectInsets(-35, 35, 26, -50)
        check("insets written by Edit Mode are taken away again", freed())
        check("the window is not clamped to the screen at all: the layout keeps the chat on screen",
            ChatFrame1.clamped == false)
        ChatFrame1:SetClampedToScreen(true)
        check("and clamping switched back on by the client is switched off again", ChatFrame1.clamped == false)
        ChatFrame1.left, ChatFrame1.bottom, holder.left, holder.bottom = 40, 66, 16, 16
        env.printed = {}
        SlashCmdList.RIKUI("debug")
        check("debug reports where the holder and the window stand, the saved place and the clamp",
            printedContains("Chat place holder=16,16 window=40,66 offset=24,50 saved=none clamped=false insets=0,0,0,0"),
            env.printed[#env.printed])
        check("the group can be resized within the chat's bounds", type(group.resize) == "table"
            and group.resize.minWidth == 250 and group.resize.maxHeight == 800)
        env.runScript(tab, "OnDragStart")
        check("dragging the tab of a locked window does nothing", not layout.IsDragging() and not layout.IsUnlocked("chat"))
        env.printed = {}
        SlashCmdList.RIKUI("chat unlock")
        check("/rik chat unlock unlocks the chat's layout group and says how to move and resize it",
            layout.IsUnlocked("chat") and printedContains("drag") and printedContains("grip"))
        local overlay = layout.Overlays.chat
        check("the unlocked chat has the arrangement system's overlay and resize grip", overlay ~= nil and overlay:IsShown()
            and overlay.grip ~= nil)
        local before = layout.Rect("chat")
        cursor = { 500, 400 }
        env.runScript(tab, "OnDragStart")
        cursor = { 540, 430 }
        tick()
        env.runScript(tab, "OnDragStop")
        local after, dropped = layout.Rect("chat"), RikUIDB.profiles.Default.positions.chat
        check("an unlocked tab drag moves the chat through the drag engine and saves the drop", not layout.IsDragging()
            and type(dropped) == "table" and math.abs(after.left - before.left - 40) < 0.01
            and math.abs(after.bottom - before.bottom - 30) < 0.01)
        cursor = { after.right, after.bottom }
        env.runScript(overlay.grip, "OnMouseDown", "LeftButton")
        cursor = { after.right + 70, after.bottom - 20 }
        env.runScript(layout.ResizeDriver, "OnUpdate", 0.016)
        env.runScript(overlay.grip, "OnMouseUp", "LeftButton")
        check("the grip resizes the window and its holder and saves the size", RikUI.Profile.chat.size.width == 500
            and RikUI.Profile.chat.size.height == 200 and ChatFrame1.width == 500 and holder.height == 200
            and math.abs(layout.Rect("chat").left - after.left) < 0.01)
        ChatFrame1:ClearAllPoints()
        ChatFrame1:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 32, 95)
        check("an Edit Mode re-anchor is answered by putting the window back on the holder",
            #ChatFrame1.points == 1 and ChatFrame1.points[1][2] == holder)
        SlashCmdList.RIKUI("chat lock")
        env.runScript(tab, "OnDragStart")
        check("/rik chat lock locks the group and stops further drags", not layout.IsUnlocked("chat")
            and not layout.IsDragging() and not overlay:IsShown())
        SlashCmdList.RIKUI("chat reset")
        check("/rik chat reset forgets the place and the size and says so", RikUIDB.profiles.Default.positions.chat == nil
            and printedContains("default place") and RikUI.Profile.chat.size ~= nil)
        SlashCmdList.RIKUI("chat sideways")
        check("an unknown chat argument prints the usage", printedContains("Usage: /rik chat"))

        module = load(nil, false, sized)
        env.fire("PLAYER_ENTERING_WORLD")
        layout = RikUI.Layout
        local lock, copy = rawget(ChatFrame1, "rikLock"), rawget(ChatFrame1, "rikCopy")
        check("the main window has a lock button left of its copy button, other windows do not", lock ~= nil
            and lock.parent == ChatFrame1 and lock.points[1][1] == "TOPRIGHT"
            and lock.points[1][4] < copy.points[1][4] and rawget(ChatFrame2, "rikLock") == nil)
        check("a locked button rests dim with a closed white padlock icon", lock.alpha == 0.35
            and lock.icon.rikIcon == "lock" and lock.icon.color[3] == 1 and lock.icon.color[4] == nil)
        env.runScript(lock, "OnDragStart")
        check("dragging a locked button does nothing", not layout.IsDragging())
        env.click(lock)
        check("a click unlocks the layout group: full alpha, gold open padlock icon", layout.IsUnlocked("chat")
            and lock.alpha == 1 and lock.icon.rikIcon == "lock-open" and lock.icon.color[3] < 1)
        check("the open padlock rises above the overlay that covers the window, so it can lock again",
            lock.strata == "FULLSCREEN_DIALOG" and layout.Overlays.chat.strata == "DIALOG")
        env.click(lock)
        check("a second click locks and the padlock goes back to the window's strata", not layout.IsUnlocked("chat")
            and lock.strata == "LOW" and lock.alpha == 0.35)
        env.click(lock)
        env.runScript(lock, "OnEnter")
        check("hovering explains the button", GameTooltip:IsShown() and lock.alpha == 1)
        env.runScript(lock, "OnLeave")
        check("an unlocked button stays bright after the cursor leaves", lock.alpha == 1)
        cursor = { 300, 300 }
        env.runScript(lock, "OnDragStart")
        check("dragging the unlocked button drags the chat", layout.IsDragging())
        env.runScript(lock, "OnDragStop")
        layout.LockAll()
        check("locking every frame from the arrangement system dims the padlock too", lock.alpha == 0.35
            and lock.icon.rikIcon == "lock")
        layout.UnlockAll()
        check("and unlocking every frame opens it", lock.alpha == 1)
        env.inCombat = true
        env.fire("PLAYER_REGEN_DISABLED")
        env.printed = {}
        env.click(lock)
        check("in combat the padlock says why it stays locked", not layout.IsUnlocked("chat") and printedContains("combat"))
        env.inCombat = false

        module = load({ positions = { chat = { point = "CENTER", relativePoint = "CENTER", x = 100, y = 80 } } }, false, sized)
        check("a saved position is applied at the next login", module.Holder ~= nil
            and module.Holder.points[#module.Holder.points][4] == 100 and module.Holder.points[#module.Holder.points][5] == 80
            and ChatFrame1.points[1][2] == module.Holder)
        module = load({ positions = { chat = { point = "CENTER", relativePoint = "CENTER", x = 100, y = 80 } } }, true, sized)
        check("a combat login leaves the window alone until the holder is placed", ChatFrame1.points == nil)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("leaving combat places the holder, then the window", module.Holder.points[#module.Holder.points][4] == 100
            and ChatFrame1.points[1][2] == module.Holder)
        -- What you see of the chat is more than its message area: the panel's border, the tabs above,
        -- the channel strip and the input bar below. The layout group covers all of it.
        module = load(nil, false, sized, function()
            RikUI.Layouts = { ChatFootprint = { left = 4, right = 4, top = 28, bottom = 50 } }
        end)
        env.fire("PLAYER_ENTERING_WORLD")
        holder, group = module.Holder, RikUI.Layout.Groups.chat
        check("the chat's rectangle covers the panel, the tabs, the strip and the input bar", holder.width == 438
            and holder.height == 258 and RikUI.Profile.chat.size.width == 430 and RikUI.Profile.chat.size.height == 180)
        check("the message area sits inside it, under the tabs", #ChatFrame1.points == 1 and ChatFrame1.points[1][1] == "TOPLEFT"
            and ChatFrame1.points[1][2] == holder and ChatFrame1.points[1][4] == 4 and ChatFrame1.points[1][5] == -28)
        check("the resize bounds are the window's bounds plus what surrounds it", group.resize.minWidth == 258
            and group.resize.minHeight == 198 and group.resize.maxWidth == 1208)
        group.resize.apply(508, 278)
        check("a resize of the rectangle sizes the message area by the difference", ChatFrame1.width == 500
            and ChatFrame1.height == 200 and holder.width == 508 and holder.height == 278
            and RikUI.Profile.chat.size.height == 200)
        UIParent.GetWidth, UIParent.GetHeight, GetCursorPosition = savedWidth, savedHeight, savedCursor

        module = load({ modules = { chat = false } })
        env.runScript(ChatFrame1Tab, "OnDragStart")
        check("a disabled module never takes the chat window over", ChatFrame1.points == nil and module.Holder == nil
            and RikUI.Layout.Groups.chat == nil)
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
