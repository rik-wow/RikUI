-- Aura cells: a strip cell whose static icon sits under one of the client's aura slots. The
-- slot shows the aura's icon and timer while the aura is present and hides otherwise, so an
-- inactive cell reads as "not up" (a seal that dropped, a DoT that expired). Two secure
-- containers, one per unit, host the slots; RikUI places and decorates a slot frame and never
-- reads what it shows.
local core, panel = RikUI, RikUI.Cooldowns
local cells = {}
panel.Cells = cells
local UNITS = { player = { filter = "HELPFUL" }, target = { filter = "HARMFUL|PLAYER", harmful = true } }
local FLOW = { anchor = "TOPLEFT", horizontal = "Right", vertical = "Down", lineSize = 1 }
local LEVEL_ABOVE = 5
local containers, slots = {}, { player = {}, target = {} }

local function key(index) return "cell" .. index end

local function host(unit)
    if containers[unit] ~= nil then return containers[unit] or nil end
    local auras = core.Auras
    local frame = auras and auras.CreateContainer
        and auras.CreateContainer("cooldowns_" .. unit, panel.Strip.Frame, unit, FLOW)
    if frame then frame:SetPoint("TOPLEFT", panel.Strip.Frame, "TOPLEFT", 0, 0) end
    containers[unit] = frame or false
    return frame or nil
end

local function create(container, unit, index, ids)
    local frame = container:AddAuraSlot(key(index), UNITS[unit].filter, {
        initializeFrame = core.Auras.Decorator({ size = panel.Strip.SIZE, harmful = UNITS[unit].harmful }),
        candidateFilters = { includeSpellIDs = ids },
    })
    slots[unit][index] = frame
    return frame
end

local function attach(unit, index, button, ids)
    local container = host(unit)
    if not container then return end
    local frame = slots[unit][index]
    if frame then
        container:SetAuraSlotCandidateFilters(key(index), { includeSpellIDs = ids })
        container:SetAuraSlotEnabled(key(index), true)
    else
        frame = create(container, unit, index, ids)
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    frame:SetFrameLevel(button:GetFrameLevel() + LEVEL_ABOVE)
end

local function detach(unit, index)
    if slots[unit][index] then host(unit):SetAuraSlotEnabled(key(index), false) end
end

-- Bind cell `index` to one unit's aura set (`aura = { unit, ids }`) or to none. Slots are created
-- once per index and unit; the container never removes them, so later binds refilter in place.
function cells.Attach(index, button, aura)
    for unit in pairs(UNITS) do
        local ok, reason
        if aura and aura.unit == unit then ok, reason = pcall(attach, unit, index, button, aura.ids)
        else ok, reason = pcall(detach, unit, index) end
        if not ok then panel.Warn("cell", reason) end
    end
end

function cells.Trim(count)
    for unit in pairs(UNITS) do
        for index in pairs(slots[unit]) do
            if index > count then
                local ok, reason = pcall(detach, unit, index)
                if not ok then panel.Warn("cell", reason) end
            end
        end
    end
end

local function refresh(unit)
    local container = containers[unit]
    if not container then return end
    local ok, reason = pcall(container.UpdateAllAuras, container)
    if not ok then panel.Warn("cell refresh", reason) end
end

function cells.Enable()
    core:RegisterEvent("PLAYER_TARGET_CHANGED", function() refresh("target") end, panel)
    core:RegisterEvent("PLAYER_ENTERING_WORLD", function() refresh("player"); refresh("target") end, panel)
end
