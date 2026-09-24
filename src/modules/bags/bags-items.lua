-- Item grid of the one-bag view. Buttons come from Blizzard's ContainerFrameItemButtonTemplate, whose
-- click, drag, tooltip and sell handlers read the slot from the button's ID and the bag from the
-- parent's ID (GetBagID falls back to GetParent():GetID()). Each bag therefore gets a plain parent
-- frame carrying its ID, and RikUI never calls the mixin's Initialize, SetBagID or UpdateCooldown:
-- those write Lua fields (bagID, hasItem) the secure handlers read later. RikUI draws on its own
-- rik* regions and on the template's Cooldown frame only.
local core, media, ui = RikUI, RikUI.Media, RikUI.UI
local bags = core.Bags

local BAG_IDS = { 0, 1, 2, 3, 4 }
local BUTTON_TYPE, TEMPLATE, NAME_FORMAT = "ItemButton", "ContainerFrameItemButtonTemplate", "RikUIBag%dSlot%d"
local SLOT, GAP, COLUMNS, EDGE, COUNT_INSET = 36, 2, 10, 1, 2
local ICON_MIN, ICON_MAX = 0.07, 0.93
local EMPTY, BORDER = { 0.055, 0.065, 0.08, 0.95 }, { 0.25, 0.28, 0.32 }
local MIN_BORDER_QUALITY = 2 -- uncommon
local DIM_ALPHA, FULL_ALPHA, DIM_OVERLAY = 0.25, 1, { 0, 0, 0, 0.6 }
local NAME_PATTERN = "%[(.-)%]"
local COPPER_PER_SILVER, COPPER_PER_GOLD = 100, 10000
local GOLD, SILVER, COPPER = "%d|cffffd700g|r", "%d|cffc7c7cfs|r", "%d|cffeda55fc|r"
local bagFrames, search, filter = {}, "", "all"
local ITEM_CONSUMABLE, ITEM_WEAPON, ITEM_ARMOR, ITEM_QUEST = 0, 2, 4, 12
local ITEM_REAGENT, ITEM_TRADE_GOODS = 5, 7

local function plain(value, kind)
    return not core.Secret.IsSecret(value) and type(value) == kind
end

function bags.GridSize(total)
    local rows = math.max(1, math.ceil(total / COLUMNS))
    return COLUMNS * SLOT + (COLUMNS - 1) * GAP, rows * SLOT + (rows - 1) * GAP
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
    local column, row = index % COLUMNS, math.floor(index / COLUMNS)
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
    local ok, start, duration, enable = pcall(C_Container.GetContainerItemCooldown, bag, slot)
    if not ok or not plain(start, "number") or not plain(duration, "number") then return end
    if duration > 0 and enable ~= 0 then widget:SetCooldown(start, duration) else widget:Clear() end
end

-- Blizzard's own bag search marks each item record isFiltered; clients without it match on the name.
local function nativeSearch()
    return type(C_Container.SetItemSearch) == "function"
end

local function categoryMatches(button)
    if filter == "all" then return true end
    if not button.rikFilled then return false end
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
    if nativeSearch() then return not button.rikFiltered end
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
    button.rikName, button.rikFilled = itemName(info), info ~= nil
    button.rikFiltered = info ~= nil and plain(info.isFiltered, "boolean") and info.isFiltered
    bags.UpdateNewItem(button)
    classify(button, info, bag, slot)
    updateCooldown(button, bag, slot)
    dim(button)
end

local function slotCount(bag)
    local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
    if not ok or not plain(slots, "number") then return 0 end
    return slots
end

-- Returns the next grid index and how many of this bag's slots hold an item; nil when no button
-- could be created.
local function refreshBag(frame, index)
    local slots, used = slotCount(frame:GetID()), 0
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
    local index, used = 0, 0
    for _, bag in ipairs(BAG_IDS) do
        local nextIndex, filled = refreshBag(bagFrame(bag), index)
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

-- The client answers SetItemSearch with INVENTORY_SEARCH_UPDATE, which redraws the open grid.
function bags.SetSearch(text)
    if not plain(text, "string") then text = "" end
    search = text:lower():match("^%s*(.-)%s*$")
    if nativeSearch() then
        local ok, reason = pcall(C_Container.SetItemSearch, search)
        if not ok then bags.Warn("search", reason) end
    end
    eachButton(dim)
    bags.UpdateTitle()
end

function bags.SetFilter(value)
    if value ~= "all" and value ~= "junk" and value ~= "quest" and value ~= "gear" and value ~= "use"
        and value ~= "materials" then return end
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

function bags.UpdateMoney()
    if not bags.Holder then return end
    local ok, amount = pcall(GetMoney)
    if not ok then
        bags.Warn("money", amount)
        return
    end
    bags.Holder.money:SetText(plain(amount, "number") and bags.MoneyText(amount) or "")
end
