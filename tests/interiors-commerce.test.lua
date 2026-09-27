return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local restore = widgets.install()
    local saved = {}
    local names = { "MerchantFrame", "BankFrame", "MailFrame", "OpenMailFrame", "TradeFrame" }
    for _, name in ipairs(names) do saved[name] = _G[name] end
    local ok, reason = pcall(function()
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/panels/interiors.lua",
            "src/modules/panels/interiors-commerce.lua" })
        for _, name in ipairs(names) do
            local root, row, item = CreateFrame("Frame"), CreateFrame("Frame"), CreateFrame("Button")
            function root:GetChildren() return row end
            function row:GetChildren() return item end
            function item:GetChildren() end
            row.Name, row.SlotTexture = row:CreateFontString(), row:CreateTexture()
            item.icon = item:CreateTexture()
            item.IconBorder = item:CreateTexture()
            item.IconBorder:SetVertexColor(0.3, 0.5, 1)
            local clicks = 0
            item:SetScript("OnClick", function() clicks = clicks + 1 end)
            _G[name] = root
            RikUI.Interiors.Discover()
            check(name .. " row styled", RikUI.Interiors.State(row).fill and row.SlotTexture.alpha == 0)
            check(name .. " item styled", item.icon.coords[1] == 0.08 and RikUI.Interiors.State(item).edge)
            env.runScript(item, "OnClick")
            check(name .. " native action preserved", clicks == 1 and item.points == nil)
            local state = RikUI.Interiors.State(item)
            RikUI.Interiors.Discover()
            check(name .. " refresh reuses decoration", RikUI.Interiors.State(item) == state)
        end
        local inbox = CreateFrame("Frame", "RikTestInbox")
        function inbox:GetChildren() end
        RikTestInboxSender, RikTestInboxSubject = inbox:CreateFontString(), inbox:CreateFontString()
        RikTestInboxSender:SetText("Auction House")
        RikTestInboxSubject:SetText("Auction successful")
        RikUI.Interiors.Walk(inbox, "commerce")
        local mailState = RikUI.Interiors.State(inbox)
        check("legacy mail subject gains its own reading band", mailState.subjectPlate
            and mailState.subjectPlate.points[1][2] == RikTestInboxSubject
            and RikTestInboxSubject:GetText() == "Auction successful")
        local subjectPlate = mailState.subjectPlate
        RikTestInboxSubject:Hide()
        RikUI.Interiors.Walk(inbox, "commerce")
        check("hidden pooled mail subject clears its band", subjectPlate and not subjectPlate:IsShown())
        RikTestInboxSubject:Show()
        RikUI.Interiors.Walk(inbox, "commerce")
        check("mail band reuses native bounds", mailState.subjectPlate == subjectPlate
            and subjectPlate and subjectPlate:IsShown() and inbox.points == nil)
        RikTestInboxSender, RikTestInboxSubject, RikTestInbox = nil, nil, nil
        local money = CreateFrame("Frame")
        function money:GetChildren() end
        money.Amount = money:CreateFontString()
        money.Amount:SetText("12345")
        RikUI.Interiors.Walk(money, "commerce")
        check("money keeps amount and gains font", money.Amount:GetText() == "12345"
            and money.Amount.fontPath == RikUI.Media.font)
        local disabled = CreateFrame("Button")
        function disabled:GetChildren() end
        disabled.icon, disabled.DisabledOverlay = disabled:CreateTexture(), disabled:CreateTexture()
        RikUI.Interiors.Walk(disabled, "commerce")
        check("bank lock overlay retained", rawget(disabled.DisabledOverlay, "alpha") == nil)
    end)
    for _, name in ipairs(names) do _G[name] = saved[name] end
    restore()
    check("commerce interiors suite completes", ok, reason)
end

