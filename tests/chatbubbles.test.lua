-- Fake engine chat bubbles with the 69913 ChatBubbleTemplate keys. The suite drives the burst scan
-- by hand through the scanner's OnUpdate and checks that forbidden bubbles are never touched.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local API = { "C_ChatBubbles", "ChatBubbleFont" }
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local restore = widgets.install()
    local PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge",
        "BottomEdge", "LeftEdge", "RightEdge", "Center", "Tail" }
    local world = { bubbles = {}, reads = 0 }
    local function bubble(forbidden)
        local holder = CreateFrame("Frame", nil, WorldFrame)
        local child = CreateFrame("Frame", nil, holder)
        for _, key in ipairs(PIECES) do child[key] = child:CreateTexture() end
        child.String = child:CreateFontString()
        function child:IsForbidden() return forbidden == true end
        function holder:IsForbidden() return forbidden == true end
        function holder:GetChildren() return child end
        holder.child = child
        world.bubbles[#world.bubbles + 1] = holder
        return holder
    end
    local function installClient()
        world.bubbles, world.reads = {}, 0
        C_ChatBubbles = { GetAllChatBubbles = function()
            world.reads = world.reads + 1
            return world.bubbles
        end }
        ChatBubbleFont = { font = { "Fonts\\FRIZQT__.TTF", 14, "" } }
        function ChatBubbleFont:GetFont() return unpack(self.font) end
        function ChatBubbleFont:SetFont(path, size, flags) self.font = { path, size, flags }; return true end
    end
    local function load(profile, prepare)
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/chatbubbles/chatbubbles.lua" }, profile, false, function()
            installClient()
            if prepare then prepare() end
        end)
        return RikUI.ChatBubbles
    end
    local function tick(module, seconds) env.runScript(module.Scanner, "OnUpdate", seconds) end
    local function isFlat(child)
        return child.Center.alpha == 0 and child.TopLeftCorner.alpha == 0 and child.Tail.alpha == 0
            and child.rikFill ~= nil and child.rikFill.texture == RikUI.Skin.FLAT and #child.rikBorder == 4
    end
    local ok, reason = pcall(function()
        local module = load()
        check("the bubble font object takes the RikUI font at Blizzard's size",
            ChatBubbleFont.font[1] == RikUI.Media.font and ChatBubbleFont.font[2] == 14)
        check("nothing scans until somebody talks", world.reads == 0 and module.Scanner:GetScript("OnUpdate") == nil)

        local first = bubble()
        env.fire("CHAT_MSG_SAY", "hello")
        check("a bubble chat event starts the scan", module.Scanner:GetScript("OnUpdate") ~= nil)
        tick(module, 0.05)
        check("the scan waits for its interval", world.reads == 0 and first.child.rikFill == nil)
        tick(module, 0.06)
        check("a new bubble loses its nine-slice and tail and gets an inset flat fill with an edge",
            isFlat(first.child) and first.child.rikFill.points[1][4] > 0 and first.child.rikBorder[1].points[1][4] > 0)
        check("the bubble fades in and its string is not written", first.child.rikFade.plays == 1
            and rawget(first.child.String, "fontPath") == nil)
        check("bubble has an inset top light and compact pointer", first.child.rikTopLight and first.child.rikPointer
            and first.child.rikPointer.rikIcon == "chevron-down" and first.child.rikPointer.width == 12)
        local pointer = first.child.rikPointer
        local fill = first.child.rikFill
        tick(module, 0.1)
        check("a bubble is skinned once", first.child.rikFill == fill and first.child.rikFade.plays == 1)
        first.child:Hide()
        first.child:Show()
        check("a reused bubble fades in again when the engine shows it", first.child.rikFade.plays == 2)

        check("pooled bubble keeps one pointer", first.child.rikPointer == pointer)
        local hidden = bubble(true)
        tick(module, 0.1)
        check("a forbidden bubble is never touched", hidden.child.rikFill == nil
            and rawget(hidden.child.Center, "alpha") == nil)
        tick(module, 1)
        local reads = world.reads
        check("the scan stops a second after the last event", module.Scanner:GetScript("OnUpdate") == nil)
        local late = bubble()
        env.fire("CHAT_MSG_MONSTER_YELL", "intruders")
        tick(module, 0.1)
        check("a monster yell starts it again", world.reads == reads + 1 and isFlat(late.child))
        check("a clean run prints nothing", #env.printed == 0)
        SlashCmdList.RIKUI("debug")
        check("debug reports the skinned bubbles", widgets.printedContains(env, "Chat bubbles skinned=2 font=true"))

        module = load()
        local broken = bubble()
        function broken.child.Center:SetAlpha() error("alpha refused") end
        env.fire("CHAT_MSG_PARTY", "pull")
        tick(module, 0.1)
        tick(module, 0.1)
        check("a bubble that refuses the skin is reported once and not retried",
            widgets.printedContains(env, "Chat bubbles skin") and #env.printed == 1)
        local bare = bubble()
        bare.child.Center, bare.child.Tail, bare.child.TopEdge = nil, nil, nil
        tick(module, 0.1)
        check("a bubble missing art keys still gets the fill", bare.child.rikFill ~= nil and #env.printed == 1)
        local empty = bubble()
        function empty:GetChildren() return nil end
        tick(module, 0.1)
        check("a bubble without a child is skipped", #env.printed == 1)

        module = load(nil, function() C_ChatBubbles, ChatBubbleFont = nil, nil end)
        env.fire("CHAT_MSG_SAY", "hello")
        check("a client without the bubble API stays idle and silent", module.Scanner == nil and #env.printed == 0)

        module = load({ modules = { chatbubbles = false } })
        bubble()
        env.fire("CHAT_MSG_SAY", "hello")
        check("a disabled module leaves bubbles and the font stock", module.Scanner == nil
            and ChatBubbleFont.font[1] == "Fonts\\FRIZQT__.TTF")
    end)
    restore()
    for _, name in ipairs(API) do _G[name] = saved[name] end
    check("chat bubble suite completes", ok, reason)
end
