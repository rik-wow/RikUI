-- The flyout's cooldown tools: Move/Done over RikUI's own keys, Tracked spells, combat and Edit Mode locks.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local saved = { C_CVar = C_CVar, CooldownViewerSettings = CooldownViewerSettings, ShowUIPanel = ShowUIPanel,
        EditModeManagerFrame = EditModeManagerFrame, EventRegistry = EventRegistry, C_CooldownViewer = C_CooldownViewer }
    local restoreWidgets = widgets.install()
    local cvar, shown, editing = "1", 0, false
    local FILES = { "src/ui/skin.lua", "src/ui/scroll.lua", "src/ui/shell.lua", "src/layout/layout-unlock.lua",
        "src/layout/layout-drag.lua", "src/platform/editmode.lua", "src/modules/cooldowns/cooldowns.lua",
        "src/modules/cooldowns/cooldowns-strip.lua", "src/modules/cooldowns/cooldowns-native.lua",
        "src/modules/cooldowns/cooldowns-controls.lua" }
    local function load(profile, combat)
        return widgets.loadAddon(env, FILES, profile, combat, function()
            C_CVar = {
                GetCVarBool = function() return cvar == "1" end,
                SetCVar = function(_, value) assert(not env.inCombat); cvar = value end,
            }
            C_CooldownViewer = nil
            CooldownViewerSettings = CreateFrame("Frame")
            ShowUIPanel = function(frame) assert(frame == CooldownViewerSettings); shown = shown + 1 end
            EditModeManagerFrame = { IsEditModeActive = function() return editing end }
            EventRegistry = { RegisterCallback = function() end }
        end)
    end
    local ok, reason = pcall(function()
        load()
        local panel = RikUI.Cooldowns
        local dock = panel.Controls.Dock
        check("the flyout carries the cooldown tools", RikUI.Shell.Entries.cooldowns ~= nil and dock ~= nil
            and dock.move.label.text == "Move" and dock.settings.label.text == "Tracked spells")
        RikUI.Layout.Register(CreateFrame("Frame", nil, UIParent), "cooldowns",
            { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 376 }, { label = "Cooldowns" })
        env.click(dock.move)
        check("Move unlocks RikUI's own strip and reads Done", RikUI.Layout.IsUnlocked("cooldowns") and dock.move.label.text == "Done")
        env.click(dock.move)
        check("Done locks the strip again", not RikUI.Layout.IsUnlocked("cooldowns") and dock.move.label.text == "Move")
        env.click(dock.settings)
        check("Tracked spells opens the client's window once", shown == 1)
        env.inCombat = true
        panel.Controls.Refresh()
        check("combat locks the controls", not dock.move:IsEnabled() and dock.message.text == "Controls locked in combat")
        env.click(dock.settings)
        check("a locked control ignores clicks", shown == 1)
        env.inCombat = false
        editing = true
        panel.Controls.Refresh()
        check("Edit Mode locks the controls", not dock.settings:IsEnabled()
            and dock.message.text == "Finish Edit Mode to use these controls")
        editing = false
        panel.Controls.Refresh()
        check("controls return when both end", dock.move:IsEnabled() and dock.message.text == "")
        check("the native viewers are switched off while the module runs", cvar == "0")
        load({ modules = { cooldowns = false } })
        check("a disabled module adds no flyout entry", RikUI.Shell.Entries.cooldowns == nil)
    end)
    for key, value in pairs(saved) do _G[key] = value end
    restoreWidgets()
    env.inCombat = false
    check("cooldown controls suite completes", ok, reason)
end
