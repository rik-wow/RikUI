local widgets = require("widget_stub")
local fixture = {}
function fixture.Frame(parent, key, kind)
    local f = CreateFrame(kind or "Frame", nil, parent)
    local methods = getmetatable(f).__index
    setmetatable(f, { __index = function(t, name)
        if name:match("^Get") or name:match("^Set") or name:match("^Is") or name:match("^Create")
            or name:match("^Clear") or name:match("^Hook") or name:match("^Has")
            or name == "Show" or name == "Hide" then return methods(t, name) end
    end })
    f.children, f.regions = {}, {}
    function f:GetChildren() return unpack(self.children) end
    function f:GetRegions() return unpack(self.regions) end
    function f:SetScale(value) self.scale = value end
    if parent then parent.children[#parent.children + 1] = f; parent[key] = f end
    return f
end
function fixture.Text(frame, key, text)
    local region = frame:CreateFontString()
    region:SetText(text or key)
    frame[key] = region
    frame.regions[#frame.regions + 1] = region
    return region
end
function fixture.Texture(frame, key)
    local region = frame:CreateTexture()
    frame[key] = region
    frame.regions[#frame.regions + 1] = region
    return region
end
function fixture.Button(parent, key)
    local button = fixture.Frame(parent, key, "Button")
    fixture.Text(button, "Text", key)
    function button:GetFontString() return self.Text end
    button:SetScript("OnClick", function(self) self.clicks = (self.clicks or 0) + 1 end)
    return button
end
function fixture.List(parent, key, header)
    local list = fixture.Frame(parent, key)
    fixture.Texture(list, "Background")
    fixture.Frame(list, "NineSlice")
    local box = fixture.Frame(list, "ScrollBox")
    box:SetWidth(580)
    box.callbacks, box.rows, box.provider = {}, {}, { native = true }
    box.view = { extent = 20 }
    function box.view:SetElementExtent(value) self.extent = value end
    function box:GetView() return self.view end
    function box:FullUpdate() self.updates = (self.updates or 0) + 1 end
    function box:RegisterCallback(event, fn, owner)
        self.callbacks[event] = self.callbacks[event] or {}
        table.insert(self.callbacks[event], { fn = fn, owner = owner })
    end
    function box:ForEachFrame(fn) for _, row in ipairs(self.rows) do fn(row) end end
    function box:Initialize(row)
        self.rows[#self.rows + 1] = row
        for _, callback in ipairs(self.callbacks.init or {}) do callback.fn(callback.owner, row) end
    end
    fixture.Frame(list, "ScrollBar")
    if header ~= false then
        fixture.Frame(list, "HeaderContainer")
        local refresh = fixture.Frame(list, "RefreshFrame")
        fixture.Button(refresh, "RefreshButton")
        fixture.Text(refresh, "TotalQuantity")
        fixture.Text(list, "ResultsText", "No results"):Hide()
        fixture.Frame(list, "LoadingSpinner"):Hide()
        list.tableBuilder = { width = 0 }
        function list.tableBuilder:SetTableWidth(width) self.width = width end
        function list.tableBuilder:Arrange() self.arranged = (self.arranged or 0) + 1 end
    end
    return list
end
function fixture.Form(parent, key)
    local form = fixture.Frame(parent, key)
    local item = fixture.Frame(form, "ItemDisplay", "Button")
    local slot = fixture.Frame(item, "ItemButton", "Button")
    fixture.Texture(slot, "Icon")
    fixture.Text(item, "ItemName", "Native item")
    fixture.Text(form, "CreateAuctionLabel", "Create Auction")
    for _, name in ipairs({ "QuantityInput", "PriceInput", "SecondaryPriceInput", "Duration", "Deposit", "TotalPrice" }) do
        local field = fixture.Frame(form, name)
        fixture.Text(field, "Label", name)
    end
    fixture.Frame(form.QuantityInput, "InputBox", "EditBox"):SetText("7")
    fixture.Button(form.QuantityInput, "MaxButton")
    fixture.Frame(form.PriceInput, "MoneyInputFrame").amount = 12345
    fixture.Frame(form.SecondaryPriceInput, "MoneyInputFrame").amount = 9000
    fixture.Frame(form.Duration, "Dropdown", "DropdownButton").durationIndex = 2
    fixture.Frame(form.Deposit, "MoneyDisplayFrame").amount = 100
    fixture.Frame(form.TotalPrice, "MoneyDisplayFrame").amount = 86415
    fixture.Button(form, "PostButton"):SetEnabled(false)
    function form:Layout() self.layouts = (self.layouts or 0) + 1 end
    fixture.Frame(form, "Overlay", "Button")
    return form
end
function fixture.Root()
    local f, button = fixture.Frame, fixture.Button
    local root = f()
    root:SetSize(800, 538)
    root.selectedTab = 1
    for _, key in ipairs({ "BuyTab", "SellTab", "AuctionsTab", "CloseButton" }) do button(root, key) end
    local title = f(root, "TitleContainer")
    fixture.Text(title, "TitleText", "Native auction title")
    f(root, "MoneyFrameInset")
    fixture.Frame(f(root, "MoneyFrameBorder"), "MoneyFrame").amount = 500000
    local search = f(root, "SearchBar")
    for _, key in ipairs({ "FavoritesSearchButton", "SearchButton" }) do button(search, key) end
    f(search, "SearchBox", "EditBox"):SetText("Runecloth")
    f(search, "FilterButton", "DropdownButton")
    fixture.List(root, "CategoriesList", false)
    local browse = f(root, "BrowseResultsFrame")
    fixture.List(browse, "ItemList")
    browse.ItemList.getNumEntries = function() return 12 end
    browse.searchStarted = true
    f(root, "WoWTokenResults"):Hide()
    local buy = f(root, "ItemBuyFrame")
    button(buy, "BackButton")
    f(buy, "ItemDisplay")
    fixture.List(buy, "ItemList")
    button(f(buy, "BuyoutFrame"), "BuyoutButton")
    local bid = f(buy, "BidFrame")
    f(bid, "BidAmount").amount = 33333
    button(bid, "BidButton"):SetEnabled(false)
    buy:Hide()
    local commodity = f(root, "CommoditiesBuyFrame")
    button(commodity, "BackButton")
    fixture.Form(commodity, "BuyDisplay")
    button(commodity.BuyDisplay, "BuyButton")
    fixture.List(commodity, "ItemList")
    commodity:Hide()
    fixture.Form(root, "ItemSellFrame"):Hide()
    fixture.Form(root, "CommoditiesSellFrame"):Hide()
    fixture.List(root, "ItemSellList"):Hide()
    fixture.List(root, "CommoditiesSellList"):Hide()
    f(root, "WoWTokenSellFrame"):Hide()
    local owned = f(root, "AuctionsFrame")
    owned.selectedTab = 1
    button(owned, "AuctionsTab"); button(owned, "BidsTab"); button(owned, "CancelAuctionButton")
    button(f(owned, "BuyoutFrame"), "BuyoutButton")
    button(f(owned, "BidFrame"), "BidButton")
    fixture.List(owned, "SummaryList", false)
    for _, key in ipairs({ "AllAuctionsList", "BidsList", "ItemList", "CommoditiesList" }) do fixture.List(owned, key) end
    f(owned, "ItemDisplay")
    owned:Hide()
    f(root, "DialogOverlay", "Button"):Hide()
    local dialog = f(root, "BuyDialog")
    f(dialog, "Border")
    f(dialog, "PriceFrame").amount = 765432
    fixture.Text(f(dialog, "ItemDisplay"), "ItemText", "Native purchase confirmation")
    for _, key in ipairs({ "BuyNowButton", "CancelButton", "OkayButton" }) do button(dialog, key) end
    f(dialog, "LoadingSpinner"):Hide()
    f(dialog, "DarkOverlay"):Hide()
    dialog:Hide()
    return root
end
-- Resolve the actual anchor constraints used by the presentation, in top-left coordinates.
function fixture.Bounds(frame, visited)
    visited = visited or {}
    assert(not visited[frame], "cyclic layout anchors")
    visited[frame] = true
    local fractions = { TOPLEFT = {0,0}, TOPRIGHT = {1,0}, BOTTOMLEFT = {0,1},
        BOTTOMRIGHT = {1,1}, LEFT = {0,0.5}, RIGHT = {1,0.5}, TOP = {0.5,0},
        BOTTOM = {0.5,1}, CENTER = {0.5,0.5} }
    local xs, ys = {}, {}
    for _, point in ipairs(frame.points or {}) do
        local target = fixture.Bounds(point[2], visited)
        local from, to = fractions[point[1]], fractions[point[3]]
        xs[#xs+1] = { from[1], target.x + to[1] * target.w + point[4] }
        ys[#ys+1] = { from[2], target.y + to[2] * target.h - point[5] }
    end
    local function solve(equations, size)
        size = type(size) == "number" and size or 0
        for i = 2, #equations do
            if equations[i][1] ~= equations[1][1] then
                size = (equations[i][2] - equations[1][2]) / (equations[i][1] - equations[1][1])
                break
            end
        end
        return equations[1] and equations[1][2] - equations[1][1] * size or 0, size
    end
    local x, w = solve(xs, frame.width)
    local y, h = solve(ys, frame.height)
    visited[frame] = nil
    return { x=x, y=y, w=w, h=h, right=x+w, bottom=y+h }
end

return fixture
