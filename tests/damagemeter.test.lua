-- Fake damage meter with the 69913 shape: an owner frame whose SetupSessionWindow makes windows named
-- DamageMeterSessionWindow<n>, each with a header texture, strings on the window, its two dropdowns
-- and its container, a scroll box of entries and a local player entry. Entries answer Blizzard's
-- getters. The suite checks the flat pieces and that nothing Blizzard drives from settings is written.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local NAMES = { "DamageMeter", "DamageMeterSessionWindow1", "DamageMeterSessionWindow2", "ScrollBoxListMixin" }
    local saved = {}
    for _, name in ipairs(NAMES) do saved[name] = _G[name] end
    local restore = widgets.install()

    local function text(owner, key, size)
        local value = owner:CreateFontString()
        function value:GetFont() return "Fonts\\FRIZQT__.TTF", size, "" end
        owner[key] = value
        return value
    end
    local function entry(parent)
        local frame = CreateFrame("Button", nil, parent)
        local bar = CreateFrame("StatusBar", nil, frame)
        function bar:SetStatusBarTexture(texture) self.barTexture = texture end
        local parts = { bar = bar, name = text(bar, "Name", 12), value = text(bar, "Value", 12),
            background = bar:CreateTexture(), edge = bar:CreateTexture(), icon = frame:CreateTexture() }
        function frame:GetStatusBar() return parts.bar end
        function frame:GetName() return parts.name end
        function frame:GetValue() return parts.value end
        function frame:GetBackground() return parts.background end
        function frame:GetBackgroundEdge() return parts.edge end
        function frame:GetIconTexture() return parts.icon end
        frame.parts = parts
        return frame
    end
    local function scrollBox(parent)
        local box = CreateFrame("Frame", nil, parent)
        box.rows, box.callbacks = {}, {}
        function box:ForEachFrame(callback) for _, row in ipairs(self.rows) do callback(row) end end
        function box:RegisterCallback(event, callback, owner)
            table.insert(self.callbacks, { event = event, callback = callback, owner = owner })
        end
        return box
    end
    local function window(index)
        local frame = CreateFrame("Frame", "DamageMeterSessionWindow" .. index, DamageMeter)
        frame.children = {}
        function frame:GetChildren() return unpack(self.children) end
        frame.Header = frame:CreateTexture()
        text(frame, "SessionTimer", 13)
        frame.SessionDropdown, frame.DamageMeterTypeDropdown = CreateFrame("Button", nil, frame), CreateFrame("Button", nil, frame)
        text(frame.SessionDropdown, "SessionName", 13)
        text(frame.DamageMeterTypeDropdown, "TypeName", 13)
        local container = CreateFrame("Frame", nil, frame)
        frame.MinimizeContainer = container
        container.Background = container:CreateTexture()
        text(container, "NotActive", 13)
        container.ScrollBox, container.LocalPlayerEntry = scrollBox(container), entry(container)
        container.ScrollBox.rows[1] = entry(container.ScrollBox)
        container.SourceWindow = CreateFrame("Frame", nil, container)
        container.SourceWindow.ScrollBox = scrollBox(container.SourceWindow)
        return frame
    end
    local function installClient()
        for _, name in ipairs(NAMES) do _G[name] = nil end
        ScrollBoxListMixin = { Event = { OnAcquiredFrame = "OnAcquiredFrame" } }
        DamageMeter = CreateFrame("Frame", "DamageMeter", UIParent)
        function DamageMeter:SetupSessionWindow(index, data)
            data.sessionWindow = data.sessionWindow or window(index)
            data.sessionWindow.alpha = 0.8
        end
        window(1)
    end
    local function load(profile, prepare)
        widgets.loadAddon(env, { "skin.lua", "controls.lua", "damagemeter.lua" }, profile, false, prepare or installClient)
        return RikUI.DamageMeter
    end
    local ok, reason = pcall(function()
        local module = load()
        local first = DamageMeterSessionWindow1
        local container = first.MinimizeContainer
        check("a window that exists at login loses its header art and gets a flat header with an edge",
            first.Header.alpha == 0 and module.Headers[first].fill.texture == RikUI.Skin.FLAT
            and module.Headers[first].fill.points[1][2] == first.Header and #module.Headers[first].edge == 4)
        check("the window's strings take the typeface at Blizzard's size and keep their colour",
            first.SessionTimer.fontPath == RikUI.Media.font and first.SessionTimer.fontSize == 13
            and first.SessionDropdown.SessionName.fontPath == RikUI.Media.font
            and first.DamageMeterTypeDropdown.TypeName.fontPath == RikUI.Media.font
            and container.NotActive.fontPath == RikUI.Media.font and rawget(first.SessionTimer, "textColor") == nil)
        check("window alpha, background alpha, size and points stay Blizzard's", rawget(first, "alpha") == nil
            and rawget(container.Background, "alpha") == nil and first.width == nil and first.points == nil
            and first.rikFade == nil)
        local row = container.ScrollBox.rows[1]
        check("an entry already in the list gets the RikUI bar texture, typeface, faded shadow art and a cropped icon",
            row.parts.bar.barTexture == RikUI.Media.statusbar and row.parts.name.fontPath == RikUI.Media.font
            and row.parts.value.fontSize == 12 and row.parts.background.alpha == 0 and row.parts.edge.alpha == 0
            and row.parts.icon.coords[1] > 0 and rawget(row.parts.bar, "color") == nil)
        check("the local player entry is skinned too", container.LocalPlayerEntry.parts.bar.barTexture == RikUI.Media.statusbar)
        check("both scroll boxes are watched once for rows handed out later", #container.ScrollBox.callbacks == 1
            and #container.SourceWindow.ScrollBox.callbacks == 1
            and container.ScrollBox.callbacks[1].event == "OnAcquiredFrame")
        local late = entry(container.ScrollBox)
        local watch = container.ScrollBox.callbacks[1]
        watch.callback(watch.owner, late, {}, true)
        check("a row handed out later is skinned", late.parts.bar.barTexture == RikUI.Media.statusbar
            and late.parts.name.fontPath == RikUI.Media.font)

        local data = {}
        DamageMeter:SetupSessionWindow(2, data)
        local second = data.sessionWindow
        check("a window Blizzard sets up later is skinned after Blizzard's own setup",
            second.alpha == 0.8 and second.Header.alpha == 0 and module.Headers[second] ~= nil)
        local header = module.Headers[second]
        DamageMeter:SetupSessionWindow(2, data)
        check("a second setup of the same window adds nothing", module.Headers[second] == header
            and #second.MinimizeContainer.ScrollBox.callbacks == 1 and #env.printed == 0)
        SlashCmdList.RIKUI("debug")
        check("debug reports the windows", widgets.printedContains(env, "DamageMeter windows=2 failed=0"))

        module = load(nil, function()
            installClient()
            function DamageMeterSessionWindow1.Header:SetAlpha() error("header locked") end
        end)
        DamageMeter:SetupSessionWindow(1, { sessionWindow = DamageMeterSessionWindow1 })
        check("a window that refuses the skin at login is reported once and not retried", #env.printed == 1
            and widgets.printedContains(env, "DamageMeter skin") and module.Headers[DamageMeterSessionWindow1] == nil)

        module = load(nil, function()
            for _, name in ipairs(NAMES) do _G[name] = nil end
        end)
        check("a client without the damage meter says nothing", #env.printed == 0)

        module = load({ modules = { damagemeter = false } })
        check("a disabled module leaves the meter stock", rawget(DamageMeterSessionWindow1.Header, "alpha") == nil)
    end)
    restore()
    for _, name in ipairs(NAMES) do _G[name] = saved[name] end
    check("damage meter suite completes", ok, reason)
end
