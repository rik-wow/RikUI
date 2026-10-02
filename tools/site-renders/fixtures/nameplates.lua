-- Nameplates: stand-in units and Blizzard's nameplate driver over the world plate.

-- Nameplates. The simulator has no 3D world, so C_NamePlate never hands out a plate. Blizzard's own
-- driver and templates build the plates here (Blizzard_NamePlates, NamePlateScriptBaseMixin for the
-- engine methods a script plate lacks), and each plate's unit token answers through a unit the
-- simulator already has: every Unit* and C_UnitAuras reader maps the token to that unit. RikUI's
-- nameplate module then runs its normal NAME_PLATE_UNIT_ADDED path. The plates stand over the
-- creatures recorded with the world plate (RikRenderWorld.actors, written by plates.mjs).
local PLATE_UNITS, PLATE_CASTS, PLATE_AURAS, PLATE_CLASS, PLATE_THREAT = {}, {}, {}, {}, {}

local PLATE_READERS, PLATE_NOT_TARGET = {}, {}

local plateShimsReady = false

local function plateUnit(unit)
    if type(unit) == "string" then return PLATE_UNITS[unit] or unit end
    return unit
end

local function installPlateShims()
    if plateShimsReady then return end
    plateShimsReady = true
    local unitFunctions = {}
    for name, fn in pairs(_G) do
        if type(fn) == "function" and name:match("^Unit[A-Z]") then unitFunctions[name] = fn end
    end
    for name, fn in pairs(unitFunctions) do
        local castReader = name:match("^UnitCasting") or name:match("^UnitChannel")
        -- Either argument may be the plate token: UnitIsFriend("player", token) asks about the token.
        _G[name] = function(unit, second, ...)
            local readers = type(unit) == "string" and PLATE_READERS[unit] or type(second) == "string" and PLATE_READERS[second]
            if readers and readers[name] then return unpack(readers[name]) end
            if castReader and type(unit) == "string" and PLATE_CASTS[unit] then return fn(PLATE_CASTS[unit], plateUnit(second), ...) end
            return fn(plateUnit(unit), plateUnit(second), ...)
        end
    end
    local auraFunctions = {}
    for name, fn in pairs(C_UnitAuras) do
        if type(fn) == "function" then auraFunctions[name] = fn end
    end
    for name, fn in pairs(auraFunctions) do
        C_UnitAuras[name] = function(unit, ...)
            if type(unit) == "string" and PLATE_AURAS[unit] then return fn(PLATE_AURAS[unit], ...) end
            return fn(plateUnit(unit), ...)
        end
    end
    local baseClassification, baseThreat, baseDetailed, baseIsUnit = UnitClassification, UnitThreatSituation, UnitDetailedThreatSituation, UnitIsUnit
    UnitClassification = function(unit) return PLATE_CLASS[unit] or baseClassification(unit) end
    -- Threat exists only where a scenario says so; the client answers nil out of combat, and the
    -- simulator would answer 0% for every unit.
    UnitThreatSituation = function(unit, other)
        local level = PLATE_THREAT[unit] or PLATE_THREAT[other]
        if level then return level end
        if PLATE_UNITS[unit] or PLATE_UNITS[other] then return nil end
        return baseThreat(unit, other)
    end
    UnitDetailedThreatSituation = function(unit, other)
        local level = PLATE_THREAT[unit] or PLATE_THREAT[other]
        if level then return level >= 2, level, 100, 100, 1200 end
        if PLATE_UNITS[unit] or PLATE_UNITS[other] then return nil end
        return baseDetailed(unit, other)
    end
    -- A plate token is only ever the unit it stands for; soft targets stay out of a capture.
    UnitIsUnit = function(a, b)
        if type(a) == "string" and a:match("^soft") or type(b) == "string" and b:match("^soft") then return false end
        if a == b then return true end
        if PLATE_NOT_TARGET[a] or PLATE_NOT_TARGET[b] then return false end
        local ma, mb = plateUnit(a), plateUnit(b)
        if ma == mb then return true end
        if PLATE_UNITS[a] or PLATE_UNITS[b] then return false end
        return baseIsUnit(ma, mb) == true
    end
    -- Readers the simulator lacks for compact unit frames; the answers are the quiet defaults.
    local defaults = { UnitTreatAsPlayerForDisplay = false, UnitIsBossMob = false, UnitNameplateShowsWidgetsOnly = false,
        UnitShouldDisplayName = true, UnitWidgetSet = nil, UnitIsOwnerOrControllerOfUnit = false, UnitIsBattlePetCompanion = false,
        UnitIsWildBattlePet = false, UnitPhaseReason = nil, UnitInPartyShard = true, UnitGetTotalAbsorbs = 0,
        UnitGetTotalHealAbsorbs = 0, UnitGetIncomingHeals = 0, UnitHasIncomingResurrection = false, UnitSelectionType = 0,
        UnitIsInteractable = true, UnitHasEffectivelyTankAura = false, UnitIsBehindCamera = false, PlayerIsSpellTarget = false,
        UnitShouldDisplaySpellTargetName = false,
        GetSpecialization = 1, GetSpecializationSystem = 0, GetSpecializationRole = "DAMAGER" }
    for name, value in pairs(defaults) do
        if rawget(_G, name) == nil then _G[name] = function() return value end end
    end
    -- Readers whose quiet answer is nil (a table literal cannot hold those).
    for _, name in ipairs({ "UnitWidgetSet", "UnitPhaseReason" }) do
        if rawget(_G, name) == nil then _G[name] = function() return nil end end
    end
    GetRaidTargetIndex = function() return nil end
    -- The plate's loss-of-control lookup indexes a constant the simulator lacks.
    if type(Constants) == "table" then
        Constants.LossOfControlConsts = Constants.LossOfControlConsts or {}
        Constants.LossOfControlConsts.LOSS_OF_CONTROL_ACTIVE_INDEX = Constants.LossOfControlConsts.LOSS_OF_CONTROL_ACTIVE_INDEX or 1
    end
    -- The level badge colour needs the quest trivial range; the simulator answers nil.
    if C_QuestLog and not (type(C_QuestLog.GetTrivialRange) == "function" and C_QuestLog.GetTrivialRange()) then
        C_QuestLog.GetTrivialRange = function() return 5 end
    end
    -- The simulator's colour objects refuse a number in WrapTextInColorCode and Blizzard passes the
    -- level as one; when Blizzard's update fails, the same text is set from a string.
    local updateLevelDiff = CompactUnitFrame_UpdatePlayerLevelDiff
    CompactUnitFrame_UpdatePlayerLevelDiff = function(frame)
        if pcall(updateLevelDiff, frame) then return end
        local badge = frame.PlayerLevelDiffFrame
        if not badge or not badge:ShouldDisplay(frame.unit) then return end
        local level = UnitEffectiveLevel(frame.unit)
        local color = UNIT_LEVEL_NON_ATTACKABLE
        if UnitCanAttack("player", frame.unit) then color = badge:GetDifficultyColor(level - UnitEffectiveLevel("player")) end
        badge.playerLevelDiffText:SetText(color:WrapTextInColorCode(tostring(level)))
        if badge.highLevelTexture then
            badge.highLevelTexture:SetShown(level <= 0)
            badge.playerLevelDiffText:SetShown(level > 0)
        end
        badge:Show()
    end
    assert(C_AddOns.LoadAddOn("Blizzard_NamePlates"))
    -- The simulator's aura data carries no nameplate display flags, and its registry answers true
    -- for the show-all-personal-auras setting; the client's default is off.
    if type(NamePlateConstants) == "table" and NamePlateConstants.SHOW_ALL_PERSONAL_AURAS_CVAR then
        RikRenderNameplateCVar(NamePlateConstants.SHOW_ALL_PERSONAL_AURAS_CVAR, "0")
    end
end

-- A nameplate CVar as Blizzard's registry reports it (the simulator's SetCVar does not reach the registry).
function RikRenderNameplateCVar(name, value)
    local registry = CVarCallbackRegistry
    local getBool, getValue = registry.GetCVarValueBool, registry.GetCVarValue
    registry.GetCVarValueBool = function(self, cvar, ...)
        if cvar == name then return value == "1" or value == true end
        return getBool(self, cvar, ...)
    end
    if getValue then
        registry.GetCVarValue = function(self, cvar, ...)
            if cvar == name then return tostring(value) end
            return getValue(self, cvar, ...)
        end
    end
end

-- Another unit's cast reads answer with the player's cast (the simulator casts only for the player):
-- call RikRenderCast first, then this, then fire the unit's cast event.
function RikRenderCastAlias(unit)
    installPlateShims()
    PLATE_CASTS[unit] = "player"
    A_Admin.FireEvent("UNIT_SPELLCAST_START", unit)
end

-- A unit token the simulator lacks answers as another unit (target of target as the player).
function RikRenderUnitAlias(token, unit)
    installPlateShims()
    PLATE_UNITS[token] = unit
end

-- A creature the simulator does not have: readers answer for this token with fixed values.
-- reaction: "hostile" (default), "neutral" or "friendly"; the colour and attackability follow it.
local REACTIONS = {
    hostile = { UnitReaction = { 2 }, UnitCanAttack = { true }, UnitIsEnemy = { true }, UnitIsFriend = { false }, UnitSelectionColor = { 1, 0, 0, 1 } },
    neutral = { UnitReaction = { 4 }, UnitCanAttack = { true }, UnitIsEnemy = { false }, UnitIsFriend = { false }, UnitSelectionColor = { 1, 1, 0, 1 } },
    friendly = { UnitReaction = { 5 }, UnitCanAttack = { false }, UnitIsEnemy = { false }, UnitIsFriend = { true }, UnitSelectionColor = { 0, 1, 0, 1 } },
}

function RikRenderCreature(name, level, health, healthMax, reaction, extra)
    local readers = { UnitName = { name }, UnitLevel = { level }, UnitEffectiveLevel = { level },
        UnitHealth = { health }, UnitHealthMax = { healthMax or health }, UnitIsPlayer = { false },
        UnitClass = { nil }, UnitClassBase = { nil }, UnitIsTapDenied = { false }, UnitIsDead = { false },
        UnitIsDeadOrGhost = { false }, UnitIsConnected = { true }, UnitExists = { true },
        UnitCreatureType = { "Beast" }, UnitIsPVP = { false }, UnitPower = { 0 }, UnitPowerMax = { 0 } }
    for key, value in pairs(REACTIONS[reaction or "hostile"]) do readers[key] = value end
    for key, value in pairs(extra or {}) do readers[key] = value end
    return readers
end

-- entries: { { unit = "target", actor = "Mangy Wolf", nth = 1, screen = { x, y }, classification = "elite",
--              threat = 3, castFrom = "player", aurasFrom = "player", notTarget = true,
--              readers = RikRenderCreature("Young Wolf", 1, 30) }, ... }
-- The plates become children of a capture root covering the crop; the root is returned.
local PLATE_LIFT = 26

function RikRenderNameplates(entries, name, left, bottom, width, height)
    installPlateShims()
    local holder = CreateFrame("Frame", name or "RikRenderNameplates", UIParent)
    holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left or 0, bottom or 0)
    holder:SetSize(width or UIParent:GetWidth(), height or UIParent:GetHeight())
    local plates, list, tokens = {}, {}, {}
    C_NamePlate.GetNamePlateForUnit = function(unit) return plates[unit] end
    C_NamePlate.GetNamePlates = function() return list end
    local screenHeight = UIParent:GetHeight()
    for index, entry in ipairs(entries) do
        local token = "nameplate" .. index
        PLATE_UNITS[token] = entry.unit or "target"
        PLATE_CASTS[token], PLATE_AURAS[token] = entry.castFrom, entry.aurasFrom
        PLATE_CLASS[token], PLATE_THREAT[token] = entry.classification, entry.threat
        PLATE_READERS[token], PLATE_NOT_TARGET[token] = entry.readers, entry.notTarget
        local spot = entry.screen or RikRenderActor(entry.actor, entry.nth)
        local base = CreateFrame("Frame", "RikRenderNamePlate" .. index, holder)
        base:SetSize(160, 50)
        base:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", spot.x, screenHeight - spot.y + PLATE_LIFT)
        Mixin(base, NamePlateScriptBaseMixin)
        NamePlateDriverFrame:OnNamePlateCreated(base)
        plates[token], list[#list + 1], tokens[#tokens + 1] = base, base, token
    end
    -- Blizzard's driver acquires the unit frame on this event; RikUI's handler follows it.
    for _, token in ipairs(tokens) do A_Admin.FireEvent("NAME_PLATE_UNIT_ADDED", token) end
    for _, token in ipairs(tokens) do
        if PLATE_CASTS[token] then A_Admin.FireEvent("UNIT_SPELLCAST_START", token) end
    end
    RikRenderResize(holder)
    RikRenderRemeasure(holder)
    return holder, plates
end
-- Recycle the driver's plate for a new public sample name. Blizzard updates text and RikUI
-- receives the real removal/addition events; no addon regions are resized by the fixture.
function RikRenderPlateReuse(token, name)
    assert(PLATE_READERS[token], "No sample readers for " .. token)
    A_Admin.FireEvent("NAME_PLATE_UNIT_REMOVED", token)
    PLATE_READERS[token].UnitName = { name }
    A_Admin.FireEvent("NAME_PLATE_UNIT_ADDED", token)
end
