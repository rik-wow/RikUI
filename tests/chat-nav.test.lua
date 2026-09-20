-- Scrolling, sizing, history and typing. The stub models a ScrollingMessageFrame's offset and its
-- clearing SetMaxLines; how the grip drags and how Edit Mode reacts to a resized main window need
-- a beta check.
return function(check)
    local env = require("wow_stub")
    local stub = require("chat_stub")
    local widgets = require("widget_stub")
    local restoreCreate = widgets.install()
    local API = { "CHAT_FRAMES", "NUM_CHAT_WINDOWS", "ChatFrameUtil", "EventRegistry", "SetItemRef", "ChatFontNormal",
        "FCF_SetChatWindowFontSize", "FCFTab_UpdateAlpha", "FCFTab_UpdateColors", "ItemRefTooltip", "ChatTypeInfo",
        "IsControlKeyDown" }
    local FILES = { "core.lua", "hide.lua", "editmode.lua", "media.lua", "motion.lua", "setup.lua", "setup-apply.lua", "layout-geometry.lua", "layout.lua", "layout-rects.lua",
        "motion.lua", "skin.lua", "layout-unlock.lua", "layout-drag.lua", "unitframes.lua", "unitframes-status.lua", "chat.lua", "chat-skin.lua", "chat-copy.lua",
        "chat-move.lua", "chat-lines.lua", "chat-history.lua", "chat-scroll.lua", "chat-size.lua", "chat-input.lua" }
    local saved, savedGet, savedSet = {}, C_CVar.GetCVar, C_CVar.SetCVar
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local savedCenter, savedScale = rawget(UIParent, "GetCenter"), rawget(UIParent, "GetEffectiveScale")
    function UIParent:GetCenter() return 400, 300 end
    function UIParent:GetEffectiveScale() return 1 end
    local state = {}
    local function load(profile, character, prepare)
        env.frames, env.printed, env.inCombat, env.hooks, env.shiftDown = {}, {}, false, {}, false
        state.control, widgets.center = false, { 300, 200 }
        stub.install(env)
        IsControlKeyDown = function() return state.control end
        if prepare then prepare() end
        profile = profile or {}
        profile.modules = profile.modules or {}
        profile.modules.unitframes = false
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = profile } }, character
        for _, file in ipairs(FILES) do assert(loadfile(file))("RikUI", {}) end
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        return RikUI.Chat
    end
    local function option(chat, key)
        for _, setting in ipairs(chat.Options.settings) do
            if setting.key == key then return setting end
        end
    end
    local function say(frame, count)
        for index = 1, count do frame:AddMessage("line " .. index, 1, 1, 1) end
    end
    local function wheel(frame, delta) env.runScript(frame, "OnMouseWheel", delta) end
    local ok, reason = pcall(function()
        local chat = load()
        local frame, button = ChatFrame1, ChatFrame1.rikJump
        say(frame, 30)
        check("at the newest line the jump button stays hidden", button.shown == false)
        frame:ScrollUp()
        check("scrolling up fades the jump button in", button.shown == true and button.fade.plays == 1
            and button.label.text == "v")
        say(frame, 3)
        check("lines that arrive while scrolled up are counted on the button", button.label.text == "v 3")
        frame:ScrollUp()
        check("more scrolling does not replay the fade", button.fade.plays == 1)
        env.click(button)
        check("clicking the button returns to the newest line and hides it", frame.offset == 0
            and button.shown == false)
        frame:ScrollUp()
        check("the count starts again after a return", button.label.text == "v" and button.fade.plays == 2)
        frame:ScrollToBottom()

        state.control = true
        wheel(frame, 1)
        check("Ctrl-wheel up jumps to the oldest line", frame.offset == #frame.messages and button.shown == true)
        wheel(frame, -1)
        check("Ctrl-wheel down jumps to the newest line", frame.offset == 0 and button.shown == false)
        state.control, env.shiftDown = false, true
        wheel(frame, 1)
        check("Shift-wheel pages", frame.offset == stub.PAGE)
        wheel(frame, -1)
        env.shiftDown = false
        wheel(frame, 1)
        check("a plain wheel is left to Blizzard", frame.offset == 0)
        option(chat, "jumpButton").set(false)
        frame:ScrollUp()
        check("switching the jump button off hides it at once", button.shown == false)
        option(chat, "jumpButton").set(true)
        check("and back on shows it for a scrolled window", button.shown == true)
        frame:ScrollToBottom()

        local grip = frame.rikGrip
        check("the resize grip is hidden while the window is locked", grip ~= nil and grip.shown == false)
        chat.SetLocked(false)
        check("unlocking shows the grip", grip.shown == true)
        env.runScript(grip, "OnMouseDown", "LeftButton")
        check("pressing the grip sizes the window from its corner within bounds", frame.sizing == "BOTTOMRIGHT"
            and frame.resizable == true and frame.bounds[1] == 250 and frame.bounds[2] == 120)
        frame.width, frame.height = 520, 260
        env.runScript(grip, "OnMouseUp", "LeftButton")
        check("releasing it saves the size and re-centres the window on its holder", frame.sizing == nil
            and RikUI.Profile.chat.size.width == 520 and RikUI.Profile.chat.size.height == 260
            and chat.Holder ~= nil and frame.points[1][2] == chat.Holder
            and type(RikUI.Profile.positions.chat) == "table")
        chat.SetLocked(true)
        check("locking hides the grip again", grip.shown == false)
        chat.ResetPosition()
        check("resetting the chat window forgets the size too", RikUI.Profile.chat.size == nil)
        env.printed = {} -- unlocking and resetting each print one line of guidance

        check("scrollback is raised to a thousand lines", frame.maxLines == 1000 and ChatFrame3.maxLines == 1000)
        check("the combat log window keeps Blizzard's scrollback", ChatFrame2.maxLines == 128)
        frame.messages = {}
        frame:AddMessage("|Hchannel:GUILD|h[G]|h hello", 0.5, 1, 0.5)
        frame:AddMessage(env.SECRET, 1, 1, 1)
        frame:AddMessage("second", 1, 1, 1)
        env.fire("PLAYER_LOGOUT")
        local store = RikUICharDB.chatHistory
        check("logging out saves the readable lines with their colours and skips secrets", #store[1] == 2
            and store[1][1].text == "|Hchannel:GUILD|h[G]|h hello" and store[1][1].g == 1 and store[1][2].text == "second"
            and store[2] == nil)

        local character = RikUICharDB
        chat = load(nil, character)
        frame = ChatFrame1
        check("after a reload the saved lines come back dimmed above a separator", #frame.messages == 3
            and frame.messages[1].text == "|Hchannel:GUILD|h[G]|h hello" and frame.messages[1].g == 0.6
            and frame.messages[1].r == 0.3 and frame.messages[3].text:find("earlier", 1, true) ~= nil)
        check("restored lines are not counted as unread", frame.rikJump.label.text == "v" or frame.rikJump.shown == false)
        frame:AddMessage("fresh", 1, 1, 1)
        env.fire("PLAYER_LOGOUT")
        store = RikUICharDB.chatHistory[1]
        check("a second logout keeps old lines at their original colour and adds the new one", #store == 3
            and store[1].g == 1 and store[3].text == "fresh")
        say(frame, 260)
        env.fire("PLAYER_LOGOUT")
        check("at most two hundred lines are kept", #RikUICharDB.chatHistory[1] == 200
            and RikUICharDB.chatHistory[1][200].text == "line 260")
        option(chat, "history").set(false)
        env.fire("PLAYER_LOGOUT")
        check("switching history off forgets what was saved", RikUICharDB.chatHistory == nil)

        check("Up and Down recall sent lines without Alt on every edit box",
            ChatFrame1.editBox.altArrows == false and ChatFrame3.editBox.altArrows == false)
        option(chat, "arrowHistory").set(false)
        check("switching it off gives Alt-arrows back", ChatFrame1.editBox.altArrows == true)
        check("whisper, channel and officer chat stay selected after sending", ChatTypeInfo.WHISPER.sticky == 1
            and ChatTypeInfo.CHANNEL.sticky == 1 and ChatTypeInfo.OFFICER.sticky == 1 and ChatTypeInfo.YELL.sticky == 0)
        option(chat, "stickyChannels").set(false)
        check("switching sticky channels off restores Blizzard's values", ChatTypeInfo.WHISPER.sticky == 0
            and ChatTypeInfo.CHANNEL.sticky == 0 and ChatTypeInfo.SAY.sticky == 1)
        check("none of this printed anything", #env.printed == 0, env.printed[1])

        chat = load({ chat = { size = { width = 480, height = 240 } } })
        check("a saved size is applied at login", ChatFrame1.width == 480 and ChatFrame1.height == 240)
        -- ChatFrame1 is an Edit Mode system: a layout apply writes the size stored in the Edit Mode layout.
        chat = load({ chat = { size = { width = 480, height = 240 } } }, nil, function()
            function ChatFrame1:UpdateSystem() self:SetSize(430, 120) end
        end)
        ChatFrame1:UpdateSystem()
        check("Edit Mode applying its layout does not reset the saved chat size", ChatFrame1.width == 480
            and ChatFrame1.height == 240)
        -- A size chosen inside Edit Mode is the player's choice: it becomes the saved size, so it survives
        -- Edit Mode discarding it on exit (a Blizzard preset layout cannot be changed) and a reload.
        local editing = false
        chat = load(nil, nil, function()
            function EditModeManagerFrame:IsEditModeActive() return editing end
        end)
        editing = true
        ChatFrame1:SetSize(520, 300)
        check("a size set while Edit Mode is open is adopted as the saved size", RikUI.Profile.chat.size ~= nil
            and RikUI.Profile.chat.size.width == 520 and RikUI.Profile.chat.size.height == 300)
        ChatFrame1:SetSize(100, 50)
        check("a size outside the bounds is not adopted", RikUI.Profile.chat.size.width == 520)
        editing = false
        ChatFrame1:SetSize(430, 120)
        check("when Edit Mode closes and reverts its unsaved change the adopted size comes back",
            ChatFrame1.width == 520 and ChatFrame1.height == 300)
        EditModeManagerFrame.IsEditModeActive = nil

        -- Whoever writes the size, by whatever route: the window's own setters are answered too.
        chat = load({ chat = { size = { width = 480, height = 240 } } })
        ChatFrame1:SetSize(430, 120)
        check("a size written straight onto the window is answered with the saved size", ChatFrame1.width == 480
            and ChatFrame1.height == 240)
        ChatFrame1:SetWidth(300)
        ChatFrame1:SetHeight(100)
        check("and so are the width and the height alone", ChatFrame1.width == 480 and ChatFrame1.height == 240)
        env.printed = {}
        SlashCmdList.RIKUI("debug")
        check("debug reports the saved size, the size now and how often the guard answered",
            widgets.printedContains(env, "Chat size saved=480x240 now=480x240 guarded=false answered=3"), env.printed[2])
        chat.SetLocked(false)
        env.runScript(ChatFrame1.rikGrip, "OnMouseDown", "LeftButton")
        ChatFrame1:SetSize(600, 300)
        check("while the grip sizes the window nothing is answered", ChatFrame1.width == 600)
        env.runScript(ChatFrame1.rikGrip, "OnMouseUp", "LeftButton")
        check("and the new size is what is saved", RikUI.Profile.chat.size.width == 600 and RikUI.Profile.chat.size.height == 300)
        chat.SetLocked(true)
        env.printed = {}
        chat = load(nil, nil, function()
            function ChatFrame1:UpdateSystem() self:SetSize(430, 120) end
        end)
        ChatFrame1:UpdateSystem()
        check("without a saved size Edit Mode's size stands", ChatFrame1.width == 430 and ChatFrame1.height == 120)
        chat = load({ chat = { size = { width = "wide" } } })
        check("a damaged saved size is ignored", ChatFrame1.width == nil and #env.printed == 0)

        load({ modules = { chat = false } })
        check("a disabled module adds no button, grip, scrollback or sticky change", rawget(ChatFrame1, "rikJump") == nil
            and rawget(ChatFrame1, "rikGrip") == nil and ChatFrame1.maxLines == 128 and ChatTypeInfo.WHISPER.sticky == 0)
    end)
    restoreCreate()
    widgets.center = nil
    UIParent.GetCenter, UIParent.GetEffectiveScale = savedCenter, savedScale
    C_CVar.GetCVar, C_CVar.SetCVar = savedGet, savedSet
    for _, name in ipairs(API) do _G[name] = saved[name] end
    env.shiftDown = false
    check("chat navigation suite completes", ok, reason)
end
