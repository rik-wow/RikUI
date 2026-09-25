-- Real button clicks, Layout drag persistence and protected top-level viewer anchors.
return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local names = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
    local saved, native, writes, callbacks, managed, snapTargets = {}, {}, 0, {}, {}, {}
    for _, name in ipairs(names) do saved[name] = _G[name] end
    for _, name in ipairs({ "C_CVar", "CooldownViewerSettings", "ShowUIPanel", "EditModeManagerFrame",
        "EventRegistry", "GetCursorPosition", "IsShiftKeyDown" }) do saved[name] = _G[name] end
    local oldWidth, oldHeight, oldScale = UIParent.GetWidth, UIParent.GetHeight, UIParent.GetEffectiveScale
    local restore, enabled, editing, reject, settings, cursor = widgets.install(), false, false, false, 0, { 600, 400 }
    -- Record actual regions on every frame so the fixture can distinguish invisible anchors
    -- from the permanent boxes/titles reported in the user's screenshot.
    local createFrame = CreateFrame
    CreateFrame = function(...)
        local frame, regions = createFrame(...), {}
        for _, method in ipairs({ "CreateTexture", "CreateFontString" }) do
            local create = frame[method]
            frame[method] = function(self, ...)
                local region = create(self, ...)
                regions[#regions + 1] = region
                return region
            end
        end
        frame.GetRegions = function() return unpack(regions) end
        return frame
    end
    local function decorated(frame)
        if not frame:IsShown() then return false end
        for _, region in ipairs({ frame:GetRegions() }) do
            if region:IsShown() and rawget(region, "alpha") ~= 0 then return true end
        end
        return false
    end
    function UIParent:GetWidth() return 1920 end
    function UIParent:GetHeight() return 1080 end
    function UIParent:GetEffectiveScale() return 1 end
    GetCursorPosition = function() return unpack(cursor) end
    IsShiftKeyDown = function() return true end
    local function load(profile, absent, combat)
        callbacks, native, managed, snapTargets = {}, {}, {}, {}
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/ui/scroll.lua", "src/ui/shell.lua", "src/layout/layout-unlock.lua", "src/layout/layout-drag.lua",
            "src/platform/editmode.lua", "src/modules/cooldownviewer/cooldownviewer.lua",
            "src/modules/cooldownviewer/cooldownviewer-style.lua", "src/modules/cooldownviewer/cooldownviewer-layout.lua",
            "src/modules/cooldownviewer/cooldownviewer-controls.lua" }, profile, combat, function()
            C_CVar = {
                GetCVarBool = function(name) assert(name == "cooldownViewerEnabled"); return enabled end,
                SetCVar = function(name, value)
                    assert(not env.inCombat and name == "cooldownViewerEnabled")
                    if reject then return end
                    enabled = value == "1"
                    for _, frame in ipairs(native) do frame:SetShown(enabled) end
                    env.fire("CVAR_UPDATE", name, value)
                end,
            }
            CooldownViewerSettings = CreateFrame("Frame")
            ShowUIPanel = function(frame) assert(frame == CooldownViewerSettings); settings = settings + 1 end
            EditModeManagerFrame = { IsEditModeActive = function() return editing end }
            EventRegistry = { RegisterCallback = function(_, event, fn, owner)
                callbacks[event] = callbacks[event] or {}
                table.insert(callbacks[event], function() fn(owner) end)
            end }
            for index, name in ipairs(names) do
                _G[name] = nil
                if not absent then
                    local frame = CreateFrame("Frame", name, UIParent)
                    native[index] = frame
                    frame:SetSize(index == 4 and 220 or (index == 2 and 80 or 200), 50)
                    frame.shown, frame.nativeScale = enabled, 1
                    frame.itemFramePool = { EnumerateActive = function() return pairs({}) end }
                    frame.UpdateSystem = function() end
                    local manager = CreateFrame("Frame", nil, UIParent)
                    frame.isManagedFrame = index ~= 4
                    frame.systemInfo = { isInDefaultPosition = true }
                    local target = { snappedFrames = { [frame] = true } }
                    snapTargets[index], frame.snappedToFrame = target, target
                    function target:Hide()
                        for child in pairs(self.snappedFrames) do
                            child.points = { { "CENTER", UIParent, "CENTER", 0, 0 } }
                            child.systemInfo.isInDefaultPosition = false
                        end
                    end
                    frame.ClearFrameSnap = function(self)
                        if self.snappedToFrame then self.snappedToFrame.snappedFrames[self] = nil end
                        self.snappedToFrame = nil
                    end
                    if frame.isManagedFrame then frame.parent, managed[frame] = manager, true end
                    frame.BreakFromFrameManager = function(self)
                        assert(not env.inCombat and self.isManagedFrame)
                        self.ignoreFramePositionManager, self.parent, managed[self] = true, UIParent, nil
                    end
                    frame.ApplySystemAnchor = function(self)
                        assert(editing and not env.inCombat)
                        self.snappedToFrame, target.snappedFrames[self] = target, true
                        if self.isManagedFrame then
                            self.ignoreFramePositionManager, self.parent, managed[self] = nil, manager, true
                        end
                        self.points = { { "CENTER", UIParent, "CENTER", 0, 0 } }
                    end
                    frame:SetScript("OnShow", function(self)
                        if self.isManagedFrame and not self.ignoreFramePositionManager then
                            managed[self], self.parent = true, manager
                            self.points = { { "CENTER", manager, "CENTER", 0, 0 } }
                        end
                    end)
                    frame.SetPointBase = function(self, ...)
                        assert(not env.inCombat and not editing, "native anchor written while suspended")
                        writes = writes + 1; self.points = { { ... } }
                    end
                    frame.ClearAllPointsBase = function(self)
                        assert(not env.inCombat and not editing); self.points = {}
                    end
                    frame.SetScaleBase = function(self, scale)
                        assert(not env.inCombat and (not editing or scale == 1)); self.nativeScale = scale
                    end
                    frame.GetNumPoints = function(self) return #(self.points or {}) end
                    frame.GetPoint = function(self) return unpack(self.points[1]) end
                    frame.GetScale = function(self) return self.nativeScale end
                    local function deny() error("native bookkeeping method called") end
                    frame.SetPoint, frame.ClearAllPoints, frame.SetScale, frame.SetParent = deny, deny, deny, deny
                end
            end
        end)
        return RikUI.CooldownViewer
    end
    local function event(name)
        for _, callback in ipairs(callbacks[name] or {}) do callback() end
    end
    local ok, reason = pcall(function()
        local module = load()
        local dock = module.Controls
        check("cooldown controls belong to closed shell while viewers are off", dock and dock:GetParent() == RikUI.Shell.Panel.scroll.content
            and not RikUI.Shell.Panel:IsShown() and not RikUI.Layout.Groups.cooldowncontrols
            and dock.toggle and dock.toggle.label.text == "Cooldowns: Off")
        env.click(RikUI.Shell.Launcher)
        check("minimap launcher reveals cooldown mouse controls", RikUI.Shell.Panel:IsShown())
        if not dock then return end
        check("hidden managed viewers are detached and positioned before combat",
            not managed[native[1]] and native[1].points[1][2] == module.Holders[names[1]])
        env.click(dock.toggle)
        check("left click enables native cooldowns with truthful label", enabled and dock.toggle.label.text == "Cooldowns: On")
        for index, name in ipairs(names) do
            check(name .. " has no permanent box or title, even with an empty visible viewer",
                native[index]:IsShown() and not decorated(module.Holders[name]))
        end
        env.click(dock.toggle)
        check("toggle remains reachable when cooldowns are hidden", not enabled and dock:IsShown()
            and dock.toggle.label.text == "Cooldowns: Off")
        reject = true
        env.click(dock.toggle)
        check("rejected CVar write is visible and does not claim On", not enabled
            and dock.toggle.label.text == "Cooldowns: Off" and dock.message.text ~= "")
        reject = false
        enabled = true; env.fire("CVAR_UPDATE", "cooldownViewerEnabled", "1")
        check("external CVar update refreshes button state", dock.toggle.label.text == "Cooldowns: On")
        env.click(dock.settings)
        check("Settings button opens native spell selection", settings == 1)
        env.click(dock.move)
        check("Move button changes to Done", dock.move.label.text == "Done")
        local layout = RikUI.Layout
        local keys = { "cooldownessential", "cooldownutility", "cooldownbuffs", "cooldownbars" }
        for index, key in ipairs(keys) do
            local group, holder = layout.Groups[key], module.Holders[names[index]]
            check(key .. " is movable with a visible empty placeholder", group and layout.IsUnlocked(key)
                and holder:IsShown() and layout.Overlays[key]:IsShown()
                and layout.Overlays[key].label.text == group.label)
            check(key .. " anchors only the native root through base methods",
                native[index].points[1][2] == holder and native[index]:GetParent() == UIParent)
            check(key .. " move bounds fit content without title space or width floor",
                holder:GetWidth() == native[index]:GetWidth() and holder:GetHeight() == native[index]:GetHeight()
                and native[index].points[1][4] == 0 and native[index].points[1][5] == 0)
        end
        for _, emptySize in ipairs({ 0, 0.01, 1 }) do
            for _, frame in ipairs(native) do frame:SetSize(emptySize, emptySize) end
            module.RefreshLayout()
            for index, key in ipairs(keys) do
                local holder = module.Holders[names[index]]
                check(key .. " keeps usable empty mover bounds at size " .. emptySize,
                    holder:GetWidth() >= 220 and holder:GetHeight() >= 30
                    and layout.Overlays[key]:GetWidth() >= 220
                    and native[index]:GetWidth() == emptySize and native[index]:GetHeight() == emptySize)
            end
        end
        for index, frame in ipairs(native) do
            frame:SetSize(index == 4 and 220 or (index == 2 and 80 or 200), 50)
        end
        module.RefreshLayout()
        check("populated compact viewer returns to its exact bounds",
            module.Holders[names[2]]:GetWidth() == 80 and module.Holders[names[2]]:GetHeight() == 50)
        local lastOverlay = layout.Overlays[keys[4]]
        env.click(lastOverlay.lock)
        check("locking one group removes its placement label and outline",
            not lastOverlay:IsShown() and not decorated(module.Holders[names[4]]))
        local key = keys[1]
        local overlay = layout.Overlays[key]
        env.runScript(overlay, "OnMouseDown", "LeftButton")
        cursor = { 450, 500 }
        env.runScript(layout.DragDriver, "OnUpdate", 0.016)
        env.runScript(overlay, "OnMouseUp", "LeftButton")
        local position = RikUI.Profile.positions[key]
        check("mouse drag persists a real position", position and position.point == "BOTTOM" and position.x ~= 0)
        env.click(dock.move)
        check("Done locks all cooldown groups", dock.move.label.text == "Move groups" and not layout.IsUnlocked(key))
        for index, groupKey in ipairs(keys) do
            check("Done removes all decoration from " .. groupKey,
                not layout.Overlays[groupKey]:IsShown() and not decorated(module.Holders[names[index]]))
        end
        local profile = RikUI.Profile
        module = load(profile); dock = module.Controls
        check("reload restores the saved viewer position", layout.GetPosition(key).x == position.x
            and RikUI.Layout.GetPosition(key).x == position.x
            and native[1].points[1][2] == module.Holders[names[1]])
        for _, frame in ipairs(native) do frame:Show() end
        local before = writes
        env.flushTimers()
        check("unchanged scans do not rewrite native anchors", writes == before)
        native[1].points = { { "CENTER", UIParent, "CENTER", 0, 0 } }
        env.flushTimers()
        check("managed frame reset is repaired by the next visible scan", native[1].points[1][2] == module.Holders[names[1]])
        local holder = module.Holders[names[1]]
        holder.GetEffectiveScale = function() return 1.5 end
        RikUI.Layout.Apply()
        check("viewer scale follows its holder's effective scale", native[1].nativeScale == 1.5)
        editing = true; event("EditMode.Enter")
        check("Edit Mode restores native management without rewriting native saved position",
            managed[native[1]] and native[1].systemInfo.isInDefaultPosition == true and native[1].nativeScale == 1)
        native[1].points = { { "CENTER", UIParent, "CENTER", 10, 10 } }
        before = writes; env.flushTimers()
        check("native Edit Mode keeps its anchors and hides RikUI chrome", writes == before
            and not module.Holders[names[1]]:IsShown() and not dock.move:IsEnabled())
        editing = false; event("EditMode.Exit"); env.flushTimers()
        check("leaving Edit Mode restores saved anchors and RikUI scale",
            native[1].points[1][2] == module.Holders[names[1]] and native[1].nativeScale == 1.5)
        holder.GetEffectiveScale = function() return 1 end
        RikUI.Layout.Apply()
        for _, frame in ipairs(native) do frame:Hide() end
        env.click(dock.move)
        env.inCombat = true; env.fire("PLAYER_REGEN_DISABLED")
        before = writes
        snapTargets[1]:Hide()
        check("old snap target cannot move or save a viewer in combat",
            native[1].systemInfo.isInDefaultPosition and native[1].points[1][2] == module.Holders[names[1]])
        native[1]:Show()
        check("combat OnShow cannot reclaim a moved viewer through the native manager",
            not managed[native[1]] and native[1].points[1][2] == module.Holders[names[1]] and writes == before)
        native[1].points = { { "CENTER", UIParent, "CENTER", 0, 0 } }
        env.click(dock.toggle); env.click(dock.move); env.click(dock.settings); env.flushTimers()
        check("combat locks movers and prevents native writes or settings clicks",
            writes == before and settings == 1 and not RikUI.Layout.IsUnlocked(key) and not dock.toggle:IsEnabled()
                and not RikUI.Layout.Overlays[key]:IsShown() and not decorated(module.Holders[names[1]]))
        env.inCombat = false; env.fire("PLAYER_REGEN_ENABLED"); env.flushTimers()
        check("combat end restores native anchors and usable controls",
            native[1].points[1][2] == module.Holders[names[1]] and dock.toggle:IsEnabled())
        for _, frame in ipairs(native) do frame:Hide() end
        native[1].ignoreFramePositionManager, managed[native[1]] = nil, true
        native[1].points = { { "CENTER", UIParent, "CENTER", 0, 0 } }
        env.fire("EDIT_MODE_LAYOUTS_UPDATED"); env.flushTimers()
        check("hidden layout resets reclaim ownership before the next combat show",
            not managed[native[1]] and native[1].points[1][2] == module.Holders[names[1]])
        local printed = #env.printed
        local failing, healthy = native[1], native[2]
        failing.points, healthy.points = {}, {}
        failing.SetPointBase = function() error("placement rejected") end
        healthy:Show(); failing:Show()
        check("a rejected root does not stop other viewers or controls",
            healthy.points[1][2] == module.Holders[names[2]] and dock.toggle:IsEnabled())
        env.flushTimers(); env.flushTimers()
        check("root placement rejection warns once and scan continues", #env.printed == printed + 1 and #env.timers == 1)
        module = load(nil, true)
        check("unsupported client has no dead toolbar", not module.Controls and #env.timers == 0)
        module = load({ modules = { cooldownviewer = false } })
        check("disabled module creates no toolbar or holders", not module.Controls and not RikUI.Layout.Groups.cooldownessential)
        check("mouse flow completes without runtime failures", #env.printed == 0)
    end)
    restore()
    for _, name in ipairs(names) do _G[name] = saved[name] end
    for _, name in ipairs({ "C_CVar", "CooldownViewerSettings", "ShowUIPanel", "EditModeManagerFrame",
        "EventRegistry", "GetCursorPosition", "IsShiftKeyDown" }) do _G[name] = saved[name] end
    UIParent.GetWidth, UIParent.GetHeight, UIParent.GetEffectiveScale = oldWidth, oldHeight, oldScale
    if not ok then error(reason) end
end
