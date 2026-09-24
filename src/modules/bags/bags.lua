-- One-bag view: a RikUI holder with a search box, a sort button, the item grid and a money line.
-- Blizzard's bag functions stay in charge of open and closed: they are post-hooked, never replaced,
-- so the bag bindings, merchants and the mailbox run untainted, and the holder mirrors whether any
-- stock container frame is shown. The stock frames park through the shared hide helper, where they
-- keep their shown flag but never draw. src/modules/bags/bags-items.lua owns the item buttons.
local core, media, layout, ui = RikUI, RikUI.Media, RikUI.Layout, RikUI.UI
local bags = { Parked = {}, Total = 0, Used = 0 }
core.Bags = bags

local HOLDER_NAME, SEARCH_NAME, KEY = "RikUIBags", "RikUIBagsSearch", "bags"
-- Bottom right, above the tooltip anchor.
local DEFAULTS = { point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT", x = -126, y = 350 }
local PAD, HEADER, FOOTER, EDGE = 8, 68, 64, 1
local CONTROL_HEIGHT, SEARCH_WIDTH, SORT_WIDTH, CLOSE_WIDTH, CONTROL_GAP = 18, 120, 40, 18, 4
local BACKGROUND, FIELD, BORDER = { 0.055, 0.065, 0.08, 0.95 }, { 0.1, 0.11, 0.13, 1 }, { 0.25, 0.28, 0.32, 1 }
local TITLE_FORMAT, SEARCH_HINT, SORT_LABEL, CLOSE_ICON = "Bags %d/%d", "Search", "Sort", "close"
local MATCH_ONE, MATCH_MANY = "  1 match", "  %d matches"
-- Blizzard's bag search box: its own handlers feed C_Container.SetItemSearch. SearchBoxTemplate art keys.
local SEARCH_TEMPLATE, SEARCH_ART = "BagSearchBoxTemplate", { "Left", "Middle", "Right" }
local STOCK_PREFIX, STOCK_COMBINED, MAX_STOCK = "ContainerFrame", "ContainerFrameCombinedBags", 16
local TOGGLES = { "OpenAllBags", "CloseAllBags", "ToggleAllBags", "OpenBackpack", "CloseBackpack", "ToggleBackpack",
    "OpenBag", "CloseBag", "ToggleBag" }
local REFRESH_EVENTS = { "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "ITEM_LOCK_CHANGED", "INVENTORY_SEARCH_UPDATE" }
local holder, warnings = nil, {}

function bags.Warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Bags " .. operation .. ": " .. tostring(reason))
end

local function isFrame(value)
    local kind = type(value)
    return (kind == "table" or kind == "userdata") and type(value.SetParent) == "function"
end

local function anyStockOpen()
    for _, frame in ipairs(bags.Parked) do
        if frame:IsShown() then return true end
    end
    return false
end

-- Runs after every Blizzard bag function; the stock frames' shown flags are the state.
function bags.Sync()
    if not holder then return end
    local open = anyStockOpen()
    if open == (holder:IsShown() == true) then return end
    if open then holder:Show() else holder:Hide() end
end

local function flat(frame, fill)
    frame.rikBackground = frame:CreateTexture(nil, "BACKGROUND")
    frame.rikBackground:SetAllPoints()
    frame.rikBackground:SetColorTexture(unpack(fill))
    frame.rikBorder = ui.Edges(frame, EDGE, "BORDER")
    for _, line in ipairs(frame.rikBorder) do line:SetVertexColor(unpack(BORDER)) end
end

local function textButton(text, width, onClick)
    local button = CreateFrame("Button", nil, holder)
    button:SetSize(width, CONTROL_HEIGHT)
    flat(button, FIELD)
    button.label = button:CreateFontString(nil, "OVERLAY")
    media.Font(button.label, "small")
    button.label:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.label:SetText(text)
    button:SetHighlightTexture(media.highlight, "ADD")
    button:SetScript("OnClick", onClick)
    return button
end

function bags.Sort()
    if type(C_Container) ~= "table" or type(C_Container.SortBags) ~= "function" then
        bags.Warn("sort", "C_Container.SortBags unavailable on this client")
        return
    end
    local ok, reason = pcall(C_Container.SortBags)
    if not ok then bags.Warn("sort", reason) end
end

local function searchChanged(box)
    local text = box:GetText()
    if box.hint then box.hint:SetShown(text == nil or text == "") end
    bags.SetSearch(text)
end

-- Only the fallback box needs these: the template brings its own prompt, clear button and keys.
local function plainSearchBox()
    local box = CreateFrame("EditBox", SEARCH_NAME, holder)
    box:SetAutoFocus(false)
    box:SetTextInsets(CONTROL_GAP, CONTROL_GAP, 0, 0)
    box.hint = box:CreateFontString(nil, "OVERLAY")
    media.Font(box.hint, "small")
    box.hint:SetPoint("LEFT", box, "LEFT", CONTROL_GAP, 0)
    box.hint:SetText(SEARCH_HINT)
    box.hint:SetTextColor(0.6, 0.6, 0.6, 1)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    box:SetScript("OnEscapePressed", function(self) self:SetText(""); searchChanged(self); self:ClearFocus() end)
    return box
end

local function createSearch()
    local ok, box = pcall(CreateFrame, "EditBox", SEARCH_NAME, holder, SEARCH_TEMPLATE)
    if not ok then box = plainSearchBox() end
    for _, key in ipairs(SEARCH_ART) do
        local art = box[key]
        if type(art) == "table" and type(art.SetAlpha) == "function" then art:SetAlpha(0) end
    end
    box:SetSize(SEARCH_WIDTH, CONTROL_HEIGHT)
    box:SetFont(media.font, media.sizes.small, "")
    flat(box, FIELD)
    box:HookScript("OnTextChanged", searchChanged)
    return box
end

local function createFilters()
    holder.filters = {}
    local offset = PAD
    for _, entry in ipairs({ { "all", "All" }, { "junk", "Junk" }, { "quest", "Quest" },
        { "gear", "Gear" }, { "use", "Use" }, { "materials", "Materials", 64 } }) do
        local key = entry[1]
        local width = entry[3] or 44
        local button = textButton(entry[2], width, function() bags.SetFilter(key) end)
        button:SetPoint("TOPLEFT", holder, "TOPLEFT", offset, -52)
        offset = offset + width + CONTROL_GAP
        holder.filters[key] = button
    end
    bags.SetFilter("all")
end

local function createControls()
    holder.title = holder:CreateFontString(nil, "OVERLAY")
    media.Font(holder.title, "label")
    holder.title:SetPoint("TOPLEFT", holder, "TOPLEFT", PAD, -PAD)
    holder.close = textButton("", CLOSE_WIDTH, function() holder:Hide() end)
    holder.close.icon = media.Icon(holder.close, CLOSE_ICON, 10, "OVERLAY")
    holder.close.icon:SetPoint("CENTER", holder.close, "CENTER", 0, 0)
    holder.close:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -PAD, -PAD)
    holder.sort = textButton(SORT_LABEL, SORT_WIDTH, bags.Sort)
    holder.sort:SetPoint("TOPLEFT", holder, "TOPLEFT", PAD + SEARCH_WIDTH + CONTROL_GAP, -30)
    holder.search = createSearch()
    holder.search:SetPoint("TOPLEFT", holder, "TOPLEFT", PAD, -30)
    createFilters()
    holder.junk = textButton("Sell junk", 114, bags.SellJunk)
    holder.junk:SetPoint("LEFT", holder.sort, "RIGHT", CONTROL_GAP, 0)
    holder.junk:Hide()
    holder.capacity = holder:CreateFontString(nil, "OVERLAY")
    media.Font(holder.capacity, "small")
    holder.capacity:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", PAD, PAD)
    holder.capacity:SetWidth(210)
    holder.capacity:SetJustifyH("LEFT")
    holder.money = holder:CreateFontString(nil, "OVERLAY")
    media.Font(holder.money, "small")
    holder.money:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -PAD, PAD)
    holder.grid = CreateFrame("Frame", nil, holder)
    holder.grid:SetPoint("TOPLEFT", holder, "TOPLEFT", PAD, -(PAD + HEADER))
end

function bags.Resize()
    local width, height = bags.GridSize(bags.Total)
    holder.grid:SetSize(width, height)
    holder:SetSize(width + 2 * PAD, height + 2 * PAD + HEADER + FOOTER)
    bags.UpdateTitle()
end

-- While a search is active the title counts the matching slots, so a search that reaches
-- nothing is visible at a glance.
function bags.UpdateTitle()
    if not holder then return end
    local text = TITLE_FORMAT:format(bags.Used, bags.Total)
    local search, dimmed, filter = bags.SearchState()
    if search ~= "" or filter ~= "all" then
        local found = bags.Total - dimmed
        text = text .. (found == 1 and MATCH_ONE or MATCH_MANY:format(found))
    end
    holder.title:SetText(text)
end

local function onShow()
    bags.Refresh()
    bags.UpdateMoney()
end

-- The frame drags by its header, edges and footer at any time; the drop goes into the profile
-- like a /rik move drop, so it survives reloads and follows the profile.
local function dragStop()
    if not holder.rikDragging then return end
    holder.rikDragging = false
    if holder.rikEngine then
        holder.rikEngine = false
        layout.EndDrag()
        return
    end
    holder:StopMovingOrSizing()
    if not layout.SaveCenter(KEY, holder, core.Profile) then
        core:Print("Bags position unavailable; the frame keeps its last saved place.")
    end
    layout.Apply()
    if layout.Settle then layout.Settle(KEY) end
end

local function enableDrag()
    holder:SetMovable(true)
    holder:RegisterForDrag("LeftButton")
    -- The arrangement engine drags it, with snapping and without overlap. In combat, or on a client
    -- that reports no screen size, the client drags it and the drop is settled afterwards.
    holder:SetScript("OnDragStart", function()
        holder.rikDragging = true
        holder.rikEngine = layout.BeginDrag ~= nil and layout.BeginDrag(KEY) == true
        if not holder.rikEngine then holder:StartMoving() end
    end)
    holder:SetScript("OnDragStop", dragStop)
end

-- Escape and the close button hide the holder directly; Blizzard's frames have to follow.
local function onHide()
    dragStop()
    bags.SetFilter("all")
    holder.search:SetText("")
    searchChanged(holder.search)
    if anyStockOpen() and type(CloseAllBags) == "function" then CloseAllBags() end
end

local function createHolder()
    holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    bags.Holder = holder
    holder:SetFrameStrata("MEDIUM")
    holder:SetClampedToScreen(true)
    holder:EnableMouse(true)
    flat(holder, BACKGROUND)
    createControls()
    bags.CreateEquipped(holder)
    enableDrag()
    holder:Hide()
    holder:SetScript("OnShow", onShow)
    holder:SetScript("OnHide", onHide)
    core.Motion.BindEntrance(holder, true)
    bags.Resize()
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, HOLDER_NAME) end
    -- A window you open over the screen and close again, like a tooltip: it neither blocks other frames
    -- nor is moved out of their way.
    layout.Register(holder, KEY, DEFAULTS, { label = "Bags", floating = true })
end

-- Fullscreen panels reparent each stock frame on their own, so every frame is parked by itself and
-- the hide helper re-parks it. Their events stay: Blizzard's bag bookkeeping keeps running.
local function park()
    local frames = {}
    for index = 1, MAX_STOCK do frames[#frames + 1] = _G[STOCK_PREFIX .. index] end
    frames[#frames + 1] = _G[STOCK_COMBINED]
    for _, frame in ipairs(frames) do
        if isFrame(frame) and core.Hide.Frame(frame) then bags.Parked[#bags.Parked + 1] = frame end
    end
end

local function refreshIfOpen()
    if holder:IsShown() then bags.Refresh() end
end

function bags:OnEnable()
    if type(C_Container) ~= "table" or not isFrame(_G[STOCK_PREFIX .. 1]) then
        bags.Warn("frames", "container frames unavailable on this client")
        return
    end
    createHolder()
    park()
    for _, name in ipairs(TOGGLES) do
        if type(_G[name]) == "function" then core.Hooks.Function(name, bags.Sync) end
    end
    for _, event in ipairs(REFRESH_EVENTS) do core:RegisterEvent(event, refreshIfOpen) end
    core:RegisterEvent("PLAYER_MONEY", bags.UpdateMoney)
    bags.EnableMerchant()
end

function bags:Debug(sample)
    local search, dimmed = bags.SearchState()
    core:Print("Bags holder=" .. tostring(holder ~= nil) .. " parked=" .. #bags.Parked .. " slots=" .. bags.Total
        .. " open=" .. tostring(holder ~= nil and holder:IsShown() == true) .. " search=\"" .. search
        .. "\" dimmed=" .. dimmed)
    sample("GetContainerNumSlots(0)", function() return C_Container.GetContainerNumSlots(0) end)
end

core:RegisterModule("bags", bags)
