return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local restore, savedMixin = widgets.install(), ScrollBoxListMixin
    local ok, reason = pcall(function()
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/panels/interiors.lua",
            "src/modules/panels/interiors-commerce.lua", "src/modules/panels/interiors-services.lua" })
        ScrollBoxListMixin = { Event = { OnAcquiredFrame = "acquire", OnInitializedFrame = "init" } }
        for _, name in ipairs({ "AuctionHouseFrame", "ClassTrainerFrame", "ProfessionsFrame", "GuildBankFrame", "PetStableFrame" }) do
            check(name .. " registered", RikUI.Interiors.Roots[name] == "services")
        end
        local trainer = CreateFrame("Button")
        function trainer:GetChildren() end
        trainer.name, trainer.BG = trainer:CreateFontString(), trainer:CreateTexture()
        RikUI.Interiors.Walk(trainer, "services")
        check("trainer lowercase label and BG styled", trainer.name.fontPath == RikUI.Media.font
            and trainer.BG.alpha == 0)
        local auction = CreateFrame("Button")
        function auction:GetChildren() end
        auction.NormalTexture, auction.SelectedHighlight = auction:CreateTexture(), auction:CreateTexture()
        RikUI.Interiors.Walk(auction, "services")
        check("auction row stripes are flat without losing selection", auction.NormalTexture.alpha == 0
            and RikUI.Interiors.State(auction).fill and rawget(auction.SelectedHighlight, "alpha") == nil)
        local list = CreateFrame("Frame")
        function list:GetChildren() end
        function list:ForEachFrame() end
        list.callbacks = {}
        function list:RegisterCallback(event, fn, owner) self.callbacks[event] = { fn, owner } end
        RikUI.Interiors.Walk(list, "services")
        local row = CreateFrame("Button")
        function row:GetChildren() end
        row.Label, row.Background, row.SelectedHighlight = row:CreateFontString(), row:CreateTexture(), row:CreateTexture()
        row.Label:SetTextColor(0.2, 0.7, 0.3)
        local cb = list.callbacks.init
        cb[1](cb[2], row)
        local state = RikUI.Interiors.State(row)
        check("late service row flattened", state.fill and row.Background.alpha == 0)
        check("availability colour and native selection retained", row.Label.textColor[2] == 0.7
            and rawget(row.SelectedHighlight, "alpha") == nil)
        row.SelectedHighlight:Hide()
        cb[1](cb[2], row)
        check("recycled service selection clears through native visibility",
            not row.SelectedHighlight:IsShown() and row.SelectedHighlight.width == 3)
        row.Background:SetAlpha(1)
        cb[1](cb[2], row)
        check("recycled rows refresh without duplicate hooks", row.Background.alpha == 0
            and RikUI.Interiors.State(row) == state and #row.hooks.OnEnter == 1)
        env.runScript(row, "OnEnter"); env.runScript(row, "OnHide")
        check("recycling cancels stale hover", state.hover.alpha == 0 and not state.enter.playing)
    end)
    ScrollBoxListMixin = savedMixin
    restore()
    check("service interiors suite completes", ok, reason)
end

