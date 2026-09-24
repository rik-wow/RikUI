-- Item grid of the one-bag view. Buttons come from Blizzard's ContainerFrameItemButtonTemplate, whose
-- click, drag, tooltip and sell handlers read the slot from the button's ID and the bag from the
-- parent's ID (GetBagID falls back to GetParent():GetID()). Each bag therefore gets a plain parent
-- frame carrying its ID, and RikUI never calls the mixin's Initialize, SetBagID or UpdateCooldown:
-- those write Lua fields (bagID, hasItem) the secure handlers read later. RikUI draws on its own
-- rik* regions and on the template's Cooldown frame only.
local core, media, ui = RikUI, RikUI.Media, RikUI.UI
local bags = core.Bags

local BAG_IDS = { 0, 1, 2, 3, 4 }
local MAX_BAG_SLOTS = 200 -- defensive allocation limit, not a client capacity claim
local BUTTON_TYPE, TEMPLATE, NAME_FORMAT = "ItemButton", "ContainerFrameItemButtonTemplate", "RikUIBag%dSlot%d"
local SLOT, GAP, DEFAULT_COLUMNS, EDGE, COUNT_INSET = 36, 2, 10, 1, 2
local MIN_COLUMNS, MAX_COLUMNS, columns = 10, 16, DEFAULT_COLUMNS
local ICON_MIN, ICON_MAX = 0.07, 0.93
local EMPTY, BORDER = { 0.055, 0.065, 0.08, 0.95 }, { 0.25, 0.28, 0.32 }
local MIN_BORDER_QUALITY = 2 -- uncommon
local DIM_ALPHA, FULL_ALPHA, DIM_OVERLAY = 0.25, 1, { 0, 0, 0, 0.6 }
local NAME_PATTERN = "%[(.-)%]"
local COPPER_PER_SILVER, COPPER_PER_GOLD = 100, 10000
local GOLD, SILVER, COPPER = "%d|cffffd700g|r", "%d|cffc7c7cfs|r", "%d|cffeda55fc|r"
local bagFrames, search, filter = {}, "", "all"
local nativeSearchAccepted = false
local ITEM_CONSUMABLE, ITEM_WEAPON, ITEM_ARMOR, ITEM_QUEST = 0, 2, 4, 12
local ITEM_REAGENT, ITEM_TRADE_GOODS = 5, 7

local function plain(value, kind)
    return not core.Secret.IsSecret(value) and type(value) == kind
end

function bags.Columns()
    local value = core.Profile and core.Profile.bags.columns
    if not plain(value, "number") or value ~= value or value == math.huge or value == -math.huge then
        return DEFAULT_COLUMNS
    end
    return math.max(MIN_COLUMNS, math.min(MAX_COLUMNS, math.floor(value)))
end

function bags.ApplyColumns()
    core.Combat.Queue(function()
        columns = bags.Columns()
        if not bags.Holder then return end
        if bags.Holder:IsShown() then bags.Refresh() else bags.Resize() end
    end, "bags:columns")
end

function bags.SetColumns(value)
    if not plain(value, "number") or value ~= value or value == math.huge or value == -math.huge then return end
    core.Profile.bags.columns = math.max(MIN_COLUMNS, math.min(MAX_COLUMNS, math.floor(value)))
    bags.ApplyColumns()
end

function bags.GridSize(total)
    local rows = math.max(1, math.ceil(total / columns))
    return columns * SLOT + (columns - 1) * GAP, rows * SLOT + (rows - 1) * GAP
end

local function bagFrame(bag)
    local frame = bagFrames[bag]
    if frame then return frame end
    frame = CreateFrame("Frame", nil, bags.Holder)
    frame:SetID(bag)
    frame:SetAllPoints(bags.Holder)
    frame.buttons = {}
    bagFrames[bag] = frame
    return frame
end

local function clearChrome(button)
    -- These templates start with decorative glow textures even before native item initialization.
    -- Blank them as well as alpha: Blizzard's animation groups may restore alpha on show.
    core.Skin.Blank(button, { "NormalTexture", "PushedTexture", "IconBorder", "NewItemTexture",
        "flash", "AugmentBorderAnimTexture", "BattlepayItemTexture", "ExtendedSlot" })
    core.Skin.Strip(button, { "icon", "Count", "Stock" })
end

local function decorate(button)
    clearChrome(button)
    button:ClearNormalTexture()
    button:SetSize(SLOT, SLOT)
    button.rikBackground = button:CreateTexture(nil, "BACKGROUND")
    button.rikBackground:SetAllPoints()
    button.rikBackground:SetColorTexture(unpack(EMPTY))
    button.rikIcon = button:CreateTexture(nil, "ARTWORK")
    button.rikIcon:SetPoint("TOPLEFT", button, "TOPLEFT", EDGE, -EDGE)
    button.rikIcon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -EDGE, EDGE)
    button.rikIcon:SetTexCoord(ICON_MIN, ICON_MAX, ICON_MIN, ICON_MAX)
    button.rikBorder = ui.Edges(button, EDGE, "OVERLAY")
    button.rikCount = button:CreateFontString(nil, "OVERLAY")
    media.Font(button.rikCount, "count")
    button.rikCount:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -COUNT_INSET, COUNT_INSET)
    button.rikDim = button:CreateTexture(nil, "OVERLAY", nil, 7)
    button.rikDim:SetAllPoints()
    button.rikDim:SetColorTexture(unpack(DIM_OVERLAY))
    button.rikDim:SetShown(false)
    bags.CreateNewItem(button)
    button:SetHighlightTexture(media.highlight, "ADD")
end

local function createButton(frame, slot)
    local ok, button = pcall(CreateFrame, BUTTON_TYPE, NAME_FORMAT:format(frame:GetID(), slot), frame, TEMPLATE)
    if not ok then
        bags.Warn("buttons", button)
        return nil
    end
    button:SetID(slot)
    decorate(button)
    frame.buttons[slot] = button
    return button
end

local function place(button, index)
    local column, row = index % columns, math.floor(index / columns)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", bags.Holder.grid, "TOPLEFT", column * (SLOT + GAP), -row * (SLOT + GAP))
end

local function readInfo(bag, slot)
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if not ok then
        bags.Warn("items", info)
        return nil
    end
    return plain(info, "table") and info or nil
end

local function borderColor(quality)
    if not plain(quality, "number") or quality < MIN_BORDER_QUALITY then return BORDER[1], BORDER[2], BORDER[3] end
    local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
    if not ok or not plain(r, "number") or not plain(g, "number") or not plain(b, "number") then
        return BORDER[1], BORDER[2], BORDER[3]
    end
    return r, g, b
end

local function itemName(info)
    local link = info and info.hyperlink
    if not plain(link, "string") then return nil end
    local name = link:match(NAME_PATTERN)
    return name and name:lower() or nil
end

local function updateCooldown(button, bag, slot)
    local widget = button.Cooldown
    if type(widget) ~= "table" and type(widget) ~= "userdata" then return end
    if not button.rikFilled then widget:Clear(); return end
    local ok, start, duration, enable = pcall(C_Container.GetContainerItemCooldown, bag, slot)
    if not ok or not plain(start, "number") or not plain(duration, "number")
        or not plain(enable, "number") or enable ~= 1
        or start ~= start or start < 0 or start == math.huge
        or duration ~= duration or duration <= 0 or duration == math.huge then
        widget:Clear()
        return
    end
    widget:SetCooldown(start, duration)
end

-- Blizzard's own bag search marks each item record isFiltered; clients without it match on the name.
local function nativeSearch()
    return type(C_Container.SetItemSearch) == "function"
end

local function categoryMatches(button)
    if filter == "all" then return true end
    if not button.rikFilled then return false end
    if filter == "new" then return button.rikFresh == true end
    if filter == "junk" then return button.rikQuality == 0 end
    if filter == "quest" then return button.rikQuest or button.rikClass == ITEM_QUEST end
    if filter == "gear" then return button.rikClass == ITEM_WEAPON or button.rikClass == ITEM_ARMOR end
    if filter == "materials" then return button.rikClass == ITEM_REAGENT or button.rikClass == ITEM_TRADE_GOODS end
    return button.rikClass == ITEM_CONSUMABLE
end

local function classify(button, info, bag, slot)
    local quality = info and info.quality
    button.rikQuality = plain(quality, "number") and quality or nil
    button.rikClass, button.rikQuest = nil, false
    local link = info and info.hyperlink
    if plain(link, "string") and C_Item and type(C_Item.GetItemInfoInstant) == "function" then
        local ok, _, _, _, _, _, class = pcall(C_Item.GetItemInfoInstant, link)
        if ok and plain(class, "number") then button.rikClass = class end
    end
    if info and type(C_Container.GetContainerItemQuestInfo) == "function" then
        local ok, quest = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
        if ok and plain(quest, "table") then
            button.rikQuest = plain(quest.isQuestItem, "boolean") and quest.isQuestItem
        end
    end
end

local function matches(button)
    if not categoryMatches(button) then return false end
    if search == "" then return true end
    if not button.rikFilled then return false end
    if nativeSearchAccepted and button.rikFiltered ~= nil then return not button.rikFiltered end
    local name = button.rikName
    return name ~= nil and name:find(search, 1, true) ~= nil
end

local function dim(button)
    button.rikDimmed = not matches(button)
    button.rikDim:SetShown(button.rikDimmed)
    button:SetAlpha(button.rikDimmed and DIM_ALPHA or FULL_ALPHA)
end

local function itemFeedback(button, info)
    local identity = info and info.hyperlink
    local count = info and info.stackCount
    if not plain(identity, "string") or not plain(count, "number") then
        button.rikItemIdentity, button.rikItemCount = nil, nil
        return
    end
    if button.rikObserved and (button.rikItemIdentity ~= identity or button.rikItemCount ~= count) then
        core.Motion.Flash(button)
    end
    button.rikItemIdentity, button.rikItemCount = identity, count
end

function bags.UpdateButton(button)
    clearChrome(button)
    local bag, slot = button:GetParent():GetID(), button:GetID()
    local info = readInfo(bag, slot)
    itemFeedback(button, info)
    button.rikObserved = true
    local icon, count = info and info.iconFileID, info and info.stackCount
    if core.Secret.IsSecret(icon) then icon = nil end
    button.rikIcon:SetTexture(icon)
    button.rikIcon:SetDesaturated(info ~= nil and plain(info.isLocked, "boolean") and info.isLocked)
    button.rikCount:SetText(plain(count, "number") and count > 1 and tostring(count) or "")
    local r, g, b = borderColor(info and info.quality)
    for _, line in ipairs(button.rikBorder) do line:SetVertexColor(r, g, b, 1) end
    local itemID = info and info.itemID
    button.rikItemID = plain(itemID, "number") and itemID or nil
    button.rikName, button.rikFilled = itemName(info), info ~= nil
    button.rikFiltered = nil
    if info and plain(info.isFiltered, "boolean") then button.rikFiltered = info.isFiltered end
    bags.UpdateNewItem(button)
    classify(button, info, bag, slot)
    updateCooldown(button, bag, slot)
    dim(button)
end

local function slotCount(bag)
    local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
    if not ok or not plain(slots, "number") or slots ~= slots or slots < 0
        or slots > MAX_BAG_SLOTS or slots % 1 ~= 0 then return nil end
    return slots
end

-- Returns the next grid index and how many of this bag's slots hold an item; nil when no button
-- could be created.
local function refreshBag(frame, index, slots)
    local used = 0
    for slot = 1, slots do
        local button = frame.buttons[slot] or createButton(frame, slot)
        if not button then return nil end
        place(button, index)
        bags.UpdateButton(button)
        button:Show()
        index, used = index + 1, used + (button.rikFilled and 1 or 0)
    end
    for slot = slots + 1, #frame.buttons do frame.buttons[slot]:Hide() end
    return index, used
end

function bags.Refresh()
    local sizes = {}
    for _, bag in ipairs(BAG_IDS) do
        sizes[bag] = slotCount(bag)
        if sizes[bag] == nil then bags.Warn("sizes", "Inventory size unavailable; keeping the last layout."); return end
    end
    local index, used = 0, 0
    for _, bag in ipairs(BAG_IDS) do
        local nextIndex, filled = refreshBag(bagFrame(bag), index, sizes[bag])
        if not nextIndex then return end
        index, used = nextIndex, used + filled
    end
    bags.RefreshEquipped()
    bags.UpdateCapacity()
    bags.RefreshMerchant()
    bags.Total, bags.Used = index, used
    bags.Resize()
end

local function eachButton(visit)
    for _, frame in pairs(bagFrames) do
        for _, button in ipairs(frame.buttons) do visit(button) end
    end
end

function bags.RefreshLock(_, bag, slot)
    if not bags.Holder or not bags.Holder:IsShown() then return end
    if not plain(bag, "number") or bag ~= bag or bag < 0 or bag > 4 or bag % 1 ~= 0
        or not plain(slot, "number") or slot ~= slot or slot < 1 or slot > MAX_BAG_SLOTS or slot % 1 ~= 0 then return end
    local frame = bagFrames[bag]
    local button = frame and frame.buttons[slot]
    if not button or not button:IsShown() then return end
    local info = readInfo(bag, slot)
    button.rikIcon:SetDesaturated(info ~= nil and plain(info.isLocked, "boolean") and info.isLocked)
end

function bags.RefreshItemData(_, itemID, success)
    if not bags.Holder or not bags.Holder:IsShown() then return end
    if not plain(success, "boolean") or not success or not plain(itemID, "number")
        or itemID ~= itemID or itemID <= 0 or itemID == math.huge or itemID % 1 ~= 0 then return end
    local changed = false
    eachButton(function(button)
        if button:IsShown() and button.rikItemID == itemID then
            local filled = button.rikFilled
            bags.UpdateButton(button)
            bags.Used = bags.Used + (button.rikFilled and 1 or 0) - (filled and 1 or 0)
            changed = true
        end
    end)
    if changed then bags.UpdateTitle() end
end

function bags.RefreshCooldowns()
    if not bags.Holder or not bags.Holder:IsShown() then return end
    eachButton(function(button)
        if button:IsShown() then updateCooldown(button, button:GetParent():GetID(), button:GetID()) end
    end)
end

-- The client answers SetItemSearch with INVENTORY_SEARCH_UPDATE, which redraws the open grid.
function bags.SetSearch(text)
    if not plain(text, "string") then text = "" end
    search = text:lower():match("^%s*(.-)%s*$")
    nativeSearchAccepted = nativeSearch()
    if nativeSearchAccepted then
        local ok, result = pcall(C_Container.SetItemSearch, search)
        nativeSearchAccepted = ok and not core.Secret.IsSecret(result) and result ~= false
        if not nativeSearchAccepted then bags.Warn("search", ok and "Search unavailable" or result) end
    end
    eachButton(dim)
    bags.UpdateTitle()
end

function bags.SetFilter(value)
    if value ~= "all" and value ~= "junk" and value ~= "quest" and value ~= "gear" and value ~= "use"
        and value ~= "materials" and value ~= "new" then return end
    filter = value
    for key, button in pairs(bags.Holder.filters) do
        button.label:SetTextColor(key == filter and 1 or 0.65, key == filter and 0.82 or 0.65, key == filter and 0 or 0.65)
    end
    eachButton(dim)
    bags.UpdateTitle()
end

function bags.SearchState()
    local dimmed = 0
    eachButton(function(button)
        if button.rikDimmed and button:IsShown() then dimmed = dimmed + 1 end
    end)
    return search, dimmed, filter
end

function bags.MoneyText(amount)
    local gold, silver = math.floor(amount / COPPER_PER_GOLD), math.floor(amount % COPPER_PER_GOLD / COPPER_PER_SILVER)
    local parts = {}
    if gold > 0 then parts[#parts + 1] = GOLD:format(gold) end
    if gold > 0 or silver > 0 then parts[#parts + 1] = SILVER:format(silver) end
    parts[#parts + 1] = COPPER:format(amount % COPPER_PER_SILVER)
    return table.concat(parts, " ")
end

local lastMoney, income, spent, moneyGap = nil, 0, 0, false

function bags.MoneySession()
    return { income = income, spent = spent, net = income - spent, partial = moneyGap }
end

function bags.UpdateMoney()
    if not bags.Holder then return end
    local ok, amount = pcall(GetMoney)
    if not ok or not plain(amount, "number") or amount ~= amount or amount < 0
        or amount == math.huge or amount % 1 ~= 0 then
        if not ok then bags.Warn("money", amount) end
        lastMoney, moneyGap = nil, true
        bags.Holder.money:SetText("")
        return
    end
    if lastMoney then
        local delta = amount - lastMoney
        if delta > 0 then income = income + delta else spent = spent - delta end
    end
    lastMoney = amount
    bags.Holder.money:SetText(bags.MoneyText(amount))
end

function bags.ResetMoneySession()
    lastMoney, income, spent, moneyGap = nil, 0, 0, false
    bags.UpdateMoney()
end

function bags.ShowMoneySession(button)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText("Session money")
    GameTooltip:AddLine("Income: " .. bags.MoneyText(income))
    GameTooltip:AddLine("Spent: " .. bags.MoneyText(spent))
    local net = income - spent
    GameTooltip:AddLine("Net: " .. (net < 0 and "-" or "+") .. bags.MoneyText(math.abs(net)))
    if moneyGap then GameTooltip:AddLine("Partial: some balance updates were unavailable.") end
    GameTooltip:AddLine("Click the money line to reset. Includes all observed balance changes.")
    GameTooltip:Show()
end
