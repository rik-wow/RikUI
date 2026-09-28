-- Development fixture only; never loaded by RikUI.
assert(A_Admin and RikUI and RikUI.Runtime.loggedIn, "RikUI did not finish startup")
RikUI.Profile.reducedMotion = true
RikUI.Wizard.Close()
if GameMenuFrame then GameMenuFrame:Hide() end

function RikRenderCenter(frame, scale)
    assert(frame, "Missing preview frame")
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetScale(scale or 1)
end

-- The headless simulator does not emit OnSizeChanged. Deliver the actual
-- callbacks using calculated sizes, leaving RikUI's layout code untouched.
function RikRenderResize(root)
    local previous = {}
    -- Secure aura frames refuse readouts from this tainted fixture; they lay themselves out.
    local function visit(frame)
        local readable, width, height = pcall(frame.GetSize, frame)
        if not readable then return end
        local old = previous[frame]
        if not old or old[1] ~= width or old[2] ~= height then
            previous[frame] = { width, height }
            local callback = frame:GetScript("OnSizeChanged")
            if callback then callback(frame, width, height) end
        end
        local listed, children = pcall(function() return { frame:GetChildren() } end)
        if not listed then return end
        for _, child in ipairs(children) do visit(child) end
    end
    for pass = 1, 6 do visit(root) end
end

function RikRenderCheck(root)
    assert(root, "Scenario root is missing")
    for _, entry in ipairs(RikUI:GetErrors()) do
        error(entry.context .. ": " .. entry.detail)
    end
    CreateFrame("Frame", "RIK_RENDER_OK", root):Hide()
end

-- The simulator's built-in spellbook and spell metadata belong to another game version. These
-- inputs describe a Forever character by level 10 using RikUI's own catalogue (data/spells-<class>.lua,
-- ranks and acquisition levels: rank 1 of every spell learned by 10, rank 2 of those learned by 4),
-- so the addon's spellbook scans, icons and action textures read the current client's spells.
-- RikUI still resolves ranks, membership and drawing itself.
local SPELLS_BY_10 = {
    DRUID = { 5176, 5177, 8921, 8924, 467, 339, 16689, 18960, 5487, 99, 6795, 6807, 5185, 5186, 1126, 5232, 774, 1058 },
    HUNTER = { 13163, 13165, 883, 2641, 6991, 982, 75, 1978, 13549, 3044, 1130, 5116, 2973, 14260, 1494, 19883, 5149 },
    MAGE = { 1459, 1460, 5504, 5505, 587, 5143, 118, 133, 143, 2136, 168, 7300, 116, 205, 122, 1296017, 1302508 },
    PALADIN = { 635, 639, 20154, 20287, 465, 19740, 20271, 679, 498, 21082, 1152, 853, 633, 1022, 1311649 },
    PRIEST = { 1243, 1244, 17, 1277455, 10797, 2050, 2052, 585, 591, 139, 13908, 1277370, 2006, 589, 594, 586, 9035, 8092, 2652 },
    ROGUE = { 2098, 6760, 5171, 1752, 1757, 53, 2589, 1776, 5277, 2983, 1784, 1785, 921, 6770, 1804 },
    SHAMAN = { 403, 529, 8042, 8044, 2484, 5730, 8050, 3599, 8017, 8018, 8071, 8154, 324, 8024, 8075, 331, 332 },
    WARLOCK = { 172, 6222, 702, 1108, 1454, 980, 5782, 1120, 687, 696, 688, 6201, 697, 348, 707, 686, 695 },
}
local CLASS_IDS = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
local CLASS_ICONS = { WARRIOR = 626008, PALADIN = 626003, HUNTER = 626000, ROGUE = 626005, PRIEST = 626004, SHAMAN = 626006, MAGE = 626001, WARLOCK = 626007, DRUID = 625999 }

function RikRenderSpellbook(class)
    class = class or "PALADIN"
    local list = assert(SPELLS_BY_10[class], "No level-10 spell list for " .. class)
    local catalog, icons, names, known, items = RikUI.Spells.Catalog(class), {}, {}, {}, {}
    for name, entry in pairs(catalog) do
        for _, id in ipairs(entry.ranks) do icons[id], names[id] = entry.icon, name end
    end
    for _, id in ipairs(list) do
        assert(icons[id], "Spell " .. id .. " is not in RikUI's " .. class .. " catalogue")
        known[id] = true
        items[#items + 1] = id
    end
    local title = class:sub(1, 1) .. class:sub(2):lower()
    C_SpellBook.GetNumSpellBookSkillLines = function() return 1 end
    C_SpellBook.GetSpellBookSkillLineInfo = function(index)
        if index ~= 1 then return nil end
        return { name = title, iconID = CLASS_ICONS[class], itemIndexOffset = 0, numSpellBookItems = #items,
            isGuild = false, shouldHide = false, specID = nil, offSpecID = nil }
    end
    C_SpellBook.GetSpellBookItemInfo = function(slot, bank)
        local id = bank == Enum.SpellBookSpellBank.Player and items[slot]
        if not id then return nil end
        return { itemType = Enum.SpellBookItemType.Spell, spellID = id, actionID = id, name = names[id],
            iconID = icons[id], isOffSpec = false, isPassive = false, skillLineIndex = 1 }
    end
    local function isKnown(id) return known[id] == true end
    C_SpellBook.IsSpellKnown, C_SpellBook.IsSpellInSpellBook, C_SpellBook.IsSpellKnownOrOverridesKnown = isKnown, isKnown, isKnown
    IsSpellKnown, IsPlayerSpell, IsSpellKnownOrOverridesKnown = isKnown, isKnown, isKnown
    local texture, spellName = C_Spell.GetSpellTexture, C_Spell.GetSpellName
    C_Spell.GetSpellTexture = function(id) return icons[id] or texture(id) end
    C_Spell.GetSpellName = function(id) return names[id] or spellName(id) end
    -- The two action texture readers are wrapped separately and never call each other, so the
    -- simulator's own aliasing between them cannot loop.
    local busy = false
    local function catalogueTexture(fallback)
        return function(slot)
            if busy then return fallback(slot) end
            busy = true
            local kind, id = GetActionInfo(slot)
            busy = false
            if kind == "spell" and icons[id] then return icons[id] end
            return fallback(slot)
        end
    end
    GetActionTexture = catalogueTexture(GetActionTexture)
    if C_ActionBar and type(rawget(C_ActionBar, "GetActionTexture")) == "function" then
        C_ActionBar.GetActionTexture = catalogueTexture(rawget(C_ActionBar, "GetActionTexture"))
    end
end

-- A character of another class at level 10: the seed's paladin becomes this class, with that class's
-- spellbook. RikUI's class-driven modules read the class through the normal unit APIs; the ones that
-- decided at login that the paladin has no use for them (combo points, totems, form mana) are
-- enabled again now, exactly as they would be for a character of this class.
function RikRenderPlayer(class, level)
    class = class or "PALADIN"
    A_Admin.SetPlayerClass(assert(CLASS_IDS[class], "Unknown class " .. class))
    if level then A_Admin.SetPlayerLevel(level) end
    RikRenderSpellbook(class)
    for _, name in ipairs({ "combopoints", "totems", "druidmana" }) do
        local module = RikUI.Modules and RikUI.Modules[name]
        if module and type(module.OnEnable) == "function" and not module.Holder then
            local ok, reason = pcall(module.OnEnable, module)
            assert(ok, name .. ": " .. tostring(reason))
        end
    end
    A_Admin.FireEvent("PLAYER_TARGET_CHANGED")
end

-- Combo points on the current target (rogues and druids).
function RikRenderComboPoints(points)
    GetComboPoints = function() return points end
    A_Admin.FireEvent("PLAYER_TARGET_CHANGED")
    A_Admin.FireEvent("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
end

-- Active totems: entries by slot, { name, icon, duration, elapsed }; a nil entry leaves the slot empty.
function RikRenderTotems(entries)
    local now = GetTime()
    GetTotemInfo = function(slot)
        local totem = entries[slot]
        if not totem then return false, "", 0, 0, 0 end
        return true, totem[1], now - (totem[4] or 0), totem[3], totem[2]
    end
    for slot = 1, 4 do A_Admin.FireEvent("PLAYER_TOTEM_UPDATE", slot) end
    if RikUI.Totems and RikUI.Totems.Refresh then RikUI.Totems.Refresh() end
end

-- A druid in Cat (form 3) or Bear (form 1) form: energy or rage on the primary bar, mana behind it.
function RikRenderForm(form, power, powerMax, mana, manaMax)
    local powerType = form == 1 and 1 or 3
    local token = form == 1 and "RAGE" or "ENERGY"
    A_Admin.SetPlayerPower(power, powerMax, powerType)
    A_Admin.SetPlayerPower(mana, manaMax, 0)
    -- The simulator keeps one primary power; the form's power is answered here for the untyped reads.
    local basePowerType, basePower, basePowerMax = UnitPowerType, UnitPower, UnitPowerMax
    UnitPowerType = function(unit, ...) if unit == "player" then return powerType, token end return basePowerType(unit, ...) end
    UnitPower = function(unit, kind, ...)
        if unit == "player" and (kind == nil or kind == powerType) then return power end
        return basePower(unit, kind, ...)
    end
    UnitPowerMax = function(unit, kind, ...)
        if unit == "player" and (kind == nil or kind == powerType) then return powerMax end
        return basePowerMax(unit, kind, ...)
    end
    GetShapeshiftForm = function() return form end
    A_Admin.FireEvent("UPDATE_SHAPESHIFT_FORM")
    A_Admin.FireEvent("UNIT_DISPLAYPOWER", "player")
end

-- Cooldown state for the strip: the simulator's Forever profile returns no cooldown duration
-- objects, so these supply them on the game clock; each entry is { id, duration, elapsed }.
function RikRenderCooldowns(entries)
    local now, durations = GetTime(), {}
    for _, entry in ipairs(entries) do
        local duration = C_DurationUtil.CreateDuration()
        duration:SetTimeFromStart(now - entry.elapsed, entry.duration)
        durations[entry.id] = duration
    end
    C_Spell.GetSpellCooldownDuration = function(id) return durations[id] end
    C_Spell.GetSpellChargeDuration = function() return nil end
    C_Spell.GetSpellDisplayCount = function() return "" end
end

-- A class's combat HUD mid-fight: abilities cooling down, one class buff up, the HUD arranged, the
-- strip rebuilt and the (always present) simulator pet frame hidden. Call RikRenderPlayer(class)
-- first for a class other than the seed's paladin.
local HUD_CLASSES = {
    PALADIN = { cooldowns = { { 853, 60, 19.1 }, { 1022, 300, 268.1 }, { 498, 300, 255.1 } }, buff = { 20287, "Seal of Righteousness", 132325, 30 } },
    ROGUE = { cooldowns = { { 2983, 300, 120 }, { 5277, 300, 200 }, { 1776, 10, 3 } }, buff = { 5171, "Slice and Dice", 132306, 9 },
        power = { 75, 100, 3 }, combo = 3 },
    SHAMAN = { cooldowns = { { 8042, 6, 2 }, { 8050, 6, 4 } }, buff = { 324, "Lightning Shield", 136051, 600 },
        totems = { { "Searing Totem", 135825, 55, 20 }, { "Strength of Earth Totem", 136023, 120, 30 }, { "Healing Stream Totem", 135127, 60, 10 } } },
    DRUID = { cooldowns = { { 6795, 10, 3 } }, buff = { 467, "Thorns", 136104, 600 }, form = { 3, 60, 100, 180, 300 } },
}
function RikRenderHUDState(class)
    local state = assert(HUD_CLASSES[class or "PALADIN"], "No HUD state for " .. tostring(class))
    local cooldowns = {}
    for _, entry in ipairs(state.cooldowns) do cooldowns[#cooldowns + 1] = { id = entry[1], duration = entry[2], elapsed = entry[3] } end
    RikRenderCooldowns(cooldowns)
    A_Admin.AddBuff(state.buff[1], state.buff[2], state.buff[3], state.buff[4], 0)
    if state.power then A_Admin.SetPlayerPower(unpack(state.power)) end
    if state.form then RikRenderForm(unpack(state.form)) end
    if state.combo then RikRenderComboPoints(state.combo) end
    if state.totems then RikRenderTotems(state.totems) end
    assert(RikUI.Layout.ApplyCombatHUD())
    RikUI.Cooldowns.Rebuild()
    RikUI.UnitFrames.Refresh()
    if RikUI.CombatResource and RikUI.CombatResource.Refresh then RikUI.CombatResource.Refresh() end
    RikUIUnit_petframe:Hide()
    RikRenderRefreshAuras()
end

-- A player cast one second into Holy Light on a manual clock, so the bar's fill is fixed.
function RikRenderCast(spell, name, icon, duration, elapsed)
    spell, name, icon = spell or 635, name or "Holy Light", icon or "Interface\\Icons\\Spell_Holy_HolyBolt"
    duration, elapsed = duration or 2.5, elapsed or 1
    A_Admin.SetCasting(spell, name, icon, duration)
    local clock = C_DurationUtil.CreateManualClock(elapsed)
    local object = C_DurationUtil.CreateDuration()
    object:SetClock(clock)
    object:SetTimeFromStart(0, duration)
    local reader = UnitCastingDuration
    UnitCastingDuration = function(unit) if unit == "player" then return object end return reader(unit) end
    A_Admin.FireEvent("UNIT_SPELLCAST_START", "player")
end

-- A player channel on a manual clock, mirroring RikRenderCast.
function RikRenderChannel(spell, name, icon, duration, elapsed)
    spell, name, icon = spell or 15407, name or "Mind Flay", icon or "Interface\\Icons\\Spell_Shadow_SiphonMana"
    duration, elapsed = duration or 3, elapsed or 1.2
    local clock = C_DurationUtil.CreateManualClock(elapsed)
    local object = C_DurationUtil.CreateDuration()
    object:SetClock(clock)
    object:SetTimeFromStart(0, duration)
    local startMs = GetTime() * 1000
    UnitChannelInfo = function(unit)
        if unit == "player" then return name, name, icon, startMs, startMs + duration * 1000, false, false, spell end
    end
    UnitChannelDuration = function(unit) if unit == "player" then return object end end
    UnitCastingInfo = function() return nil end
    A_Admin.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
end

-- A main-hand swing frozen one second into a 2.4 s cycle.
function RikRenderSwing(elapsed, speed)
    local started = GetTime()
    A_Admin.FireEvent("PLAYER_SWING", speed or 2.4, Enum.PlayerSwingType.MainHand)
    GetTime = function() return started + (elapsed or 1) end
    local mainHand = RikUI.SwingTimer.Bars[Enum.PlayerSwingType.MainHand]
    mainHand:GetScript("OnUpdate")(mainHand, 0)
end

-- A capture root for several top-level frames: the simulator renders one frame's subtree, so the
-- frames are re-parented to a holder covering the crop while keeping their screen anchors.
function RikRenderGroup(name, frames, left, bottom, width, height)
    local holder = CreateFrame("Frame", name, UIParent)
    holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    holder:SetSize(width, height)
    for _, frame in ipairs(frames) do
        assert(frame, "Missing frame for " .. name)
        frame:SetParent(holder)
    end
    return holder
end

-- The whole combat HUD as one capture root, laid out by RikUI; the holder matches the crop.
local HUD_FRAMES = { "RikUICooldowns", "RikUICombatResource", "RikUICast_player", "RikUISwingTimer",
    "RikUIClassAuras_player", "RikUIClassAuras_target", "RikUIUnit_player", "RikUIUnit_target", "RikUIUnit_focus" }
function RikRenderHUDGroup(name, left, bottom, width, height, names)
    local frames = {}
    for _, global in ipairs(names or HUD_FRAMES) do frames[#frames + 1] = _G[global] end
    local holder = RikRenderGroup(name, frames, left, bottom, width, height)
    RikRenderResize(holder)
    return holder
end

-- Apply one settings value through the option spec RikUI's settings panel uses, so a sequence
-- frame shows exactly what the control would do.
function RikRenderSetOption(pageId, key, value)
    for _, page in ipairs(RikUI.Options.Pages()) do
        if page.id == pageId then
            for _, spec in ipairs(page.specs) do
                if spec.key == key then
                    assert(type(spec.set) == "function", pageId .. "." .. key .. " has no setter")
                    local ok, reason = spec.set(value)
                    assert(ok ~= false, pageId .. "." .. key .. ": " .. tostring(reason))
                    return
                end
            end
            error("No setting " .. key .. " on page " .. pageId)
        end
    end
    error("No settings page " .. pageId)
end

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

-- Auras. The seed addon makes Blizzard's aura containers work in the simulator (their intrinsic
-- OnLoad, and the PLAYER/RAID filter parts); the simulator only ever puts auras on the player, so a
-- unit's aura reads can be pointed at the player's list. Containers refresh on request, because
-- the simulator does not route UNIT_AURA into a container's private partition.
local AURA_SOURCES = {}
local auraShimsReady = false
local function installAuraShims()
    if auraShimsReady then return end
    auraShimsReady = true
    local auraFunctions = {}
    for name, fn in pairs(C_UnitAuras) do
        if type(fn) == "function" then auraFunctions[name] = fn end
    end
    for name, fn in pairs(auraFunctions) do
        C_UnitAuras[name] = function(unit, ...)
            if type(unit) == "string" and AURA_SOURCES[unit] then return fn(AURA_SOURCES[unit], ...) end
            return fn(unit, ...)
        end
    end
end

-- entries: { { id, name, icon, duration, harmful = true, own = true }, ... }; from: units whose aura
-- reads should answer with the player's list, e.g. { target = "player" }. Debuffs count as the
-- player's own; a buff does when `own` says so (the seed's PLAYER filter reads RikRenderOwnAuras).
function RikRenderAuras(entries, from)
    installAuraShims()
    for unit, source in pairs(from or {}) do AURA_SOURCES[unit] = source end
    A_Admin.ClearBuffs()
    for _, aura in ipairs(entries) do
        if aura.own then RikRenderOwnAuras[aura[1]] = true end
        if aura.harmful then
            A_Admin.AddDebuff(aura[1], aura[2], aura[3], aura[4] or 0, 0)
        else
            A_Admin.AddBuff(aura[1], aura[2], aura[3], aura[4] or 0, 0)
        end
    end
    RikRenderRefreshAuras()
end

-- Every RikUI aura container reads its unit's list again.
function RikRenderRefreshAuras()
    for name, frame in pairs(_G) do
        if type(name) == "string" and name:match("^RikUI") and type(frame) == "table" and type(frame.GetObjectType) == "function"
            and frame:GetObjectType() == "AuraContainer" and type(GetForbiddenObjectTable) == "function" then
            local private = GetForbiddenObjectTable(frame)
            if type(private) == "table" and type(private.UpdateAllAuras) == "function" then
                pcall(private.UpdateAllAuras, private)
                if type(private.OnWeaponEnchantChanged) == "function" then pcall(private.OnWeaponEnchantChanged, private) end
            end
        end
    end
end

-- A breath, fatigue or feign-death timer: the client sends the range with MIRROR_TIMER_START and the
-- bar polls GetMirrorTimerProgress (milliseconds).
function RikRenderMirrorTimer(timer, value, maximum, label)
    GetMirrorTimerProgress = function(name) if name == timer then return value end return 0 end
    GetMirrorTimerInfo = function(index) if index == 1 then return timer, value, maximum, -1, false, label end return "UNKNOWN" end
    A_Admin.FireEvent("MIRROR_TIMER_START", timer, value, maximum, -1, false, label)
end

-- Blizzard's loss-of-control alert with one active effect; RikUI skins the frame in place.
function RikRenderLossOfControl(locType, spell, text, icon, duration, remaining)
    local now = GetTime()
    local data = { locType = locType, spellID = spell, displayText = text, iconTexture = icon,
        startTime = now - (duration - remaining), timeRemaining = remaining, duration = duration,
        lockoutSchool = 0, priority = 5, displayType = 2 }
    C_LossOfControl.GetActiveLossOfControlData = function() return data end
    C_LossOfControl.GetActiveLossOfControlDataCount = function() return 1 end
    LossOfControlFrame:SetUpDisplay(false, data)
    LossOfControlFrame:Show()
end

-- A proc overlay at a screen location (Enum.ScreenLocationType); the native pool draws it and RikUI
-- replaces the artwork.
function RikRenderProc(locationType, spell)
    local getBool = GetCVarBool
    GetCVarBool = function(name, ...) if name == "displaySpellActivationOverlays" then return true end return getBool(name, ...) end
    A_Admin.FireEvent("SPELL_ACTIVATION_OVERLAY_SHOW", spell or 20375, "Interface\\SpellActivationOverlay\\Art_of_War", locationType, 1, 255, 255, 255)
    -- The overlays fade in through an animation; the capture shows them at rest.
    for _, overlay in ipairs({ SpellActivationOverlayFrame:GetChildren() }) do
        if overlay:IsShown() then
            if overlay.animIn then overlay.animIn:Stop() end
            overlay:SetAlpha(1)
        end
    end
    SpellActivationOverlayFrame:SetAlpha(1)
end

-- The game clock some seconds ahead, for timers that read GetTime.
function RikRenderAdvanceClock(seconds)
    local base = GetTime
    local started = base()
    GetTime = function() return base() - started + started + seconds end
end

-- The game's cooldown manager entries, as the C_CooldownViewer API lists them: essential and utility
-- spell ids. The settings provider is absent so the strip reads the API, as it does before that
-- frame exists in the client.
function RikRenderViewerEntries(essential, utility)
    local set, infos, nextId = {}, {}, 1000
    local categories = Enum.CooldownViewerCategory
    for name, spells in pairs({ Essential = essential or {}, Utility = utility or {} }) do
        local ids = {}
        for _, spell in ipairs(spells) do
            nextId = nextId + 1
            ids[#ids + 1] = nextId
            infos[nextId] = { spellID = spell, hasAura = false, selfAura = false, flags = 0, isKnown = true, isInvisible = false, linkedSpellIDs = {} }
        end
        set[categories[name]] = ids
    end
    C_CooldownViewer.GetCooldownViewerCategorySet = function(category) return set[category] or {} end
    C_CooldownViewer.GetCooldownViewerCooldownInfo = function(id) return infos[id] end
    if CooldownViewerSettings then CooldownViewerSettings.GetDataProvider = function() return nil end end
    RikUI.Cooldowns.Rebuild()
end

-- The setup wizard's record that a preset was applied for a role, so empty preset slots show their
-- ghost icons on the bars.
function RikRenderGhosts(class, role)
    RikUI.CharDB.applied = { class = class or "PALADIN", role = role or "dps" }
    for _, bar in pairs(RikUI.Bars.Frames) do
        if RikUI.Bars.RefreshGhosts then RikUI.Bars.RefreshGhosts(bar) end
    end
end

-- The extra action button with a spell, as a quest or encounter grants it.
function RikRenderExtraAction(spell)
    C_ActionBar.HasExtraActionBar = function() return true end
    A_Admin.SetActionSlot(169, spell or 20271)
    ExtraActionBar_Update()
    -- The intro animation would raise the alpha over time; the frame is shown at rest here.
    if ExtraActionBarFrame.intro then ExtraActionBarFrame.intro:Stop() end
    ExtraActionBarFrame:SetAlpha(1)
    if ExtraActionButton1 and ExtraActionButton1.Update then pcall(ExtraActionButton1.Update, ExtraActionButton1) end
end

-- A zone ability button.
function RikRenderZoneAbility(spell, icon)
    C_ZoneAbility.GetActiveAbilities = function() return { { spellID = spell or 20271, textureKit = "genericaura", uiPriority = 1 } } end
    C_ZoneAbility.GetZoneAbilityIcon = function() return icon or 135959 end
    ZoneAbilityFrame:UpdateDisplayedZoneAbilities()
    ZoneAbilityFrame:Show()
end

-- Blizzard's scrolling combat text with a few messages; RikUI supplies the font.
-- messages: { { text, r, g, b, displayType }, ... }
function RikRenderCombatText(messages)
    if type(CombatText_LoadUI) == "function" then CombatText_LoadUI() end
    local scroll = CombatTextUtil and CombatTextUtil.StandardScroll
    for _, message in ipairs(messages) do
        CombatText:AddMessage(message[1], scroll, message[2] or 1, message[3] or 1, message[4] or 1, message[5], false)
    end
    CombatText:Show()
end

-- The personal resource display (the player's own plate), shown as the client does when its setting is on.
function RikRenderPersonalResource()
    assert(C_AddOns.LoadAddOn("Blizzard_PersonalResourceDisplay"))
    C_GameRules = C_GameRules or {}
    C_GameRules.IsPersonalResourceDisplayEnabled = function() return true end
    local frame = PersonalResourceDisplayFrame
    frame:SetVisibleSetting(Enum.PersonalResourceDisplayVisibleSetting and Enum.PersonalResourceDisplayVisibleSetting.Always or 0)
    frame:UpdateShownState()
    frame:Show()
    -- Edit Mode applies the class-colour setting in the client (default off: the plain health colour).
    -- The default colour is a client-defined global; the simulator defines it as white, the client's is green.
    PERSONAL_RESOURCE_DISPLAY_DEFAULT_HEALTH_COLOR = CreateColor(0, 1, 0)
    frame:SetShowClassColor(false)
    return frame
end

-- The combat timer some seconds into a fight, or just after it ended.
function RikRenderCombatTimer(seconds, ended)
    FlashClientIcon = FlashClientIcon or function() end -- Blizzard's low-health frame calls it on entering combat
    A_Admin.FireEvent("PLAYER_REGEN_DISABLED")
    RikRenderAdvanceClock(seconds)
    if ended then A_Admin.FireEvent("PLAYER_REGEN_ENABLED") end
    RikUI.CombatTimer.Refresh()
end

-- The session stopwatch running for some seconds.
function RikRenderStopwatch(seconds)
    RikUI.CombatTimer.StopwatchAction("start")
    RikRenderAdvanceClock(seconds)
    RikUI.CombatTimer.RefreshStopwatch()
end

-- A weapon swing bar in one state. kind: "MainHand", "OffHand" or "Ranged"; opts: { speed, elapsed,
-- auto (ranged auto-shot running), moving, inRange (true, false or "unknown"), kiting }.
function RikRenderSwingState(kind, opts)
    opts = opts or {}
    local swingType = Enum.PlayerSwingType[kind]
    if opts.kiting ~= nil then RikUI.Profile.swingtimer.kiting = opts.kiting end
    if opts.inRange ~= nil then
        C_SwingTimer.IsTargetWithinSwingRange = function() if opts.inRange == "unknown" then return nil end return opts.inRange end
    end
    if opts.moving ~= nil then GetUnitSpeed = function() return opts.moving and 7 or 0 end end
    local base = GetTime
    local started = base()
    if kind == "Ranged" and opts.auto then A_Admin.FireEvent("START_AUTOREPEAT_SPELL") end
    A_Admin.FireEvent("PLAYER_SWING", opts.speed or 2.4, swingType)
    GetTime = function() return started + (opts.elapsed or 1) end
    local bar = RikUI.SwingTimer.Bars[swingType]
    bar:GetScript("OnUpdate")(bar, 0)
    return bar
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

-- A temporary weapon enchant on the main hand for the enchant slot of the buff row.
function RikRenderWeaponEnchant(charges, minutes, icon)
    local expiration = (minutes or 25) * 60 * 1000
    GetWeaponEnchantInfo = function() return true, expiration, charges or 0, 2504, false, 0, 0, 0, false, 0, 0, 0 end
    local texture = GetInventoryItemTexture
    GetInventoryItemTexture = function(unit, slot)
        if unit == "player" and slot == 16 then return icon or 135274 end
        return texture(unit, slot)
    end
    A_Admin.FireEvent("WEAPON_ENCHANT_CHANGED")
    RikRenderRefreshAuras()
end

-- The screen point of a creature in the world plate, by name (the nth match), one yard above its feet.
function RikRenderActor(name, nth)
    assert(RikRenderWorld, "This scenario has no world plate")
    local seen = 0
    for _, actor in ipairs(RikRenderWorld.actors) do
        if actor.name == name then
            seen = seen + 1
            if seen == (nth or 1) then return actor end
        end
    end
    error("No actor named " .. name .. " in plate " .. RikRenderWorld.plate)
end

-- The simulator measures a font string when its text is set; RikUI changes fonts afterwards, so a
-- string keeps a stale width until its text is set again. This sets every string again, in place.
function RikRenderRemeasure(root)
    local function visit(frame)
        local listed, regions = pcall(function() return { frame:GetRegions() } end)
        if listed then
            for _, region in ipairs(regions) do
                if type(region.GetText) == "function" and type(region.SetText) == "function" then
                    local text = region:GetText()
                    if text and text ~= "" then region:SetText(text) end
                end
            end
        end
        local ok, children = pcall(function() return { frame:GetChildren() } end)
        if not ok then return end
        for _, child in ipairs(children) do visit(child) end
    end
    visit(root)
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

-- Inputs for two items whose artwork was extracted from the current client.
-- These supply game API data; RikUI still creates and paints every control.
function RikRenderItems()
    local items = {
        [6948] = { name = "Hearthstone", icon = 134414, count = 1 },
        [118] = { name = "Minor Healing Potion", icon = 134829, count = 5 },
    }
    local slots = { 6948, 118 }
    C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end
    C_Container.GetContainerNumFreeSlots = function(bag) return bag == 0 and 14 or 0, 0 end
    C_Container.GetContainerItemInfo = function(bag, slot)
        local id = bag == 0 and slots[slot]
        local item = items[id]
        if not item then return nil end
        return { itemID = id, iconFileID = item.icon, stackCount = item.count,
            quality = 1, isLocked = false, hasNoValue = false,
            hyperlink = "|cffffffff|Hitem:" .. id .. "::::::::10:::::|h[" .. item.name .. "]|h|r" }
    end
    C_Container.SetItemSearch = function() return false end
    C_Container.GetContainerItemQuestInfo = function() return { isQuestItem = false } end
    local texture, bagSlots = GetInventoryItemTexture, {}
    for bag = 1, 4 do bagSlots[C_Container.ContainerIDToInventoryID(bag)] = true end
    GetInventoryItemTexture = function(unit, slot)
        if unit == "player" and bagSlots[slot] then return nil end
        return texture(unit, slot)
    end
    GetNumLootItems = function() return 2 end
    GetLootSlotInfo = function(slot)
        local item = items[slots[slot]]
        if item then return item.icon, item.name, item.count, nil, 1, false, false end
    end
end

-- ===== Everyday interface =====

-- The simulator's Minimap widget draws a fixed placeholder picture. The client's own minimap tiles
-- for the ground around Goldshire go over it: Azeroth tiles 30-32 x 48-50, 533 yards and 256 pixels
-- each, placed so the Lion's Pride Inn sits under the player dot at the centre.
local TILE_PIXELS = 256
local PLAYER_TILE = { column = 31, row = 49, fx = 0.80, fy = 0.74 }
local function placeTile(parent, size, tx, ty, path)
    local x0, y0 = math.max(0, tx), math.max(0, ty)
    local x1, y1 = math.min(size, tx + TILE_PIXELS), math.min(size, ty + TILE_PIXELS)
    if x1 <= x0 or y1 <= y0 then return end
    local tex = parent:CreateTexture(nil, "BACKGROUND")
    tex:SetTexture(path)
    tex:SetPoint("TOPLEFT", parent, "TOPLEFT", x0, -y0)
    tex:SetSize(x1 - x0, y1 - y0)
    tex:SetTexCoord((x0 - tx) / TILE_PIXELS, (x1 - tx) / TILE_PIXELS, (y0 - ty) / TILE_PIXELS, (y1 - ty) / TILE_PIXELS)
end

function RikRenderMinimapTiles()
    local holder = RikUIMinimap
    assert(holder, "Minimap holder missing")
    local tiles = CreateFrame("Frame", "RikRenderMinimapTiles", holder)
    tiles:SetAllPoints(Minimap)
    tiles:SetFrameLevel(Minimap:GetFrameLevel() + 1)
    local size = Minimap:GetWidth()
    local originX = size / 2 - PLAYER_TILE.fx * TILE_PIXELS
    local originY = size / 2 - PLAYER_TILE.fy * TILE_PIXELS
    for column = PLAYER_TILE.column - 1, PLAYER_TILE.column + 1 do
        for row = PLAYER_TILE.row - 1, PLAYER_TILE.row + 1 do
            placeTile(tiles, size, originX + (column - PLAYER_TILE.column) * TILE_PIXELS,
                originY + (row - PLAYER_TILE.row) * TILE_PIXELS, "World/Minimaps/Azeroth/map" .. column .. "_" .. row)
        end
    end
    -- The client draws the indicator and queue frames over the map; keep them above the mosaic.
    for _, frame in ipairs(RikUI.Minimap.Adopted) do
        if frame:GetFrameLevel() <= tiles:GetFrameLevel() then frame:SetFrameLevel(tiles:GetFrameLevel() + 1) end
    end
    -- The clock and coordinates refresh from the holder's own tick.
    RikUI.Minimap.Tick(holder, 1)
    return tiles
end

-- Performance readout: the simulator answers a flat 60 FPS and no latency; these are ordinary values.
function RikRenderPerformance(fps, latency)
    GetFramerate = function() return fps end
    GetNetStats = function() return 1.2, 0.4, latency, latency end
    RikRenderSetOption("minimap", "performance", true)
end

-- New mail: the client raises UPDATE_PENDING_MAIL and answers HasNewMail.
function RikRenderMail()
    HasNewMail = function() return true end
    A_Admin.FireEvent("UPDATE_PENDING_MAIL")
    -- The icon shows when the reminder animation finishes; the simulator never finishes it.
    if MiniMapMailIcon then MiniMapMailIcon:SetShown(HasNewMail()) end
end

-- A listed premade group: the queue eye's status frame reads C_LFGList for it.
function RikRenderQueueStatus(name, applicants)
    -- The simulator reports a pet battle queue of its own; none is wanted here. The client resolves
    -- the |4 plural token in the applicant line when it draws it; the resolved text is supplied.
    C_PetBattles.GetPVPMatchmakingInfo = function() return nil end
    LFG_LIST_PENDING_APPLICANTS = "%d Pending Applicants"
    C_LFGList.HasActiveEntryInfo = function() return true end
    C_LFGList.GetActiveEntryInfo = function() return { name = name, activityIDs = { 1 }, censored = false } end
    C_LFGList.GetNumApplicants = function() return applicants, applicants end
    QueueStatusFrame:Update()
    QueueStatusFrame:Show()
    return QueueStatusFrame
end

-- Tracking menu: the minimap's own tracking dropdown, opened the way a right-click does.
function RikRenderTrackingMenu()
    RikUI.Minimap.OpenTracking()
end

-- Experience and reputation come from the unit readers.
function RikRenderExperience(current, maximum, rested)
    UnitXP = function() return current end
    UnitXPMax = function() return maximum end
    GetXPExhaustion = function() return rested end
    -- The simulator's character watches a retail faction; no faction is watched unless a fixture says so.
    if not RikRenderWatchedFaction then C_Reputation.GetWatchedFactionData = function() return nil end end
    RikUI.XPBar.Refresh()
end

function RikRenderReputation(name, reaction, standing, low, high)
    RikRenderWatchedFaction = true
    C_Reputation.GetWatchedFactionData = function()
        return { factionID = 72, name = name, reaction = reaction, currentStanding = standing,
            currentReactionThreshold = low, nextReactionThreshold = high }
    end
    RikUI.XPBar.Refresh()
end

-- A gain: the bar records the value it showed, then the client raises PLAYER_XP_UPDATE.
function RikRenderExperienceGain(before, after, maximum)
    -- The gain label is part of the bar's animation; captures otherwise run with motion reduced.
    RikUI.Profile.reducedMotion = false
    RikRenderSetOption("xpbar", "xpbar.animations", true)
    RikRenderExperience(before, maximum, nil)
    A_Admin.FireEvent("PLAYER_XP_UPDATE", "player")
    RikRenderExperience(after, maximum, nil)
    A_Admin.FireEvent("PLAYER_XP_UPDATE", "player")
    local row = RikUI.XPBar.Rows.xp
    if row.gainAnim then row.gainAnim:Stop() end
    if row.gainText then row.gainText:SetAlpha(1) end
    if row.flashAnim then row.flashAnim:Stop() end
    if row.flash then row.flash:SetAlpha(0) end
end

-- Durability: the client answers GetInventoryAlertStatus per alert slot (1 worn, 2 broken) and
-- GetInventoryItemDurability per inventory slot.
function RikRenderDurability(statuses, percents, tooltip)
    GetInventoryAlertStatus = function(index) return statuses[index] or 0 end
    GetInventoryItemDurability = function(slot)
        local value = percents and percents[slot]
        if value then return value, 100 end
        return nil
    end
    RikUI.Durability.Refresh()
    local pill = RikUI.Durability.Pill
    local broken = false
    for _, status in pairs(statuses) do if status == 2 then broken = true end end
    if RikUI.Durability.Pulse then RikUI.Durability.Pulse:Stop() end
    if pill.alert then pill.alert:SetAlpha(broken and 0.25 or 0) end
    if RikUI.Durability.Fade then RikUI.Durability.Fade:Stop() end
    pill:SetAlpha(1)
    if tooltip then pill:GetScript("OnEnter")(pill) end
    return pill
end

-- Tooltips through GameTooltip's own setters; RikUI's anchor hook places the frame.
function RikRenderTooltip(kind, a, b)
    local tip = GameTooltip
    -- The tooltip's unit health bar polls this client reader, which the simulator lacks.
    UnitPercentHealthFromGUID = UnitPercentHealthFromGUID or function()
        return math.floor(UnitHealth("target") / math.max(1, UnitHealthMax("target")) * 100 + 0.5)
    end
    -- The PTR issue reporter appends a keybind notice to every tooltip on test builds.
    if type(PTR_IssueReporter) == "table" then PTR_IssueReporter.HookIntoTooltip = function() end end
    GameTooltip_SetDefaultAnchor(tip, UIParent)
    if kind == "unit" then tip:SetUnit(a or "target")
    elseif kind == "item" then tip:SetItemByID(a)
    elseif kind == "spell" then tip:SetSpellByID(a)
    elseif kind == "inventory" then tip:SetInventoryItem("player", a)
    elseif kind == "aura" then tip:SetUnitAura("player", a or 1, b or "HELPFUL")
    else error("Unknown tooltip kind " .. tostring(kind)) end
    tip:Show()
    RikRenderRemeasure(tip)
    return tip
end

function RikRenderCompareTooltip(slot)
    local tip = RikRenderTooltip("inventory", slot or 16)
    GameTooltip_ShowCompareItem(tip)
    RikRenderRemeasure(ShoppingTooltip1)
    RikRenderRemeasure(ShoppingTooltip2)
    return tip
end

-- Chat lines the way the client formats them, through AddMessage; RikUI's line filters then
-- shorten tags, colour names and add timestamps as configured.
local function chatColor(kind)
    local info = ChatTypeInfo and ChatTypeInfo[kind]
    if info then return info.r, info.g, info.b end
    return 1, 1, 1
end

local CHAT_SAMPLE = {
    { "SYSTEM", "Quest accepted: Kobold Camp Cleanup" },
    { "SAY", "|Hplayer:Mira|h[Mira]|h says: Anyone heading to the Deadmines later?" },
    { "PARTY", "|Hchannel:PARTY|h[Party]|h |Hplayer:Mira|h[Mira]|h: Meet at the inn first." },
    { "PARTY", "|Hchannel:PARTY|h[Party]|h |Hplayer:Rik|h[Rik]|h: On my way." },
    { "GUILD", "|Hchannel:GUILD|h[Guild]|h |Hplayer:Toddrick|h[Toddrick]|h: Grats on 10!" },
    { "WHISPER", "|Hplayer:Mira|h[Mira]|h whispers: Do you still need linen?" },
    { "CHANNEL", "|Hchannel:channel:1|h[1. General]|h |Hplayer:Remy|h[Remy]|h: WTS Linen Cloth, 10s a stack" },
    { "LOOT", "You receive loot: |cffffffff|Hitem:118|h[Minor Healing Potion]|h|rx2." },
}

function RikRenderChatLines(lines)
    -- Lines fade two minutes after they arrive in the client; these have just arrived.
    ChatFrame1:SetFading(false)
    for _, line in ipairs(lines or CHAT_SAMPLE) do
        ChatFrame1:AddMessage(line[2], chatColor(line[1]))
    end
end

-- The edit box open on a channel, with text typed.
function RikRenderChatInput(text, chatType)
    local box = ChatFrame1EditBox
    box:SetAttribute("chatType", chatType or "PARTY")
    if ChatEdit_UpdateHeader then pcall(ChatEdit_UpdateHeader, box) end
    box:Show()
    box:SetText(text or "")
    box:SetFocus()
    box:SetAlpha(1)
    if RikUI.Chat.RefreshInputLayout then RikUI.Chat.RefreshInputLayout() end
    return box
end

-- Scrolled up: the jump-to-newest button appears.
function RikRenderChatScrolled()
    for _ = 1, 3 do ChatFrame1:ScrollUp() end
    local handler = ChatFrame1:GetScript("OnScrollChanged") or ChatFrame1:GetScript("OnMessageScrollChanged")
    if handler then handler(ChatFrame1) end
end

-- Chat bubbles: the engine pools its bubbles and lists them through C_ChatBubbles. A bubble here
-- is Blizzard's ChatBubbleTemplate under a holder, listed the same way, over a named actor.
local bubbles = {}
function RikRenderBubble(name, text, actorName, nth, dx, dy)
    local actor = type(actorName) == "table" and actorName or RikRenderActor(actorName, nth)
    local bubble = CreateFrame("Frame", name, UIParent)
    bubble:SetSize(1, 1)
    bubble:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", actor.x + (dx or 0), RikRenderWorld.height - actor.y + (dy or 44))
    local frame = CreateFrame("Frame", nil, bubble, "ChatBubbleTemplate")
    frame.String:SetWidth(0)
    frame.String:SetText(text)
    frame.String:ClearAllPoints()
    frame.String:SetPoint("BOTTOM", bubble, "TOP", 0, 16)
    bubbles[#bubbles + 1] = bubble
    C_ChatBubbles.GetAllChatBubbles = function() return bubbles end
    A_Admin.FireEvent("CHAT_MSG_SAY", text, actorName)
    local scanner = RikUI.ChatBubbles.Scanner
    local handler = scanner and scanner:GetScript("OnUpdate")
    if handler then handler(scanner, 1) end
    return bubble
end

-- Alert toasts through their own systems. The loot toast obeys the enableLootToasts CVar.
local function freezeAlerts(system)
    for frame in system.alertFramePool:EnumerateActive() do
        if frame.animIn then frame.animIn:Stop() end
        if frame.waitAndAnimOut then frame.waitAndAnimOut:Stop() end
        frame:SetAlpha(1)
    end
end

function RikRenderAlerts(kinds)
    local getBool = C_CVar.GetCVarBool
    C_CVar.GetCVarBool = function(name, ...)
        if name == "enableLootToasts" then return true end
        return getBool(name, ...)
    end
    local systems = {}
    for _, kind in ipairs(kinds) do
        if kind == "loot" then
            local link = select(2, GetItemInfo(6948))
            assert(LootAlertSystem:AddAlert(link, 1, 0, 0, nil, false, false, 0, false, false, false), "loot alert refused")
            systems[#systems + 1] = LootAlertSystem
        elseif kind == "money" then
            -- The client draws coin icons inside the money string; the simulator has none.
            GetMoneyString = function(copper) return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100) end
            assert(MoneyWonAlertSystem:AddAlert(15342), "money alert refused")
            systems[#systems + 1] = MoneyWonAlertSystem
        elseif kind == "achievement" then
            assert(AchievementAlertSystem:AddAlert(6), "achievement alert refused")
            systems[#systems + 1] = AchievementAlertSystem
        else error("Unknown alert " .. tostring(kind)) end
    end
    for _, system in ipairs(systems) do freezeAlerts(system) end
    AlertFrame:Show()
    -- Alert frames are pooled under UIParent and anchored to AlertFrame; a group holds them all.
    local frames = { AlertFrame }
    for _, system in ipairs(systems) do
        for frame in system.alertFramePool:EnumerateActive() do frames[#frames + 1] = frame end
    end
    return frames
end

-- Centre-screen banners. The event toast manager reads the next toast from the client.
function RikRenderEventToast(title, subtitle, textureKit)
    local info = { eventToastID = 1, title = title, subtitle = subtitle,
        displayType = Enum.EventToastDisplayType.NormalTitleAndSubTitle, uiTextureKit = textureKit or "levelup" }
    C_EventToastManager.GetNextToastToDisplay = function() return info end
    EventToastManagerFrame:DisplayToast(true)
    local toast = EventToastManagerFrame.currentDisplayingToast
    assert(toast, "no event toast shown")
    for _, region in ipairs({ toast:GetRegions() }) do region:SetAlpha(1) end
    toast:SetAlpha(1)
    EventToastManagerFrame:SetAlpha(1)
    return EventToastManagerFrame
end

function RikRenderBossBanner(name)
    A_Admin.FireEvent("BOSS_KILL", 1, name)
    assert(BossBanner:IsShown(), "boss banner hidden")
    BossBanner.Title:SetAlpha(1)
    BossBanner.SubTitle:SetAlpha(1)
    return BossBanner
end

function RikRenderObjectiveBanner(title)
    local frame = ObjectiveTrackerTopBannerFrame
    frame.questTitle, frame.showWorldQuests = title, false
    TopBannerManager_Show(frame)
    assert(frame:IsShown(), "objective banner hidden")
    frame.PopAnim:Stop()
    for _, key in ipairs({ "Title", "Subtitle", "UpLine", "DownLine" }) do
        if frame[key] then frame[key]:SetAlpha(1) end
    end
    frame:SetAlpha(1)
    return frame
end

-- Social toasts. Their templates' animation groups inherit parentKeys the simulator drops, so the
-- groups are created from Blizzard's own templates before the alert code plays them.
local function socialAnimations(frame)
    if not frame.animIn then frame.animIn = frame:CreateAnimationGroup(nil, "SocialToastAnimInTemplate") end
    if not frame.waitAndAnimOut then
        local group = frame:CreateAnimationGroup(nil, "SocialToastAnimOutTemplate")
        if not group.animOut then group.animOut = group:CreateAnimation("Alpha") end
        frame.waitAndAnimOut = group
    end
end

local function freezeSocial(frame)
    frame.animIn:Stop()
    frame.waitAndAnimOut:Stop()
    frame:SetAlpha(1)
end

function RikRenderTimeAlert(seconds)
    GetSessionTime = function() return seconds end
    -- The client resolves the |4 plural tokens SecondsToTime emits when it draws the string; the
    -- simulator draws them raw, so the resolved text is supplied.
    SecondsToTime = function()
        local hours, minutes = math.floor(seconds / 3600), math.floor(seconds / 60) % 60
        return string.format("%d %s %d %s", hours, hours == 1 and "Hour" or "Hours", minutes, minutes == 1 and "Minute" or "Minutes")
    end
    socialAnimations(TimeAlertFrame)
    TimeAlertFrame:Start(600000)
    TimeAlertFrame:OnUpdate(0)
    freezeSocial(TimeAlertFrame)
    return TimeAlertFrame
end

function RikRenderFriendToast(invites)
    BNGetNumFriendInvites = function() return invites end
    socialAnimations(BNToastFrame)
    -- A new friend request: the pending-invite line uses a plural token the simulator leaves raw.
    BNToastFrame:AddToast(5, invites)
    assert(BNToastFrame:IsShown(), "friend toast hidden")
    freezeSocial(BNToastFrame)
    return BNToastFrame
end

function RikRenderVoiceToast()
    local frame = VoiceChatPromptActivateChannel
    socialAnimations(frame)
    if frame.Text and (frame.Text:GetText() or "") == "" then
        frame.Text:SetText(VOICE_CHAT_PROMPT_CHANNEL_ACTIVATE or "Voice chat is available for this channel.")
    end
    frame:Show()
    frame:SetAlpha(1)
    return frame
end

-- Small HUD frames.
function RikRenderFramerate(fps)
    GetFramerate = function() return fps end
    IsCpuBound = IsCpuBound or function() return nil end
    FramerateFrame:Show()
    FramerateFrame.fpsTime = 0
    FramerateFrame:OnUpdate(1)
    return FramerateFrame
end

function RikRenderNavigationMarker(distance, actorName, nth)
    local actor = RikRenderActor(actorName, nth)
    C_Navigation.GetDistance = function() return distance end
    IN_GAME_NAVIGATION_RANGE = "%s yds" -- the client resolves the |4 plural token when drawing
    local frame = SuperTrackedFrame
    -- The marker follows the client's navigation state every frame; the capture holds one moment.
    frame:SetScript("OnUpdate", nil)
    frame:Show()
    frame.isClamped = false
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", actor.x, RikRenderWorld.height - actor.y + 40)
    frame:UpdateDistanceText()
    frame.Icon:Show()
    frame:SetAlpha(1)
    return frame
end

-- Screen text. FadingFrame keeps time from GetTime, so the clock moves past the fade-in.
function RikRenderZoneText(zone, subzone)
    A_Admin.SetZone(zone, 37)
    A_Admin.SetSubZone(subzone or "")
    A_Admin.FireEvent("ZONE_CHANGED_NEW_AREA")
    RikRenderAdvanceClock(1)
    ZoneTextFrame:SetAlpha(1)
    return ZoneTextFrame
end

function RikRenderSubZoneText(subzone)
    A_Admin.SetSubZone(subzone)
    A_Admin.FireEvent("ZONE_CHANGED")
    RikRenderAdvanceClock(1)
    SubZoneTextFrame:SetAlpha(1)
    -- The invisible frame sits at the screen centre while its string hangs from the top; wrap it.
    SubZoneTextFrame:ClearAllPoints()
    SubZoneTextFrame:SetPoint("TOPLEFT", SubZoneTextString, "TOPLEFT", -8, 8)
    SubZoneTextFrame:SetPoint("BOTTOMRIGHT", SubZoneTextString, "BOTTOMRIGHT", 8, -8)
    return SubZoneTextFrame
end

function RikRenderErrorText(text)
    UIErrorsFrame:SetFading(false) -- the line has just arrived; it fades two seconds later
    UIErrorsFrame:AddMessage(text, 1, 0.1, 0.1)
    return UIErrorsFrame
end

function RikRenderRaidWarning(text)
    RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
    -- The line fades in by the clock; move the clock into the hold.
    RikRenderAdvanceClock(1)
    return RaidWarningFrame
end

-- Bags: item identities the fixture supplies; the simulator knows none of these ids.
local BAG_ITEMS = {
    [6948] = { name = "Hearthstone", icon = 134414, count = 1, quality = 1, class = 15, subclass = 0 },
    [118] = { name = "Minor Healing Potion", icon = 134829, count = 5, quality = 1, class = 0, subclass = 1 },
    [2589] = { name = "Linen Cloth", icon = 132889, count = 12, quality = 1, class = 7, subclass = 5 },
    [117] = { name = "Tough Jerky", icon = 133971, count = 4, quality = 1, class = 0, subclass = 5 },
    [25] = { name = "Worn Shortsword", icon = 135274, count = 1, quality = 1, class = 2, subclass = 7, level = 2, equipLoc = "INVTYPE_WEAPON" },
    [3300] = { name = "Rabbit's Foot", icon = 133731, count = 3, quality = 0, class = 15, subclass = 0 },
    [3299] = { name = "Fractured Canine", icon = 133724, count = 2, quality = 0, class = 15, subclass = 0 },
    [2070] = { name = "Darnassian Bleu", icon = 133950, count = 6, quality = 1, class = 0, subclass = 5 },
    [4865] = { name = "Torn Note", icon = 134939, count = 1, quality = 1, class = 12, subclass = 0 },
}
local BAG_SLOTS = { 6948, 118, 2589, 117, 25, 3300, 3299, 2070, 4865 }

function RikRenderBagItems()
    local items, slots = BAG_ITEMS, BAG_SLOTS
    -- The backpack holds the items; one six-slot bag is equipped, the other bag slots are empty.
    C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 16 or bag == 1 and 6 or 0 end
    C_Container.GetContainerNumFreeSlots = function(bag)
        if bag == 0 then return 16 - #slots, 0 end
        if bag == 1 then return 6, 0 end
        return 0, 0
    end
    local inventoryTexture = GetInventoryItemTexture
    local bagSlots = {}
    for bag = 1, 4 do bagSlots[C_Container.ContainerIDToInventoryID(bag)] = bag end
    GetInventoryItemTexture = function(unit, inventoryID)
        local bag = bagSlots[inventoryID]
        if bag == 1 then return "Interface/Icons/INV_Misc_Bag_10" end
        if bag then return nil end
        return inventoryTexture(unit, inventoryID)
    end
    C_Container.GetContainerItemInfo = function(bag, slot)
        local id = bag == 0 and slots[slot]
        local item = items[id]
        if not item then return nil end
        return { itemID = id, iconFileID = item.icon, stackCount = item.count, quality = item.quality,
            isLocked = false, isReadable = false, hasLoot = false, hyperlink = "|cffffffff|Hitem:" .. id .. "::::::::10:::::|h[" .. item.name .. "]|h|r",
            isFiltered = false, hasNoValue = item.quality == 0 and false or false, itemName = item.name }
    end
    C_Container.GetContainerItemID = function(bag, slot) return bag == 0 and slots[slot] or nil end
    C_Container.GetContainerItemLink = function(bag, slot)
        local info = C_Container.GetContainerItemInfo(bag, slot)
        return info and info.hyperlink
    end
    local itemInfo, instant = GetItemInfo, C_Item.GetItemInfoInstant
    local function known(id)
        if type(id) == "string" then id = tonumber(id:match("item:(%d+)")) or tonumber(id) end
        return items[id], id
    end
    GetItemInfo = function(id)
        local item, numeric = known(id)
        if not item then return itemInfo(id) end
        return item.name, "|cffffffff|Hitem:" .. numeric .. "::::::::10:::::|h[" .. item.name .. "]|h|r", item.quality,
            item.level or 1, 1, nil, nil, item.count > 1 and 20 or 1, item.equipLoc or "", item.icon, item.quality == 0 and 3 or 25,
            item.class, item.subclass
    end
    C_Item.GetItemInfo = GetItemInfo
    C_Item.GetItemInfoInstant = function(id)
        local item, numeric = known(id)
        if not item then return instant(id) end
        return numeric, nil, nil, item.equipLoc or "", item.icon, item.class, item.subclass
    end
    C_Item.GetItemQualityByID = function(id) local item = known(id); return item and item.quality end
    return slots
end

function RikRenderBagFilter(value)
    assert(RikUI.Bags.SetFilter, "no bag filters")
    RikUI.Bags.SetFilter(value)
end

-- One slot holds an item that starts a quest, another a newly looted item.
function RikRenderBagMarkers(questSlot, newSlot)
    C_Container.GetContainerItemQuestInfo = function(bag, slot)
        local starts = bag == 0 and slot == questSlot
        return { isQuestItem = starts, questID = starts and 62 or nil, isActive = false }
    end
    C_NewItems = C_NewItems or {}
    C_NewItems.IsNewItem = function(bag, slot) return bag == 0 and slot == newSlot end
    RikUI.Bags.Refresh()
end

function RikRenderCapacityHUD(lowOnly)
    RikRenderSetOption("bags", "capacityHUD", true)
    RikRenderSetOption("bags", "capacityLowOnly", lowOnly == true)
    RikUI.Bags.UpdateCapacity()
    return RikUI.Bags.CapacityHUD
end

-- A merchant open: junk sale and repair controls appear in the bag window.
function RikRenderMerchant(repairCost)
    GetRepairAllCost = function() return repairCost or 0, (repairCost or 0) > 0 end
    CanMerchantRepair = function() return (repairCost or 0) > 0 end
    A_Admin.FireEvent("MERCHANT_SHOW")
    if RikUI.Bags.RefreshMerchant then RikUI.Bags.RefreshMerchant() end
    if RikUI.Bags.RefreshRepair then RikUI.Bags.RefreshRepair() end
end

-- Loot: coins take a slot of their own; a roll comes from the group loot readers.
function RikRenderLootCoins(copper)
    local count, info, slotType = GetNumLootItems, GetLootSlotInfo, GetLootSlotType
    local base = count()
    local gold, silver, cop = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. " Gold" end
    if silver > 0 then parts[#parts + 1] = silver .. " Silver" end
    if cop > 0 then parts[#parts + 1] = cop .. " Copper" end
    GetNumLootItems = function() return base + 1 end
    GetLootSlotInfo = function(slot)
        if slot == base + 1 then return "Interface\\Icons\\INV_Misc_Coin_02", table.concat(parts, "\n"), 0, nil, 1 end
        return info(slot)
    end
    GetLootSlotType = function(slot)
        if slot == base + 1 then return 2 end
        return slotType and slotType(slot) or 1
    end
end

function RikRenderLootRoll(name, icon, quality, seconds)
    local link = "|cff1eff00|Hitem:2488::::::::10:::::|h[" .. name .. "]|h|r"
    GetLootRollItemInfo = function() return icon, name, 1, quality, true, true, true, false, nil, nil, nil, nil, false end
    GetLootRollItemLink = function() return link end
    GetLootRollTimeLeft = function() return (seconds or 60) * 0.6 end
    GroupLootContainer_AddRoll(1, seconds or 60)
    assert(GroupLootFrame1:IsShown(), "roll frame hidden")
    GroupLootFrame1.Timer:SetValue((seconds or 60) * 0.6)
    if RikUI.Loot.SkinRolls then RikUI.Loot.SkinRolls() end
    return GroupLootFrame1
end

function RikRenderLootConfirm(name)
    local popup = StaticPopup_Show("LOOT_BIND", name)
    assert(popup, "no loot confirmation")
    return popup
end
