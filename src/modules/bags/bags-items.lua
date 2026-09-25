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
local nativeSearchAccepted, searchTerms = false, nil
local ITEM_CONSUMABLE, ITEM_WEAPON, ITEM_ARMOR, ITEM_QUEST = 0, 2, 4, 12
local ITEM_REAGENT, ITEM_TRADE_GOODS = 5, 7

local function plain(value, kind)
    return not core.Secret.IsSecret(value) and type(value) == kind
end

local favoriteSource, favoriteIDs = nil, {}
local MAX_FAVORITES, MAX_ITEM_ID = 50, 1000000000

local function validID(id)
    return plain(id, "number") and id > 0 and id <= MAX_ITEM_ID and id % 1 == 0
end

local function favorites()
    local source = core.Profile and core.Profile.bags.favorites or ""
    if not plain(source, "string") or #source > 550 then source = "" end
    if source == favoriteSource then return favoriteIDs end
    favoriteSource, favoriteIDs = source, {}
    local count = 0
    for token in source:gmatch("[^,]+") do
        local id = tonumber(token)
        if validID(id) and count < MAX_FAVORITES and not favoriteIDs[id] then
            favoriteIDs[id], count = true, count + 1
        end
    end
    return favoriteIDs
end

function bags.IsFavorite(id)
    return validID(id) and favorites()[id] == true
end

function bags.ToggleFavorite(input)
    if not core.Profile or not plain(input, "string") or #input > 1024 then return nil, "Use an item ID or item link." end
    local id = tonumber(input:match("^%s*(%d+)%s*$") or input:match("|Hitem:(%d+):"))
    if not validID(id) then return nil, "Use a valid item ID or item link." end
    local saved, list = favorites(), {}
    local adding = not saved[id]
    for itemID in pairs(saved) do if itemID ~= id then list[#list + 1] = itemID end end
    if adding and #list >= MAX_FAVORITES then return nil, "Keep at most 50 favorite items." end
    if adding then list[#list + 1] = id end
    table.sort(list)
    for index, itemID in ipairs(list) do list[index] = tostring(itemID) end
    core.Profile.bags.favorites = table.concat(list, ",")
    core:Changed()
    if bags.Holder and bags.Holder:IsShown() then bags.Refresh() end
    return true, (adding and "Added favorite item " or "Removed favorite item ") .. id .. "."
end

core:RegisterCommand("favorite", function(input)
    if input == "" then
        core:Print("Use /rik favorite <item link or ID> to toggle. Protect favorites in Bags settings guards RikUI bulk junk sales; individual sales remain available.")
        return
    end
    local _, message = bags.ToggleFavorite(input)
    core:Print(message)
end, "Toggle a bag favorite: /rik favorite <item link or ID>", bags)

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
    button.rikLevel = button:CreateFontString(nil, "OVERLAY")
    media.Font(button.rikLevel, "small")
    button.rikLevel:SetPoint("TOPRIGHT", button, "TOPRIGHT", -COUNT_INSET, -COUNT_INSET)
    button.rikLevel:SetTextColor(1, 1, 1)
    button.rikFavorite = button:CreateFontString(nil, "OVERLAY")
    media.Font(button.rikFavorite, "small")
    button.rikFavorite:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", COUNT_INSET, COUNT_INSET)
    button.rikFavorite:SetTextColor(1, 0.82, 0)
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

local function categoryMatches(button, category)
    local filter = category or filter
    if filter == "all" then return true end
    if not button.rikFilled then return false end
    if filter == "favorites" then return bags.IsFavorite(button.rikItemID) end
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

local QUALITIES = { poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5 }
local CATEGORIES = { all = true, junk = true, quest = true, gear = true, use = true, materials = true, new = true, favorites = true }
local MAX_SEARCH, MAX_TERMS = 256, 16

local function parseSearch(text)
    if not text:find(":", 1, true) and not text:find("!", 1, true) then return nil end
    local terms = {}
    for token in text:gmatch("%S+") do
        if #terms >= MAX_TERMS then return { { kind = "invalid" } } end
        local negate = token:sub(1, 1) == "!"
        if negate then token = token:sub(2) end
        local kind, value = token:match("^(%a+):(.*)$")
        terms[#terms + 1] = { kind = kind or "name", value = value or token, negate = negate }
    end
    return terms
end

local function numericTerm(button, term)
    local operator, expected = term.value:match("^([<>=]*)(%d+)$")
    local compare = {
        [""] = function(a, b) return a == b end, ["="] = function(a, b) return a == b end,
        [">"] = function(a, b) return a > b end, [">="] = function(a, b) return a >= b end,
        ["<"] = function(a, b) return a < b end, ["<="] = function(a, b) return a <= b end,
    }
    expected = tonumber(expected)
    if not compare[operator] or not expected or expected > 1000000000 then return nil end
    local actual = button.rikStackCount
    if term.kind == "level" then
        actual = nil
        if button.rikLink and C_Item and type(C_Item.GetDetailedItemLevelInfo) == "function" then
            local ok, level = pcall(C_Item.GetDetailedItemLevelInfo, button.rikLink)
            if ok then actual = level end
        end
    end
    if not plain(actual, "number") or actual ~= actual or actual < 0 or actual >= math.huge
        or actual % 1 ~= 0 then return nil end
    return compare[operator](actual, expected)
end

local function termMatch(button, term)
    local value = term.value
    if not value or value == "" then return nil end
    if term.kind == "count" or term.kind == "level" then return numericTerm(button, term) end
    if term.kind == "name" then
        if not button.rikName then return nil end
        return button.rikName:find(value, 1, true) ~= nil
    elseif term.kind == "q" then
        local quality = QUALITIES[value] or tonumber(value)
        if not quality or quality < 0 or quality > 5 or quality % 1 ~= 0 or button.rikQuality == nil then return nil end
        return button.rikQuality == quality
    elseif term.kind == "id" then
        local id = tonumber(value)
        if not id or id <= 0 or id == math.huge or id % 1 ~= 0 or not button.rikItemID then return nil end
        return button.rikItemID == id
    elseif term.kind == "type" then
        if not CATEGORIES[value] then return nil end
        if value ~= "all" and value ~= "new" and value ~= "favorites" and value ~= "junk" and not button.rikClass and not button.rikQuest then return nil end
        if value == "junk" and button.rikQuality == nil then return nil end
        return categoryMatches(button, value)
    end
end

local function structuredMatch(button)
    for _, term in ipairs(searchTerms) do
        local matched = termMatch(button, term)
        if matched == nil or matched == term.negate then return false end
    end
    return true
end

local function matches(button)
    if not categoryMatches(button) then return false end
    if search == "" then return true end
    if not button.rikFilled then return false end
    if searchTerms then return structuredMatch(button) end
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

local function updateLevel(button, info)
    button.rikLevel:SetText("")
    if core.Profile.bags.itemLevels ~= true then return end
    if button.rikClass ~= ITEM_WEAPON and button.rikClass ~= ITEM_ARMOR then return end
    if not info or not plain(info.hyperlink, "string")
        or not C_Item or type(C_Item.GetDetailedItemLevelInfo) ~= "function" then return end
    local ok, level = pcall(C_Item.GetDetailedItemLevelInfo, info.hyperlink)
    if ok and plain(level, "number") and level > 0 and level < math.huge and level % 1 == 0 then
        button.rikLevel:SetText(tostring(level))
    end
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
    button.rikFavorite:SetText(bags.IsFavorite(button.rikItemID) and "F" or "")
    button.rikStackCount = plain(count, "number") and count or nil
    button.rikLink = info and plain(info.hyperlink, "string") and info.hyperlink or nil
    button.rikName, button.rikFilled = itemName(info), info ~= nil
    button.rikFiltered = nil
    if info and plain(info.isFiltered, "boolean") then button.rikFiltered = info.isFiltered end
    bags.UpdateNewItem(button)
    classify(button, info, bag, slot)
    updateLevel(button, info)
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
    search = search:sub(1, MAX_SEARCH)
    searchTerms = parseSearch(search)
    nativeSearchAccepted = nativeSearch()
    if nativeSearchAccepted then
        local ok, result = pcall(C_Container.SetItemSearch, searchTerms and "" or search)
        nativeSearchAccepted = ok and not core.Secret.IsSecret(result) and result ~= false
        if not nativeSearchAccepted then bags.Warn("search", ok and "Search unavailable" or result) end
    end
    eachButton(dim)
    bags.UpdateTitle()
end

function bags.SetFilter(value)
    if value ~= "all" and value ~= "junk" and value ~= "quest" and value ~= "gear" and value ~= "use"
        and value ~= "materials" and value ~= "new" and value ~= "favorites" then return end
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
