-- Fake static popups, game menu and ghost frame with the 69913 region names. The suite checks that
-- only alpha, fonts, font objects and new child regions are written.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local API = { "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4", "GameMenuFrame", "GhostFrame",
        "GhostFrameContentsFrameText", "GhostFrameContentsFrameIcon", "CreateFont" }
    local saved = {}
    for _, name in ipairs(API) do saved[name] = _G[name] end
    local restore = widgets.install()
    local FLAT = "Interface\\BUTTONS\\WHITE8X8"
    local GETTERS = { "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }
    local function button(parent, keys)
        local value = CreateFrame("Button", nil, parent)
        value.art, value.fontObjects = {}, {}
        for _, getter in ipairs(GETTERS) do
            local texture = value:CreateTexture()
            value.art[getter] = texture
            value[getter] = function() return texture end
        end
        for _, key in ipairs(keys or {}) do value[key] = value:CreateTexture() end
        function value:SetNormalFontObject(object) self.fontObjects.normal = object end
        function value:SetHighlightFontObject(object) self.fontObjects.highlight = object end
        function value:SetDisabledFontObject(object) self.fontObjects.disabled = object end
        return value
    end
    local function popup(name)
        local frame = CreateFrame("Frame", name, UIParent)
        frame.Border, frame.BG = CreateFrame("Frame", nil, frame), CreateFrame("Frame", nil, frame)
        frame.Text, frame.SubText = frame:CreateFontString(), frame:CreateFontString()
        frame.ButtonContainer = CreateFrame("Frame", nil, frame)
        for index = 1, 4 do frame.ButtonContainer["Button" .. index] = button(frame.ButtonContainer) end
        frame.ExtraButton = button(frame)
        frame.EditBox = CreateFrame("EditBox", nil, frame)
        frame.EditBox.NineSlice = CreateFrame("Frame", nil, frame.EditBox)
        frame:Hide()
        return frame
    end
    local function menu()
        local frame = CreateFrame("Frame", "GameMenuFrame", UIParent)
        frame.Border, frame.Header = CreateFrame("Frame", nil, frame), CreateFrame("Frame", nil, frame)
        for _, key in ipairs({ "LeftBG", "RightBG", "CenterBG" }) do frame.Header[key] = frame.Header:CreateTexture() end
        frame.Header.Text = frame.Header:CreateFontString()
        frame.buttonPool = { active = {} }
        function frame.buttonPool:EnumerateActive() return pairs(self.active) end
        function frame:AddButton()
            local value = button(self, { "Left", "Center", "Right" })
            self.buttonPool.active[value] = true
            return value
        end
        frame:Hide()
        return frame
    end
    local function ghost()
        local frame = button(UIParent, { "Left", "Middle", "Right" })
        GhostFrame = frame
        GhostFrameContentsFrameText = frame:CreateFontString()
        GhostFrameContentsFrameIcon = frame:CreateTexture()
        function GhostFrameContentsFrameIcon:SetTexCoord(...) self.coords = { ... } end
        frame:Hide()
        return frame
    end
    local function installClient()
        for index = 1, 4 do popup("StaticPopup" .. index) end
        menu()
        ghost()
        CreateFont = function(name)
            local object = { name = name }
            function object:SetFont(path, size, flags) self.fontPath, self.fontSize, self.flags = path, size, flags end
            function object:SetTextColor(...) self.color = { ... } end
            return object
        end
    end
    local function load(profile, combat, prepare)
        widgets.loadAddon(env, { "src/modules/popups/popups.lua", "src/modules/popups/popups-skin.lua" }, profile, combat, function()
            installClient()
            if prepare then prepare() end
        end)
        return RikUI.Popups
    end
    local function flatButton(value)
        return value.art.GetNormalTexture.alpha == 0 and value.art.GetPushedTexture.alpha == 0
            and value.rikBacking ~= nil and value.rikBacking.texture == FLAT and #value.rikBorder == 4
            and value.rikHighlight.texture == RikUI.Media.highlight
    end
    local ok, reason = pcall(function()
        local module = load()
        local first, second = StaticPopup1, StaticPopup2
        check("nothing is skinned before a popup shows", first.Border.alpha == nil and first.rikBackdrop == nil)
        first:Show()
        check("a popup's dialog art is faded and replaced with a flat fill and edge on first show",
            first.Border.alpha == 0 and first.BG.alpha == 0 and first.rikBackdrop.texture == FLAT
            and #first.rikBorder == 4 and first.rikFade.plays == 1)
        check("popup text takes the RikUI font", first.Text.fontPath == RikUI.Media.font
            and first.SubText.fontPath == RikUI.Media.font and first.SubText.fontSize < first.Text.fontSize)
        check("popup body has a quiet secondary caption and inset top rule",
            first.SubText.textColor[1] < first.Text.textColor[1] and first.rikTopRule)
        local accept = first.ButtonContainer.Button1
        check("every popup button goes flat with a highlight", flatButton(accept)
            and flatButton(first.ButtonContainer.Button4) and flatButton(first.ExtraButton))
        check("button text uses shared RikUI font objects so state changes keep the font",
            accept.fontObjects.normal ~= nil and accept.fontObjects.normal.fontPath == RikUI.Media.font
            and accept.fontObjects.highlight ~= accept.fontObjects.normal and accept.fontObjects.disabled ~= nil
            and first.ExtraButton.fontObjects.normal == accept.fontObjects.normal)
        check("the popup edit box goes flat", first.EditBox.NineSlice.alpha == 0 and #first.EditBox.rikBorder == 4)
        env.runScript(first.EditBox, "OnEditFocusGained")
        check("popup input has a visible focus outline", first.EditBox.rikBorder[1].color[3] == 1)
        env.runScript(first.EditBox, "OnEditFocusLost")
        check("popup input clears focus outline", first.EditBox.rikBorder[1].color[3] < 1)
        accept:SetEnabled(false)
        env.runScript(accept, "OnDisable")
        check("popup disabled actions recede", accept.rikBacking.color[1] < 0.1 and accept.rikHighlight.alpha == 0)
        accept:SetEnabled(true)
        env.runScript(accept, "OnEnable")
        check("popup enabled actions return", accept.rikBacking.color[1] == 0.1 and accept.rikHighlight.alpha == 1)
        env.runScript(accept, "OnMouseDown", "LeftButton")
        check("popup actions give press feedback", accept.rikPress and accept.rikPress.region.alpha > 0)
        env.runScript(accept, "OnMouseUp", "LeftButton")
        check("the popup was not moved, resized, reparented or rescripted", first.points == nil and first.width == nil
            and first.parent == UIParent and first:GetScript("OnShow") == nil)
        env.runScript(first.EditBox, "OnEditFocusGained")
        first.EditBox:Hide()
        check("hidden popup input clears focus", first.EditBox.rikBorder[1].color[3] < 1)
        local topRule = first.rikTopRule
        local backdrop = first.rikBackdrop
        first:Hide()
        first:Show()
        check("a second show fades in again without a second skin", first.rikFade.plays == 2
            and first.rikBackdrop == backdrop)
        check("reused popup keeps its existing top rule", first.rikTopRule == topRule)
        check("another popup stays stock until it shows", second.Border.alpha == nil)
        second:Show()
        check("each popup is skinned on its own first show", second.Border.alpha == 0 and module.Skinned.StaticPopup2)

        local gameMenu = GameMenuFrame
        local resume = gameMenu:AddButton()
        gameMenu:Show()
        check("the game menu loses its border and header art and gets the flat fill and a gold title",
            gameMenu.Border.alpha == 0 and gameMenu.Header.LeftBG.alpha == 0 and gameMenu.Header.CenterBG.alpha == 0
            and gameMenu.rikBackdrop.texture == FLAT and gameMenu.Header.Text.fontPath == RikUI.Media.font
            and gameMenu.Header.Text.textColor[3] == 0 and gameMenu.rikFade.plays == 1)
        check("pooled menu buttons lose their three slices and go flat", resume.Left.alpha == 0
            and resume.Center.alpha == 0 and resume.Right.alpha == 0 and flatButton(resume))
        local backing = resume.rikBacking
        gameMenu:Hide()
        local later = gameMenu:AddButton()
        gameMenu:Show()
        check("a button the pool made later is skinned on the next show, the first one only once",
            flatButton(later) and resume.rikBacking == backing and gameMenu.rikFade.plays == 2)

        GhostFrame:Show()
        check("the ghost frame goes flat with the RikUI font and a cropped icon", GhostFrame.Left.alpha == 0
            and GhostFrame.Middle.alpha == 0 and flatButton(GhostFrame)
            and GhostFrameContentsFrameText.fontPath == RikUI.Media.font
            and GhostFrameContentsFrameIcon.coords[1] > 0 and GhostFrame.rikFade.plays == 1)
        check("nothing was printed by a clean skin", #env.printed == 0)
        SlashCmdList.RIKUI("debug")
        check("debug reports the skin state", widgets.printedContains(env, "Popups hooked=6 skinned=4 failed=0"))

        module = load(nil, false, function()
            StaticPopup1 = CreateFrame("Frame", "StaticPopup1", UIParent)
            StaticPopup1:Hide()
            GameMenuFrame.buttonPool = nil
            function StaticPopup2.Border:SetAlpha() error("border refused") end
        end)
        StaticPopup1:Show()
        GameMenuFrame:Show()
        check("a frame missing every optional region still gets the fill and says nothing",
            StaticPopup1.rikBackdrop ~= nil and GameMenuFrame.rikBackdrop ~= nil and #env.printed == 0)
        StaticPopup2:Show()
        StaticPopup2:Hide()
        StaticPopup2:Show()
        check("a failed skin is reported once, not retried and not faded in",
            widgets.printedContains(env, "Popups skin StaticPopup2") and #env.printed == 1
            and StaticPopup2.rikFade == nil and not module.Skinned.StaticPopup2)

        module = load(nil, false, function() StaticPopup3:Show() end)
        check("a popup already showing at login is skinned at once", StaticPopup3.Border.alpha == 0)
        env.inCombat = true
        StaticPopup4:Show()
        env.inCombat = false
        check("a first show in combat skins without a protected write", StaticPopup4.Border.alpha == 0
            and #env.printed == 0)

        module = load(nil, false, function() CreateFont = nil end)
        StaticPopup1:Show()
        check("a client without CreateFont keeps Blizzard's button font and says nothing",
            flatButton(StaticPopup1.ButtonContainer.Button1)
            and StaticPopup1.ButtonContainer.Button1.fontObjects.normal == nil and #env.printed == 0)

        module = load(nil, false, function() StaticPopup1, GameMenuFrame, GhostFrame = nil, nil, nil end)
        check("missing frames are skipped silently", module.Hooked.StaticPopup1 == nil
            and module.Hooked.StaticPopup2 == true and #env.printed == 0)

        module = load({ modules = { popups = false } })
        StaticPopup1:Show()
        check("a disabled module leaves the popups stock", StaticPopup1.Border.alpha == nil
            and StaticPopup1.rikBackdrop == nil)
    end)
    restore()
    for _, name in ipairs(API) do _G[name] = saved[name] end
    env.inCombat = false
    check("popup suite completes", ok, reason)
end
