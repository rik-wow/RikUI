return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local fixture = require("auctionhouse_fixture")
    local restore = widgets.install()
    local names = { "AuctionHouseFrame", "ScrollBoxListMixin", "C_AuctionHouse", "PanelTemplates_SetTab",
        "AuctionHouseFilterButton_SetUp", "UIParent" }
    local saved = {}
    for _, name in ipairs(names) do saved[name] = _G[name] end
    local ok, reason = pcall(function()
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/panels/interiors.lua",
            "src/modules/auctionhouse/auctionhouse.lua", "src/modules/auctionhouse/auctionhouse-layout.lua",
            "src/modules/auctionhouse/auctionhouse-style.lua" })
        local auction, root = RikUI.AuctionHouse, fixture.Root()
        UIParent = fixture.Frame()
        UIParent:SetSize(1920, 1080)
        AuctionHouseFrame = root
        ScrollBoxListMixin = { Event = { OnAcquiredFrame = "acquire", OnInitializedFrame = "init" } }
        local calls, ready = 0, true
        C_AuctionHouse = setmetatable({ IsThrottledMessageSystemReady = function() return ready end },
            { __index = function() return function() calls = calls + 1; error("unexpected auction backend call") end end })
        local setTab = function(frame, tab) frame.selectedTab = tab end
        PanelTemplates_SetTab = setTab
        AuctionHouseFilterButton_SetUp = function(button) button.NormalTexture:SetAlpha(1) end
        local searchClick = root.SearchBar.SearchButton:GetScript("OnClick")
        local postClick = root.ItemSellFrame.PostButton:GetScript("OnClick")
        local buyClick = root.BuyDialog.BuyNowButton:GetScript("OnClick")
        local provider = root.BrowseResultsFrame.ItemList.ScrollBox.provider
        auction.Refresh()
        check("auction family replaces generic services", RikUI.Interiors.Roots.AuctionHouseFrame == "auction")
        check("auction house has a dedicated wider workspace", root.width == 1080 and root.height == 660)
        check("auction navigation moved into the header", root.BuyTab.point[1] == "TOPLEFT"
            and root.BuyTab.point[5] == -55 and root.AuctionsTab.width == 180)
        check("search field has room for long item names", root.SearchBar.SearchBox.width > 600)
        check("browse and selling have separate panels", root.CategoriesList.points[1][4] < root.BrowseResultsFrame.points[1][4]
            and root.ItemSellFrame.points[1][4] < root.ItemSellList.points[1][4])
        local function gap(a, b)
            local first, second = fixture.Bounds(a), fixture.Bounds(b)
            return first.right + 8 <= second.x
        end
        check("search controls have non-overlapping bounds", gap(root.SearchBar.SearchBox, root.SearchBar.FilterButton)
            and gap(root.SearchBar.FilterButton, root.SearchBar.SearchButton))
        check("buy and sell columns have real gutters", gap(root.CategoriesList, root.BrowseResultsFrame)
            and gap(root.CommoditiesBuyFrame.BuyDisplay, root.CommoditiesBuyFrame.ItemList)
            and gap(root.ItemSellFrame, root.ItemSellList))
        local itemHeader, itemRows = fixture.Bounds(root.ItemBuyFrame.ItemDisplay), fixture.Bounds(root.ItemBuyFrame.ItemList)
        local itemActions = fixture.Bounds(root.ItemBuyFrame.BuyoutFrame)
        check("purchase rows fit between item summary and actions", itemHeader.bottom + 8 <= itemRows.y
            and itemRows.bottom + 8 <= itemActions.y and itemRows.h > 200)
        local summary, managed = fixture.Bounds(root.AuctionsFrame.SummaryList), fixture.Bounds(root.AuctionsFrame.AllAuctionsList)
        check("owned summary and result table fit without overlap", summary.right + 8 <= managed.x and managed.w > 600)
        check("native money is preserved", root.MoneyFrameBorder.MoneyFrame.amount == 500000)
        check("refresh never queries or transacts", calls == 0)
        check("native result provider remains attached", root.BrowseResultsFrame.ItemList.ScrollBox.provider == provider)
        check("native item search text is preserved", root.SearchBar.SearchBox:GetText() == "Runecloth")
        check("posting retains entered quantity, price and duration", root.ItemSellFrame.QuantityInput.InputBox:GetText() == "7"
            and root.ItemSellFrame.PriceInput.MoneyInputFrame.amount == 12345
            and root.ItemSellFrame.Duration.Dropdown.durationIndex == 2)
        check("unavailable post and bid actions stay disabled", not root.ItemSellFrame.PostButton:IsEnabled()
            and not root.ItemBuyFrame.BidFrame.BidButton:IsEnabled())
        check("native confirmation retains price and visibility", root.BuyDialog.PriceFrame.amount == 765432
            and not root.BuyDialog:IsShown() and not root.DialogOverlay:IsShown())
        check("native action scripts are retained", root.SearchBar.SearchButton:GetScript("OnClick") == searchClick
            and root.ItemSellFrame.PostButton:GetScript("OnClick") == postClick
            and root.BuyDialog.BuyNowButton:GetScript("OnClick") == buyClick)
        env.runScript(root.SearchBar.SearchButton, "OnClick")
        env.runScript(root.BuyDialog.BuyNowButton, "OnClick")
        check("buttons still execute their native handlers", root.SearchBar.SearchButton.clicks == 1
            and root.BuyDialog.BuyNowButton.clicks == 1)
        local list = root.BrowseResultsFrame.ItemList
        check("result row extent uses native scroll view", list.ScrollBox.view.extent == 28 and list.ScrollBox.updates == 1)
        check("table headers and cached widths are refreshed", list.HeaderContainer.height == 28 and list.tableBuilder.width == 580)
        check("footer reports actual native result count", root.rikAuction.status:GetText():find("12 results", 1, true) ~= nil)
        list.LoadingSpinner:Show(); auction.Refresh()
        check("loading state remains visible and explained", list.LoadingSpinner:IsShown()
            and root.rikAuction.status:GetText():find("Searching", 1, true) ~= nil)
        list.LoadingSpinner:Hide()
        list.getNumEntries = function() return 0 end
        auction.Refresh()
        check("empty results offer useful guidance", root.rikAuction.status:GetText():find("No results", 1, true) ~= nil)
        ready = false; auction.Refresh()
        check("throttling reports waiting without retrying requests", root.rikAuction.status:GetText():find("Waiting", 1, true) ~= nil
            and calls == 0)
        ready = true
        local row = fixture.Button(list.ScrollBox, "TestRow")
        row.rowData = { auctionID = 42, buyoutAmount = 98765 }
        fixture.Texture(row, "SelectedHighlight"):Hide()
        fixture.Texture(row, "HighlightTexture"):Hide()
        fixture.Texture(row, "NormalTexture")
        fixture.Texture(row, "Icon"):SetAlpha(0.5)
        row.Text:SetTextColor(0.12, 1, 0.12)
        list.ScrollBox:Initialize(row)
        check("pooled rows acquire custom furniture", row.rikAuction and row.rikAuction.rowFill ~= nil)
        check("row styling preserves native payload and quality", row.rowData.auctionID == 42
            and row.rowData.buyoutAmount == 98765 and row.Text.textColor[2] == 1)
        check("item icons become legible without clearing native fading", row.Icon.width == 20 and row.Icon.alpha == 0.5)
        check("unselected pooled rows remain unselected", not row.SelectedHighlight:IsShown())
        row.SelectedHighlight:SetAlpha(0.4); row.SelectedHighlight:Show()
        list.ScrollBox:Initialize(row)
        check("selection styling preserves native visibility and alpha", row.SelectedHighlight:IsShown()
            and row.SelectedHighlight.alpha == 0.4 and row.SelectedHighlight.width == 3)
        local fill = row.rikAuction.rowFill
        row.SelectedHighlight:Hide(); list.ScrollBox:Initialize(row)
        check("recycled selection clears with no duplicate furniture", not row.SelectedHighlight:IsShown()
            and row.rikAuction.rowFill == fill)
        local category = fixture.Button(root.CategoriesList.ScrollBox, "Category")
        fixture.Texture(category, "NormalTexture")
        fixture.Texture(category, "SelectedTexture"):Show()
        fixture.Texture(category, "HighlightTexture")
        AuctionHouseFilterButton_SetUp(category)
        check("late loaded category setup gets custom treatment", category.NormalTexture.alpha == 0
            and category.SelectedTexture.width == 3 and category.SelectedTexture:IsShown())
        local chrome = root.rikAuction.chrome
        local hooks = #root.hooks.OnShow
        auction.Refresh(); auction.Refresh()
        check("repeated refresh reuses chrome and hooks", root.rikAuction.chrome == chrome and #root.hooks.OnShow == hooks
            and list.ScrollBox.updates == 1)
        root.BrowseResultsFrame:Hide(); root.ItemSellFrame:Show()
        PanelTemplates_SetTab(root, 2); env.flushTimers()
        check("native tab changes update custom selection", root.SellTab.rikAuction.rail:IsShown()
            and not root.BuyTab.rikAuction.rail:IsShown())
        check("sell mode gets relevant guidance", root.rikAuction.status:GetText():find("Drag an item", 1, true) ~= nil)
        root.ItemSellFrame:Hide(); root.AuctionsFrame:Show()
        PanelTemplates_SetTab(root, 3); PanelTemplates_SetTab(root.AuctionsFrame, 2); env.flushTimers()
        check("owned auctions and bids keep both tab levels", root.AuctionsTab.rikAuction.rail:IsShown()
            and root.AuctionsFrame.BidsTab.rikAuction.rail:IsShown()
            and not root.AuctionsFrame.AuctionsTab.rikAuction.rail:IsShown())
        UIParent:SetSize(960, 600); auction.Refresh()
        check("small viewport scales entire workspace to fit", root.scale < 1
            and root.width * root.scale <= 920 and root.height * root.scale <= 540)
        UIParent:SetSize(1920, 1080); auction.Refresh()
        check("large viewport restores full readable size", root.scale == 1)
        local untouched = fixture.Root()
        AuctionHouseFrame = untouched
        env.inCombat = true; auction.Refresh()
        check("first open in combat defers custom layout", untouched.width == 800 and untouched.rikAuction == nil)
        env.inCombat = false; auction.Refresh()
        check("deferred layout can apply after combat", untouched.width == 1080)
        local disabled = fixture.Root()
        AuctionHouseFrame = disabled
        RikUI.Panels = { enabled = false }; auction.Refresh()
        check("disabled panels leave auction native", disabled.width == 800 and disabled.rikAuction == nil)
        RikUI.Panels = { FrameEnabled = function() return false end }; auction.Refresh()
        check("commerce opt-out leaves auction native", disabled.width == 800 and disabled.rikAuction == nil)
        RikUI.Panels = nil
        function disabled:IsForbidden() return true end
        auction.Refresh()
        check("forbidden auction is never decorated", disabled.rikAuction == nil)
        AuctionHouseFrame = nil
        auction.Refresh()
        check("load-on-demand absence is harmless", true)
        for _, message in ipairs(env.printed) do
            check("auction styling reports no client errors", not message:find("Interiors client limit", 1, true), message)
        end
    end)
    for _, name in ipairs(names) do _G[name] = saved[name] end
    env.inCombat = false
    restore()
    check("auction house suite completes", ok, reason)
end
