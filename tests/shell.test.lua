-- Shared launcher lifecycle, late native tools and bounded utility growth.
return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local restore = widgets.install()
    local oldReporter, oldReload, oldSpecial = PTR_IssueReporter, ReloadUI, UISpecialFrames
    local oldHeight, oldScale = UIParent.GetHeight, UIParent.GetEffectiveScale
    UIParent.GetHeight = function() return 720 end
    UIParent.GetEffectiveScale = function() return 1 end
    UISpecialFrames = {}
    local files = { "src/ui/skin.lua", "src/ui/scroll.lua", "src/ui/shell.lua", "src/ui/shell-tools.lua",
        "src/layout/layout-unlock.lua", "src/layout/layout-drag.lua", "src/modules/unitframes/unitframes-party.lua" }
    local ok, reason = pcall(function()
        PTR_IssueReporter = nil
        widgets.loadAddon(env, files)
        local shell, layout = RikUI.Shell, RikUI.Layout
        local chrome = shell.Panel.chrome
        check("utility title has a separate inset header", chrome and chrome.header.height == 44)
        check("window separates overlapping surfaces with three shadow rings", chrome and chrome.shadow and #chrome.shadow == 3)
        check("window header accent follows header visibility", chrome and chrome.accent and chrome.accent:IsShown())
        if chrome then
            local again = RikUI.Skin.WindowChrome(shell.Panel, 52, 20)
            check("window chrome updates without accumulating regions", again == chrome
                and chrome.header.height == 52 and chrome.footer.height == 20)
            RikUI.Skin.WindowChrome(shell.Panel, 44)
            check("removing a footer clears its backing and rule", not chrome.footer:IsShown()
                and not chrome.footerRule:IsShown())
        end
        local party = RikUI.UnitFrames.Party
        party.Holder = CreateFrame("Frame", nil, UIParent)
        RikUI.UnitFrames.enabled = true
        party.SetTest = function(value) party.Testing = value; return true end
        local opened, reloads = nil, 0
        RikUI.Options = { Open = function(id) opened = id end }
        ReloadUI = function() reloads = reloads + 1 end
        check("utility control has a reusable inset surface", shell.Launcher.surface and RikUI.Skin.ButtonSurface(shell.Launcher) == shell.Launcher.surface)
        check("one compact launcher and a closed flyout at login", shell.Launcher.width == 64 and not shell.Panel:IsShown())
        check("missing minimap uses a top-right fallback", shell.Launcher.point[1] == "TOPRIGHT" and shell.Launcher.point[2] == UIParent)
        check("only the flyout participates in Escape dismissal", UISpecialFrames[#UISpecialFrames] == "RikUIUtilityPanel")
        env.runScript(shell.Launcher, "OnEnter")
        check("launcher has a soft hover wash", shell.Launcher.rikHover and shell.Launcher.rikHover.enter:IsPlaying())
        env.runScript(shell.Launcher, "OnMouseDown", "LeftButton")
        check("launcher responds while pressed", shell.Launcher.rikPress and shell.Launcher.rikPress.region.alpha == 0.24)
        env.runScript(shell.Launcher, "OnMouseUp", "LeftButton")
        env.click(shell.Launcher)
        check("launcher opens grouped tools with a clipped viewport", shell.Panel:IsShown() and shell.Panel.scroll.view.clips == true)
        local groupIcon = shell.Panel.groupIcons and shell.Panel.groupIcons.Interface
        check("utility groups have stable icon identities", groupIcon and groupIcon.rikIcon == "settings")
        local groupSurface = shell.Panel.groupSurfaces and shell.Panel.groupSurfaces.Interface
        check("utility groups have backing and visible entry counts", groupSurface and groupSurface.count:GetText() ~= "")
        shell.Rebuild()
        check("utility rebuild reuses group furniture", groupSurface and shell.Panel.groupSurfaces.Interface == groupSurface)
        check("utility rebuild reuses group icons", groupIcon and shell.Panel.groupIcons.Interface == groupIcon)
        check("action rows have direction cues but launcher stays compact",
            shell.Entries.profiles.frame.chevron and not shell.Launcher.chevron)
        check("utility close uses the bundled close glyph", shell.Panel.close.icon and shell.Panel.close.icon.rikIcon == "close")
        env.click(shell.Entries.profiles.frame)
        check("utility close waits for its fade", shell.Panel:IsShown() and shell.Panel.rikClosing)
        shell.Panel.rikExit:Finish()
        check("profile action opens correct config page and closes shell", opened == "profiles" and not shell.Panel:IsShown())
        shell.Open(); env.click(shell.Entries["party-preview"].frame)
        check("party preview has a mouse entry point", party.Testing and shell.Entries["party-preview"].frame.label.text == "Hide party preview")
        shell.Open(); env.click(shell.Entries["party-preview"].frame)
        check("party preview can be dismissed from the same entry", not party.Testing)
        local map = CreateFrame("Frame", nil, UIParent)
        map.rikFooterHeight = 44
        RikUI.Minimap = { Holder = map }
        shell.Anchor()
        check("late minimap becomes launcher anchor above status footer", shell.Launcher.point[2] == map
            and shell.Launcher.point[1] == "BOTTOMRIGHT" and shell.Launcher.point[5] == 48)
        shell.Open()
        env.click(shell.Entries.move.frame)
        check("move starts existing editor and changes launcher to Done", layout.IsMoving() and shell.Launcher.label.text == "Done")
        shell.Close()
        check("closing flyout preserves move session", layout.IsMoving())
        env.click(shell.Launcher)
        check("Done launcher ends editing without a permanent toolbar", not layout.IsMoving() and shell.Launcher.label.text == "RikUI")
        layout.UnlockAll(); shell.Refresh()
        env.inCombat = true; env.fire("PLAYER_REGEN_DISABLED")
        env.runScript(shell.Launcher, "OnUpdate", 0.3)
        check("combat auto-lock also clears Done label", not layout.IsMoving() and shell.Launcher.label.text == "RikUI")
        env.runScript(shell.Entries.reload.frame, "OnEnter")
        env.runScript(shell.Entries.reload.frame, "OnMouseDown", "LeftButton")
        check("disabled utility has no hover or press glow", shell.Entries.reload.frame.rikHover.region.alpha == 0
            and shell.Entries.reload.frame.rikPress.region.alpha == 0)
        env.click(shell.Entries.move.frame); env.click(shell.Entries.reload.frame)
        check("stale action clicks recheck combat", not layout.IsMoving() and reloads == 0)
        env.inCombat = false; env.fire("PLAYER_REGEN_ENABLED")
        shell.Open(); env.click(shell.Dismiss)
        shell.Panel.rikExit:Finish()
        check("outside click closes flyout without removing launcher", not shell.Panel:IsShown() and shell.Launcher:IsShown())
        env.click(shell.Entries.reload.frame)
        check("reload is a real button action", reloads == 1)
        local reporter = CreateFrame("Frame", nil, UIParent)
        reporter.ReportBug, reporter.InfoButton = CreateFrame("Button", nil, reporter), CreateFrame("Button", nil, reporter)
        reporter.Data = { IsLoaded = false }
        reporter.ReportEventTypes = { UIButtonClicked = "UI_CLICK" }
        local calls = {}
        reporter.TriggerEvent = function(...) calls[#calls + 1] = { ... } end
        local update = function() end
        reporter:SetScript("OnUpdate", update)
        PTR_IssueReporter = reporter
        shell.AdoptReporter()
        check("incomplete native reporter keeps its launcher", reporter.alpha ~= 0 and not shell.Entries.report)
        reporter.Data = { IsLoaded = true, CurrentBugButtonContext = "context", ButtonDataPackage = { marker = 1 } }
        env.fire("ADDON_LOADED", "Blizzard_PTRFeedback"); env.flushTimers()
        check("ready reporter is consolidated without hiding native root", shell.Entries.report
            and reporter:IsShown() and reporter.alpha == 0 and reporter.ReportBug.mouseEnabled == false)
        check("native reporter timer is preserved", reporter:GetScript("OnUpdate") == update)
        shell.Open(); env.click(shell.Entries.report.frame)
        shell.Panel.rikExit:Finish()
        check("report button dispatches native event with exact current payload", #calls == 1 and calls[1][1] == "UI_CLICK"
            and calls[1][2] == "context" and calls[1][3] == reporter.Data.ButtonDataPackage and not shell.Panel:IsShown())
        reporter.Data.CurrentBugButtonContext, reporter.Data.ButtonDataPackage = nil, nil
        shell.Open(); env.click(shell.Entries.report.frame)
        shell.Panel.rikExit:Finish()
        check("native report forwards missing arguments unchanged", #calls == 2 and calls[2][1] == "UI_CLICK" and calls[2][2] == nil)
        for index = 1, 30 do
            shell.Register("extra" .. index, { group = "Tools", label = "Extra " .. index, order = 50 + index, action = function() end })
        end
        check("expanding tool registry grows scroll range instead of HUD footprint", shell.Panel.width == 320
            and shell.Panel.height < 720 and shell.Panel.scroll.range > 0)
        local pane = shell.Panel.scroll
        check("scroll grip stays attached to the native thumb", pane.bar.grip and #pane.bar.grip == 3
            and pane.bar.grip[1].point[2] == pane.bar:GetThumbTexture())
        RikUI.Scroll.Resize(pane, 290, 5)
        check("tiny viewports hide the thumb grip", pane.bar.grip and not pane.bar.grip[1]:IsShown())
        RikUI.Scroll.Resize(pane, 290, 300)
        check("normal viewports restore the thumb grip", pane.bar.grip and pane.bar.grip[1]:IsShown())
        env.runScript(shell.Panel.scroll.view, "OnMouseWheel", -100)
        check("wheel clamps at final utility", shell.Panel.scroll.offset == shell.Panel.scroll.range)
        RikUI.Scroll.Resize(shell.Panel.scroll, 290, 3000)
        check("resizing to fit content clears stale scrolling", shell.Panel.scroll.offset == 0)
        check("utility flow completes without runtime errors", #env.printed == 1 and env.printed[1]:find("Frames locked for combat", 1, true), table.concat(env.printed, "\n"))
        local oldEntry = shell.Entries.extra1.frame
        shell.Register("extra1", { group = "Tools", label = "Replacement", action = function() end })
        check("replacing a utility hides its previous row", not oldEntry:IsShown())
        local beforeWarnings = #env.printed
        shell.Register("broken-build", { group = "Tools", build = function() error("build rejected") end })
        shell.Register("broken-label", { group = "Tools", label = function() error("label rejected") end, action = function() end })
        shell.Open(); shell.Refresh(); shell.Rebuild()
        check("bad providers are isolated and warn once", #env.printed == beforeWarnings + 2
            and not shell.Entries["broken-label"].frame:IsEnabled())
        env.click(shell.Entries.settings.frame)
        check("settings remain usable when other providers fail", opened == "general")
        widgets.loadAddon(env, files, nil, true)
        check("combat login still creates a reachable fallback launcher", RikUI.Shell.Launcher.point[1] == "TOPRIGHT")
        env.inCombat = false; env.fire("PLAYER_REGEN_ENABLED")
        check("post-combat discovery remains usable", RikUI.Shell.Launcher ~= nil)
    end)
    PTR_IssueReporter, ReloadUI, UISpecialFrames = oldReporter, oldReload, oldSpecial
    UIParent.GetHeight, UIParent.GetEffectiveScale = oldHeight, oldScale
    env.inCombat = false
    restore()
    if not ok then error(reason) end
end
