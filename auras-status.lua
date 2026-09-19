-- Aura and enchant readers and their sinks. Aura values are never compared unless issecretvalue
-- says they are readable; timers come from the client's duration object or from readable times.
local core, auras = RikUI, RikUI.Auras
local PLAYER, MIN_COUNT, COUNT_FORMAT, MILLISECONDS = "player", 2, "%d", 1000
local ENCHANT_SLOTS = { 16, 17, 18 } -- INVSLOT_MAINHAND, INVSLOT_OFFHAND, INVSLOT_RANGED
local PLAYER_UNITS = { player = true, pet = true, vehicle = true }
local colors = {
    buff = { 0.25, 0.28, 0.32 },
    none = { 0.8, 0, 0 },
    Magic = { 0.2, 0.6, 1 },
    Curse = { 0.6, 0, 1 },
    Disease = { 0.6, 0.4, 0 },
    Poison = { 0, 0.6, 0 },
}
auras.Colors = colors
-- Auras another caster applied shrink to this scale and dim their icon to this alpha.
local emphasis = { scale = 0.75, alpha = 0.5 }
auras.Emphasis = emphasis
local enchantMemory = {}

local function readable(value, kind)
    return not core.Secret.IsSecret(value) and type(value) == kind
end

-- Secret values are never compared, not even against nil.
local function present(value)
    return core.Secret.IsSecret(value) or value ~= nil
end

local function boolean(value)
    if core.Secret.IsSecret(value) then return value end
    return value == true
end

local function api(namespace, name)
    local table = _G[namespace]
    if type(table) ~= "table" or type(table[name]) ~= "function" then return nil end
    return table[name]
end

-- A secret aura record cannot be indexed, so the row treats it like a throwing read.
local function readAura(unit, index, filter)
    local reader = api("C_UnitAuras", "GetAuraDataByIndex")
    if not reader then error("C_UnitAuras.GetAuraDataByIndex unavailable", 0) end
    local aura = reader(unit, index, filter)
    if core.Secret.IsSecret(aura) then error("aura record is secret", 0) end
    return aura
end

local function readEnchant(slot)
    local reader = api("C_PaperDollInfo", "GetTemporaryEnchantmentInfo")
    if not reader then return nil end
    local ok, info = core.Secret.Read(reader, slot)
    if not ok then auras.Warn("enchant", info); return nil end
    if core.Secret.IsSecret(info) or type(info) ~= "table" then return nil end
    return info
end

local function collectEnchants(entries)
    for _, slot in ipairs(ENCHANT_SLOTS) do
        local info = readEnchant(slot)
        if info then entries[#entries + 1] = { unit = PLAYER, slot = slot, info = info } end
    end
end

local function collect(row)
    local entries = {}
    if row.enchants then collectEnchants(entries) end
    for index = 1, row.slots - #entries do
        local aura = readAura(row.unit, index, row.filter)
        if not aura then break end
        entries[#entries + 1] = { unit = row.unit, index = index, filter = row.filter, aura = aura }
    end
    return entries
end

local function setIcon(button, entry)
    if entry.aura then button.icon:SetTexture(entry.aura.icon); return end
    local ok, texture = core.Secret.Read(GetInventoryItemTexture, PLAYER, entry.slot)
    if not ok then auras.Warn("enchant icon", texture); texture = nil end
    button.icon:SetTexture(texture)
end

-- The client formats the count and applies the minimum, so a secret count still displays.
local function displayCount(entry)
    local reader = api("C_UnitAuras", "GetAuraApplicationDisplayCount")
    if not reader or not readable(entry.aura.auraInstanceID, "number") then return nil end
    local ok, count = core.Secret.Read(reader, entry.unit, entry.aura.auraInstanceID, MIN_COUNT)
    if not ok then auras.Warn("count", count); return nil end
    if present(count) then return count end
    return nil
end

local function applications(entry)
    if entry.aura then return entry.aura.applications end
    return entry.info.chargesRemaining
end

local function setCount(button, entry)
    local text = entry.aura and displayCount(entry)
    if present(text) then button.count:SetText(text); return end
    local count = applications(entry)
    if readable(count, "number") and count >= MIN_COUNT then
        button.count:SetFormattedText(COUNT_FORMAT, count)
    else
        button.count:SetText("")
    end
end

local function borderColor(entry)
    if not entry.aura or entry.filter == "HELPFUL" then return colors.buff end
    local dispel = entry.aura.dispelName
    if readable(dispel, "string") then return colors[dispel] or colors.none end
    return colors.none
end

local function setBorder(button, entry)
    local color = borderColor(entry)
    for _, line in ipairs(button.border) do line:SetVertexColor(color[1], color[2], color[3], 1) end
end

-- Whether the player or their pet applied the aura: the record flag when present, otherwise a
-- readable source token; unknown ownership keeps the aura at full size.
local function ownAura(aura)
    local flag = aura.isFromPlayerOrPlayerPet
    if present(flag) then return flag end
    local source = aura.sourceUnit
    if readable(source, "string") then return PLAYER_UNITS[source] == true end
    return true
end

-- A secret flag reaches only the alpha sink; the scale changes only on a readable false.
local function setEmphasis(button, entry)
    local own = ownAura(entry.aura)
    button.icon:SetAlphaFromBoolean(boolean(own), 1, emphasis.alpha)
    local scale = 1
    if readable(own, "boolean") and not own then scale = emphasis.scale end
    button:SetScale(scale)
end

local function durationObject(entry)
    local reader = api("C_UnitAuras", "GetAuraDuration")
    if not reader or not readable(entry.aura.auraInstanceID, "number") then return nil end
    local ok, duration = core.Secret.Read(reader, entry.unit, entry.aura.auraInstanceID)
    if not ok then auras.Warn("duration", duration); return nil end
    if core.Secret.IsSecret(duration) then return nil end
    return duration
end

local function applyObject(widget, object)
    local ok, reason = pcall(widget.SetCooldownFromDurationObject, widget, object, true)
    if not ok then auras.Warn("timer", reason) end
    return ok
end

local function setAuraTimer(widget, entry)
    local object = durationObject(entry)
    if object ~= nil and applyObject(widget, object) then return end
    local duration, expiration = entry.aura.duration, entry.aura.expirationTime
    if readable(duration, "number") and readable(expiration, "number") and duration > 0 then
        widget:SetCooldown(expiration - duration, duration)
    else
        widget:Clear()
    end
end

local function timedEnchant(info)
    return readable(info.hasExpirationTime, "boolean") and info.hasExpirationTime
        and readable(info.remainingTimeMs, "number") and readable(info.enchantID, "number")
end

-- The client reports only the remaining time, so the duration is the remaining time seen
-- when an enchant first appears or is refreshed, as Blizzard's own container does.
local function snapshotDuration(slot, info)
    local memory, remaining = enchantMemory[slot], info.remainingTimeMs / MILLISECONDS
    if not memory or memory.enchantID ~= info.enchantID or remaining > memory.remaining then
        memory = { enchantID = info.enchantID, duration = remaining }
        enchantMemory[slot] = memory
    end
    memory.remaining = remaining
    return memory.duration, remaining
end

local function setEnchantTimer(widget, entry)
    if not timedEnchant(entry.info) then
        enchantMemory[entry.slot] = nil
        widget:Clear()
        return
    end
    local duration, remaining = snapshotDuration(entry.slot, entry.info)
    widget:SetCooldown(GetTime() + remaining - duration, duration)
end

local function apply(button, entry, emphasise)
    button.entry = entry
    setIcon(button, entry)
    setCount(button, entry)
    setBorder(button, entry)
    if entry.aura then setAuraTimer(button.cooldown, entry) else setEnchantTimer(button.cooldown, entry) end
    if emphasise and entry.aura then setEmphasis(button, entry) end
    button:Show()
end

local function clear(button)
    if not button.entry then return end
    button.entry = nil
    button.cooldown:Clear()
    button:Hide()
end

local function syncCancelButton(button, entry)
    if not entry then button:Hide(); return end
    button:SetAttribute("index", entry.index)
    button:SetAttribute("filter", entry.filter)
    button:SetAttribute("target-slot", entry.slot)
    button:Show()
end

local function applyCancel(row)
    row.cancelPending = false
    if not row.cancel then return end
    for index, button in ipairs(row.cancel.buttons) do syncCancelButton(button, row.entries[index]) end
end

local function queueCancel(row)
    if not row.cancel or row.cancelPending then return end
    row.cancelPending = true
    core.Combat.Queue(function() applyCancel(row) end)
end

local function draw(row, entries)
    row.entries = entries
    for index, button in ipairs(row.buttons) do
        local entry = entries[index]
        if entry then apply(button, entry, row.emphasis) else clear(button) end
    end
    queueCancel(row)
end

local function anyBlocked(rows)
    for _, row in pairs(rows) do
        if row.blocked then return true end
    end
    return false
end

function auras.ClearRow(row)
    draw(row, {})
end

-- A read that throws or returns a secret record keeps the last display until the next
-- event or the end of combat; the owning module's /rik debug line reports the blocked state.
function auras.RefreshRow(row)
    local ok, entries = pcall(collect, row)
    row.blocked = not ok
    if ok then draw(row, entries) else row.module.Warn("read", entries) end
    row.module.blocked = anyBlocked(row.module.Rows)
end

function auras.FirstAuraInstance(unit, filter)
    local ok, aura = pcall(readAura, unit, 1, filter)
    if not ok or not aura then return nil end
    local id = aura.auraInstanceID
    if readable(id, "number") then return id end
    return nil
end
