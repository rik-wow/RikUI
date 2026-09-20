-- Flat loot list in place of Blizzard's LootFrame. It reads the same globals the stock frame reads
-- and loots with LootSlot from a plain click; auto-loot stays the client's. The stock frame is
-- parked with its events dropped because both its hide path and its open path call CloseLoot.
-- loot-rolls.lua skins the group roll frames.
local core, media, layout, unitframes = RikUI, RikUI.Media, RikUI.Layout, RikUI.UnitFrames
local loot = { Rows = {}, SkinnedRolls = {}, Options = { title = "Loot", settings = {} } }
core.Loot = loot

local HOLDER_NAME, KEY = "RikUILoot", "loot"
local ROW_WIDTH, ROW_HEIGHT, ROW_GAP, PAD, EDGE, ICON = 220, 26, 2, 4, 1, 22
-- Right of the screen centre, anchored by its top so the list grows downward, clear of the unit frames.
local DEFAULTS = { point = "TOPLEFT", relativePoint = "CENTER", x = 200, y = 140 }
local CURSOR_X, CURSOR_Y = -30, 20
local BACKGROUND, BORDER, WHITE = { 0.06, 0.07, 0.09, 0.9 }, { 0.25, 0.28, 0.32, 1 }, { 1, 1, 1 }
local FLAT = "Interface\\BUTTONS\\WHITE8X8"
local EVENTS = { "LOOT_OPENED", "LOOT_CLOSED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED" }
local holder, closing, warnings = nil, false, {}

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
    frame.rikBorder = unitframes.Edges(frame, EDGE, "BORDER")
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
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.name = row:CreateFontString(nil, "OVERLAY")
    media.Font(row.name, "label")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.count = row:CreateFontString(nil, "OVERLAY")
    media.Font(row.count, "small")
    row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 1, -1)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(row)
    highlight:SetTexture(media.highlight)
    row:SetScript("OnClick", onClick)
    row:SetScript("OnEnter", onEnter)
    row:SetScript("OnLeave", onLeave)
    loot.Rows[#loot.Rows + 1] = row
    return row
end

local function qualityColor(quality)
    if not readable(quality, "number") then return WHITE end
    local ok, r, g, b = pcall(C_Item.GetItemQualityColor, quality)
    if not ok or not readable(r, "number") then return WHITE end
    return { r, g, b }
end

-- Returns false when the slot holds nothing to show.
local function fillRow(row, slot)
    local ok, texture, name, quantity, currencyID, quality = pcall(GetLootSlotInfo, slot)
    if not ok then warn("slot", texture) return false end
    if texture == nil and name == nil then return false end
    row.slot, row.currency = slot, currencyID ~= nil
    row.icon:SetTexture(not core.Secret.IsSecret(texture) and texture or nil)
    -- Coin text arrives as one line per denomination.
    row.name:SetText(readable(name, "string") and name:gsub("\n", ", ") or "")
    row.name:SetTextColor(unpack(qualityColor(quality)))
    row.count:SetText(readable(quantity, "number") and quantity > 1 and tostring(quantity) or "")
    return true
end

local function stackRows()
    local shown = 0
    for _, row in ipairs(loot.Rows) do
        if row:IsShown() then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", holder, "TOPLEFT", PAD, -PAD - shown * (ROW_HEIGHT + ROW_GAP))
            shown = shown + 1
        end
    end
    local rows = math.max(shown, 1)
    holder:SetSize(ROW_WIDTH + 2 * PAD, rows * (ROW_HEIGHT + ROW_GAP) - ROW_GAP + 2 * PAD)
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
    for _, row in ipairs(loot.Rows) do
        if row.slot == slot and row:IsShown() then return row end
    end
end

function loot.Open()
    local ok, slots = pcall(GetNumLootItems)
    if not ok then warn("open", slots); slots = 0 end
    for _, row in ipairs(loot.Rows) do row:Hide() end
    for slot = 1, readable(slots, "number") and slots or 0 do
        local row = loot.Rows[slot] or createRow()
        if fillRow(row, slot) then row:Show() else row:Hide() end
    end
    stackRows()
    place()
    holder:Show()
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
    if row and not fillRow(row, slot) then row:Hide(); stackRows() end
end

local HANDLERS = { LOOT_OPENED = loot.Open, LOOT_CLOSED = loot.Close, LOOT_SLOT_CLEARED = loot.SlotCleared,
    LOOT_SLOT_CHANGED = loot.SlotChanged }

local function createHolder()
    holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    holder:SetFrameStrata("HIGH")
    holder:SetSize(ROW_WIDTH + 2 * PAD, ROW_HEIGHT + 2 * PAD)
    flat(holder, "BACKGROUND")
    holder:Hide()
    -- Escape and a manual hide end the loot session the way the stock frame's OnHide does.
    holder:SetScript("OnHide", function() if not closing then CloseLoot() end end)
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = HOLDER_NAME end
    -- At the cursor the list places itself and stands over other frames for a moment, like a tooltip;
    -- at its layout position it is a group like any other and gives way when it grows.
    layout.Register(holder, KEY, DEFAULTS, { label = "Loot list", floating = loot.AtCursor })
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
