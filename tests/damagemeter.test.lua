-- Fake damage meter with the 69913 shape: an owner frame (an Edit Mode system) whose
-- SetupSessionWindow makes windows named DamageMeterSessionWindow<n>; each window has a header
-- texture, three header buttons, strings on the window, its dropdowns and its container, a scroll box
-- of entries and a local player entry. Entries answer Blizzard's getters and, like the client, put
-- their shadow art back to full alpha in UpdateBackground. The suite checks the designed pieces, the
-- motion, the layout holder and that nothing Blizzard drives from settings is written.
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
        local bar, iconFrame = CreateFrame("StatusBar", nil, frame), CreateFrame("Frame", nil, frame)
        function bar:SetStatusBarTexture(texture) self.barTexture = texture end
        local parts = { bar = bar, name = text(bar, "Name", 12), value = text(bar, "Value", 12),
            background = bar:CreateTexture(), edge = bar:CreateTexture(), icon = iconFrame:CreateTexture(),
            iconFrame = iconFrame }
        function frame:GetStatusBar() return parts.bar end
        function frame:GetName() return parts.name end
        function frame:GetValue() return parts.value end
        function frame:GetBackground() return parts.background end
        function frame:GetBackgroundEdge() return parts.edge end
        function frame:GetIcon() return parts.iconFrame end
        function frame:GetIconTexture() return parts.icon end
        function frame:UpdateBackground() parts.background:SetAlpha(1); parts.edge:SetAlpha(1) end
        frame.parts = parts
        return frame
    end
    local function scrollBox(parent, broken)
        local box = CreateFrame("Frame", nil, parent)
        box.rows, box.callbacks = {}, {}
        function box:ForEachFrame(callback)
            if broken then error("view is not ready") end
            for _, row in ipairs(self.rows) do callback(row) end
        end
        function box:RegisterCallback(event, callback, owner)
            table.insert(self.callbacks, { event = event, callback = callback, owner = owner })
        end
        return box
    end
    local function headerButton(parent)
        local button = CreateFrame("Button", nil, parent)
        button.normal = button:CreateTexture()
        function button:GetNormalTexture() return self.normal end
        return button
    end
    local function window(index, brokenList)
        local frame = CreateFrame("Frame", "DamageMeterSessionWindow" .. index, DamageMeter)
        frame.children = {}
        function frame:GetChildren() return unpack(self.children) end
        frame.Header = frame:CreateTexture()
        text(frame, "SessionTimer", 13)
        frame.MinimizeButton, frame.SettingsDropdown = headerButton(frame), headerButton(frame)
        frame.SessionDropdown, frame.DamageMeterTypeDropdown = CreateFrame("Button", nil, frame), CreateFrame("Button", nil, frame)
        frame.DamageMeterTypeDropdown.Arrow = frame.DamageMeterTypeDropdown:CreateTexture()
        text(frame.SessionDropdown, "SessionName", 13)
        text(frame.DamageMeterTypeDropdown, "TypeName", 13)
        local container = CreateFrame("Frame", nil, frame)
        frame.MinimizeContainer = container
        container.Background = container:CreateTexture()
        text(container, "NotActive", 13)
        container.ScrollBox, container.LocalPlayerEntry = scrollBox(container, brokenList), entry(container)
        container.ScrollBox.rows[1] = entry(container.ScrollBox)
        container.SourceWindow = CreateFrame("Frame", nil, container)
        container.SourceWindow.ScrollBox = scrollBox(container.SourceWindow)
        return frame
    end
    local function installClient(brokenList)
        for _, name in ipairs(NAMES) do _G[name] = nil end
        ScrollBoxListMixin = { Event = { OnAcquiredFrame = "OnAcquiredFrame" } }
        DamageMeter = CreateFrame("Frame", "DamageMeter", UIParent)
        DamageMeter:SetSize(400, 200)
        function DamageMeter:SetupSessionWindow(index, data)
            data.sessionWindow = data.sessionWindow or window(index)
            data.sessionWindow.alpha = 0.8
        end
        function DamageMeter:ApplySystemAnchor()
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10)
        end
        window(1, brokenList)
    end
    local function load(profile, prepare)
        widgets.loadAddon(env, { "src/platform/editmode.lua", "src/ui/skin.lua", "src/modules/controls/controls.lua", "src/modules/damagemeter/damagemeter.lua" }, profile, false, prepare or installClient)
        return RikUI.DamageMeter
    end
    local function anchoredTo(frame, holder)
        local point = frame.points and frame.points[#frame.points]
        return point and point[1] == "TOPLEFT" and point[2] == holder and point[3] == "TOPLEFT"
    end
    local ok, reason = pcall(function()
        local module = load()
        local first = DamageMeterSessionWindow1
        local container = first.MinimizeContainer
        local head = module.Headers[first]
        check("a window that exists at login loses its header art and gets a flat header, an edge and an accent rule",
            first.Header.alpha == 0 and head.fill.texture == RikUI.Skin.FLAT and head.fill.points[1][2] == first.Header
            and #head.edge == 4 and head.accent.height == 2 and head.accent.points[1][1] == "BOTTOMLEFT")
        check("the window's strings take the typeface at Blizzard's size and keep their colour",
            first.SessionTimer.fontPath == RikUI.Media.font and first.SessionTimer.fontSize == 13
            and first.SessionDropdown.SessionName.fontPath == RikUI.Media.font
            and first.DamageMeterTypeDropdown.TypeName.fontPath == RikUI.Media.font
            and container.NotActive.fontPath == RikUI.Media.font and rawget(first.SessionTimer, "textColor") == nil)
        local minimize = module.Buttons[first.MinimizeButton]
        check("the minimize and settings buttons go flat with a glyph and a hover tween, the type arrow becomes a glyph",
            first.MinimizeButton.normal.alpha == 0 and minimize.fill.texture == RikUI.Skin.FLAT
            and minimize.glyph.rikIcon == "minus" and minimize.glyph.color[4] == nil and minimize.hover ~= nil
            and module.Buttons[first.SettingsDropdown].glyph.rikIcon == "settings"
            and first.DamageMeterTypeDropdown.Arrow.alpha == 0
            and module.Buttons[first.DamageMeterTypeDropdown].glyph.rikIcon == "chevron-down")
        check("window alpha, background alpha, size and points stay Blizzard's", rawget(first, "alpha") == nil
            and rawget(container.Background, "alpha") == nil and first.width == nil and first.points == nil
            and first.rikFade == nil)

        local row = container.ScrollBox.rows[1]
        local record = module.Entries[row]
        check("an entry already in the list gets the flat bar texture, an own track and edge, the typeface and a cropped icon",
            row.parts.bar.barTexture == RikUI.Media.statusbar and record.track.layer == "BACKGROUND" and #record.edge == 4
            and row.parts.name.fontPath == RikUI.Media.font and row.parts.value.fontSize == 12
            and row.parts.icon.coords[1] > 0 and rawget(row.parts.bar, "color") == nil)
        check("its icon edge is drawn over the icon inside its bounds, because the entry clips its children",
            record.iconEdge[1].layer == "OVERLAY" and record.iconEdge[1].points[1][2] == row.parts.icon
            and record.iconEdge[1].points[1][4] == 0)
        check("Blizzard's shadow art is faded", row.parts.background.alpha == 0 and row.parts.edge.alpha == 0)
        local watch = container.ScrollBox.callbacks[1]
        row:UpdateBackground()
        watch.callback(watch.owner, row, {}, false)
        check("and faded again when the row is handed out after Blizzard's UpdateBackground put it back",
            row.parts.background.alpha == 0 and row.parts.edge.alpha == 0)
        check("the local player entry is skinned too", module.Entries[container.LocalPlayerEntry] ~= nil)
        check("both scroll boxes are watched once for rows handed out later", #container.ScrollBox.callbacks == 1
            and #container.SourceWindow.ScrollBox.callbacks == 1
            and container.ScrollBox.callbacks[1].event == "OnAcquiredFrame")

        local late = entry(container.ScrollBox)
        watch.callback(watch.owner, late, {}, true)
        check("a newly created row is skinned and fades in once", module.Entries[late] ~= nil
            and module.Entries[late].fade.plays == 1)
        watch.callback(watch.owner, late, {}, false)
        check("a pooled row handed out again does not fade again, so a combat refresh cannot flicker",
            module.Entries[late].fade.plays == 1)
        env.runScript(late, "OnEnter")
        check("hovering a row fades its highlight in", module.Entries[late].hover.plays == 1
            and module.Entries[late].highlight.texture == RikUI.Media.highlight)

        local holder = module.Holder
        local group = RikUI.Layout.Groups.damagemeter
        check("the meter hangs on a RikUI holder that /rik move can drag, sized like the meter",
            holder ~= nil and group ~= nil and group.frames[1] == holder and holder.width == 400 and holder.height == 200
            and anchoredTo(DamageMeter, holder))
        local function applyLayout()
            DamageMeter:ApplySystemAnchor()
            env.fire("EDIT_MODE_LAYOUTS_UPDATED")
            env.flushTimers()
        end
        applyLayout()
        check("when Edit Mode re-anchors the meter it goes back onto the holder", anchoredTo(DamageMeter, holder))
        function DamageMeter:IsEditing() return true end
        applyLayout()
        check("but while Edit Mode is open the meter is left where Edit Mode puts it", not anchoredTo(DamageMeter, holder))
        DamageMeter.IsEditing = nil
        DamageMeter:SetSize(300, 150)
        env.runScript(DamageMeter, "OnSizeChanged")
        check("the holder follows a resize done in Edit Mode", holder.width == 300 and holder.height == 150)

        local data = {}
        DamageMeter:SetupSessionWindow(2, data)
        local second = data.sessionWindow
        env.flushTimers()
        check("a window Blizzard sets up later is found while the meter is shown and skinned after Blizzard's setup",
            second.alpha == 0.8 and second.Header.alpha == 0 and module.Headers[second] ~= nil)
        local header = module.Headers[second]
        DamageMeter:SetupSessionWindow(2, data)
        env.flushTimers()
        check("a second setup of the same window adds nothing", module.Headers[second] == header
            and #second.MinimizeContainer.ScrollBox.callbacks == 1 and #env.printed == 0)
        SlashCmdList.RIKUI("debug")
        check("debug reports windows, entries and watched lists",
            widgets.printedContains(env, "DamageMeter windows=2 entries=5 lists=4 failed=0"))

        module = load(nil, function() installClient(true) end)
        local broken = DamageMeterSessionWindow1.MinimizeContainer.ScrollBox
        check("a list that cannot be walked yet is still watched, and the rest of the window is skinned",
            #broken.callbacks == 1 and module.Headers[DamageMeterSessionWindow1] ~= nil
            and module.Entries[DamageMeterSessionWindow1.MinimizeContainer.LocalPlayerEntry] ~= nil
            and #env.printed == 0)

        module = load(nil, function()
            installClient()
            function DamageMeterSessionWindow1.Header:SetAlpha() error("header locked") end
        end)
        DamageMeter:SetupSessionWindow(1, { sessionWindow = DamageMeterSessionWindow1 })
        env.flushTimers()
        SlashCmdList.RIKUI("debug")
        check("a window that refuses the skin is reported once, not retried, and debug repeats the reason",
            widgets.printedContains(env, "DamageMeter skin") and widgets.printedContains(env, "header locked")
            and module.Headers[DamageMeterSessionWindow1] == nil)

        module = load(nil, function()
            for _, name in ipairs(NAMES) do _G[name] = nil end
        end)
        check("a client without the damage meter says nothing and makes no holder", #env.printed == 0
            and module.Holder == nil)

        module = load({ modules = { damagemeter = false } })
        check("a disabled module leaves the meter stock and unanchored", rawget(DamageMeterSessionWindow1.Header, "alpha") == nil
            and DamageMeter.points == nil)
    end)
    restore()
    for _, name in ipairs(NAMES) do _G[name] = saved[name] end
    check("damage meter suite completes", ok, reason)
end
