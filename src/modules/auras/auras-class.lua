-- Curated class effects plus the client's tracked and aura-backed cooldown entries, filtered and
-- rendered by the client's secure aura containers. Never read aura values, inspect pooled
-- buttons, infer missing buffs, or run expiry timers.
local core, auras = RikUI, RikUI.Auras
local tracker = { title = "Class effects", Rows = {}, native = { player = {}, target = {} } }
core.ClassAuras = tracker
core.ClassAuraProfiles = core.ClassAuraProfiles or {}
local SIZE, GAP, PER_LINE, MAX_PLAYER, MAX_TARGET = 28, 4, 6, 12, 6
local WIDTH, HEIGHT = PER_LINE * (SIZE + GAP) - GAP, 2 * (SIZE + GAP) - GAP
local FLOW = { anchor = "TOPLEFT", horizontal = "Right", vertical = "Down", lineSize = WIDTH }
local NATIVE_KEY = "classauras-native"
local warnings, nativeSignature = {}, ""
local ROWS = {
    { key = "player", unit = "player", layout = "classbuffs", label = "Buffs", x = -WIDTH - GAP / 2 },
    { key = "target", unit = "target", layout = "classeffects", label = "Target effects", x = GAP / 2 },
}
-- Which native set each group draws from: the player's own auras, or the player's effects on the target.
local GROUPS = {
    player = { filter = "HELPFUL", max = MAX_PLAYER, native = "player" },
    harmful = { filter = "HARMFUL|PLAYER", max = MAX_TARGET, harmful = true, native = "target" },
    helpful = { filter = "HELPFUL|PLAYER", max = MAX_TARGET, native = "target" },
}

local function warn(key, reason)
    if warnings[key] then return end
    warnings[key] = true
    core:Print("Class auras " .. key .. ": " .. tostring(reason))
end

-- Expand only this class's published rank families. An unknown name must not become an unfiltered group.
function tracker.SpellIDs(class, names)
    if type(names) ~= "table" then return nil, "spell list unavailable" end
    local ids = {}
    for _, name in ipairs(names) do
        local entry = core.Spells and core.Spells.Entry(name, class)
        if not entry or type(entry.ranks) ~= "table" or #entry.ranks == 0 then
            return nil, "unknown class spell " .. tostring(name)
        end
        for _, id in ipairs(entry.ranks) do
            if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then return nil, "invalid spell ID" end
            ids[id] = true
        end
    end
    return ids
end

local function group(container, key, ids, newLine, reserve)
    if not ids or next(ids) == nil then return end
    local spec = GROUPS[key]
    local options = auras.GroupOptions({ size = SIZE, harmful = spec.harmful }, spec.max - (reserve or 0), newLine)
    options.candidateFilters = { includeSpellIDs = ids }
    container:AddAuraGroup(key, spec.filter, options)
end

local function enchants(container)
    local slots = AuraContainerItemEnchantmentSlot or { MainHand = 0, OffHand = 1 }
    for _, name in ipairs({ "MainHand", "OffHand" }) do
        container:AddItemEnchantment(slots[name], { initializeFrame = auras.Decorator({ size = SIZE }) })
    end
    container:SetItemEnchantmentLayout(auras.GroupLayout(SIZE))
end

local function populate(container, row, filters, profile)
    if row.key == "player" then
        if profile.enchants then enchants(container) end
        group(container, "player", filters.player, false, profile.enchants and 2 or 0)
    else
        group(container, "harmful", filters.harmful)
        group(container, "helpful", filters.helpful, next(filters.harmful) ~= nil)
    end
end

local function groupKeys(row)
    return row.key == "player" and { "player" } or { "harmful", "helpful" }
end

-- Profile families plus the native IDs for the group's unit. Include lists are whitelists, so a
-- native ID of the wrong polarity never matches and needs no separate handling.
local function filtersFor(row, class, profile)
    local filters = {}
    for _, key in ipairs(groupKeys(row)) do
        local ids, reason = tracker.SpellIDs(class, profile[key] or {})
        if not ids then return nil, reason end
        for id in pairs(tracker.native[GROUPS[key].native] or {}) do ids[id] = true end
        filters[key] = ids
    end
    return filters
end

local function createRow(row, class, profile)
    local filters, reason = filtersFor(row, class, profile)
    if not filters then warn(row.key, reason); return end
    local populated = row.key == "player" and profile.enchants
    for _, ids in pairs(filters) do populated = populated or next(ids) ~= nil end
    if not populated then return end
    local proxy = CreateFrame("Frame", "RikUIClassAuras_" .. row.key, UIParent)
    proxy:SetSize(WIDTH, HEIGHT)
    proxy:EnableMouse(false)
    local container = auras.CreateContainer("class_" .. row.key, proxy, row.unit, FLOW)
    if not container or not auras.Populate(container, populate, row, filters, profile) then proxy:Hide(); return end
    container:SetPoint("TOPLEFT", proxy, "TOPLEFT", 0, 0)
    proxy.container = container
    core.Layout.Register(proxy, row.layout,
        { point = "TOPLEFT", relativePoint = "TOP", x = row.x, y = -300 }, { label = row.label })
    tracker.Rows[row.key] = proxy
end

local function context()
    if tracker.enabled == false then return nil end
    local ok, _, class = core.Secret.Read(UnitClass, "player")
    if not ok or core.Secret.IsSecret(class) then return nil end
    local profile = core.ClassAuraProfiles[class]
    if type(profile) ~= "table" then return nil end
    return class, profile
end

local function build()
    local class, profile = context()
    if not class then return end
    for _, row in ipairs(ROWS) do
        if not tracker.Rows[row.key] then createRow(row, class, profile) end
    end
end

-- Existing groups take the merged filters in place (the container never drops a group); a group
-- or row that was never created because its set was empty is created now.
local function refilter(row, class, profile)
    local proxy = tracker.Rows[row.key]
    if not proxy then createRow(row, class, profile); return end
    local filters, reason = filtersFor(row, class, profile)
    if not filters then warn(row.key, reason); return end
    local container = proxy.container
    for _, key in ipairs(groupKeys(row)) do
        local ids = filters[key]
        local ok, problem = true, nil
        if container:HasAuraGroup(key) then
            ok, problem = pcall(container.SetAuraGroupCandidateFilters, container, key, { includeSpellIDs = ids })
        elseif next(ids) ~= nil then
            ok, problem = pcall(group, container, key, ids, key == "helpful" and next(filters.harmful) ~= nil)
        end
        if not ok then warn("native", problem) end
    end
end

local function applyNative()
    local class, profile = context()
    if not class then return end
    for _, row in ipairs(ROWS) do refilter(row, class, profile) end
end

local function signature(sets)
    local ids = {}
    for _, unit in ipairs({ "player", "target" }) do
        for id in pairs(sets[unit]) do ids[#ids + 1] = unit .. ":" .. id end
    end
    table.sort(ids)
    return table.concat(ids, ",")
end

-- The cooldown strip hands over the client's tracked and aura-backed entries: spell IDs whose
-- auras belong on the player row or on the target row. Unchanged sets touch nothing.
function tracker.SetNativeAuraIDs(sets)
    if type(sets) ~= "table" or type(sets.player) ~= "table" or type(sets.target) ~= "table" then return nil, "invalid aura sets" end
    local next = signature(sets)
    if next == nativeSignature then return true end
    nativeSignature, tracker.native = next, { player = sets.player, target = sets.target }
    core.Combat.Queue(applyNative, NATIVE_KEY)
    return true
end

local function refresh(key)
    local row = tracker.Rows[key]
    if not row then return end
    local ok, reason = pcall(row.container.UpdateAllAuras, row.container)
    if not ok then warn("refresh", reason) end
    local shown, failure = pcall(row.SetShown, row, ok)
    if not shown then warn("visibility", failure) end
end

function tracker:OnEnable()
    core.Combat.Queue(build)
    core:RegisterEvent("PLAYER_TARGET_CHANGED", function() refresh("target") end)
    core:RegisterEvent("PLAYER_ENTERING_WORLD", function() refresh("player"); refresh("target") end)
end

function tracker:Debug()
    core:Print("Class auras rows=" .. auras.Count(tracker.Rows) .. " (native filtered effects; absence is not a warning)")
end

core:RegisterModule("classauras", tracker)

