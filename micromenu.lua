-- Flat strip replacing the micro menu and the bag bar. Micro buttons are secure click delegates to
-- the stock buttons, so every panel opens through Blizzard's own handler in and out of combat; bag
-- buttons call the client's bag toggles. MicroMenu and BagsBar park only once the strip exists.
local core, media, layout, unitframes = RikUI, RikUI.Media, RikUI.Layout, RikUI.UnitFrames
local micromenu = { Buttons = {}, Bags = {} }
core.MicroMenu = micromenu

local HOLDER_NAME, KEY = "RikUIMicroMenu", "micromenu"
local SIZE, GAP, GROUP_GAP, EDGE, ICON_INSET = 22, 2, 8, 1, 2
local DEFAULTS = { point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT", x = -16, y = 16 }
local BACKGROUND, BORDER = { 0.06, 0.07, 0.09, 0.9 }, { 0.25, 0.28, 0.32, 1 }
local FLAT = "Interface\\BUTTONS\\WHITE8X8"
local BACKPACK_ICON, KEYRING_ICON = "Interface\\Icons\\INV_Misc_Bag_08", "Interface\\Icons\\INV_Misc_Key_14"
local BACKPACK, LAST_BAG, KEYRING_FALLBACK = 0, 4, -2
-- Every micro button the Mainline file defines on 69913; the client decides which exist and show.
local MICRO = {
    { "CharacterMicroButton", "C" }, { "ProfessionMicroButton", "P" }, { "PlayerSpellsMicroButton", "S" },
    { "SpellbookMicroButton", "B" }, { "TalentMicroButton", "T" }, { "AchievementMicroButton", "A" },
    { "LegacyMicroButton", "L" }, { "QuestLogMicroButton", "Q" }, { "HousingMicroButton", "H" },
    { "GuildMicroButton", "G" }, { "LFDMicroButton", "F" }, { "CollectionsMicroButton", "O" },
    { "EJMicroButton", "J" }, { "HelpMicroButton", "?" }, { "StoreMicroButton", "$" }, { "MainMenuMicroButton", "=" },
}
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
    button:SetPoint("LEFT", holder, "LEFT", offset, 0)
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(button)
    background:SetTexture(FLAT)
    background:SetVertexColor(unpack(BACKGROUND))
    button.rikBorder = unitframes.Edges(button, EDGE, "BORDER")
    for _, line in ipairs(button.rikBorder) do line:SetVertexColor(unpack(BORDER)) end
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(button)
    highlight:SetTexture(media.highlight)
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
    button.label = text(button, "label", "CENTER")
    button.label:SetText(letter)
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
    button.count = text(button, "small", "BOTTOMRIGHT")
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
        if stock then createMicro(stock, entry[2], offset); offset = offset + SIZE + GAP end
    end
    if offset > 0 then offset = offset + GROUP_GAP end
    for bag = BACKPACK, LAST_BAG do
        createBag(bag, bag == BACKPACK and BACKPACK_TOOLTIP or BAGSLOT, offset)
        offset = offset + SIZE + GAP
    end
    local keyring = keyringBag()
    if keyring then createBag(keyring, KEYRING, offset); offset = offset + SIZE + GAP end
    return offset - GAP
end

local function build()
    holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    holder:SetSize(createButtons(), SIZE)
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
        hooksecurefunc(bars, "UpdateStockVisibility", micromenu.UpdateStock)
    end
end

function micromenu:Debug()
    core:Print("Micro menu holder=" .. tostring(holder ~= nil) .. " buttons=" .. #micromenu.Buttons
        .. " bags=" .. #micromenu.Bags)
end

core:RegisterModule("micromenu", micromenu)
