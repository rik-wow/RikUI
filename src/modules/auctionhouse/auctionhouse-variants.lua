-- Exact auction links retain random suffixes that the grouped item summary can omit.
local auction = RikUI.AuctionHouse

local function populate(cell, data)
    local link = data.itemLink
    local namedLink = type(link) == "string" and link:match("|H[^|]+|h%[.+%]|h")
    cell.Text:SetText(data.isVirtualEntry and (data.virtualEntryText or "")
        or (namedLink and link or "Item details unavailable"))
end

local function createCell(cell)
    cell:EnableMouse(false) -- The native row keeps selection and its exact-link tooltip.
    cell.Text = auction.Text(cell, "", "label")
    cell.Text:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, -4)
    cell.Text:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 0, 4)
    cell.Text:SetWordWrap(true)
    cell.Text:SetMaxLines(2)
    cell.Populate = populate
    cell.OnLineEnter = function() end
    cell.OnLineLeave = function() end
end

local function resetCell(_, cell)
    cell:Hide()
    cell:ClearAllPoints()
    cell.rowData = nil
    cell.Text:SetText("")
end

function auction.Variants(list)
    local root = AuctionHouseFrame
    local owner = root and root.ItemBuyFrame
    if not owner or list ~= owner.ItemList or not auction.Allowed(list) or InCombatLockdown() then return end
    local layout = list.tableBuilderLayoutFunction
    if type(layout) ~= "function" or type(list.SetTableBuilderLayout) ~= "function"
        or type(CreateFramePool) ~= "function" then return end
    local state = auction.State(list)
    if layout == state.variantLayout then return end

    -- A private pool prevents our text/methods leaking into Blizzard's shared template pools.
    state.variantPool = state.variantPool or CreateFramePool("Frame", nil, nil, resetCell, false, createCell)
    state.variantLayout = function(builder)
        layout(builder)
        local columns = builder:GetColumns()
        for _, column in ipairs(columns) do
            if column.pool and column.pool:GetTemplate() == "AuctionHouseTableCellItemQuantityLeftTemplate" then
                column:SetFixedConstraints(110, 0)
            end
        end
        local column = builder:AddColumn()
        column:ConstructHeader("BUTTON", "AuctionHouseTableHeaderStringTemplate", owner, "Item / enchantment", nil)
        column:SetFillConstraints(1, 0)
        column:SetCellPadding(10, 10)
        column.args, column.pool = {}, state.variantPool
        -- Leave the native price, quantity, socket and time columns in their original order.
        table.remove(columns, #columns)
        table.insert(columns, 1, column)
    end
    list:SetTableBuilderLayout(state.variantLayout)
end
