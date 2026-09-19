-- Player buffs, debuffs and weapon enchants on Blizzard's aura containers. The container reads
-- auras in secure code and drives the decorated buttons (auras-button.lua), so nothing here
-- touches C_UnitAuras; this file owns the containers, their flow layout, the layout proxies,
-- the stock frames and the shared container factory that auras-units.lua reuses.
local core, layout = RikUI, RikUI.Layout
local auras = { Rows = {}, Gap = 4 }
core.Auras = auras

local SIZE, GAP, PER_LINE = 30, 4, 8
local STEP = SIZE + GAP
local LINE_SIZE = PER_LINE * STEP - GAP
local CONTAINER_TYPE, CONTAINER_TEMPLATE, FRAME_PREFIX = "AuraContainer", "CustomAuraContainerTemplate", "RikUIAuras_"
-- Both player rows fill right-to-left and downward from the proxy's top right corner.
local FLOW = { anchor = "TOPRIGHT", horizontal = "Left", vertical = "Down", lineSize = LINE_SIZE }
local DIRECTIONS = { Left = -1, Right = 1, Up = 1, Down = -1 } -- AnchorUtil.FlowDirection on 69913
local ENCHANT_SLOTS = { "MainHand", "OffHand", "Ranged" } -- AuraContainerItemEnchantmentSlot keys
local ENCHANT_SLOT_VALUES = { MainHand = 0, OffHand = 1, Ranged = 2 }
local ROWS = {
    { key = "buffs", filter = "HELPFUL", slots = 32, lines = 4, enchants = true, cancel = true },
    { key = "debuffs", filter = "HARMFUL", slots = 16, lines = 2, harmful = true },
}
-- Top right beside the minimap cluster; the debuff rows sit under the four buff rows.
local DEFAULTS = {
    buffs = { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -200, y = -13 },
    debuffs = { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -200, y = -13 - 4 * STEP },
}
local STOCK_FRAMES = { "BuffFrame", "DebuffFrame" }
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

local function enumValue(enum, name, fallback)
    if type(enum) == "table" and enum[name] ~= nil then return enum[name] end
    return fallback
end

local function direction(name)
    local enum = type(AnchorUtil) == "table" and AnchorUtil.FlowDirection
    return enumValue(enum, name, DIRECTIONS[name])
end

local function configure(container, unit, flow)
    container:SetEditModePreviewEnabled(false)
    container:SetUnit(unit)
    container:SetFlowLayoutAnchorPoint(flow.anchor)
    container:SetFlowLayoutGrowthDirection(direction(flow.horizontal), direction(flow.vertical))
    container:SetFlowLayoutMaximumLineSize(flow.lineSize)
end

-- One Blizzard container per unit, or nil with one warning when the client lacks the template.
-- flow: anchor corner, horizontal and vertical growth names, maximum line size in pixels.
function auras.CreateContainer(name, parent, unit, flow)
    local ok, container = pcall(CreateFrame, CONTAINER_TYPE, FRAME_PREFIX .. name, parent, CONTAINER_TEMPLATE)
    if not ok then auras.Warn("container", container); return nil end
    local configured, reason = pcall(configure, container, unit, flow)
    if not configured then auras.Warn("container", reason); container:Hide(); return nil end
    return container
end

-- Runs a container population step; a failure hides the container and reports once.
function auras.Populate(container, populate, ...)
    local ok, reason = pcall(populate, container, ...)
    if ok then return true end
    auras.Warn("container", reason)
    container:Hide()
    return false
end

local function addEnchants(container, spec)
    for _, name in ipairs(ENCHANT_SLOTS) do
        local slot = enumValue(AuraContainerItemEnchantmentSlot, name, ENCHANT_SLOT_VALUES[name])
        container:AddItemEnchantment(slot, { initializeFrame = auras.Decorator(spec) })
    end
    container:SetItemEnchantmentLayout(auras.GroupLayout(spec.size))
end

local function populateRow(container, row)
    local spec = { size = SIZE, harmful = row.harmful, cancel = row.cancel }
    if row.enchants then addEnchants(container, spec) end
    container:AddAuraGroup(row.key, row.filter, auras.GroupOptions(spec, row.slots))
end

-- The proxy is a plain frame with the row's nominal footprint: it carries the layout key and
-- the mover box, while the container inside sizes itself to the visible auras.
local function createRow(row)
    local proxy = CreateFrame("Frame", FRAME_PREFIX .. row.key, UIParent)
    proxy:SetSize(LINE_SIZE, row.lines * STEP - GAP)
    local container = auras.CreateContainer(row.key .. "Container", proxy, "player", FLOW)
    if not container or not auras.Populate(container, populateRow, row) then proxy:Hide(); return nil end
    container:SetPoint(FLOW.anchor, proxy, FLOW.anchor, 0, 0)
    proxy.key, proxy.container = row.key, container
    layout.Register(proxy, row.key, DEFAULTS[row.key])
    auras.Rows[row.key] = proxy
    return proxy
end

local function replacementsReady()
    for _, row in ipairs(ROWS) do
        if not auras.Rows[row.key] then return false end
    end
    return true
end

local function hideStock()
    stockPending = false
    if not auras.enabled or not replacementsReady() then return end
    for _, name in ipairs(STOCK_FRAMES) do
        local frame = _G[name]
        -- No native handler must keep running: the RikUI containers own the player's auras now.
        if frame then core.Hide.Frame(frame, false) end
    end
end

function auras.UpdateStockVisibility()
    if stockPending then return end
    stockPending = true
    core.Combat.Queue(hideStock)
end

function auras:OnEnable()
    core.Combat.Queue(function()
        for _, row in ipairs(ROWS) do
            if not auras.Rows[row.key] then createRow(row) end
        end
        auras.UpdateStockVisibility()
    end)
    core:RegisterEvent("PLAYER_ENTERING_WORLD", auras.UpdateStockVisibility)
end

function auras.Count(containers)
    local total = 0
    for _ in pairs(containers) do total = total + 1 end
    return total
end

function auras:Debug(sample)
    core:Print("Auras containers=" .. auras.Count(auras.Rows) .. " combat=" .. tostring(InCombatLockdown()))
    sample("ShouldAurasBeSecret()", auras.Api("C_Secrets", "ShouldAurasBeSecret"))
    sample("GetAuraDataByIndex(player,1,HELPFUL)", auras.Api("C_UnitAuras", "GetAuraDataByIndex"), "player", 1, "HELPFUL")
end

core:RegisterModule("auras", auras)
