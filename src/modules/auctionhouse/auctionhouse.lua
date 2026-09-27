-- Custom presentation of Blizzard's auction controls. Native controllers own all transactions.
local core, skin, interiors = RikUI, RikUI.Skin, RikUI.Interiors
local auction = { WIDTH = 1080, HEIGHT = 660, PAD = 16, SIDEBAR = 200 }
core.AuctionHouse = auction
auction.ACCENT, auction.PANEL = { 0.3, 0.75, 1, 1 }, { 0.075, 0.09, 0.12, 1 }
local pending, refreshing = false, false
local nativeHooks = {}

function auction.IsFrame(frame)
    return interiors.IsFrame(frame)
end

function auction.Allowed(frame)
    if not auction.IsFrame(frame) then return false end
    if type(frame.IsForbidden) == "function" and frame:IsForbidden() then return false end
    if type(frame.IsProtected) == "function" and frame:IsProtected() then return false end
    if core.Panels and core.Panels.enabled == false then return false end
    return not core.Panels or not core.Panels.FrameEnabled or core.Panels.FrameEnabled(frame)
end

function auction.State(frame)
    if not frame.rikAuction then frame.rikAuction = {} end
    return frame.rikAuction
end

function auction.Text(frame, text, role)
    local label = frame:CreateFontString(nil, "OVERLAY")
    core.Media.Font(label, role or "label")
    label:SetText(text)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    return label
end

function auction.Card(frame)
    if not auction.Allowed(frame) then return end
    local state = auction.State(frame)
    if not state.fill then
        state.fill = skin.Fill(frame, auction.PANEL)
        state.edge = skin.Outline(frame)
    end
    skin.Strip(frame, { "Background", "NineSlice" })
end

local function modeHint(frame)
    if frame.AuctionsFrame and frame.AuctionsFrame:IsShown() then return "Manage your auctions and bids." end
    for _, key in ipairs({ "ItemSellFrame", "CommoditiesSellFrame" }) do
        local sell = frame[key]
        if sell and sell:IsShown() then
            if type(sell.GetItem) == "function" and sell:GetItem() then
                return "Set your price and duration, then review the total before posting."
            end
            return "Drag an item from your bags to start a listing."
        end
    end
    return "Search by name or choose a category. Right-click a result for favorites."
end

function auction.Status(frame)
    local state = auction.State(frame)
    if not state.status then return end
    local message = modeHint(frame)
    local browse = frame.BrowseResultsFrame
    local list = browse and browse:IsShown() and browse.ItemList
    if list and list.LoadingSpinner and list.LoadingSpinner:IsShown() then
        message = "Searching the auction house..."
    elseif list and browse.searchStarted and type(list.getNumEntries) == "function" then
        local count = list.getNumEntries()
        if type(count) == "number" then
            message = count == 0 and "No results. Try another name or adjust your filters."
                or string.format("%d results  •  Select an item to compare listings.", count)
        end
    end
    if C_AuctionHouse and type(C_AuctionHouse.IsThrottledMessageSystemReady) == "function"
        and not C_AuctionHouse.IsThrottledMessageSystemReady() then
        message = "Waiting for the auction house..."
    end
    state.status:SetText(message)
end

function auction.Shell(frame)
    local state = auction.State(frame)
    if not state.chrome then
        state.chrome = skin.WindowChrome(frame, 96, 42)
        state.title = auction.Text(frame, AUCTION_HOUSE or "Auction House", "heading")
        state.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -17)
        state.caption = auction.Text(frame, "Browse, trade and manage your listings", "small")
        state.caption:SetPoint("LEFT", state.title, "RIGHT", 18, 0)
        state.caption:SetTextColor(0.6, 0.68, 0.78)
        state.status = auction.Text(frame, "", "small")
        state.status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 16)
        state.status:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -230, 16)
        state.status:SetHeight(16)
        skin.Strip(frame, { "TitleBg", "Bg", "Portrait", "PortraitContainer", "NineSlice" })
        local title = frame.TitleContainer and frame.TitleContainer.TitleText or frame.TitleText
        if skin.IsRegion(title) then title:SetAlpha(0) end
        if skin.IsRegion(frame.rikBackdrop) then frame.rikBackdrop:SetAlpha(0) end
    end
    auction.Status(frame)
end

function auction.Refresh()
    local frame = AuctionHouseFrame
    if refreshing or not auction.Allowed(frame) or not frame:IsShown() or InCombatLockdown() then return end
    refreshing = true
    local ok, reason = pcall(interiors.Walk, frame, "auction")
    refreshing = false
    if not ok then interiors.Warn(frame, reason) end
end

function auction.Queue()
    if pending then return end
    pending = true
    local function refresh() pending = false; auction.Refresh() end
    if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0, refresh) else refresh() end
end

local function decorate(frame)
    if not auction.Allowed(frame) or InCombatLockdown() then return end
    if frame == AuctionHouseFrame then
        auction.HookNative()
        if core.Controls then core.Controls.Walk(frame) end
        auction.Shell(frame)
        auction.Layout(frame)
    end
    auction.Style(frame)
end

interiors.Register("auction", { "AuctionHouseFrame" }, decorate)
interiors.RegisterRefresh("auction", { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
    "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_BROWSE_FAILURE", "ITEM_SEARCH_RESULTS_UPDATED",
    "ITEM_SEARCH_RESULTS_ADDED", "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED",
    "OWNED_AUCTIONS_UPDATED", "BIDS_UPDATED", "AUCTION_HOUSE_FAVORITES_UPDATED",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT",
    "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_PURCHASE_COMPLETED",
    "AUCTION_HOUSE_SHOW_ERROR", "ITEM_KEY_ITEM_INFO_RECEIVED", "PLAYER_REGEN_ENABLED",
    "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "ADDON_LOADED" }, {}, auction.Queue)

-- Global post-hooks and script/callback hooks only; never hook a Blizzard widget method.
function auction.HookNative()
    if not nativeHooks.tabs then
        nativeHooks.tabs = core.Hooks.Function("PanelTemplates_SetTab", function(frame)
            local root = AuctionHouseFrame
            if root and (frame == root or frame == root.AuctionsFrame) then auction.Queue() end
        end)
    end
    if not nativeHooks.categories then
        nativeHooks.categories = core.Hooks.Function("AuctionHouseFilterButton_SetUp", function(button)
            if auction.Allowed(button) and not InCombatLockdown() then auction.Style(button) end
        end)
    end
end
