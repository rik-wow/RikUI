-- Synthetic character, isolated from the player's WTF and SavedVariables.
-- This addon loads first, so two simulator gaps are closed before RikUI creates its frames.
-- 1. The simulator never runs an AuraContainer's intrinsic OnLoad (Blizzard's
--    CustomAuraContainerPrivateMixin:OnLoad in the frame's private partition), so no container ever
--    creates a button. Running it right after creation is what the client does.
local createFrame = CreateFrame
CreateFrame = function(kind, ...)
    local frame = createFrame(kind, ...)
    if kind == "AuraContainer" and type(GetForbiddenObjectTable) == "function" then
        local private = GetForbiddenObjectTable(frame)
        if type(private) == "table" and type(private.OnLoad) == "function" and not private.rikRenderLoaded then
            private.rikRenderLoaded = true
            private:OnLoad()
        end
    end
    return frame
end
-- 2. The simulator's aura queries know HELPFUL and HARMFUL but drop every id when the filter adds
--    PLAYER, RAID or CANCELABLE. Those parts are applied here from the aura data the simulator
--    already returns.
local instanceIDs, auraData = C_UnitAuras.GetUnitAuraInstanceIDs, C_UnitAuras.GetAuraDataByAuraInstanceID
-- Buffs the simulator adds carry no caster; a fixture lists the ones the player cast here by spell id.
RikRenderOwnAuras = {}
local function holds(aura, part)
    if part == "PLAYER" then return aura.isFromPlayerOrPlayerPet == true or RikRenderOwnAuras[aura.spellId] == true end
    if part == "RAID" then return aura.isRaid == true end
    if part == "CANCELABLE" then return not aura.isHarmful end
    if part == "NOT_CANCELABLE" then return aura.isHarmful == true end
    return true
end
-- A part may be negated ("!PLAYER": other casters' auras).
local function accepts(aura, parts)
    for _, part in ipairs(parts) do
        local negated = part:sub(1, 1) == "!"
        local truth = holds(aura, negated and part:sub(2) or part)
        if truth == negated then return false end
    end
    return true
end
-- 3. A debuff the simulator adds answers the HARMFUL query but carries isHarmful == false in its aura
--    data, which sends it to Blizzard's nameplate buff list instead of the debuff list. The spell ids
--    added as debuffs are remembered so the data says what the client says.
RikRenderHarmful = {}
local addDebuff = A_Admin.AddDebuff
A_Admin.AddDebuff = function(spellId, ...)
    RikRenderHarmful[spellId] = true
    return addDebuff(spellId, ...)
end
-- Blizzard's containers also read the caster and the harm flag from the aura data itself.
local function correct(aura)
    if type(aura) ~= "table" then return aura end
    if RikRenderOwnAuras[aura.spellId] then aura.isFromPlayerOrPlayerPet, aura.sourceUnit = true, "player" end
    if RikRenderHarmful[aura.spellId] then aura.isHarmful, aura.isHelpful = true, false end
    -- The client answers false for an ordinary buff; the simulator leaves the field out, and Blizzard's
    -- enemy nameplate buff list treats a missing false as "keep".
    if aura.isStealable == nil then aura.isStealable = false end
    return aura
end
local important = C_Spell and C_Spell.IsSpellImportant
if type(important) == "function" then
    C_Spell.IsSpellImportant = function(...) return important(...) == true end
end
for _, name in ipairs({ "GetAuraDataByAuraInstanceID", "GetAuraDataByIndex", "GetAuraDataBySlot" }) do
    local reader = C_UnitAuras[name]
    if type(reader) == "function" then
        C_UnitAuras[name] = function(...) return correct(reader(...)) end
    end
end
-- Blizzard's nameplate aura lists read whole lists.
local unitAuras = C_UnitAuras.GetUnitAuras
if type(unitAuras) == "function" then
    C_UnitAuras.GetUnitAuras = function(...)
        local list = unitAuras(...) or {}
        for _, aura in ipairs(list) do correct(aura) end
        return list
    end
end
auraData = C_UnitAuras.GetAuraDataByAuraInstanceID
C_UnitAuras.GetUnitAuraInstanceIDs = function(unit, filter, ...)
    local base, parts = {}, {}
    for part in tostring(filter or ""):gmatch("[^|]+") do
        if part == "HELPFUL" or part == "HARMFUL" then base[#base + 1] = part else parts[#parts + 1] = part end
    end
    local ids = instanceIDs(unit, table.concat(base, "|"), ...) or {}
    if #parts == 0 then return ids end
    local kept = {}
    for _, id in ipairs(ids) do
        local aura = auraData(unit, id)
        if aura and accepts(aura, parts) then kept[#kept + 1] = id end
    end
    return kept
end
A_Admin.SetPlayerName("Rik")
A_Admin.SetPlayerClass(2)
A_Admin.SetPlayerRace(0)
A_Admin.SetPlayerLevel(10)
A_Admin.SetPlayerHealth(212, 220)
A_Admin.SetPlayerPower(287, 287, 0)
A_Admin.SetZone("Elwynn Forest", 37)
A_Admin.SetSubZone("Goldshire")
A_Admin.SetMoney(17342)
A_Admin.ClearActionBars()
for slot, spell in pairs({ [1]=679, [2]=20271, [3]=20287, [6]=853, [8]=1152, [9]=635, [11]=20287 }) do
    A_Admin.SetActionSlot(slot, spell)
end
A_Admin.SetTarget("Mangy Wolf", 5, 1, true)
A_Admin.SetTargetHealth(57, 102)
A_Admin.SetTargetPower(0, 0, 1)
A_Admin.SetFocus("Mira", 10, 5, false)
A_Admin.SetFocusHealth(176, 210)
A_Admin.SetFocusPower(240, 300, 0)

-- The saved account settings of a player who chose "Reduce cosmetic motion": RikUI reads that startup
-- setting once at login, and the headless simulator never finishes an entrance animation, so every
-- capture shows its element at rest. Everything else stays at RikUI's defaults.
RikUIDB = { version = 1, profiles = { Default = { reducedMotion = true } } }

-- 2. The simulator keeps macros it creates but answers GetMacroInfo with nothing, so RikUI's restart
--    backup (a macro it writes and reads back) reports "the client did not retain the restart backup
--    macro" on every run. A client keeps macros; this in-memory copy behaves like one for the session.
local macroStore = {}
local function macroSlot(key)
    if type(key) == "number" then return macroStore[key] and key or nil end
    for index, entry in ipairs(macroStore) do
        if entry.name == key then return index end
    end
end
function GetNumMacros() return #macroStore, 0 end
function GetMacroIndexByName(name) return macroSlot(name) or 0 end
function GetMacroInfo(key)
    local slot = macroSlot(key)
    local entry = slot and macroStore[slot]
    if not entry then return nil end
    return entry.name, entry.icon, entry.body, false
end
function GetMacroBody(key)
    local slot = macroSlot(key)
    return slot and macroStore[slot].body or nil
end
function CreateMacro(name, icon, body)
    if type(name) ~= "string" or name == "" or #macroStore >= 138 then return nil end
    macroStore[#macroStore + 1] = { name = name, icon = icon, body = body or "" }
    return #macroStore
end
function EditMacro(key, name, icon, body)
    local slot = macroSlot(key)
    if not slot then return nil end
    local entry = macroStore[slot]
    entry.name, entry.icon, entry.body = name or entry.name, icon or entry.icon, body or entry.body
    return slot
end
function DeleteMacro(key)
    local slot = macroSlot(key)
    if slot then table.remove(macroStore, slot) end
end
