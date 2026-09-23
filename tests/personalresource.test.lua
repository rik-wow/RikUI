-- Source-shaped PRD bars: anonymous background atlas and untouched prediction regions.
return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local saved = PersonalResourceDisplayFrame
    local restore = widgets.install()
    local valueCalls, reads, frames, bars
    local savedHealth, savedPower = UnitHealth, UnitPower

    local function forbiddenWrite() error("PRD ownership violation") end
    local function bar(parent)
        local frame = CreateFrame("StatusBar", nil, parent)
        frame:SetSize(200, 12)
        frame:SetPoint("TOP", parent, "TOP")
        frame.texture, frame.value, frame.high = "stock-fill", {}, {}
        frame.color = { 0.1, 0.4, 0.8 }
        frame.TextString, frame.LeftText, frame.RightText = frame:CreateFontString(), frame:CreateFontString(), frame:CreateFontString()
        frame.TextString:SetText("native text")
        local background, prediction = frame:CreateTexture(), frame:CreateTexture()
        function background:GetAtlas() return "UI-HUD-CoolDownManager-Bar-BG" end
        function prediction:GetAtlas() return "prediction-art" end
        frame.regions = { background, prediction, frame.TextString }
        function frame:GetRegions() return unpack(self.regions) end
        function frame:IsForbidden() return false end
        frame.stockBackground, frame.prediction = background, prediction
        frame.SetValue = function() valueCalls = valueCalls + 1; forbiddenWrite() end
        frame.SetMinMaxValues, frame.SetStatusBarColor = forbiddenWrite, forbiddenWrite
        frame.SetParent, frame.SetPoint, frame.ClearAllPoints, frame.SetSize = forbiddenWrite, forbiddenWrite, forbiddenWrite, forbiddenWrite
        bars[#bars + 1] = frame
        return frame
    end
    local function client(shown)
        local frame = CreateFrame("Frame", "PersonalResourceDisplayFrame", UIParent)
        function frame:IsForbidden() return false end
        frame.HealthBarsContainer = CreateFrame("Frame", nil, frame)
        frame.HealthBarsContainer.healthBar = bar(frame.HealthBarsContainer)
        frame.PowerBar, frame.AlternatePowerBar = bar(frame), bar(frame)
        frame.shown, frame.AlternatePowerBar.shown = shown == true, false
        local script = function() frames = frames + 1 end
        frame:SetScript("OnShow", script)
        frame.nativeShow = script
        return frame
    end
    local function load(profile, prepare, combat)
        valueCalls, reads, frames, bars = 0, 0, 0, {}
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/personalresource/personalresource.lua" },
            profile, combat, prepare or function() client(true) end)
        return RikUI.PersonalResource
    end
    local ok, reason = pcall(function()
        UnitHealth, UnitPower = function() reads = reads + 1; forbiddenWrite() end, function() reads = reads + 1; forbiddenWrite() end
        local module = load()
        for index, frame in ipairs(bars) do
            local parts = module.Parts[frame]
            check("PRD bar " .. index .. " uses the shared fill and flat backing", frame.texture == RikUI.Media.statusbar
                and parts and parts.backing.texture == RikUI.Skin.FLAT)
            check("PRD bar " .. index .. " has four one-pixel overlay edges", parts and #parts.edge == 4
                and parts.edge[1].height == 1 and parts.edge[3].width == 1 and parts.edge[1].layer == "OVERLAY")
            check("only the PRD background atlas is faded", frame.stockBackground.alpha == 0
                and rawget(frame.prediction, "alpha") == nil)
            check("native text content stays while its font changes", frame.TextString.fontPath == RikUI.Media.font
                and frame.LeftText.fontPath == RikUI.Media.font and frame.RightText.fontPath == RikUI.Media.font
                and frame.TextString:GetText() == "native text")
            check("native values, colour, geometry and parents stay owned by the client", type(frame.value) == "table"
                and type(frame.high) == "table" and frame.color[2] == 0.4 and frame.width == 200 and #frame.points == 1)
        end
        check("no health or power reads or value writes", reads == 0 and valueCalls == 0)
        check("hidden alternate power stays hidden", not PersonalResourceDisplayFrame.AlternatePowerBar:IsShown())
        check("native OnShow script remains installed", PersonalResourceDisplayFrame:GetScript("OnShow") == PersonalResourceDisplayFrame.nativeShow)
        local first, parts = bars[1], module.Parts[bars[1]]
        first.texture = "stock-reset"
        env.inCombat = true
        PersonalResourceDisplayFrame:Hide()
        PersonalResourceDisplayFrame:Show()
        env.fire("ADDON_LOADED", "unrelated")
        PersonalResourceDisplayFrame:Hide()
        PersonalResourceDisplayFrame:Show()
        env.inCombat = false
        check("repeat shows reuse skin and preserve native script execution", module.Parts[first] == parts
            and first.texture == RikUI.Media.statusbar and frames == 2 and #env.printed == 0)
        SlashCmdList.RIKUI("debug")
        check("PRD diagnostics identify three skinned bars", widgets.printedContains(env, "Personal resource bars=3 failed=0"))

        module = load(nil, function() client(false) end, true)
        check("combat login does not force a hidden display to show", not PersonalResourceDisplayFrame:IsShown())
        PersonalResourceDisplayFrame:Show()
        env.inCombat = false
        check("first show in combat applies region-only skin", bars[1].texture == RikUI.Media.statusbar and #env.printed == 0)

        module = load(nil, function() PersonalResourceDisplayFrame = nil end)
        check("missing frame is quiet", next(module.Parts) == nil and #env.printed == 0)
        client(false)
        env.fire("ADDON_LOADED", "Blizzard_PersonalResourceDisplay")
        PersonalResourceDisplayFrame:Show()
        check("late-loaded display is discovered", bars[1].texture == RikUI.Media.statusbar)

        module = load(nil, function() client(true); PersonalResourceDisplayFrame.IsForbidden = function() return true end end)
        check("forbidden display is skipped", next(module.Parts) == nil and #env.printed == 0)
        module = load(nil, function() client(true); bars[1].IsForbidden = function() return true end end)
        check("forbidden bar is skipped without skipping usable bars", not module.Parts[bars[1]] and module.Parts[bars[2]])
        module = load(nil, function()
            client(true)
            PersonalResourceDisplayFrame.HealthBarsContainer = nil
            PersonalResourceDisplayFrame.PowerBar = nil
            PersonalResourceDisplayFrame.AlternatePowerBar = nil
        end)
        check("missing optional bars are quiet", next(module.Parts) == nil and #env.printed == 0)

        module = load(nil, function() client(true); bars[1].SetStatusBarTexture = function() error("skin refused") end end)
        PersonalResourceDisplayFrame:Hide(); PersonalResourceDisplayFrame:Show()
        check("refused skin reports once and leaves other bars usable", #env.printed == 1 and not module.Parts[bars[1]]
            and module.Parts[bars[2]] ~= nil)
        module = load(nil, function()
            client(true)
            bars[1].regions, bars[1].TextString, bars[1].LeftText, bars[1].RightText = {}, nil, nil, nil
        end)
        check("a bar without optional art or text still gets its skin", module.Parts[bars[1]] and #env.printed == 0)
        module = load(nil, function()
            client(true)
            PersonalResourceDisplayFrame.HookScript = function() error("hook refused") end
        end)
        env.fire("ADDON_LOADED", "unrelated")
        check("a refused hook is reported once without installing a partial skin", #env.printed == 1
            and next(module.Parts) == nil)
        module = load({ modules = { personalresource = false } })
        PersonalResourceDisplayFrame:Hide(); PersonalResourceDisplayFrame:Show()
        check("disabled module leaves stock display intact", bars[1].texture == "stock-fill"
            and rawget(bars[1].stockBackground, "alpha") == nil and next(module.Parts) == nil)
    end)
    UnitHealth, UnitPower = savedHealth, savedPower
    restore()
    PersonalResourceDisplayFrame = saved
    env.inCombat = false
    check("personal resource suite completes", ok, reason)
end
