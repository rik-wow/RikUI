local loadfile = dofile("tests/load_addon.lua").Loadfile
-- The strip, the edit box colour, the tab dots and the name clicks all act through Blizzard's own
-- entry points, which the suite fakes and records. Whether camelot gives each docked window its
-- own edit box, and whether an invite from addon code is allowed, need a beta check.
return function(check)
    local env = require("wow_stub")
    local stub = require("chat_stub")
    local restoreCreate = require("widget_stub").install()
    local API = { "CHAT_FRAMES", "NUM_CHAT_WINDOWS", "ChatFrameUtil", "EventRegistry", "SetItemRef", "ChatFontNormal",
        "FCF_SetChatWindowFontSize", "FCFTab_UpdateAlpha", "FCFTab_UpdateColors", "ItemRefTooltip", "ChatTypeInfo",
        "CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA", "CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA", "GENERAL_CHAT_DOCK",
        "FCFDock_GetSelectedWindow", "GetChannelList", "IsInGroup", "IsInRaid", "IsInGuild", "C_GuildInfo",
        "C_PartyInfo", "C_FriendList", "IsAltKeyDown", "IsControlKeyDown" }
    local FILES = { "src/core/core.lua", "src/platform/hooks.lua", "src/platform/hide.lua", "src/platform/editmode.lua", "src/ui/media.lua", "src/ui/motion.lua", "src/setup/setup.lua", "src/setup/setup-apply.lua", "src/layout/layout-geometry.lua", "src/layout/layout.lua", "src/layout/layout-rects.lua",
        "src/ui/motion.lua", "src/ui/skin.lua", "src/layout/layout-unlock.lua", "src/layout/layout-drag.lua", "src/modules/unitframes/unitframes.lua", "src/modules/unitframes/unitframes-status.lua", "src/modules/chat/chat.lua", "src/modules/chat/chat-skin.lua", "src/modules/chat/chat-copy.lua",
        "src/modules/chat/chat-move.lua", "src/modules/chat/chat-lines.lua", "src/modules/chat/chat-history.lua", "src/modules/chat/chat-scroll.lua", "src/modules/chat/chat-size.lua", "src/modules/chat/chat-input.lua",
        "src/modules/chat/chat-editbox.lua", "src/modules/chat/chat-strip.lua", "src/modules/chat/chat-tabs.lua", "src/modules/chat/chat-clicks.lua" }
    local saved, savedGet, savedSet = {}, C_CVar.GetCVar, C_CVar.SetCVar
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local state = {}
    local function installEditBox(box)
        box.chatType, box.text, box.headers = "SAY", "", 0
        function box:GetChatType() return self.chatType end
        function box:SetChatType(kind) self.chatType = kind end
        function box:GetChannelTarget() return self.channelTarget end
        function box:SetChannelTarget(target) self.channelTarget = target end
        function box:UpdateHeader() self.headers = self.headers + 1 end
        function box:GetText() return self.text end
    end
    local function installClient()
        state.group, state.raid, state.guild, state.officer, state.alt, state.control = false, false, false, false, false, false
        state.selected, state.active, state.opened, state.replied, state.deactivated = nil, nil, {}, nil, nil
        state.invited, state.who = {}, {}
        for id = 1, stub.WINDOWS do installEditBox(_G["ChatFrame" .. id].editBox) end
        ChatFrame3.isDocked, ChatFrame3.shown = true, false
        ChatFrameUtil.OpenChat = function(text, frame)
            state.opened[#state.opened + 1] = { text = text, frame = frame }
            state.active = (frame or ChatFrame1).editBox
            state.active:UpdateHeader()
            return state.active
        end
        ChatFrameUtil.ReplyTell = function(frame) state.replied = frame end
        ChatFrameUtil.GetActiveWindow = function() return state.active end
        ChatFrameUtil.DeactivateChat = function(box) state.deactivated, state.active = box, nil end
        GENERAL_CHAT_DOCK = {}
        FCFDock_GetSelectedWindow = function() return state.selected end
        GetChannelList = function() return 1, "General", false, 2, "Trade", false end
        IsInGroup = function() return state.group end
        IsInRaid = function() return state.raid end
        IsInGuild = function() return state.guild end
        C_GuildInfo = { IsGuildOfficer = function() return state.officer end }
        C_PartyInfo = { InviteUnit = function(name) state.invited[#state.invited + 1] = name end }
        C_FriendList = { SendWho = function(query) state.who[#state.who + 1] = query end }
        IsAltKeyDown = function() return state.alt end
        IsControlKeyDown = function() return state.control end
    end
    local function load(profile, prepare)
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        stub.install(env)
        installClient()
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
    local function option(chat, key)
        for _, setting in ipairs(chat.Options.settings) do
            if setting.key == key then return setting end
        end
    end
    local function labels(chat)
        local text = {}
        for _, button in ipairs(chat.Strip.Buttons) do text[#text + 1] = button.label.text end
        return table.concat(text, " ")
    end
    local function button(chat, label)
        for _, candidate in ipairs(chat.Strip.Buttons) do
            if candidate.label.text == label then return candidate end
        end
    end
    local function sameColor(color, info) return color[1] == info.r and color[2] == info.g and color[3] == info.b end
    local ok, reason = pcall(function()
        local chat = load()
        local holder, box = chat.Strip.Holder, ChatFrame1.editBox
        check("the channel strip hangs under the chat panel and belongs to the screen, not to one window",
            holder.parent == UIParent and holder.points[1][2] == ChatFrame1.rikPanel and holder.points[1][3] == "BOTTOMLEFT"
            and holder.height == 18)
        check("a solo, guildless character sees say, yell, reply and the joined channels", labels(chat) == "S Y W 1 2",
            labels(chat))
        check("the main and docked edit boxes move under the strip and other windows keep their own place",
            box.points[1][2] == holder and ChatFrame3.editBox.points[1][2] == holder
            and ChatFrame2.editBox.points[1][2] == ChatFrame2.rikPanel)
        state.group, state.raid, state.guild, state.officer = true, true, true, true
        env.fire("GROUP_ROSTER_UPDATE")
        env.fire("PLAYER_GUILD_UPDATE")
        check("group, raid, guild and officer buttons appear when they can be used", labels(chat) == "S Y P R G O W 1 2",
            labels(chat))
        check("buttons are flat, lettered in the RikUI font and coloured like their channel",
            #button(chat, "G").rikBorder == 4 and button(chat, "G").label.fontPath == RikUI.Media.font
            and sameColor(button(chat, "G").label.textColor, ChatTypeInfo.GUILD))

        state.selected = ChatFrame3
        env.click(button(chat, "P"))
        check("a click opens the selected window's edit box on that channel without sending anything",
            state.opened[1].frame == ChatFrame3 and state.opened[1].text == nil and ChatFrame3.editBox.chatType == "PARTY"
            and ChatFrame3.editBox.headers == 2)
        state.selected = nil
        env.click(button(chat, "2"))
        check("a numbered channel sets the channel target", box.chatType == "CHANNEL" and box.channelTarget == 2
            and state.opened[2].frame == ChatFrame1)
        env.click(button(chat, "W"))
        check("the reply button hands over to Blizzard's reply", state.replied == ChatFrame1)

        local art = box.rikArt
        check("the edit box border and a two-pixel accent bar take the channel's colour",
            sameColor(box.rikBorder[1].color, ChatTypeInfo.CHANNEL2) and sameColor(art.accent.color, ChatTypeInfo.CHANNEL2)
            and art.accent.width == 2 and art.accentPulse.plays == 1)
        -- The typing area must stay dark: a full-size light texture washed the text out in game, because
        -- the fourth component of SetVertexColor is the alpha and undid the SetAlpha(0) before it.
        local field = art.field.color
        check("the typing area is an opaque dark field and nothing light spans it", field[1] < 0.1 and field[2] < 0.1
            and field[3] < 0.1 and field[4] >= 0.95 and rawget(box, "rikFlash") == nil and art.accent.alpha ~= 0)
        box:UpdateHeader()
        check("a header refresh on the same channel does not pulse again", art.accentPulse.plays == 1)
        env.click(button(chat, "G"))
        check("switching channel recolours and pulses once more", sameColor(box.rikBorder[1].color, ChatTypeInfo.GUILD)
            and sameColor(art.accent.color, ChatTypeInfo.GUILD) and art.accentPulse.plays == 2)
        check("the focus glow rests invisible", art.glow.alpha == 0)
        env.runScript(box, "OnEditFocusGained")
        check("taking the focus fades a glow in around the box in the channel's colour", art.glow.alpha == 1
            and art.glow.fade.plays == 1 and sameColor(art.glow.lines[1].color, ChatTypeInfo.GUILD))
        env.runScript(box, "OnEditFocusLost")
        check("losing the focus takes it away", art.glow.alpha == 0)
        env.runScript(box, "OnShow")
        check("the box's art fades in when the box opens, on a frame of RikUI's own", art.fade.plays == 1
            and rawget(box, "fade") == nil)
        local selected = RikUI.Chat.Colors.selected
        check("the active channel's button carries the selected border",
            button(chat, "G").rikBorder[1].color[1] == selected[1] and button(chat, "2").rikBorder[1].color[1] ~= selected[1])
        option(chat, "editColor").set(false)
        check("switching the edit box colour off returns the plain border and a neutral accent",
            box.rikBorder[1].color[1] == RikUI.Chat.Colors.border[1] and art.accent.color[1] == RikUI.Chat.Colors.border[1])
        option(chat, "editColor").set(true)
        option(chat, "channelStrip").set(false)
        check("switching the strip off hides it and puts the edit boxes back under their panels",
            holder.shown == false and box.points[1][2] == ChatFrame1.rikPanel)
        option(chat, "channelStrip").set(true)

        -- Motion on the window itself. Blizzard fades tabs and its own textures; RikUI only ever tweens
        -- regions and frames of its own.
        local tab, panel = ChatFrame1Tab, ChatFrame1.rikPanel
        check("the panel behind the window fades in once at login", panel.fade ~= nil and panel.fade.plays == 1)
        check("a tab has a hover highlight and a selection underline, both invisible at rest",
            tab.rikHover ~= nil and tab.rikHover.alpha == 0 and tab.rikUnderline ~= nil and tab.rikUnderline.alpha == 0
            and tab.rikUnderline.height == 2)
        env.runScript(tab, "OnEnter")
        check("hovering a tab fades a soft highlight in", tab.rikHover.alpha == 0.35 and tab.rikHover.fade.plays == 1
            and tab.rikHover.fade.animation.to == 0.35)
        env.runScript(tab, "OnLeave")
        check("leaving takes it away", tab.rikHover.alpha == 0)
        FCFTab_UpdateColors(tab, true)
        local gold = RikUI.Chat.Colors.selected
        check("selecting a tab fades a gold underline in under its label", tab.rikUnderline.alpha == 1
            and tab.rikUnderline.fade.plays == 1 and tab.rikUnderline.color[1] == gold[1] and tab.rikUnderline.color[4] == nil)
        FCFTab_UpdateColors(tab, true)
        check("a repeated colour update does not replay it", tab.rikUnderline.fade.plays == 1)
        FCFTab_UpdateColors(tab, false)
        check("deselecting takes the underline away", tab.rikUnderline.alpha == 0)
        local copy, lock = ChatFrame1.rikCopy, ChatFrame1.rikLock
        env.runScript(copy, "OnEnter")
        env.runScript(lock, "OnEnter")
        check("the copy and padlock buttons fade to full brightness under the cursor instead of snapping",
            copy.alpha == 1 and copy.rikHoverFade.plays == 1 and lock.alpha == 1 and lock.rikHoverFade.plays == 1)
        env.runScript(copy, "OnLeave")
        env.runScript(lock, "OnLeave")
        check("and back on restores both", holder.shown == true and box.points[1][2] == holder)

        check("tabs stay visible without the mouse", CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA == 1
            and CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA == 0.6 and ChatFrame1Tab.alpha == 1)
        stub.receive(ChatFrame3, "UPDATE_CHAT_COLOR")
        check("an event that adds no line puts no dot", ChatFrame3Tab.rikDot.shown == false)
        stub.receive(ChatFrame3, "CHAT_MSG_GUILD", "hi")
        check("a line in a window that is not shown puts a dot on its tab", ChatFrame3Tab.rikDot.shown == true
            and ChatFrame3Tab.rikPulse.playing ~= true)
        stub.receive(ChatFrame3, "CHAT_MSG_WHISPER", "psst")
        check("a whisper makes the dot pulse", ChatFrame3Tab.rikPulse.playing == true
            and ChatFrame3Tab.rikPulse.looping == "BOUNCE")
        ChatFrame3:Show()
        check("opening the tab clears the dot and stops the pulse", ChatFrame3Tab.rikDot.shown == false
            and ChatFrame3Tab.rikPulse.playing == false)
        stub.receive(ChatFrame1, "CHAT_MSG_SAY", "hi")
        ChatFrame2.shown = false
        stub.receive(ChatFrame2, "COMBAT_LOG_EVENT", "You hit a wolf")
        check("a shown window and the combat log never get a dot", ChatFrame1Tab.rikDot.shown == false
            and rawget(ChatFrame2Tab, "rikDot") == nil)
        ChatFrame3.shown = false
        stub.receive(ChatFrame3, "CHAT_MSG_SAY", "again")
        check("a line after the window was open is new again", ChatFrame3Tab.rikDot.shown == true)
        option(chat, "tabsVisible").set(false)
        check("switching visible tabs off restores the hover fade and clears the dots",
            CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA == 0 and ChatFrame1Tab.alpha == 0 and ChatFrame3Tab.rikDot.shown == false)
        option(chat, "tabsVisible").set(true)

        local LINK = "player:Bob-Realm:12:WHISPER:BOB"
        state.alt, state.active = true, box
        SetItemRef(LINK, "[Bob]", "LeftButton", ChatFrame1)
        check("Alt-click on a name invites and closes the empty whisper box Blizzard opened",
            state.invited[1] == "Bob-Realm" and state.deactivated == box)
        state.alt, state.control, state.active, state.deactivated = false, true, box, nil
        box.text = "half a sentence"
        SetItemRef(LINK, "[Bob]", "LeftButton", ChatFrame1)
        check("Ctrl-click runs a who on the name and leaves a box with text open", state.who[1] == "n-\"Bob\""
            and state.deactivated == nil)
        state.alt = true
        SetItemRef(LINK, "[Bob]", "RightButton", ChatFrame1)
        SetItemRef("item:1", "[Sword]", "LeftButton", ChatFrame1)
        check("right clicks and other links are left to Blizzard", #state.invited == 1 and #state.who == 1)
        option(chat, "nameClicks").set(false)
        SetItemRef(LINK, "[Bob]", "LeftButton", ChatFrame1)
        check("switching name clicks off stops both", #state.invited == 1 and #state.who == 1)
        check("none of this printed anything", #env.printed == 0, env.printed[1])

        chat = load(nil, function() ChatFrameUtil.OpenChat, C_PartyInfo, C_FriendList = nil, nil, nil end)
        check("a client without OpenChat gets no strip and keeps its edit boxes", chat.Strip.Holder == nil
            and ChatFrame1.editBox.points[1][2] == ChatFrame1.rikPanel)
        state.alt = true
        SetItemRef(LINK, "[Bob]", "LeftButton", ChatFrame1)
        check("a client without the invite call ignores the click quietly", #env.printed == 0)

        load({ modules = { chat = false } })
        ChatFrame3:AddMessage("hi", 1, 1, 1)
        check("a disabled module adds no strip, dot or click handling", rawget(ChatFrame3Tab, "rikDot") == nil
            and RikUI.Chat.Strip.Holder == nil and CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA == 0.4)
    end)
    restoreCreate()
    C_CVar.GetCVar, C_CVar.SetCVar = savedGet, savedSet
    for _, name in ipairs(API) do _G[name] = saved[name] end
    check("chat controls suite completes", ok, reason)
end
