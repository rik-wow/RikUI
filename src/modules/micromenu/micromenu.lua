-- Flat strip replacing the micro menu and the bag bar. Micro buttons are secure click delegates to
-- the stock buttons, so every panel opens through Blizzard's own handler in and out of combat; bag
-- buttons call the client's bag toggles. MicroMenu and BagsBar park only once the strip exists.
local core, media, layout, ui = RikUI, RikUI.Media, RikUI.Layout, RikUI.UI
local micromenu = { Buttons = {}, Bags = {} }
core.MicroMenu = micromenu

local HOLDER_NAME, KEY = "RikUIMicroMenu", "micromenu"
local SIZE, GAP, EDGE, ICON_INSET, COLUMNS = 22, 2, 1, 2, 10
local DEFAULTS = { point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT", x = -16, y = 16 }
local BACKGROUND, BORDER = { 0.06, 0.07, 0.09, 0.9 }, { 0.25, 0.28, 0.32, 1 }
local FULL_COLOR, SPACE_COLOR = { 1, 0.35, 0.25 }, { 0.85, 0.95, 0.9 }
local FLAT = "Interface\\BUTTONS\\WHITE8X8"
local BACKPACK_ICON, KEYRING_ICON = "Interface\\Icons\\INV_Misc_Bag_08", "Interface\\Icons\\INV_Misc_Key_14"
local BACKPACK, LAST_BAG, KEYRING_FALLBACK = 0, 4, -2
-- Every micro button the Mainline file defines on 69913; the client decides which exist and show.
local MICRO = {
    { "CharacterMicroButton", "character" }, { "ProfessionMicroButton", "profession" },
    { "PlayerSpellsMicroButton", "spells" }, { "SpellbookMicroButton", "spellbook" }, { "TalentMicroButton", "talents" },
    { "AchievementMicroButton", "achievement" }, { "LegacyMicroButton", "legacy" }, { "QuestLogMicroButton", "quest" },
    { "HousingMicroButton", "housing" }, { "GuildMicroButton", "guild" }, { "LFDMicroButton", "groupfinder" },
    { "CollectionsMicroButton", "collections" }, { "EJMicroButton", "journal" }, { "HelpMicroButton", "help" },
    { "StoreMicroButton", "store" }, { "MainMenuMicroButton", "menu" },
}
local MICRO_ICON_SIZE = 14
local STOCK = { "MicroMenu", "BagsBar" }
local holder, warnings = nil, {}

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Micro menu " .. operation .. ": " .. tostring(reason))
end

local function isFrame(value)
    local kind = type(value)
    return (kind == "table" or kind == "userdata") and type(value.SetParent) == "function"
end

local function decorate(button, offset)
    button:SetSize(SIZE, SIZE)
    button:SetPoint("TOPLEFT", holder, "TOPLEFT", (offset % COLUMNS) * (SIZE + GAP),
        -math.floor(offset / COLUMNS) * (SIZE + GAP))
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(button)
    background:SetTexture(FLAT)
    background:SetVertexColor(unpack(BACKGROUND))
    button.rikBorder = ui.Edges(button, EDGE, "BORDER")
    for _, line in ipairs(button.rikBorder) do line:SetVertexColor(unpack(BORDER)) end
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(button)
    highlight:SetTexture(media.highlight)
    core.Motion.BindHover(button)
end

local function text(button, role, point)
    local region = button:CreateFontString(nil, "OVERLAY")
    media.Font(region, role)
    region:SetPoint(point, button, point, 0, 0)
    return region
end

local function showTooltip(button)
    if type(button.tooltip) ~= "string" then return end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(button.tooltip)
end

local function hideTooltip() GameTooltip:Hide() end

local function microTooltip(button)
    local stockText = button.stock.tooltipText
    button.tooltip = type(stockText) == "string" and stockText or button.stock:GetName()
    showTooltip(button)
end

local function createMicro(stock, letter, offset)
    local button = CreateFrame("Button", HOLDER_NAME .. stock:GetName(), holder, "SecureActionButtonTemplate")
    button.stock = stock
    button:SetAttribute("type", "click")
    button:SetAttribute("clickbutton", stock)
    button:RegisterForClicks("AnyDown", "AnyUp")
    decorate(button, offset)
    button.icon = media.Icon(button, letter, MICRO_ICON_SIZE, "OVERLAY")
    button.icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    button:SetScript("OnEnter", microTooltip)
    button:SetScript("OnLeave", hideTooltip)
    micromenu.Buttons[#micromenu.Buttons + 1] = button
end

local function toggleBag(button)
    if button.bag == BACKPACK then ToggleBackpack() else ToggleBag(button.bag) end
end

local function createBag(bag, tooltip, offset)
    local button = CreateFrame("Button", HOLDER_NAME .. "Bag" .. tostring(bag):gsub("-", "Key"), holder)
    button.bag, button.tooltip = bag, tooltip
    decorate(button, offset)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", ICON_INSET, -ICON_INSET)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -ICON_INSET, ICON_INSET)
    button.countBacking = button:CreateTexture(nil, "ARTWORK", nil, 1)
    button.countBacking:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    button.countBacking:SetSize(18, 12)
    button.countBacking:SetTexture(FLAT)
    button.countBacking:SetVertexColor(0.015, 0.02, 0.03, 0.92)
    button.count = text(button, "small", "BOTTOMRIGHT")
    button.count:ClearAllPoints()
    button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 1)
    button.count:SetWidth(18)
    button.count:SetJustifyH("RIGHT")
    button.count:SetWordWrap(false)
    button:SetScript("OnClick", toggleBag)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", hideTooltip)
    micromenu.Bags[#micromenu.Bags + 1] = button
end

local function keyringBag()
    if type(C_ActionBar) ~= "table" or type(C_ActionBar.ShouldShowKeyring) ~= "function" then return nil end
    local ok, shown = pcall(C_ActionBar.ShouldShowKeyring)
    if not ok or shown ~= true then return nil end
    return KEYRING_CONTAINER or KEYRING_FALLBACK
end

local function bagIcon(bag)
    if bag == BACKPACK then return BACKPACK_ICON end
    if bag < BACKPACK then return KEYRING_ICON end
    return GetInventoryItemTexture("player", C_Container.ContainerIDToInventoryID(bag))
end

local function readBag(bag)
    local icon = bagIcon(bag)
    if bag < BACKPACK or not icon then return icon, nil end
    return icon, C_Container.GetContainerNumFreeSlots(bag)
end

local function refreshBag(button)
    local ok, icon, free = pcall(readBag, button.bag)
    if not ok then warn("bags", icon); icon, free = nil, nil end
    if core.Secret.IsSecret(icon) then icon = nil end
    button.icon:SetTexture(icon)
    local readable = not core.Secret.IsSecret(free) and type(free) == "number"
        and free >= 0 and free < math.huge and free == math.floor(free)
    local full = readable and free == 0
    button.countBacking:SetShown(readable)
    button.count:SetTextColor(unpack(full and FULL_COLOR or SPACE_COLOR))
    for _, edge in ipairs(button.rikBorder) do edge:SetVertexColor(unpack(full and FULL_COLOR or BORDER)) end
    button.count:SetText(readable and tostring(free) or "")
end

function micromenu.RefreshBags()
    for _, button in ipairs(micromenu.Bags) do refreshBag(button) end
end

-- Native menu layout skips anchors while it is parked outside its container.
local function refreshMenuLayout(frame)
    local parent = frame:GetParent()
    if parent and parent == MicroMenuContainer and type(parent.Layout) == "function" then parent:Layout() end
end

-- The stock buttons stay the click targets, so their events stay registered while parked.
function micromenu.UpdateStock()
    if not holder or not core.Profile then return end
    local hidden = core.Profile.showStockBars ~= true
    for _, name in ipairs(STOCK) do
        local frame = _G[name]
        if isFrame(frame) then
            if hidden then core.Hide.Frame(frame, true)
            elseif core.Hide.IsHidden(frame) then core.Hide.Restore(frame, refreshMenuLayout) end
        end
    end
end

-- The Mainline file defines buttons Forever never adds to the menu (the adventure guide's handler
-- calls a nil global there); an orphan still reports shown, so membership is the parent.
local function shownStock(name)
    local stock = _G[name]
    if not isFrame(stock) or type(stock.IsShown) ~= "function" then return nil end
    if type(stock.GetParent) ~= "function" or stock:GetParent() ~= MicroMenu then return nil end
    return stock:IsShown() and stock or nil
end

local function createButtons()
    local offset = 0
    for _, entry in ipairs(MICRO) do
        local stock = shownStock(entry[1])
        if stock then createMicro(stock, entry[2], offset); offset = offset + 1 end
    end
    -- Keep the native button order while wrapping inside the reserved utility column.
    for bag = BACKPACK, LAST_BAG do
        createBag(bag, bag == BACKPACK and BACKPACK_TOOLTIP or BAGSLOT, offset)
        offset = offset + 1
    end
    local keyring = keyringBag()
    if keyring then createBag(keyring, KEYRING, offset); offset = offset + 1 end
    return math.min(offset, COLUMNS) * (SIZE + GAP) - GAP,
        math.ceil(offset / COLUMNS) * (SIZE + GAP) - GAP
end

local function build()
    holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    holder:SetSize(createButtons())
    layout.Register(holder, KEY, DEFAULTS)
    micromenu.Holder = holder
    micromenu.RefreshBags()
    micromenu.UpdateStock()
end

function micromenu:OnEnable()
    core.Combat.Queue(build)
    core:RegisterEvent("BAG_UPDATE_DELAYED", micromenu.RefreshBags)
    local bars = core.Bars
    if type(bars) == "table" and type(bars.UpdateStockVisibility) == "function" then
        core.Hooks.Owned(bars, "UpdateStockVisibility", micromenu.UpdateStock)
    end
end

function micromenu:Debug()
    core:Print("Micro menu holder=" .. tostring(holder ~= nil) .. " buttons=" .. #micromenu.Buttons
        .. " bags=" .. #micromenu.Bags)
end

core:RegisterModule("micromenu", micromenu)
