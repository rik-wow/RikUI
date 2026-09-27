local core, auction, skin = RikUI, RikUI.AuctionHouse, RikUI.Skin
local ROW_HEIGHT = 28
local TEXT_KEYS = { "Text", "Label", "LabelTitle", "Subtext", "ItemName", "ItemText", "Name", "Price",
    "ResultsText", "SearchingText", "TotalQuantity", "ExtraInfo", "Prefix", "GoldText", "SilverText", "CopperText" }
local ACTIONS = { "SearchButton", "BuyButton", "PostButton", "BuyoutButton", "BidButton",
    "CancelAuctionButton", "BuyNowButton", "OkayButton", "CancelButton", "BackButton", "MaxButton" }

local function font(region)
    if not skin.IsRegion(region) or type(region.GetObjectType) ~= "function"
        or region:GetObjectType() ~= "FontString" then return end
    skin.Typeface(region, 13)
end

local function texture(region, frame, color, rail)
    if not skin.IsRegion(region) or type(region.SetTexture) ~= "function" then return end
    region:SetTexture(skin.FLAT)
    region:SetTexCoord(0, 1, 0, 1)
    region:SetBlendMode("BLEND")
    region:SetVertexColor(unpack(color))
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    if rail then
        region:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
        region:SetWidth(3)
    else
        region:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    end
end

local function row(frame)
    local selected = frame.SelectedHighlight or frame.SelectedTexture
    if not skin.IsRegion(selected) then return end
    local state = auction.State(frame)
    if not state.rowFill then
        state.rowFill = skin.Fill(frame, { 0.09, 0.105, 0.135, 1 }, 1)
        state.rowRule = frame:CreateTexture(nil, "BORDER")
        state.rowRule:SetTexture(skin.FLAT)
        state.rowRule:SetVertexColor(0.2, 0.24, 0.3, 0.5)
        state.rowRule:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 0)
        state.rowRule:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 0)
        state.rowRule:SetHeight(1)
    end
    texture(selected, frame, { 0.3, 0.75, 1 }, true)
    texture(frame.HighlightTexture, frame, { 0.18, 0.23, 0.3 }, false)
    skin.Strip(frame, { "NormalTexture", "Lines" })
    local normal = type(frame.GetNormalTexture) == "function" and frame:GetNormalTexture()
    if skin.IsRegion(normal) then normal:SetAlpha(0) end
    local index = type(frame.GetElementData) == "function" and frame:GetElementData()
    local even = type(index) == "number" and index % 2 == 0
    state.rowFill:SetVertexColor(unpack(even and { 0.075, 0.09, 0.115, 1 } or { 0.095, 0.11, 0.14, 1 }))
end

local function scroll(frame)
    local box = frame.ScrollBox
    if not auction.Allowed(box) or type(box.GetView) ~= "function" then return end
    local view = box:GetView()
    if type(view) ~= "table" or type(view.SetElementExtent) ~= "function" then return end
    local state = auction.State(box)
    local height = auction.State(frame).variantLayout and 44 or ROW_HEIGHT
    if state.view ~= view or state.rowHeight ~= height then
        state.view, state.rowHeight = view, height
        view:SetElementExtent(height)
        if type(box.FullUpdate) == "function" then box:FullUpdate() end
    end
end

local function list(frame)
    if not auction.Allowed(frame.HeaderContainer) or not auction.Allowed(frame.ScrollBox) then return end
    auction.Card(frame)
    auction.Card(frame.HeaderContainer)
    frame.HeaderContainer:SetHeight(28)
    local header = auction.State(frame.HeaderContainer)
    header.fill:SetVertexColor(0.12, 0.145, 0.185, 1)
    local refresh = frame.RefreshFrame
    if auction.Allowed(refresh) then
        auction.Point(refresh, frame, "TOPRIGHT", "TOPRIGHT", -8, 30)
    end
    local width = frame.ScrollBox:GetWidth()
    local state = auction.State(frame)
    if frame.tableBuilder and type(width) == "number" and width > 0 and state.tableWidth ~= width then
        state.tableWidth = width
        frame.tableBuilder:SetTableWidth(width)
        frame.tableBuilder:Arrange()
    end
    if skin.IsRegion(frame.ResultsText) then
        core.Media.Font(frame.ResultsText, "label")
        frame.ResultsText:SetTextColor(unpack(skin.INK))
        frame.ResultsText:SetWordWrap(true)
    end
end

local function itemDisplay(frame)
    if not auction.Allowed(frame.ItemButton) then return end
    auction.Card(frame)
    -- Only the decorative header atlas; keep actual item art and tooltip targets.
    for _, region in ipairs({ frame:GetRegions() }) do
        if type(region.GetAtlas) == "function" and region:GetAtlas() == "auctionhouse-itemheaderframe" then
            region:SetAlpha(0)
        end
    end
    local button = frame.ItemButton
    core.Interiors.Item(button)
    if skin.IsRegion(button.Icon) then skin.CropIcon(button.Icon) end
end

local function itemCell(frame)
    if not frame.rowData and not skin.IsRegion(frame.SelectedHighlight) then return end
    if not skin.IsRegion(frame.Text) or not skin.IsRegion(frame.Icon)
        or frame.Icon:GetObjectType() ~= "Texture" then return end
    skin.CropIcon(frame.Icon)
    frame.Icon:SetSize(20, 20)
    if skin.IsRegion(frame.IconBorder) then frame.IconBorder:SetSize(22, 22) end
end

local function action(button)
    if not auction.Allowed(button) then return end
    local state = auction.State(button)
    if not state.action then
        state.action = true
        skin.ButtonFonts(button)
        core.Motion.BindPress(button)
    end
    if button.rikFill then
        local enabled = type(button.IsEnabled) ~= "function" or button:IsEnabled()
        button.rikFill:SetVertexColor(unpack(enabled and { 0.12, 0.23, 0.29, 1 } or { 0.055, 0.065, 0.08, 1 }))
    end
end

local function fields(frame)
    if not auction.Allowed(frame.InputBox) and not auction.Allowed(frame.MoneyInputFrame)
        and not auction.Allowed(frame.MoneyDisplayFrame) and not auction.Allowed(frame.Dropdown) then return end
    -- Native aligned form children retain their tab order, bounds and value validation.
    local state = auction.State(frame)
    if not state.fieldRule then
        state.fieldRule = frame:CreateTexture(nil, "BACKGROUND")
        state.fieldRule:SetTexture(skin.FLAT)
        state.fieldRule:SetVertexColor(0.22, 0.27, 0.33, 0.6)
        state.fieldRule:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, -5)
        state.fieldRule:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, -5)
        state.fieldRule:SetHeight(1)
    end
    if skin.IsRegion(frame.Label) then frame.Label:SetTextColor(0.7, 0.77, 0.86) end
end

local function dialogs(frame)
    local root = AuctionHouseFrame
    if not root then return end
    if frame == root.BuyDialog then
        auction.Card(frame)
        skin.Strip(frame, { "Border" })
        local state = auction.State(frame)
        if not state.dialogTop then
            state.dialogTop = skin.Fill(frame, { 0.3, 0.75, 1, 1 })
            state.dialogTop:ClearAllPoints()
            state.dialogTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
            state.dialogTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
            state.dialogTop:SetHeight(2)
        end
    elseif frame == root.DialogOverlay then
        local state = auction.State(frame)
        if not state.dim then state.dim = skin.Fill(frame, { 0.01, 0.015, 0.025, 0.78 }) end
    end
end

function auction.Style(frame)
    if not auction.Allowed(frame) or InCombatLockdown() then return end
    auction.Variants(frame)
    row(frame); scroll(frame); list(frame); itemDisplay(frame); itemCell(frame); fields(frame); dialogs(frame)
    for _, key in ipairs(TEXT_KEYS) do font(frame[key]) end
    for _, region in ipairs({ frame:GetRegions() }) do font(region) end
    for _, key in ipairs(ACTIONS) do action(frame[key]) end
    -- Interiors already decorates shown children and pooled rows locally.
    -- Queuing the root here feeds native row recycling back into a full relayout.
end
