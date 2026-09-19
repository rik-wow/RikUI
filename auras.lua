-- Shared aura button factory plus the player buffs, debuffs and weapon enchants. Aura values
-- only reach sinks (auras-status.lua); this file owns frames, layout, the secure cancel layer,
-- events and the stock frames. auras-units.lua builds the target and pet rows on the same factory.
local core, media, layout, unitframes = RikUI, RikUI.Media, RikUI.Layout, RikUI.UnitFrames
local auras = { Rows = {}, blocked = false }
core.Auras = auras

local SIZE, GAP, PER_ROW, EDGE, ICON_CROP, CANCEL_LEVEL = 30, 4, 8, 1, 0.07, 5
local STEP = SIZE + GAP
-- A row fills from its origin corner: player rows run right-to-left and downward.
local DIRECTIONS = { TOPRIGHT = { x = -1, y = -1 }, BOTTOMLEFT = { x = 1, y = 1 } }
local ROWS = {
    { key = "buffs", unit = "player", filter = "HELPFUL", slots = 32, size = SIZE, perLine = PER_ROW,
        origin = "TOPRIGHT", enchants = true, cancel = true },
    { key = "debuffs", unit = "player", filter = "HARMFUL", slots = 16, size = SIZE, perLine = PER_ROW,
        origin = "TOPRIGHT" },
}
-- Top right beside the minimap cluster; the debuff rows sit under the four buff rows.
local DEFAULTS = {
    buffs = { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -200, y = -13 },
    debuffs = { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -200, y = -13 - 4 * STEP },
}
local STOCK_FRAMES = { "BuffFrame", "DebuffFrame" }
local COMBAT_HIDDEN = "[combat] hide; show"
local BACKGROUND = { 0.055, 0.065, 0.08, 0.95 }
local FRAME_PREFIX = "RikUIAuras_"
local warnings, stockPending = {}, false

function auras.Warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Auras " .. operation .. ": " .. tostring(reason))
end

function auras.Api(namespace, name)
    local table = _G[namespace]
    if type(table) == "table" and type(table[name]) == "function" then return table[name] end
    return function() error(namespace .. "." .. name .. " unavailable", 0) end
end

function auras.RowSize(spec)
    local step = spec.size + GAP
    return spec.perLine * step - GAP, math.ceil(spec.slots / spec.perLine) * step - GAP
end

local function slotOffset(spec, index)
    local step, direction = spec.size + GAP, DIRECTIONS[spec.origin]
    local column, line = (index - 1) % spec.perLine, math.floor((index - 1) / spec.perLine)
    return column * step * direction.x, line * step * direction.y
end

local function tooltipEntry(button)
    local entry = button.entry or (button.display and button.display.entry)
    if not entry or type(GameTooltip) ~= "table" or type(GameTooltip.SetOwner) ~= "function" then return nil end
    return entry
end

local function showTooltip(button)
    local entry = tooltipEntry(button)
    if not entry then return end
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOMLEFT")
    local ok, reason
    if entry.slot then
        ok, reason = pcall(GameTooltip.SetInventoryItem, GameTooltip, entry.unit, entry.slot)
    else
        ok, reason = pcall(GameTooltip.SetUnitAura, GameTooltip, entry.unit, entry.index, entry.filter)
    end
    if not ok then GameTooltip:Hide(); auras.Warn("tooltip", reason) end
end

local function hideTooltip()
    if type(GameTooltip) == "table" and type(GameTooltip.Hide) == "function" then GameTooltip:Hide() end
end

local function hoverScripts(frame)
    frame:SetScript("OnEnter", showTooltip)
    frame:SetScript("OnLeave", hideTooltip)
end

local function cooldown(button)
    local widget = CreateFrame("Cooldown", nil, button)
    widget:SetAllPoints(button)
    widget:EnableMouse(false)
    widget:SetDrawEdge(false)
    widget:SetDrawBling(false)
    widget:SetHideCountdownNumbers(false)
    widget:SetCountdownFont("NumberFontNormal")
    widget:SetSwipeColor(0, 0, 0, 0.8)
    return widget
end

-- The count sits on a frame above the cooldown so the swipe never covers it.
local function countText(button)
    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints(button)
    overlay:EnableMouse(false)
    overlay:SetFrameLevel(button.cooldown:GetFrameLevel() + 1)
    local region = overlay:CreateFontString(nil, "OVERLAY")
    media.Font(region, "count")
    region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    return region
end

local function decorate(button)
    button.background = button:CreateTexture(nil, "BACKGROUND")
    button.background:SetAllPoints()
    button.background:SetColorTexture(unpack(BACKGROUND))
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", EDGE, -EDGE)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -EDGE, EDGE)
    button.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    button.border = unitframes.Edges(button, EDGE, "OVERLAY")
    button.cooldown = cooldown(button)
    button.count = countText(button)
end

local function createButton(row, spec, index)
    local button = CreateFrame("Frame", nil, row)
    button:SetSize(spec.size, spec.size)
    button:SetPoint(spec.origin, row, spec.origin, slotOffset(spec, index))
    button:EnableMouse(true)
    decorate(button)
    hoverScripts(button)
    button:Hide()
    return button
end

-- Rows are plain frames any module may build under any parent and refresh through
-- auras.RefreshRow; the owning module keeps its own Rows table and blocked flag.
function auras.CreateRow(spec, parent, owner)
    local row = CreateFrame("Frame", FRAME_PREFIX .. spec.key, parent)
    row.key, row.unit, row.filter, row.slots = spec.key, spec.unit, spec.filter, spec.slots
    row.enchants, row.emphasis, row.module = spec.enchants, spec.emphasis, owner
    row.buttons, row.entries = {}, {}
    row:SetSize(auras.RowSize(spec))
    for index = 1, spec.slots do row.buttons[index] = createButton(row, spec, index) end
    owner.Rows[spec.key] = row
    return row
end

local function createCancelButton(parent, display)
    local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    button.display = display
    button:SetAllPoints(display)
    button:RegisterForClicks("RightButtonUp")
    button:SetAttribute("type2", "cancelaura")
    hoverScripts(button)
    button:Hide()
    return button
end

-- The cancel layer is protected: a state driver hides it in combat and every write to it
-- goes through the combat queue, so the display layer underneath stays free to redraw.
local function createCancelLayer(row)
    local parent = CreateFrame("Frame", FRAME_PREFIX .. row.key .. "Cancel", row)
    parent:SetAllPoints(row)
    parent:SetFrameLevel(row:GetFrameLevel() + CANCEL_LEVEL)
    parent.buttons = {}
    for index, display in ipairs(row.buttons) do parent.buttons[index] = createCancelButton(parent, display) end
    local ok, reason = pcall(RegisterStateDriver, parent, "visibility", COMBAT_HIDDEN)
    if not ok then auras.Warn("cancel driver", reason) end
    return parent
end

local function createPlayerRow(spec)
    local row = auras.CreateRow(spec, UIParent, auras)
    if spec.cancel then row.cancel = createCancelLayer(row) end
    layout.Register(row, spec.key, DEFAULTS[spec.key])
    return row
end

local function replacementsReady()
    for _, spec in ipairs(ROWS) do
        if not auras.Rows[spec.key] then return false end
    end
    return true
end

local function hideStock()
    stockPending = false
    if not auras.enabled or not replacementsReady() then return end
    for _, name in ipairs(STOCK_FRAMES) do
        local frame = _G[name]
        -- No native handler must keep running: the RikUI rows own the player's auras now.
        if frame then core.Hide.Frame(frame, false) end
    end
end

function auras.UpdateStockVisibility()
    if stockPending then return end
    stockPending = true
    core.Combat.Queue(hideStock)
end

local function eachRow(callback)
    for _, spec in ipairs(ROWS) do
        local row = auras.Rows[spec.key]
        if row then callback(row) end
    end
end

function auras.Refresh()
    eachRow(auras.RefreshRow)
end

local function refreshEnchants()
    eachRow(function(row)
        if row.enchants then auras.RefreshRow(row) end
    end)
end

local function registerEvents()
    core:RegisterEvent("UNIT_AURA", function(_, unit)
        if core.Secret.IsSecret(unit) or unit == "player" then auras.Refresh() end
    end)
    core:RegisterEvent("WEAPON_ENCHANT_CHANGED", refreshEnchants)
    core:RegisterEvent("WEAPON_SLOT_CHANGED", refreshEnchants)
    core:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if auras.blocked then auras.Refresh() end
    end)
    core:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        auras.Refresh()
        auras.UpdateStockVisibility()
    end)
end

function auras:OnEnable()
    core.Combat.Queue(function()
        for _, spec in ipairs(ROWS) do
            if not auras.Rows[spec.key] then auras.RefreshRow(createPlayerRow(spec)) end
        end
        auras.UpdateStockVisibility()
    end)
    registerEvents()
end

function auras:Debug(sample)
    core:Print("Auras blocked=" .. tostring(auras.blocked) .. " combat=" .. tostring(InCombatLockdown()))
    sample("GetAuraDataByIndex(player,1,HELPFUL)", auras.Api("C_UnitAuras", "GetAuraDataByIndex"), "player", 1, "HELPFUL")
    sample("ShouldAurasBeSecret()", auras.Api("C_Secrets", "ShouldAurasBeSecret"))
    local id = auras.FirstAuraInstance("player", "HELPFUL")
    if id ~= nil then sample("GetAuraDuration(player, first buff)", auras.Api("C_UnitAuras", "GetAuraDuration"), "player", id) end
end

core:RegisterModule("auras", auras)
