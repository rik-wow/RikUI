-- Fake font objects with Blizzard's sizes and a pooled raid warning frame shaped like 69913's.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local OBJECTS = { ZoneTextFont = 102, SubZoneTextFont = 26, PVPInfoTextFont = 22, ErrorFont = 16 }
    local API = { "ZoneTextFont", "SubZoneTextFont", "PVPInfoTextFont", "ErrorFont", "GameFontNormalHuge",
        "AutoFollowStatusText", "RaidWarningFrame" }
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local restore = widgets.install()
    local function fontObject(size)
        local object = { path = "Fonts\\FRIZQT__.TTF", size = size, flags = "", writes = 0 }
        function object:GetFont() return self.path, self.size, self.flags end
        function object:SetFont(path, height, flags)
            if self.refuse then return false end
            self.path, self.size, self.flags, self.writes = path, height, flags, self.writes + 1
            return true
        end
        return object
    end
    local function installClient()
        for name, size in pairs(OBJECTS) do _G[name] = fontObject(size) end
        GameFontNormalHuge = fontObject(20)
        AutoFollowStatusText = fontObject(20)
        local frame = CreateFrame("Frame", "RaidWarningFrame", UIParent)
        frame.fontStringPool = { active = {} }
        function frame.fontStringPool:EnumerateActive() return pairs(self.active) end
        function frame:AcquireOrEvictSlot()
            local line = fontObject(20)
            self.fontStringPool.active[line] = true
            return line
        end
    end
    local function load(profile, combat, prepare)
        widgets.loadAddon(env, { "src/modules/screentext/screentext.lua" }, profile, combat, function()
            installClient()
            if prepare then prepare() end
        end)
        return RikUI.ScreenText
    end
    local function restyled(object, size)
        return object.path == RikUI.Media.font and object.size == size and object.flags == "OUTLINE"
    end
    local ok, reason = pcall(function()
        local module = load()
        check("zone, subzone, PvP and error text take the outlined RikUI font at Blizzard's sizes",
            restyled(ZoneTextFont, 102) and restyled(SubZoneTextFont, 26) and restyled(PVPInfoTextFont, 22)
            and restyled(ErrorFont, 16))
        check("the auto-follow text takes the font too", restyled(AutoFollowStatusText, 20))
        check("the shared huge game font is left alone", GameFontNormalHuge.writes == 0)

        -- The frame's OnUpdate runs every frame while a line shows, before the new line is drawn.
        local function frameTick() env.runScript(RaidWarningFrame, "OnUpdate", 0.016) end
        local first = RaidWarningFrame:AcquireOrEvictSlot()
        frameTick()
        check("a raid warning line gets the font before its first frame is drawn", restyled(first, 20))
        local second = RaidWarningFrame:AcquireOrEvictSlot()
        frameTick()
        check("a reused line is restyled once, a new one on arrival", first.writes == 1 and restyled(second, 20))
        check("nothing was printed by a clean restyle", #env.printed == 0)
        SlashCmdList.RIKUI("debug")
        check("debug reports the restyled counts", widgets.printedContains(env, "Screen text fonts=5 warnings=2"))

        module = load(nil, true)
        check("fonts are not protected, so a combat login restyles at once", restyled(ZoneTextFont, 102))

        module = load(nil, false, function() ErrorFont.refuse, ZoneTextFont.size = true, 0 end)
        check("a refused font is reported once and the rest still restyle",
            widgets.printedContains(env, "Screen text font ErrorFont") and #env.printed == 1
            and restyled(SubZoneTextFont, 26))
        check("a font object without a usable size falls back to the module's size", restyled(ZoneTextFont, 32))

        module = load(nil, false, function()
            ZoneTextFont, AutoFollowStatusText, RaidWarningFrame = nil, nil, nil
        end)
        check("missing font objects and a missing raid warning frame are skipped silently",
            restyled(SubZoneTextFont, 26) and #env.printed == 0)
        module = load(nil, false, function() RaidWarningFrame.AcquireOrEvictSlot = nil end)
        check("a raid warning frame without the slot method is left alone silently", #env.printed == 0)

        module = load({ modules = { screentext = false } })
        check("a disabled module leaves the stock fonts", ZoneTextFont.writes == 0 and ErrorFont.writes == 0)
    end)
    restore()
    for _, name in ipairs(API) do _G[name] = saved[name] end
    env.inCombat = false
    check("screen text suite completes", ok, reason)
end
