-- Pinned 69913 viewer shapes; protected frames reject all non-region writes.
return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local names = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
    local saved, created, snapshots = {}, {}, {}
    for _, name in ipairs(names) do saved[name] = _G[name] end
    local restore = widgets.install()
    local function texture(owner, atlas)
        local region = owner:CreateTexture()
        local methods = getmetatable(region).__index
        setmetatable(region, { __index = function(t, key)
            if key:match("^[A-Z]") then return methods(t, key) end
        end })
        function region:GetAtlas() return atlas end
        return region
    end
    local function deny() error("protected frame write") end
    local function protect(frame)
        local snapshot = {}
        for key, value in pairs(frame) do snapshot[key] = value end
        snapshots[frame] = snapshot
        for _, method in ipairs({ "SetAttribute", "SetParent", "SetPoint", "ClearAllPoints", "SetSize",
            "SetAlpha", "SetScript", "HookScript", "SetStatusBarTexture", "SetValue", "SetMinMaxValues",
            "SetStatusBarColor", "SetText", "SetCooldown", "SetCooldownFromDurationObject" }) do
            frame[method], snapshot[method] = deny, deny
        end
        local meta = getmetatable(frame)
        setmetatable(frame, { __index = meta.__index, __newindex = deny })
    end
    local function item(parent, kind)
        local value = CreateFrame("Frame", nil, parent)
        local owner = kind == "bar" and CreateFrame("Frame", nil, value) or value
        local icon = texture(owner)
        if kind == "bar" then value.Icon, owner.Icon = owner, icon else value.Icon = icon end
        local mask = texture(owner, "UI-HUD-CoolDownManager-Mask")
        local otherMask = texture(owner, "unrelated-mask")
        local masks = { mask, otherMask }
        function icon:GetNumMaskTextures() return #masks end
        function icon:GetMaskTexture(index) return masks[index] end
        function icon:RemoveMaskTexture(target)
            for index = #masks, 1, -1 do if masks[index] == target then table.remove(masks, index) end end
        end
        local overlay = texture(owner, "UI-HUD-CoolDownManager-IconOverlay")
        local range = texture(owner, "UI-HUD-CoolDownManager-IconOverlay-Unusable")
        function owner:GetRegions() return icon, mask, overlay, range end
        local count
        if kind == "bar" then
            count = owner:CreateFontString()
            owner.Applications = count
            value.Bar = CreateFrame("StatusBar", nil, value)
            local fill = texture(value.Bar)
            function value.Bar:GetStatusBarTexture() return fill end
            value.Bar.BarBG = texture(value.Bar, "UI-HUD-CoolDownManager-Bar-BG")
            value.Bar.Name, value.Bar.Duration = value.Bar:CreateFontString(), value.Bar:CreateFontString()
            value.Bar.Name:SetText("Secret-backed spell name")
            value.Bar.Duration:SetText("native duration")
            value.Bar.Name:SetTextColor(1, 0.82, 0)
            function value.Bar.Name:GetFont() return "native", 18 end
            function value.Bar.Duration:GetFont() return "native", 9 end
            value.Bar.Duration:Hide()
            value.Bar.Pip = texture(value.Bar)
            value.Bar.value = env.SECRET
            protect(value.Bar)
        else
            value.Cooldown = CreateFrame("Cooldown", nil, value)
            local font = value.Cooldown:CreateFontString()
            function value.Cooldown:GetCountdownFontString() return font end
            protect(value.Cooldown)
            local container = CreateFrame("Frame", nil, value)
            count = container:CreateFontString()
            if kind == "buff" then
                value.Applications, container.Applications = container, count
            else
                value.ChargeCount, container.Current = container, count
            end
            protect(container)
        end
        value.DebuffBorder = CreateFrame("Frame", nil, value)
        value.DebuffBorder.Texture = texture(value.DebuffBorder, "native-dispel-border")
        value.DebuffBorder.Texture:SetVertexColor(0, 1, 0)
        protect(value.DebuffBorder)
        local extra, originalCreate = {}, owner.CreateTexture
        created[value] = extra
        function owner:CreateTexture(...)
            local region = originalCreate(self, ...)
            extra[#extra + 1] = region
            return region
        end
        if owner ~= value then protect(owner) end
        protect(value)
        return value, { icon = icon, masks = masks, overlay = overlay, range = range, count = count }
    end
    local function viewer(name, kind, shown)
        local value = CreateFrame("Frame", name, UIParent)
        value.shown = shown == true
        local active = {}
        value.itemFramePool = { EnumerateActive = function() return pairs(active) end }
        value.auraInstanceIDToItemFramesMap = setmetatable({}, { __index = deny, __pairs = deny })
        local first, regions = item(value, kind)
        active[first] = true
        return value, first, regions, active
    end
    local function load(profile, prepare)
        created, snapshots = {}, {}
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/cooldownviewer/cooldownviewer.lua",
            "src/modules/cooldownviewer/cooldownviewer-style.lua" },
            profile, false, function()
                for _, name in ipairs(names) do _G[name] = nil end
                if prepare then prepare() end
            end)
        return RikUI.CooldownViewer
    end
    local function unchanged()
        for frame, snapshot in pairs(snapshots) do
            for key, value in pairs(frame) do if snapshot[key] ~= value then return false end end
            for key, value in pairs(snapshot) do if frame[key] ~= value then return false end end
        end
        return true
    end
    local ok, reason = pcall(function()
        local holders, items, regions, pools = {}, {}, {}, {}
        load(nil, function()
            for index, name in ipairs(names) do
                holders[index], items[index], regions[index], pools[index] =
                    viewer(name, index == 4 and "bar" or (index == 3 and "buff" or "charge"), index == 1)
            end
        end)
        check("visible viewer at login is skinned", regions[1].icon.coords and regions[1].icon.coords[1] == 0.08)
        check("hidden viewers remain untouched", regions[2].icon.coords == nil and #created[items[2]] == 0)
        for index = 2, 4 do holders[index]:Show() end
        for index = 1, 4 do
            local parts, edge = regions[index], created[items[index]]
            check("viewer " .. index .. " has one cropped icon edge", parts.icon.coords and parts.icon.coords[1] == 0.08
                and #edge == 10 and edge[1].points[1][2] == parts.icon and edge[1].points[1][4] == -1)
            check("viewer " .. index .. " only removes its decorative mask and overlay",
                #parts.masks == 1 and parts.masks[1]:GetAtlas() == "unrelated-mask"
                and parts.overlay.alpha == 0 and parts.range.alpha == nil)
            check("viewer " .. index .. " count gets RikUI font", parts.count.fontPath == RikUI.Media.font)
            check("viewer " .. index .. " retains native debuff semantics",
                items[index].DebuffBorder.Texture:GetAtlas() == "native-dispel-border"
                and items[index].DebuffBorder.Texture.color[2] == 1)
        end
        check("cooldown numbers use the bar typeface and size",
            items[1].Cooldown:GetCountdownFontString().fontPath == RikUI.Media.font
            and items[1].Cooldown:GetCountdownFontString().fontSize == RikUI.Media.sizes.cooldown)
        local bar = items[4].Bar
        check("buff bar fill and strings use RikUI media", bar:GetStatusBarTexture().texture == RikUI.Media.statusbar
            and bar.Name.fontPath == RikUI.Media.font and bar.Duration.fontPath == RikUI.Media.font
            and bar.Name.fontSize == 18 and bar.Duration.fontSize == 9)
        check("buff text content, colour, duration visibility and native value remain intact",
            bar.Name.text == "Secret-backed spell name" and bar.Name.textColor[2] == 0.82
            and bar.Duration.text == "native duration" and not bar.Duration:IsShown() and bar.value == env.SECRET)
        items[4].Icon:Hide() -- Native NameOnly mode hides this child without hiding the bar item.
        check("buff bar edge belongs to the hideable icon container",
            created[items[4]][1].parent == items[4].Icon and not items[4].Icon:IsShown())
        items[4].Icon:Show()
        check("styling never writes Blizzard item fields or protected frame methods", unchanged() and #env.printed == 0)

        local originalEdge = created[items[1]][1]
        regions[1].icon:SetTexCoord(0, 1, 0, 1)
        regions[1].overlay:SetAlpha(1)
        regions[1].count:SetFont("native", 20)
        RikUI.Bars = { BorderColor = function() return { 0.9, 0.1, 0.2 } end }
        local late, lateParts = item(holders[2], "charge")
        pools[2][late] = true
        env.inCombat = true
        env.flushTimers()
        env.inCombat = false
        check("visible scan covers new pool frames in combat", lateParts.icon.coords and #created[late] == 10)
        check("pool reuse restores cosmetics without another edge", regions[1].icon.coords[1] == 0.08
            and regions[1].overlay.alpha == 0 and regions[1].count.fontPath == RikUI.Media.font
            and #created[items[1]] == 10 and created[items[1]][1] == originalEdge)
        check("edges refresh with the current bar border colour", originalEdge.color[1] == 0.9)
        pools[2][late] = nil
        lateParts.icon:SetTexCoord(0, 1, 0, 1)
        env.flushTimers()
        check("released pool items are not styled", lateParts.icon.coords[1] == 0)
        pools[2][late] = true
        env.flushTimers()
        check("reacquired items reuse their edge and regain the crop", lateParts.icon.coords[1] == 0.08
            and #created[late] == 10)
        check("repeated scans still make no protected writes", unchanged() and #env.printed == 0)
        for _, holder in ipairs(holders) do holder:Hide() end
        env.flushTimers()
        check("hidden viewers stop the scan timer", #env.timers == 0)
        holders[1]:Show()
        holders[1]:Hide()
        holders[1]:Show()
        check("rapid shows keep a single scan timer", #env.timers == 1)

        load()
        check("missing viewer addon is quiet and idle", #env.timers == 0 and #env.printed == 0)
        local lateViewer, lateItem, lateRegions = viewer(names[1], "charge", true)
        env.fire("ADDON_LOADED", "Blizzard_CooldownViewer")
        env.fire("ADDON_LOADED", "Blizzard_CooldownViewer")
        check("late addon load discovers viewers only once", lateRegions.icon.coords and #created[lateItem] == 10
            and #lateViewer.hooks.OnShow == 1 and #env.timers == 1)

        load(nil, function()
            local holder, bad, _, active = viewer(names[1], "charge", true)
            function bad.Icon:SetTexCoord() error("icon locked") end
            local good, goodParts = item(holder, "buff")
            active[good] = true
            regions.good, items.bad = goodParts, bad
        end)
        env.flushTimers()
        check("one rejected item is reported once while other items skin", #env.printed == 1
            and widgets.printedContains(env, "CooldownViewer skin") and regions.good.icon.coords
            and #created[items.bad] == 0)

        load(nil, function()
            local holder, first, parts, active = viewer(names[1], "charge", true)
            function first.Icon:GetNumMaskTextures() return env.SECRET end
            function parts.overlay:GetAtlas() return env.SECRET end
            active[env.SECRET] = true
            active[CreateFrame("Frame", nil, holder)] = true -- incomplete pooled item
            regions.opaque = parts
        end)
        check("opaque hierarchy and incomplete items skip unsupported cosmetics without failure",
            regions.opaque.icon.coords and #regions.opaque.masks == 2
            and regions.opaque.overlay.alpha == nil and #env.printed == 0)

        load(nil, function()
            local broken = CreateFrame("Frame", names[1], UIParent)
            broken.itemFramePool = { EnumerateActive = function() error("pool unavailable") end }
            viewer(names[2], "charge", true)
        end)
        env.flushTimers()
        check("unavailable pools are isolated and reported once",
            #env.printed == 1 and widgets.printedContains(env, "CooldownViewer scan"))

        local disabledParts
        load({ modules = { cooldownviewer = false } }, function()
            local _, _, parts = viewer(names[1], "charge", true)
            disabledParts = parts
        end)
        env.fire("ADDON_LOADED", "Blizzard_CooldownViewer")
        check("disabled module leaves viewers stock", disabledParts.icon.coords == nil and #env.timers == 0)
    end)
    restore()
    for _, name in ipairs(names) do _G[name] = saved[name] end
    env.inCombat = false
    check("cooldown viewer suite completes", ok, reason)
end
