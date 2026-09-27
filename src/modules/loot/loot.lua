-- Flat loot list in place of Blizzard's LootFrame. It reads the same globals the stock frame reads
-- and loots with LootSlot from a plain click; auto-loot stays the client's. The stock frame is
-- parked with its events dropped because both its hide path and its open path call CloseLoot.
-- src/modules/loot/loot-rolls.lua skins the group roll frames.
local core, media, layout, ui = RikUI, RikUI.Media, RikUI.Layout, RikUI.UI
local loot = { Rows = {}, SkinnedRolls = {}, Options = { title = "Loot", settings = {} } }
core.Loot = loot

local HOLDER_NAME, KEY = "RikUILoot", "loot"
local ROW_WIDTH, ROW_HEIGHT, ROW_GAP, PAD, EDGE, ICON = 280, 38, 4, 6, 1, 30
-- Right of the screen centre, anchored by its top so the list grows downward, clear of the unit frames.
local DEFAULTS = { point = "TOPLEFT", relativePoint = "CENTER", x = 200, y = 140 }
local CURSOR_X, CURSOR_Y = -30, 20
local HEADER, CLOSE_SIZE = 30, 22
local BACKGROUND, BORDER, WHITE = { 0.06, 0.07, 0.09, 0.9 }, { 0.25, 0.28, 0.32, 1 }, { 1, 1, 1 }
local FLAT = "Interface\\BUTTONS\\WHITE8X8"
local EVENTS = { "LOOT_OPENED", "LOOT_CLOSED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED" }
local holder, closing, warnings = nil, false, {}
local sessionSlots, MAX_LOOT_SLOTS = 0, 200

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Loot " .. operation .. ": " .. tostring(reason))
end

local function readable(value, kind)
    return not core.Secret.IsSecret(value) and type(value) == kind
end

function loot.AtCursor()
    return core.Profile == nil or core.Profile.lootAtCursor ~= false
end

local function flat(frame, layer)
    local background = frame:CreateTexture(nil, layer)
    background:SetAllPoints(frame)
    background:SetTexture(FLAT)
    background:SetVertexColor(unpack(BACKGROUND))
    frame.rikBorder = ui.Edges(frame, EDGE, "BORDER")
    for _, line in ipairs(frame.rikBorder) do line:SetVertexColor(unpack(BORDER)) end
end
loot.Flat = flat

local function onClick(row)
    if IsModifiedClick() then HandleModifiedItemClick(GetLootSlotLink(row.slot)) return end
    LootSlot(row.slot)
end

local function onEnter(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if row.currency then GameTooltip:SetLootCurrency(row.slot) else GameTooltip:SetLootItem(row.slot) end
end

local function onLeave() GameTooltip:Hide() end

local function createRow()
    local row = CreateFrame("Button", nil, holder)
    row:SetSize(ROW_WIDTH, ROW_HEIGHT)
    row.rikBacking = core.Skin.Fill(row, { 0.09, 0.105, 0.135, 1 })
    row.rikQualityRail = row:CreateTexture(nil, "ARTWORK")
    row.rikQualityRail:SetTexture(FLAT)
    row.rikQualityRail:SetPoint("TOPLEFT", row, "TOPLEFT")
    row.rikQualityRail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT")
    row.rikQualityRail:SetWidth(EDGE)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    core.Skin.CropIcon(row.icon)
    row.rikIconBorder = core.Skin.Outline(row, BORDER, -1, row.icon, "OVERLAY")
    row.name = row:CreateFontString(nil, "OVERLAY")
    media.Font(row.name, "label")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(true)
    row.name:SetMaxLines(2)
    row.count = row:CreateFontString(nil, "OVERLAY")
    media.Font(row.count, "small")
    row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", -1, 1)
    row.rikCountBacking = row:CreateTexture(nil, "ARTWORK")
    row.rikCountBacking:SetTexture(FLAT)
    row.rikCountBacking:SetVertexColor(0.025, 0.03, 0.04, 0.95)
    row.rikCountBacking:SetPoint("TOPLEFT", row.count, "TOPLEFT", -2, 1)
    row.rikCountBacking:SetPoint("BOTTOMRIGHT", row.count, "BOTTOMRIGHT", 2, -1)
    row.rikCountBacking:Hide()
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(row)
    highlight:SetTexture(media.highlight)
    row:SetScript("OnClick", onClick)
    row:SetScript("OnEnter", onEnter)
    row:SetScript("OnLeave", onLeave)
    core.Motion.BindHover(row)
    loot.Rows[#loot.Rows + 1] = row
    return row
end

local function qualityColor(quality)
    if not readable(quality, "number") then return WHITE end
    local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
    if not ok or not readable(r, "number") or not readable(g, "number") or not readable(b, "number") then return WHITE end
    return { r, g, b }
end

-- Returns false when the slot holds nothing to show.
local function fillRow(row, slot)
    local ok, texture, name, quantity, currencyID, quality = pcall(GetLootSlotInfo, slot)
    if not ok then warn("slot", texture) return nil end
    if texture == nil and name == nil then return false end
    local publicQuantity = readable(quantity, "number") and quantity or nil
    if readable(name, "string") and (row.rikItemName ~= name or row.rikQuantity ~= publicQuantity) then
        row.rikReveal = true
    end
    row.rikItemName = readable(name, "string") and name or nil
    row.rikQuantity = readable(quantity, "number") and quantity or nil
    row.slot, row.currency = slot, currencyID ~= nil
    row.icon:SetTexture(not core.Secret.IsSecret(texture) and texture or nil)
    -- Coin text arrives as one line per denomination.
    row.name:SetText(readable(name, "string") and name:gsub("\n", ", ") or "")
    row.rikQualityColor = qualityColor(quality)
    row.name:SetTextColor(unpack(row.rikQualityColor))
    row.rikQualityRail:SetVertexColor(unpack(row.rikQualityColor))
    local stacked = readable(quantity, "number") and quantity > 1
    row.count:SetText(stacked and tostring(quantity) or "")
    row.rikCountBacking:SetShown(stacked)
    return true
end

local function stackRows()
    local shown = 0
    for _, row in ipairs(loot.Rows) do
        if row:IsShown() then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", holder, "TOPLEFT", PAD, -HEADER - PAD - shown * (ROW_HEIGHT + ROW_GAP))
            shown = shown + 1
        end
    end
    local rows = math.max(shown, 1)
    holder:SetSize(ROW_WIDTH + 2 * PAD, rows * (ROW_HEIGHT + ROW_GAP) - ROW_GAP + 2 * PAD + HEADER)
    holder.title:SetText(shown == 0 and "Loot  |  Empty" or ("Loot  |  " .. shown .. (shown == 1 and " item" or " items")))
    holder.empty:SetShown(shown == 0)
end

local function place()
    if not loot.AtCursor() then layout.Apply() return end
    local x, y = GetCursorPosition()
    if not readable(x, "number") or not readable(y, "number") then return end
    local scale = holder:GetEffectiveScale()
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + CURSOR_X, y / scale + CURSOR_Y)
end

local function rowFor(slot)
    if not holder:IsShown() or not readable(slot, "number") or slot ~= slot
        or slot < 1 or slot > sessionSlots or slot % 1 ~= 0 then return end
    return loot.Rows[slot]
end

local function reveal(row)
    if row.rikReveal and row:IsShown() then core.Motion.Flash(row, row.rikQualityColor) end
    row.rikReveal = nil
end

function loot.Open()
    local ok, slots = pcall(GetNumLootItems)
    if not ok or not readable(slots, "number") or slots ~= slots or slots < 0
        or slots > MAX_LOOT_SLOTS or slots % 1 ~= 0 then
        warn("open", "Loot slot count unavailable")
        slots = 0
    end
    sessionSlots = slots
    for _, row in ipairs(loot.Rows) do
        row:Hide()
        row.slot, row.rikItemName, row.rikQuantity, row.rikReveal = nil, nil, nil, nil
    end
    for slot = 1, slots do
        local row = loot.Rows[slot] or createRow()
        row.slot = slot
        if fillRow(row, slot) then row:Show() else row:Hide() end
    end
    stackRows()
    place()
    holder:Show()
    for _, row in ipairs(loot.Rows) do reveal(row) end
end

function loot.Close()
    closing = true
    holder:Hide()
    closing = false
end

function loot.SlotCleared(_, slot)
    local row = rowFor(slot)
    if not row then return end
    row:Hide()
    stackRows()
end

function loot.SlotChanged(_, slot)
    local row = rowFor(slot)
    if not row then return end
    local filled = fillRow(row, slot)
    if filled == nil then return end
    if filled then row:Show() else row:Hide() end
    reveal(row)
    stackRows()
end

local HANDLERS = { LOOT_OPENED = loot.Open, LOOT_CLOSED = loot.Close, LOOT_SLOT_CLEARED = loot.SlotCleared,
    LOOT_SLOT_CHANGED = loot.SlotChanged }

local function createHeader()
    holder.rikChrome = core.Skin.WindowChrome(holder, HEADER, 0)
    holder.title = holder:CreateFontString(nil, "OVERLAY")
    media.Font(holder.title, "label")
    holder.title:SetPoint("TOPLEFT", holder, "TOPLEFT", PAD + 4, -8)
    holder.title:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -CLOSE_SIZE - PAD * 2, -8)
    holder.title:SetJustifyH("LEFT")
    holder.close = CreateFrame("Button", nil, holder)
    holder.close:SetSize(CLOSE_SIZE, CLOSE_SIZE)
    holder.close:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -PAD, -PAD)
    holder.close.icon = media.Icon(holder.close, "close", 12, "OVERLAY")
    holder.close.icon:SetPoint("CENTER")
    holder.close:SetHighlightTexture(media.highlight, "ADD")
    holder.close:SetScript("OnClick", function() holder:Hide() end)
    holder.empty = holder:CreateFontString(nil, "OVERLAY")
    media.Font(holder.empty, "small")
    holder.empty:SetPoint("TOP", holder, "TOP", 0, -HEADER - PAD - 6)
    holder.empty:SetText("Nothing left to loot")
    holder.empty:SetTextColor(0.7, 0.75, 0.82)
end

local function createHolder()
    holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    holder:SetFrameStrata("HIGH")
    holder:SetSize(ROW_WIDTH + 2 * PAD, ROW_HEIGHT + 2 * PAD)
    createHeader()
    holder:SetClampedToScreen(true)
    holder:Hide()
    -- Escape and a manual hide end the loot session the way the stock frame's OnHide does.
    holder:SetScript("OnHide", function() if not closing then CloseLoot() end end)
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = HOLDER_NAME end
    -- Loot is a temporary overlay in either mode. Fixed placement still follows its
    -- saved anchor, but a closed popup must not push persistent HUD controls away.
    layout.Register(holder, KEY, DEFAULTS, { label = "Loot list", floating = loot.AtCursor, overlay = true })
    core.Motion.BindEntrance(holder, true)
    loot.Holder = holder
end

function loot:OnEnable()
    createHolder()
    for _, event in ipairs(EVENTS) do core:RegisterEvent(event, HANDLERS[event]) end
    -- keepEvents false: a stock frame that still hears LOOT_OPENED closes the loot it cannot show.
    if LootFrame then core.Hide.Frame(LootFrame, false) end
    if loot.SkinRolls then loot.SkinRolls() end
end

function loot:Debug()
    core:Print("Loot holder=" .. tostring(holder ~= nil) .. " rows=" .. #loot.Rows .. " rolls=" .. #loot.SkinnedRolls)
end

table.insert(loot.Options.settings, { type = "checkbox", key = "lootAtCursor", label = "Open the loot list at the cursor",
    get = loot.AtCursor, set = function(value) core.Profile.lootAtCursor = value == true end })

core:RegisterModule("loot", loot)
