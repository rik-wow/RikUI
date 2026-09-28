-- The auction house with results, an item search, owned auctions and a sell page, from the simulator's
-- auction data verbs. RikUI lays the window out; Blizzard's controllers keep the transactions.

local RESULTS = {
    -- item id, item level, min price (copper), quantity
    { 2589, 1, 40, 240 }, { 118, 1, 250, 60 }, { 2070, 1, 190, 35 }, { 117, 1, 90, 48 }, { 25, 2, 1200, 3 }, { 4865, 1, 5000, 1 },
}

local function open()
    RikRenderBagItems()
    -- Item keys resolve through the bag fixture's item data; the simulator knows none of these items.
    C_AuctionHouse.GetItemKeyInfo = function(itemKey)
        local name, _, quality, _, _, _, _, stack, equipLoc, icon = GetItemInfo(itemKey.itemID)
        if not name then return nil end
        return { itemName = name, battlePetLink = nil, appearanceLink = nil, quality = quality, iconFileID = icon, isPet = false,
            isCommodity = (stack or 1) > 1, isEquipment = equipLoc ~= nil and equipLoc ~= "" }
    end
    A_Admin.ClearAuctionBrowseResults()
    A_Admin.ClearOwnedAuctions()
    A_Admin.SetAuctionThrottleReady(true)
    for index, row in ipairs(RESULTS) do A_Admin.AddAuctionBrowseResult(row[1], row[2], row[3], row[4], false, 1000 + index) end
    A_Admin.FireEvent("AUCTION_HOUSE_SHOW")
    local frame = RikRenderWindow("AuctionHouseFrame")
    return frame
end

-- Blizzard's result rows give their name strings a height of zero and let the client size them to
-- their text; the simulator leaves them one pixel tall, so the fixture gives them a text line.
local function nameHeights(node)
    for _, region in ipairs({ node:GetRegions() }) do
        if region:GetObjectType() == "FontString" and region:GetHeight() <= 1 and (region:GetText() or "") ~= "" then
            region:SetHeight(16)
        end
    end
    for _, child in ipairs({ node:GetChildren() }) do nameHeights(child) end
end

local function settle(frame)
    if RikUI.AuctionHouse and RikUI.AuctionHouse.Refresh then RikUI.AuctionHouse.Refresh() end
    RikRenderResize(frame)
    RikRenderRemeasure(frame)
    nameHeights(frame)
    return frame
end

-- The buy page with search results listed.
function RikRenderAuctionBrowse()
    local frame = open()
    A_Admin.FireEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    if frame.BrowseResultsFrame and frame.BrowseResultsFrame.ItemList and frame.BrowseResultsFrame.ItemList.RefreshScrollFrame then
        pcall(frame.BrowseResultsFrame.ItemList.RefreshScrollFrame, frame.BrowseResultsFrame.ItemList)
    end
    return settle(frame)
end

-- One commodity selected: the buy page shows the listings and the quantity controls.
function RikRenderAuctionItem()
    local frame = open()
    for index = 1, 5 do A_Admin.AddAuctionCommoditySearchResult(2589, 20 * index, 38 + index * 2, 2000 + index, "Seller" .. index) end
    A_Admin.FireEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    if frame.SelectBrowseResult then
        pcall(frame.SelectBrowseResult, frame, { itemKey = { itemID = 2589, itemLevel = 1, itemSuffix = 0, battlePetSpeciesID = 0 }, totalQuantity = 240, minPrice = 40 })
    end
    A_Admin.FireEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
    return settle(frame)
end

-- The sell page with an item placed.
function RikRenderAuctionSell()
    local frame = open()
    if frame.SetDisplayMode and AuctionHouseFrameDisplayMode then pcall(frame.SetDisplayMode, frame, AuctionHouseFrameDisplayMode.ItemSell) end
    if frame.ItemSellFrame and frame.ItemSellFrame.SetItem then
        pcall(frame.ItemSellFrame.SetItem, frame.ItemSellFrame, ItemLocation and ItemLocation:CreateFromBagAndSlot(0, 5))
    end
    return settle(frame)
end

-- The auctions page: the character's own listings.
function RikRenderAuctionOwned()
    local frame = open()
    A_Admin.AddOwnedAuction(3001, 25, 2, 1, 1200, 1600, 1, 3, 3 * 60 * 60)
    A_Admin.AddOwnedAuction(3002, 2589, 1, 20, 0, 800, 1, 4, 12 * 60 * 60)
    A_Admin.AddOwnedAuction(3003, 118, 1, 5, 0, 1250, 2, 2, 40 * 60)
    A_Admin.FireEvent("OWNED_AUCTIONS_UPDATED")
    if frame.SetDisplayMode and AuctionHouseFrameDisplayMode then pcall(frame.SetDisplayMode, frame, AuctionHouseFrameDisplayMode.Auctions) end
    settle(frame)
    -- The time-left column is an atlas icon with no text; the simulator gives such strings no area, so the
    -- column shows each auction's remaining time in words instead.
    local hours = { 3, 12, 1 }
    local index = 0
    local function visit(node)
        for _, region in ipairs({ node:GetRegions() }) do
            if region:GetObjectType() == "FontString" and (region:GetText() or ""):find("|A:", 1, true) then
                index = index + 1
                region:SetText((hours[index] or 1) .. " hr")
            end
        end
        for _, child in ipairs({ node:GetChildren() }) do visit(child) end
    end
    if frame.AuctionsFrame then visit(frame.AuctionsFrame) end
    return frame
end
