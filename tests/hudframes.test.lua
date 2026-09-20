-- The queue status tooltip with its pooled entries and the framerate label, with the 69913 keys.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local API = { "QueueStatusFrame", "FramerateFrame" }
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local restore = widgets.install()
    local ENTRY_TEXT = { "Title", "Status", "SubTitle", "TimeInQueue", "AverageWait", "ExtraText" }
    local function label(owner, size)
        local value = owner:CreateFontString()
        function value:GetFont() return "Fonts\\FRIZQT__.TTF", size, "" end
        return value
    end
    local function queueFrame()
        local frame = CreateFrame("Frame", "QueueStatusFrame", UIParent)
        frame.NineSlice = CreateFrame("Frame", nil, frame)
        frame.statusEntriesPool = { active = {} }
        function frame.statusEntriesPool:EnumerateActive() return pairs(self.active) end
        function frame:AddEntry()
            local entry = CreateFrame("Frame", nil, self)
            for _, key in ipairs(ENTRY_TEXT) do entry[key] = label(entry, key == "Title" and 16 or 12) end
            self.statusEntriesPool.active[entry] = true
            return entry
        end
        frame:Hide()
        return frame
    end
    local function framerate()
        local frame = CreateFrame("Frame", "FramerateFrame", UIParent)
        frame.Label, frame.FramerateText = label(frame, 14), label(frame, 14)
        frame:Hide()
        return frame
    end
    local function load(profile, prepare)
        widgets.loadAddon(env, { "skin.lua", "hudframes.lua" }, profile, false, function()
            queueFrame()
            framerate()
            if prepare then prepare() end
        end)
        return RikUI.HudFrames
    end
    local ok, reason = pcall(function()
        local module = load()
        local queue = QueueStatusFrame
        check("nothing is skinned before the tooltip shows", queue.NineSlice.alpha == nil and queue.rikFill == nil)
        local first = queue:AddEntry()
        queue:Show()
        check("the queue status tooltip loses its nine-slice and gets a flat fill, an edge and a fade-in",
            queue.NineSlice.alpha == 0 and queue.rikFill.texture == RikUI.Skin.FLAT and #queue.rikBorder == 4
            and queue.rikFade.plays == 1)
        check("its entries take the typeface at their own sizes and keep their colours",
            first.Title.fontPath == RikUI.Media.font and first.Title.fontSize == 16 and first.ExtraText.fontSize == 12
            and rawget(first.Status, "textColor") == nil)
        local fill = queue.rikFill
        queue:Hide()
        local later = queue:AddEntry()
        queue:Show()
        check("a second show fades in again, keeps the one fill and restyles an entry the pool made later",
            queue.rikFade.plays == 2 and queue.rikFill == fill and later.Title.fontPath == RikUI.Media.font)
        check("the tooltip was not moved, resized or rescripted", queue.points == nil and queue.width == nil
            and queue:GetScript("OnShow") == nil)

        check("the framerate label takes the typeface at login without being shown",
            FramerateFrame.Label.fontPath == RikUI.Media.font and FramerateFrame.FramerateText.fontSize == 14
            and FramerateFrame.rikFill == nil and not FramerateFrame:IsShown())
        check("a clean run prints nothing", #env.printed == 0)
        SlashCmdList.RIKUI("debug")
        check("debug reports the frames", widgets.printedContains(env, "HUD frames hooked=1 skinned=1 fonts=2"))

        module = load(nil, function() function QueueStatusFrame.NineSlice:SetAlpha() error("alpha refused") end end)
        QueueStatusFrame:Show()
        QueueStatusFrame:Hide()
        QueueStatusFrame:Show()
        check("a refused skin is reported once, not retried and not faded in",
            widgets.printedContains(env, "HUD frames skin QueueStatusFrame") and #env.printed == 1
            and QueueStatusFrame.rikFade == nil)

        module = load(nil, function() QueueStatusFrame.statusEntriesPool = nil end)
        QueueStatusFrame:Show()
        check("a tooltip without an entry pool still goes flat", QueueStatusFrame.rikFill ~= nil and #env.printed == 0)

        module = load(nil, function() QueueStatusFrame:Show() end)
        check("a tooltip already showing at login is skinned at once", QueueStatusFrame.NineSlice.alpha == 0)

        module = load(nil, function()
            local marker = CreateFrame("Frame", "SuperTrackedFrame", UIParent)
            marker.DistanceText, marker.Icon = label(marker, 12), marker:CreateTexture()
        end)
        check("the quest navigation marker's distance text takes the typeface and its icon is left alone",
            SuperTrackedFrame.DistanceText.fontPath == RikUI.Media.font and SuperTrackedFrame.DistanceText.fontSize == 12
            and rawget(SuperTrackedFrame.Icon, "alpha") == nil and SuperTrackedFrame.rikFill == nil
            and #env.printed == 0)
        SuperTrackedFrame = nil

        module = load(nil, function() QueueStatusFrame, FramerateFrame = nil, nil end)
        check("missing frames are skipped silently", #env.printed == 0)

        module = load({ modules = { hudframes = false } })
        QueueStatusFrame:Show()
        check("a disabled module leaves both frames stock", QueueStatusFrame.NineSlice.alpha == nil
            and rawget(FramerateFrame.Label, "fontPath") == nil)
    end)
    restore()
    for _, name in ipairs(API) do _G[name] = saved[name] end
    check("HUD frame suite completes", ok, reason)
end
