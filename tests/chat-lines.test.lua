-- Lines are delivered the way MessageEventHandler does it on 69913: filters first, then the tag
-- and sender are composed, then AddMessage gets the text with the event name as its eighth
-- argument. Whether the AddMessage wrapper spreads taint that matters needs a beta check.
return function(check)
    local env = require("wow_stub")
    local stub = require("chat_stub")
    local restoreCreate = require("widget_stub").install()
    local API = { "CHAT_FRAMES", "NUM_CHAT_WINDOWS", "ChatFrameUtil", "EventRegistry", "SetItemRef", "ChatFontNormal",
        "FCF_SetChatWindowFontSize", "FCFTab_UpdateAlpha", "FCFTab_UpdateColors", "ItemRefTooltip", "PlaySound",
        "SOUNDKIT", "GetTime" }
    local FILES = { "core.lua", "hide.lua", "media.lua", "motion.lua", "setup.lua", "setup-apply.lua", "layout-geometry.lua", "layout.lua", "layout-rects.lua",
        "layout-movers.lua", "unitframes.lua", "unitframes-status.lua", "chat.lua", "chat-skin.lua", "chat-copy.lua",
        "chat-move.lua", "chat-lines.lua" }
    local GROUP_FORMATS = { CHAT_MSG_GUILD = "|Hchannel:GUILD|h[Guild]|h ", CHAT_MSG_PARTY = "|Hchannel:PARTY|h[Party]|h ",
        CHAT_MSG_PARTY_LEADER = "|Hchannel:PARTY|h[Party Leader]|h ", CHAT_MSG_SAY = "", CHAT_MSG_YELL = "",
        CHAT_MSG_WHISPER = "" }
    local saved, savedGet, savedSet = {}, C_CVar.GetCVar, C_CVar.SetCVar
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local state = {}
    local function load(profile, prepare)
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        state.now, state.sounds = 100, {}
        stub.install(env)
        GetTime = function() return state.now end
        SOUNDKIT = { TELL_MESSAGE = 3081 }
        PlaySound = function(id) state.sounds[#state.sounds + 1] = id end
        if prepare then prepare() end
        profile = profile or {}
        profile.modules = profile.modules or {}
        profile.modules.unitframes = false
        RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = profile } }, nil
        for _, file in ipairs(FILES) do assert(loadfile(file))("RikUI", {}) end
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        return RikUI.Chat
    end
    -- Returns the text that reached the window, or nil when a filter discarded the line.
    local function deliver(frame, event, text, sender, lineID, channel, number)
        local discard, message, name = ChatFrameUtil.ProcessMessageEventFilters(frame, event, text, sender, "",
            channel or "", "", "", 0, number or 0, "", 0, lineID, "Player-9")
        if discard then return nil end
        local tag = GROUP_FORMATS[event]
        if event == "CHAT_MSG_CHANNEL" then tag = "|Hchannel:channel:" .. number .. "|h[" .. channel .. "]|h " end
        frame:AddMessage(tag .. "|Hplayer:" .. name .. "|h[" .. name .. "]|h: " .. message, 1, 1, 1, 1, nil, nil, event)
        return frame.messages[#frame.messages].text
    end
    local function option(chat, key)
        for _, setting in ipairs(chat.Options.settings) do
            if setting.key == key then return setting end
        end
    end
    local HIGHLIGHT = "|cffffd24d"
    local ok, reason = pcall(function()
        local chat = load(nil, function() stub.cvars.chatClassColorOverride = "1" end)
        check("class-coloured names are switched on through the client's own setting",
            stub.cvars.chatClassColorOverride == "0" and RikUI.Profile.chat.classColorsBefore == "1")
        option(chat, "classColors").set(false)
        check("switching class colours off restores the player's earlier value",
            stub.cvars.chatClassColorOverride == "1" and option(chat, "classColors").get() == false)
        option(chat, "classColors").set(true)
        check("switching class colours back on applies at once", stub.cvars.chatClassColorOverride == "0")

        local line = deliver(ChatFrame1, "CHAT_MSG_GUILD", "hello", "Bob", 1)
        check("the guild tag shrinks to one letter inside its link",
            line == "|Hchannel:GUILD|h[G]|h |Hplayer:Bob|h[Bob]|h: hello", line)
        line = deliver(ChatFrame1, "CHAT_MSG_PARTY_LEADER", "pull", "Bob", 2)
        check("a leader tag is told apart by the event, not the label", line:find("|h[PL]|h ", 1, true) ~= nil, line)
        line = deliver(ChatFrame1, "CHAT_MSG_CHANNEL", "wts [ore] cheap", "Ann", 3, "2. Trade - City", 2)
        check("a numbered channel keeps only its number",
            line == "|Hchannel:channel:2|h[2]|h |Hplayer:Ann|h[Ann]|h: wts [ore] cheap", line)
        line = deliver(ChatFrame1, "CHAT_MSG_SAY", "[Guild] is not a tag", "Bob", 4)
        check("a line without a channel link is left alone", line == "|Hplayer:Bob|h[Bob]|h: [Guild] is not a tag", line)
        ChatFrame1:AddMessage(env.SECRET, 1, 1, 1, 1, nil, nil, "CHAT_MSG_GUILD")
        ChatFrame1:AddMessage(nil, 1, 1, 1)
        check("secret and missing text reach Blizzard's AddMessage untouched",
            ChatFrame1.messages[#ChatFrame1.messages - 1].text == env.SECRET and #env.printed == 0)
        option(chat, "shortTags").set(false)
        line = deliver(ChatFrame1, "CHAT_MSG_GUILD", "again", "Bob", 5)
        check("switching short tags off takes effect without a reload", line:find("[Guild]", 1, true) ~= nil, line)
        option(chat, "shortTags").set(true)

        line = deliver(ChatFrame1, "CHAT_MSG_GUILD", "thanks probey, nice", "Bob", 6)
        check("the character's name is highlighted in any letter case", line:find(HIGHLIGHT .. "probey|r, nice", 1, true) ~= nil
            and #state.sounds == 1 and state.sounds[1] == 3081, line)
        deliver(ChatFrame2, "CHAT_MSG_GUILD", "thanks probey, nice", "Bob", 6)
        state.now = 102
        deliver(ChatFrame1, "CHAT_MSG_GUILD", "probey?", "Bob", 7)
        check("the mention sound plays once per line and at most every five seconds", #state.sounds == 1)
        state.now = 110
        deliver(ChatFrame1, "CHAT_MSG_GUILD", "probey!", "Bob", 8)
        check("a later mention sounds again", #state.sounds == 2)
        line = deliver(ChatFrame1, "CHAT_MSG_GUILD", "probeys and |Hitem:1|h[Probey Sword]|h", "Bob", 9)
        check("a longer word and text inside a hyperlink are not mentions", line:find(HIGHLIGHT, 1, true) == nil
            and line:find("|Hitem:1|h[Probey Sword]|h", 1, true) ~= nil, line)
        line = deliver(ChatFrame1, "CHAT_MSG_GUILD", "probey here", "Probey-ProbeRealm", 10)
        check("the player's own lines are not mentions", line:find(HIGHLIGHT, 1, true) == nil and #state.sounds == 2)
        state.now = 120
        line = deliver(ChatFrame1, "CHAT_MSG_WHISPER", "hey Probey", "Bob", 11)
        check("a whisper is highlighted without a second sound", line:find(HIGHLIGHT .. "Probey|r", 1, true) ~= nil
            and #state.sounds == 2, line)
        option(chat, "mentions").set(false)
        state.now = 130
        line = deliver(ChatFrame1, "CHAT_MSG_GUILD", "probey", "Bob", 12)
        check("switching mentions off stops the highlight and the sound", line:find(HIGHLIGHT, 1, true) == nil
            and #state.sounds == 2)

        state.now = 200
        local first = deliver(ChatFrame1, "CHAT_MSG_CHANNEL", "WTS ore", "Ann", 20, "2. Trade - City", 2)
        local sameLine = deliver(ChatFrame2, "CHAT_MSG_CHANNEL", "WTS ore", "Ann", 20, "2. Trade - City", 2)
        state.now = 204
        local again = deliver(ChatFrame1, "CHAT_MSG_CHANNEL", "WTS ore", "Ann", 21, "2. Trade - City", 2)
        local other = deliver(ChatFrame1, "CHAT_MSG_CHANNEL", "WTS ore", "Cid", 22, "2. Trade - City", 2)
        check("a repeated public line within ten seconds is dropped", first ~= nil and again == nil)
        check("the same line reaching a second window still shows", sameLine ~= nil)
        check("another sender saying the same thing still shows", other ~= nil)
        state.now = 211
        check("the same line shows again after ten seconds",
            deliver(ChatFrame1, "CHAT_MSG_CHANNEL", "WTS ore", "Ann", 23, "2. Trade - City", 2) ~= nil)
        deliver(ChatFrame1, "CHAT_MSG_GUILD", "ready", "Bob", 24)
        check("guild, party and whisper lines are never collapsed",
            deliver(ChatFrame1, "CHAT_MSG_GUILD", "ready", "Bob", 25) ~= nil)
        deliver(ChatFrame1, "CHAT_MSG_SAY", "test", "Probey", 26)
        check("the player's own repeats are kept", deliver(ChatFrame1, "CHAT_MSG_SAY", "test", "Probey", 27) ~= nil)
        option(chat, "collapseRepeats").set(false)
        deliver(ChatFrame1, "CHAT_MSG_YELL", "LFG", "Ann", 28)
        check("switching collapsing off shows every line", deliver(ChatFrame1, "CHAT_MSG_YELL", "LFG", "Ann", 29) ~= nil)
        check("none of this printed anything", #env.printed == 0, env.printed[1])

        chat = load({ chat = { shortTags = false, classColors = false } },
            function() stub.cvars.chatClassColorOverride = "1" end)
        check("with both switched off nothing is wrapped and the setting is left alone",
            stub.cvars.chatClassColorOverride == "1"
            and deliver(ChatFrame1, "CHAT_MSG_GUILD", "hi", "Bob", 1):find("[Guild]", 1, true) ~= nil
            and chat.RawAddMessage(ChatFrame1) == ChatFrame1.AddMessage)

        chat = load(nil, function() ChatFrameUtil.AddMessageEventFilter = nil end)
        line = GROUP_FORMATS.CHAT_MSG_GUILD .. "x"
        ChatFrame1:AddMessage(line, 1, 1, 1, 1, nil, nil, "CHAT_MSG_GUILD")
        check("a client without message filters still shortens tags",
            ChatFrame1.messages[#ChatFrame1.messages].text == "|Hchannel:GUILD|h[G]|h x")

        load({ modules = { chat = false } }, function() stub.cvars.chatClassColorOverride = "1" end)
        ChatFrame1:AddMessage(GROUP_FORMATS.CHAT_MSG_GUILD .. "x", 1, 1, 1, 1, nil, nil, "CHAT_MSG_GUILD")
        check("a disabled module touches neither the lines nor the setting",
            ChatFrame1.messages[#ChatFrame1.messages].text:find("[Guild]", 1, true) ~= nil
            and stub.cvars.chatClassColorOverride == "1")
    end)
    restoreCreate()
    C_CVar.GetCVar, C_CVar.SetCVar = savedGet, savedSet
    for _, name in ipairs(API) do _G[name] = saved[name] end
    check("chat lines suite completes", ok, reason)
end
