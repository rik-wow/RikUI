return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local restore, savedFont = widgets.install(), CreateFont
    local ok, reason = pcall(function()
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/menus/menus.lua",
            "src/modules/menus/menus-rows.lua" }, nil, false, function()
            CreateFont = function()
                local f = {}
                function f:CopyFontObject(source) self.source = source end
                function f:SetFont(path, size, flags) self.path, self.size, self.flags = path, size, flags end
                return f
            end
        end)
        local root, row = CreateFrame("Frame"), CreateFrame("Button")
        local text, mark = row:CreateFontString(), row:CreateTexture()
        local source = {}
        text.object = source
        function text:GetFontObject() return self.object end
        function text:SetFontObject(value) self.object = value end
        function text:GetFont() return "native", 14, "OUTLINE" end
        function text:SetFont() error("Use of function SetFont is disallowed") end
        function text:GetObjectType() return "FontString" end
        text:SetTextColor(0.5, 0.5, 0.5)
        function mark:GetObjectType() return "Texture" end
        function mark:GetAtlas() return self.atlas end
        function mark:SetTexture(value) self.texture, self.atlas = value, nil end
        mark.atlas = "common-dropdown-icon-checkmark-yellow"
        row.arrow, row.highlight = row:CreateTexture(), row:CreateTexture()
        local clicks = 0
        row:SetScript("OnClick", function() clicks = clicks + 1 end)
        function root:GetRegions() end
        function root:GetChildren() return row end
        function row:GetRegions() return text, mark end
        function row:GetChildren() end
        function row:CreateTexture() error("CreateTexture disallowed") end
        RikUI.Menus.StyleRows(root)
        local private = text.object
        check("menu uses private font with native size and disabled colour", private ~= source
            and private.path == RikUI.Media.font and private.size == 14 and text.textColor[1] == 0.5)
        check("check and submenu use flat assets", mark.texture == RikUI.Media.checked
            and row.arrow.texture == RikUI.Media.IconPath("chevron-right"))
        env.inCombat = true
        env.runScript(row, "OnClick")
        RikUI.Menus.StyleRows(root)
        env.inCombat = false
        check("repeat/combat styling preserves native action and font identity", clicks == 1 and text.object == private)
        text.object, mark.atlas = source, "common-dropdown-ticksquare"
        RikUI.Menus.StyleRows(root)
        check("pool reset reapplies private font and unchecked appearance", text.object == private
            and mark.texture == RikUI.Media.border and #env.printed == 0)
        function text:SetFontObject() error("font object refused") end
        text.object = source
        RikUI.Menus.StyleRows(root); RikUI.Menus.StyleRows(root)
        check("actual refused row operation reports once", #env.printed == 1
            and widgets.printedContains(env, "font object refused"))
    end)
    env.inCombat = false
    CreateFont = savedFont
    restore()
    check("menu rows suite completes", ok, reason)
end

