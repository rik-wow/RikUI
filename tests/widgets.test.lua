-- Widget updates retain native Setup methods and restyle from manager events.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local MIXINS = { "UIWidgetTemplateStatusBarMixin", "UIWidgetTemplateDoubleStatusBarMixin",
        "UIWidgetTemplateCaptureBarMixin" }
    local saved = {}
    for _, name in ipairs({ "UIWidgetManager", "DefaultWidgetLayout", "Enum" }) do saved[name] = _G[name] end
    local container
    for _, name in ipairs(MIXINS) do saved[name] = _G[name] end
    local restore = widgets.install()
    local BAR_ART = { "BGLeft", "BGRight", "BGCenter", "BorderLeft", "BorderRight", "BorderCenter", "BackgroundGlow" }
    local SIDE_ART = { "BG", "BorderLeft", "BorderRight", "BorderCenter" }
    local CAPTURE_ART = { "BarBackground", "LeftLine", "RightLine", "Divider" }
    local function label(owner)
        local value = owner:CreateFontString()
        function value:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
        return value
    end
    local function bar(parent, keys)
        local value = CreateFrame("StatusBar", nil, parent)
        for _, key in ipairs(keys) do value[key] = value:CreateTexture() end
        value.Spark, value.Label = value:CreateTexture(), label(value)
        return value
    end
    -- Blizzard's Setup sets values, colours and label font objects on every update.
    local function blizzardSetup(self)
        self.setups = (self.setups or 0) + 1
        for _, value in ipairs(self.labels) do value.fontPath = "Fonts\\FRIZQT__.TTF" end
    end
    local function make(mixin, build)
        local frame = CreateFrame("Frame", nil, UIParent)
        frame.labels = {}
        build(frame)
        frame.Setup = _G[mixin].Setup
        for index, name in ipairs(MIXINS) do if name == mixin then frame.widgetType = index end end
        container.widgetFrames[#container.widgetFrames + 1] = frame
        return frame
    end
    local function statusWidget()
        return make(MIXINS[1], function(frame)
            frame.Bar, frame.Label = bar(frame, BAR_ART), label(frame)
            frame.Bar:SetStatusBarTexture("widgetstatusbar-fill-blue")
            frame.labels = { frame.Bar.Label, frame.Label }
        end)
    end
    local function doubleWidget()
        return make(MIXINS[2], function(frame)
            frame.LeftBar, frame.RightBar, frame.Label = bar(frame, SIDE_ART), bar(frame, SIDE_ART), label(frame)
            frame.labels = { frame.LeftBar.Label, frame.RightBar.Label, frame.Label }
        end)
    end
    local function captureWidget()
        return make(MIXINS[3], function(frame)
            for _, key in ipairs(CAPTURE_ART) do frame[key] = frame:CreateTexture() end
            for _, key in ipairs({ "LeftBar", "RightBar", "NeutralBar", "Spark", "Glow1" }) do
                frame[key] = frame:CreateTexture()
            end
        end)
    end
    local function load(profile, prepare)
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/widgets/widgets.lua" }, profile, false, function()
            container = { widgetFrames = {} }
            UIWidgetManager = { registeredWidgetContainers = { [container] = true } }
            Enum = { UIWidgetVisualizationType = { StatusBar = 1, DoubleStatusBar = 2, CaptureBar = 3 } }
            DefaultWidgetLayout = function() end
            env.KNOWN_EVENTS.UPDATE_UI_WIDGET, env.KNOWN_EVENTS.UPDATE_ALL_UI_WIDGETS = true, true
            env.KNOWN_EVENTS.NAME_PLATE_UNIT_ADDED = true
            for _, name in ipairs(MIXINS) do _G[name] = { Setup = blizzardSetup } end
            if prepare then prepare() end
        end)
        return RikUI.Widgets
    end
    local function flatBar(value)
        return value.rikFill ~= nil and value.rikFill.texture == RikUI.Skin.FLAT and #value.rikBorder == 4
    end
    local ok, reason = pcall(function()
        local module = load()
        local status = statusWidget()
        status:Setup({}, nil)
        env.fire("UPDATE_UI_WIDGET"); env.flushTimers()
        check("Blizzard's Setup still runs", status.setups == 1)
        check("a status bar widget loses its background and border art and gets a flat fill and edge",
            status.Bar.BGCenter.alpha == 0 and status.Bar.BorderLeft.alpha == 0 and status.Bar.BackgroundGlow.alpha == 0
            and flatBar(status.Bar))
        check("Blizzard's fill, colour, spark and values are not written", status.Bar.texture == "widgetstatusbar-fill-blue"
            and status.Bar.color == nil and status.Bar.value == nil and rawget(status.Bar.Spark, "alpha") == nil)
        check("both labels take the RikUI typeface at their own size with the colour untouched",
            status.Bar.Label.fontPath == RikUI.Media.font and status.Label.fontPath == RikUI.Media.font
            and status.Label.fontSize == 12 and rawget(status.Label, "textColor") == nil)
        local fill = status.Bar.rikFill
        status.Bar.BGCenter.alpha = 1
        status:Setup({}, nil)
        env.fire("UPDATE_UI_WIDGET"); env.flushTimers()
        check("a later Setup keeps the one fill, fades restored art and rewrites the typeface",
            status.Bar.rikFill == fill and status.Bar.BGCenter.alpha == 0
            and status.Bar.Label.fontPath == RikUI.Media.font)

        local double = doubleWidget()
        double:Setup({}, nil)
        env.fire("UPDATE_UI_WIDGET"); env.flushTimers()
        check("both sides of a double status bar go flat", double.LeftBar.BG.alpha == 0
            and double.RightBar.BorderCenter.alpha == 0 and flatBar(double.LeftBar) and flatBar(double.RightBar)
            and double.Label.fontPath == RikUI.Media.font)

        local capture = captureWidget()
        capture:Setup({}, nil)
        env.fire("UPDATE_UI_WIDGET"); env.flushTimers()
        check("a capture bar loses its frame art and keeps its zones, spark and glows",
            capture.BarBackground.alpha == 0 and capture.LeftLine.alpha == 0 and capture.Divider.alpha == 0
            and rawget(capture.LeftBar, "alpha") == nil and rawget(capture.Glow1, "alpha") == nil)
        check("the capture bar's fill and edge span from the left zone to the right zone",
            capture.rikFill.texture == RikUI.Skin.FLAT and capture.rikFill.points[1][2] == capture.LeftBar
            and capture.rikFill.points[2][2] == capture.RightBar and #capture.rikBorder == 4
            and capture.rikBorder[1].points[1][2] == capture.rikSpan)
        check("nothing was moved, shown, hidden or printed", status.points == nil and capture.points == nil
            and #env.printed == 0)
        env.inCombat = true
        statusWidget():Setup({}, nil)
        env.fire("UPDATE_UI_WIDGET"); env.flushTimers()
        env.inCombat = false
        check("a widget that appears in combat is skinned without a protected write", #env.printed == 0)
        SlashCmdList.RIKUI("debug")
        check("debug reports hooks and frames", widgets.printedContains(env, "Widgets hooked=1 skinned=4 failed=0"))

        local before
        module = load(nil, function() before = statusWidget() end)
        before:Setup({}, nil)
        env.fire("UPDATE_UI_WIDGET"); env.flushTimers()
        check("a widget made before login is skinned too", before.Bar.rikFill ~= nil)
        check("native Setup remains untouched", before.Setup == blizzardSetup)
        local broken = statusWidget()
        function broken.Bar.BGLeft:SetAlpha() error("alpha refused") end
        broken:Setup({}, nil)
        env.fire("UPDATE_UI_WIDGET"); env.flushTimers()
        broken:Setup({}, nil)
        env.fire("UPDATE_UI_WIDGET"); env.flushTimers()
        check("a widget that refuses the skin is reported once and not retried",
            widgets.printedContains(env, "Widgets skin") and #env.printed == 1 and broken.setups == 2)
        local bare = make(MIXINS[1], function() end)
        bare:Setup({}, nil)
        env.fire("UPDATE_UI_WIDGET"); env.flushTimers()
        check("a widget without a bar is left alone silently", #env.printed == 1)

        module = load(nil, function() DefaultWidgetLayout = nil end)
        SlashCmdList.RIKUI("debug")
        check("a missing layout global is skipped", widgets.printedContains(env, "Widgets hooked=0"))

        module = load({ modules = { widgets = false } })
        local stock = statusWidget()
        stock:Setup({}, nil)
        env.fire("UPDATE_UI_WIDGET"); env.flushTimers()
        check("a disabled module leaves widgets stock", stock.Bar.rikFill == nil
            and rawget(stock.Bar.BGCenter, "alpha") == nil)
    end)
    restore()
    for _, name in ipairs(MIXINS) do _G[name] = saved[name] end
    for _, name in ipairs({ "UIWidgetManager", "DefaultWidgetLayout", "Enum" }) do _G[name] = saved[name] end
    env.inCombat = false
    check("widget suite completes", ok, reason)
end
