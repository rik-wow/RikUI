local core, auction, skin = RikUI, RikUI.AuctionHouse, RikUI.Skin
local PAD, SIDE, GAP = auction.PAD, auction.SIDEBAR, 12

function auction.Rect(frame, parent, left, top, right, bottom)
    if not auction.Allowed(frame) then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -top)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -right, bottom)
end

function auction.Box(frame, parent, left, top, width, height)
    if not auction.Allowed(frame) then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", left, -top)
    frame:SetSize(width, height)
end

local function footer(frame, parent, right, width)
    if not auction.Allowed(frame) then return end
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -right, 12)
    frame:SetSize(width, 30)
end

function auction.Nav(frame, parent, left, top, width, selected)
    if not auction.Allowed(frame) then return end
    auction.Box(frame, parent, left, top, width, 32)
    auction.Card(frame)
    local state = auction.State(frame)
    if not state.rail then
        state.rail = skin.Fill(frame, skin.GOLD)
        state.rail:ClearAllPoints()
        state.rail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
        state.rail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        state.rail:SetHeight(2)
    end
    state.rail:SetShown(selected)
    state.fill:SetVertexColor(unpack(selected and { 0.19, 0.16, 0.095, 1 } or auction.PANEL))
    skin.Strip(frame, { "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive",
        "LeftHighlight", "MiddleHighlight", "RightHighlight", "rikBacking", "rikAccent" })
    local text = frame.Text or (type(frame.GetFontString) == "function" and frame:GetFontString())
    if skin.IsRegion(text) then
        skin.Typeface(text, 13)
        text:ClearAllPoints(); text:SetPoint("CENTER", frame, "CENTER")
        text:SetTextColor(unpack(selected and skin.GOLD or skin.INK))
    end
end

local function header(frame)
    local tab = frame.selectedTab or 1
    auction.Nav(frame.BuyTab, frame, PAD, 55, 140, tab == 1)
    auction.Nav(frame.SellTab, frame, PAD + 148, 55, 140, tab == 2)
    auction.Nav(frame.AuctionsTab, frame, PAD + 296, 55, 180, tab == 3)
    local close = frame.CloseButton or (frame.BorderFrame and frame.BorderFrame.CloseButton)
    auction.Box(close, frame, auction.WIDTH - 44, 10, 30, 30)
    if auction.Allowed(frame.MoneyFrameBorder) then
        footer(frame.MoneyFrameBorder, frame, PAD, 200)
        auction.Card(frame.MoneyFrameBorder)
    end
    skin.Strip(frame, { "MoneyFrameInset" })
end

local function search(frame)
    local bar = frame.SearchBar
    if not auction.Allowed(bar) then return end
    auction.Box(bar, frame, PAD, 106, auction.WIDTH - PAD * 2, 40)
    auction.Card(bar)
    auction.Box(bar.FavoritesSearchButton, bar, 8, 6, 28, 28)
    auction.Box(bar.SearchBox, bar, 48, 6, auction.WIDTH - PAD * 2 - 330, 28)
    auction.Box(bar.FilterButton, bar, auction.WIDTH - PAD * 2 - 268, 6, 134, 28)
    auction.Box(bar.SearchButton, bar, auction.WIDTH - PAD * 2 - 122, 6, 114, 28)
end

local function browse(frame)
    auction.Rect(frame.CategoriesList, frame, PAD, 158, auction.WIDTH - PAD - SIDE, 54)
    auction.Rect(frame.BrowseResultsFrame, frame, PAD + SIDE + GAP, 158, PAD, 54)
    auction.Rect(frame.WoWTokenResults, frame, PAD + SIDE + GAP, 158, PAD, 54)
    if frame.BrowseResultsFrame then
        auction.Rect(frame.BrowseResultsFrame.ItemList, frame.BrowseResultsFrame, 0, 0, 0, 0)
    end
    auction.Card(frame.CategoriesList)
    if auction.Allowed(frame.CategoriesList) then
        local categories = frame.CategoriesList
        local state = auction.State(categories)
        if not state.caption then
            state.caption = auction.Text(categories, "Categories", "label")
            state.caption:SetPoint("TOPLEFT", categories, "TOPLEFT", 12, -12)
            state.caption:SetTextColor(unpack(skin.GOLD))
        end
        auction.Rect(categories.ScrollBox, categories, 6, 36, 25, 8)
    end
end

local function itemBuy(frame)
    local buy = frame.ItemBuyFrame
    if not auction.Allowed(buy) then return end
    auction.Rect(buy, frame, PAD + SIDE + GAP, 158, PAD, 54)
    auction.Box(buy.BackButton, buy, 0, 0, 110, 28)
    auction.Rect(buy.ItemDisplay, buy, 0, 38, 0, 0)
    if buy.ItemDisplay then
        buy.ItemDisplay:ClearAllPoints()
        buy.ItemDisplay:SetPoint("TOPLEFT", buy, "TOPLEFT", 0, -38)
        buy.ItemDisplay:SetPoint("TOPRIGHT", buy, "TOPRIGHT", 0, -38)
        buy.ItemDisplay:SetHeight(80)
        auction.Card(buy.ItemDisplay)
    end
    auction.Rect(buy.ItemList, buy, 0, 130, 0, 54)
    footer(buy.BuyoutFrame, buy, 8, 120)
    footer(buy.BidFrame, buy, 150, 250)
    if buy.BuyoutFrame and auction.Allowed(buy.BuyoutFrame.BuyoutButton) then
        buy.BuyoutFrame.BuyoutButton:SetSize(120, 30)
    end
end

local function commodityBuy(frame)
    local buy = frame.CommoditiesBuyFrame
    if not auction.Allowed(buy) then return end
    auction.Rect(buy, frame, PAD + SIDE + GAP, 158, PAD, 54)
    auction.Box(buy.BackButton, buy, 0, 0, 110, 28)
    auction.Box(buy.BuyDisplay, buy, 0, 38, 390, 410)
    auction.Rect(buy.ItemList, buy, 402, 38, 0, 0)
    if auction.Allowed(buy.BuyDisplay) then
        buy.BuyDisplay.fixedWidth, buy.BuyDisplay.fixedHeight = 390, 410
        auction.Card(buy.BuyDisplay)
        if type(buy.BuyDisplay.Layout) == "function" then buy.BuyDisplay:Layout() end
    end
end

local function sellPanel(panel, frame)
    if not auction.Allowed(panel) then return end
    auction.Rect(panel, frame, PAD, 120, auction.WIDTH - PAD - 400, 54)
    panel.fixedWidth, panel.fixedHeight = 400, auction.HEIGHT - 174
    panel.topPadding, panel.leftPadding, panel.rightPadding = 20, 20, 20
    panel.spacing, panel.bottomPadding = 18, 16
    auction.Card(panel)
    skin.Strip(panel, { "CreateAuctionTabLeft", "CreateAuctionTabMiddle", "CreateAuctionTabRight" })
    if skin.IsRegion(panel.CreateAuctionLabel) then
        panel.CreateAuctionLabel:ClearAllPoints()
        panel.CreateAuctionLabel:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, 8)
        core.Media.Font(panel.CreateAuctionLabel, "label")
    end
    if auction.Allowed(panel.PostButton) then panel.PostButton:SetSize(220, 30) end
    if type(panel.Layout) == "function" then panel:Layout() end
end

local function selling(frame)
    sellPanel(frame.ItemSellFrame, frame)
    sellPanel(frame.CommoditiesSellFrame, frame)
    auction.Rect(frame.WoWTokenSellFrame, frame, PAD, 120, auction.WIDTH - PAD - 400, 54)
    auction.Rect(frame.ItemSellList, frame, PAD + 400 + GAP, 120, PAD, 54)
    auction.Rect(frame.CommoditiesSellList, frame, PAD + 400 + GAP, 120, PAD, 54)
    for _, list in ipairs({ frame.ItemSellList, frame.CommoditiesSellList }) do
        if auction.Allowed(list) then
            local state = auction.State(list)
            if not state.caption then
                state.caption = auction.Text(list, "Current listings", "label")
                state.caption:SetPoint("BOTTOMLEFT", list, "TOPLEFT", 0, 8)
                state.caption:SetTextColor(unpack(skin.GOLD))
            end
        end
    end
end

local function management(frame)
    local owned = frame.AuctionsFrame
    if not auction.Allowed(owned) then return end
    auction.Rect(owned, frame, PAD, 108, PAD, 54)
    auction.Nav(owned.AuctionsTab, owned, 0, 0, 140, (owned.selectedTab or 1) == 1)
    auction.Nav(owned.BidsTab, owned, 148, 0, 120, owned.selectedTab == 2)
    auction.Rect(owned.SummaryList, owned, 0, 44, auction.WIDTH - PAD * 2 - SIDE, 54)
    auction.Card(owned.SummaryList)
    for _, key in ipairs({ "AllAuctionsList", "BidsList" }) do
        auction.Rect(owned[key], owned, SIDE + GAP, 44, 0, 54)
    end
    auction.Box(owned.ItemDisplay, owned, SIDE + GAP, 44, auction.WIDTH - PAD * 2 - SIDE - GAP, 80)
    for _, key in ipairs({ "ItemList", "CommoditiesList" }) do
        auction.Rect(owned[key], owned, SIDE + GAP, 136, 0, 54)
    end
    footer(owned.CancelAuctionButton, owned, 8, 180)
    footer(owned.BuyoutFrame, owned, 8, 120)
    footer(owned.BidFrame, owned, 150, 250)
end

function auction.Layout(frame)
    frame:SetClampedToScreen(true)
    frame:SetSize(auction.WIDTH, auction.HEIGHT)
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if type(width) == "number" and type(height) == "number" and width > 0 and height > 0 then
        frame:SetScale(math.min(1, (width - 40) / auction.WIDTH, (height - 60) / auction.HEIGHT))
    end
    header(frame); search(frame); browse(frame)
    itemBuy(frame); commodityBuy(frame); selling(frame); management(frame)
    if auction.Allowed(frame.DialogOverlay) then auction.Rect(frame.DialogOverlay, frame, 1, 48, 1, 1) end
end
