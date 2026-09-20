-- Fake windows holding the 69913 control templates by their region keys: a push button, a check box,
-- an edit box, a slider, both scrollbar generations and a dropdown button, next to the buttons that
-- must stay stock (item, action, secure, forbidden). The suite checks detection by keys, the flat
-- pieces, the hover and focus polish, and that the panel skin walks a window on every show.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local restore, savedCreateFont = widgets.install(), CreateFont
    local STATES = { "Normal", "Pushed", "Disabled", "Highlight" }

    local function frame(kind, parent, width)
        local value = CreateFrame(kind, nil, parent)
        value.children = {}
        function value:GetChildren() return unpack(self.children) end
        if width then value:SetWidth(width) end
        if parent and type(parent.children) == "table" then table.insert(parent.children, value) end
        return value
    end
    local function art(owner, keys)
        for _, key in ipairs(keys) do owner[key] = owner:CreateTexture() end
    end
    local function stateTextures(button)
        button.states = {}
        for _, state in ipairs(STATES) do
            button.states[state] = button:CreateTexture()
            button["Get" .. state .. "Texture"] = function(self) return self.states[state] end
        end
    end
    local function pushButton(parent)
        local button = frame("Button", parent, 100)
        art(button, { "Left", "Middle", "Right" })
        stateTextures(button)
        button.Text = button:CreateFontString()
        function button:SetNormalFontObject(object) self.normalFont = object end
        return button
    end
    local function scrollBar(parent)
        local bar = frame("Frame", parent)
        bar.Track, bar.Back, bar.Forward = frame("Frame", bar), frame("Button", bar), frame("Button", bar)
        art(bar.Track, { "Begin", "Middle", "End" })
        bar.Track.Thumb = frame("Button", bar.Track)
        art(bar.Track.Thumb, { "Begin", "Middle", "End" })
        return bar
    end
    local function legacyScrollBar(parent)
        local bar = frame("Slider", parent)
        bar.ScrollUpButton, bar.ScrollDownButton = frame("Button", bar), frame("Button", bar)
        stateTextures(bar.ScrollUpButton)
        stateTextures(bar.ScrollDownButton)
        bar.ThumbTexture = bar:CreateTexture()
        function bar:GetThumbTexture() return self.ThumbTexture end
        return bar
    end
    local function window()
        local root = frame("Frame", UIParent)
        local inner = frame("Frame", root)
        local parts = { root = root, button = pushButton(inner), check = frame("CheckButton", inner, 26),
            edit = frame("EditBox", inner), slider = frame("Slider", inner), scroll = scrollBar(inner),
            legacy = legacyScrollBar(inner), dropdown = frame("Button", inner), item = frame("Button", inner),
            action = frame("CheckButton", inner, 36), secure = pushButton(inner), forbidden = pushButton(inner) }
        stateTextures(parts.check)
        art(parts.edit, { "Left", "Middle", "Right" })
        function parts.edit:GetFont() return "Fonts\\ARIALN.TTF", 12, "" end
        function parts.edit:SetFont(path, size) self.fontPath, self.fontSize = path, size end
        art(parts.slider, { "Left", "Middle", "Right" })
        parts.slider.thumb = parts.slider:CreateTexture()
        function parts.slider:GetThumbTexture() return self.thumb end
        art(parts.dropdown, { "Background", "Arrow" })
        parts.dropdown.Text = parts.dropdown:CreateFontString()
        art(parts.item, { "icon" })
        art(parts.action, { "icon" })
        stateTextures(parts.action)
        function parts.secure:IsProtected() return true end
        function parts.forbidden:IsForbidden() return true end
        return parts
    end
    local function load(profile, files)
        widgets.loadAddon(env, files or { "skin.lua", "controls.lua" }, profile, false, function()
            CreateFont = function(name)
                local object = { name = name }
                function object:SetFont(path, size) self.fontPath, self.fontSize = path, size end
                function object:SetTextColor(...) self.color = { ... } end
                return object
            end
        end)
        return RikUI.Controls
    end
    local ok, reason = pcall(function()
        local module = load()
        local ui = window()
        module.Walk(ui.root)
        local button = ui.button
        check("a push button loses its slices and state art and gets a fill, an edge and the shared font object",
            button.Left.alpha == 0 and button.Middle.alpha == 0 and button.states.Normal.alpha == 0
            and button.states.Highlight.alpha == 0 and button.rikFill.texture == RikUI.Skin.FLAT
            and #button.rikBorder == 4 and button.normalFont ~= nil)
        check("hover is a highlight-layer texture that fades in from a hook, with no script replaced",
            button.rikHover.texture == RikUI.Media.highlight and button:GetScript("OnEnter") == nil
            and #button.hooks.OnEnter == 1 and button.rikHoverFade.plays == 0)
        env.runScript(button, "OnEnter")
        check("entering the button plays the hover fade", button.rikHoverFade.plays == 1
            and button.rikHoverFade.animation.to == 1)
        check("a check box keeps Blizzard's tick and trades its box art for an inset flat box",
            ui.check.states.Normal.alpha == 0 and ui.check.states.Pushed.alpha == 0
            and ui.check.rikFill.points[1][4] > 0 and #ui.check.rikBorder == 4 and ui.check.checkedTexture == nil)
        check("an edit box loses its border pieces and gets a field, an edge and the typeface at its own size",
            ui.edit.Left.alpha == 0 and ui.edit.Right.alpha == 0 and ui.edit.rikFill ~= nil
            and ui.edit.fontPath == RikUI.Media.font and ui.edit.fontSize == 12)
        env.runScript(ui.edit, "OnEditFocusGained")
        local focused = ui.edit.rikBorder[1].color
        env.runScript(ui.edit, "OnEditFocusLost")
        check("keyboard focus turns the edit box edge to the accent colour and back",
            focused[3] == 1 and ui.edit.rikBorder[1].color[3] < 1)
        check("a slider gets a thin flat track and a flat thumb", ui.slider.Left.alpha == 0
            and ui.slider.rikTrack.texture == RikUI.Skin.FLAT and ui.slider.rikTrack.height ~= nil
            and ui.slider.thumb.texture == RikUI.Skin.FLAT and ui.slider.thumb.width ~= nil)
        local thumb = ui.scroll.Track.Thumb
        check("a scrollbar loses its track and thumb art and gets a flat thumb with a hover fade",
            ui.scroll.Track.Middle.alpha == 0 and thumb.Begin.alpha == 0 and thumb.rikFill.texture == RikUI.Skin.FLAT
            and thumb.rikHoverFade ~= nil)
        check("a legacy scrollbar gets a flat thumb and flat step buttons with a glyph",
            ui.legacy.ThumbTexture.texture == RikUI.Skin.FLAT and ui.legacy.ScrollUpButton.states.Normal.alpha == 0
            and ui.legacy.ScrollUpButton.rikGlyph.text == "^" and ui.legacy.ScrollDownButton.rikGlyph.text == "v")
        check("a dropdown button loses its holder art, keeps its arrow and gets the typeface",
            ui.dropdown.Background.alpha == 0 and rawget(ui.dropdown.Arrow, "alpha") == nil
            and ui.dropdown.rikFill ~= nil and ui.dropdown.Text.fontPath == RikUI.Media.font)
        check("item buttons, action check buttons, secure and forbidden buttons stay stock",
            ui.item.rikFill == nil and ui.action.rikFill == nil and rawget(ui.action.states.Normal, "alpha") == nil
            and ui.secure.rikFill == nil and rawget(ui.secure.Left, "alpha") == nil and ui.forbidden.rikFill == nil)
        check("nothing was moved, resized, reparented or rescripted", button.points == nil and button.width == 100
            and button.parent == ui.root.children[1] and ui.edit:GetScript("OnEditFocusGained") == nil)

        local fill = button.rikFill
        local late = pushButton(ui.root)
        module.Walk(ui.root)
        check("a second walk skins only what is new", button.rikFill == fill and #button.hooks.OnEnter == 1
            and late.rikFill ~= nil)
        SlashCmdList.RIKUI("debug")
        check("debug reports the controls", widgets.printedContains(env, "Controls skinned=8 failed=0"))

        local deep, parent = nil, frame("Frame", UIParent)
        local top = parent
        for _ = 1, 12 do parent = frame("Frame", parent) end
        deep = pushButton(parent)
        module.Walk(top)
        check("the walk stops at its depth limit", deep.rikFill == nil)

        module = load()
        local broken = pushButton(nil)
        function broken.Left:SetAlpha() error("alpha refused") end
        module.Walk(broken)
        module.Walk(broken)
        check("a control that refuses the skin is reported once and not retried",
            widgets.printedContains(env, "Controls skin") and #env.printed == 1)
        module.Walk(nil)
        module.Walk("WorldFrame")
        check("a walk over something that is not a frame does nothing", #env.printed == 1)

        module = load(nil, { "panels.lua", "panels-skin.lua", "skin.lua", "controls.lua" })
        local merchant = frame("Frame", UIParent)
        merchant:Hide()
        MerchantFrame = merchant
        local buy = pushButton(merchant)
        RikUI.Panels.Discover()
        merchant:Show()
        check("the panel skin walks a window when it shows", buy.rikFill ~= nil)
        local later = pushButton(merchant)
        merchant:Hide()
        merchant:Show()
        check("and again on the next show, for controls the window built meanwhile", later.rikFill ~= nil)
        MerchantFrame = nil

        module = load({ modules = { controls = false } })
        local stock = window()
        module.Walk(stock.root)
        check("a disabled module leaves controls stock", stock.button.rikFill == nil
            and rawget(stock.button.Left, "alpha") == nil)
    end)
    restore()
    MerchantFrame, CreateFont = nil, savedCreateFont
    check("controls suite completes", ok, reason)
end
