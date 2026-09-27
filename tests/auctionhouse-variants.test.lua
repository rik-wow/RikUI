return function(check)
    local env, widgets = require("wow_stub"), require("widget_stub")
    local fixture, variants = require("auctionhouse_fixture"), require("auctionhouse_variants_fixture")
    local restore = widgets.install()
    local savedRoot, savedPool, savedAPI = AuctionHouseFrame, CreateFramePool, C_AuctionHouse
    local ok, reason = pcall(function()
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/modules/panels/interiors.lua",
            "src/modules/auctionhouse/auctionhouse.lua", "src/modules/auctionhouse/auctionhouse-layout.lua",
            "src/modules/auctionhouse/auctionhouse-variants.lua",
            "src/modules/auctionhouse/auctionhouse-style.lua" })
        CreateFramePool = variants.Pool
        local backendCalls = 0
        C_AuctionHouse = setmetatable({}, { __index = function()
            return function() backendCalls = backendCalls + 1; error("unexpected backend request") end
        end })
        local root = fixture.Root()
        AuctionHouseFrame = root
        local auction, list = RikUI.AuctionHouse, root.ItemBuyFrame.ItemList
        local builder, nativeLayout = variants.List(list)
        local provider = list.ScrollBox.provider
        local bear = "|cff1eff00|Hitem:15210:0:0:0:0:0:1182:123|h[Raider's Shortsword of the Bear]|h|r"
        local eagle = "|cff1eff00|Hitem:15210:0:0:0:0:0:228:456|h[Raider's Shortsword of the Eagle]|h|r"
        local first, second = { auctionID = 11, itemLink = bear, buyoutAmount = 50000 },
            { auctionID = 12, itemLink = eagle, buyoutAmount = 60000 }
        local row = fixture.Button(list.ScrollBox, "VariantRow")
        row.cells, row.rowData = {}, first
        local nativeClick, nativeEnter = row:GetScript("OnClick"), function() end
        row:SetScript("OnEnter", nativeEnter)
        builder.rows = { row }
        auction.Style(list)
        check("purchase listings expose an additional item/enchantment column", #builder.columns == 6)
        if #builder.columns ~= 6 then return end
        local column, cell = builder.columns[1], row.cells[1]
        check("variant column is unsortable", column.header.text == "Item / enchantment" and column.header.sort == nil)
        check("exact random enchantment link is visible before purchase", cell.Text:GetText() == bear)
        check("native columns remain in order", builder.columns[2].native == "Bid" and builder.columns[3].native == "Buyout"
            and builder.columns[4].native == "AuctionHouseTableCellItemQuantityLeftTemplate")
        check("variant name gets remaining space and wraps", column.fill == 1 and builder.columns[4].width == 110
            and cell.Text.wordWrap and list.ScrollBox.view.extent == 44)
        check("variant column leaves native mouse and tooltip handling intact", cell.mouseEnabled == false
            and row:GetScript("OnClick") == nativeClick and row:GetScript("OnEnter") == nativeEnter
            and not cell:GetScript("OnEnter") and not cell:GetScript("OnUpdate"))
        cell:OnLineEnter(); cell:OnLineLeave()
        row.rowData = second
        builder:Arrange()
        local reused = row.cells[1]
        check("recycled same-base item shows its own enchantment", reused == cell and reused.Text:GetText() == eagle
            and reused.rowData == second)
        check("native transaction payload is unchanged", row.rowData == second and second.auctionID == 12
            and second.buyoutAmount == 60000 and second.itemLink == eagle)
        row.rowData = { auctionID = 13, itemKey = { itemID = 15210 } }
        builder:Arrange()
        check("missing exact link clears previous suffix", cell.Text:GetText() == "Item details unavailable"
            and cell.rowData == row.rowData)
        row.rowData.itemLink = "|cff1eff00|Hitem:15210:0:0:0:0:0:1182:789|h[Épée de l’ours]|h|r"
        builder:Arrange()
        check("late exact link displays its localized name", cell.Text:GetText() == row.rowData.itemLink)
        row.rowData = { auctionID = 14, itemLink = "item:15210", itemKey = { itemID = 15210 } }
        builder:Arrange()
        check("bare item references never masquerade as exact names", cell.Text:GetText() == "Item details unavailable")
        row.rowData = { isVirtualEntry = true, virtualEntryText = "Loading more auctions..." }
        builder:Arrange()
        check("virtual loading row remains distinct from an item", cell.Text:GetText() == "Loading more auctions...")
        row.rowData = first
        builder:Arrange()
        local layouts, arrangements, updates = list.setLayouts, builder.arranged, list.ScrollBox.updates
        auction.Style(list); auction.Style(list)
        check("stationary hover causes no layout or cell rebuild", list.setLayouts == layouts
            and builder.arranged == arrangements and list.ScrollBox.updates == updates and row.cells[1] == cell)
        list:SetTableBuilderLayout(nativeLayout)
        auction.Style(list)
        check("native layout replacement reattaches exactly one column", #builder.columns == 6 and row.cells[1].Text:GetText() == bear)
        check("layout rebuild reuses the isolated cell pool", builder.columns[1].pool == column.pool and column.pool.created == 1)
        check("native provider remains attached without backend calls", list.ScrollBox.provider == provider and backendCalls == 0)
        env.runScript(row, "OnClick")
        check("native click handler still selects through its own path", row.clicks == 1)
        local peer = fixture.Button(list.ScrollBox, "PeerRow")
        peer.cells, peer.rowData = {}, second
        builder.rows = { row, peer }
        builder:Arrange()
        check("simultaneous listings display different suffixes", row.cells[1].Text:GetText() == bear
            and peer.cells[1].Text:GetText() == eagle)
        builder.rows = { peer, row }
        builder:Arrange()
        check("sorting keeps each enchantment attached to its auction", row.cells[1].Text:GetText() == bear
            and peer.cells[1].Text:GetText() == eagle and row.rowData.auctionID == 11 and peer.rowData.auctionID == 12)
        builder:Reset()
        check("released variant cells hide and clear auction data", not cell:IsShown() and cell.rowData == nil and cell.Text:GetText() == "")
        local browse = root.BrowseResultsFrame.ItemList
        local browseBuilder = variants.List(browse)
        auction.Style(browse)
        check("grouped browse and commodity lists are not treated as individual auctions", #browseBuilder.columns == 5)
        local other = fixture.Root()
        AuctionHouseFrame = other
        local otherList = other.ItemBuyFrame.ItemList
        local otherBuilder = variants.List(otherList)
        env.inCombat = true; auction.Style(otherList)
        check("variant layout defers during combat", #otherBuilder.columns == 5)
        env.inCombat = false
        RikUI.Panels = { enabled = false }; auction.Style(otherList)
        check("disabled panels preserve native variant layout", #otherBuilder.columns == 5)
        RikUI.Panels = nil
        auction.Style(otherList)
        check("deferred variant layout installs after restrictions clear", #otherBuilder.columns == 6)
    end)
    AuctionHouseFrame, CreateFramePool, C_AuctionHouse = savedRoot, savedPool, savedAPI
    env.inCombat = false
    restore()
    check("auction variant suite completes", ok, reason)
end
