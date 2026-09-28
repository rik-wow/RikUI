-- Combat HUD pieces: resources, cooldowns, casts, swings, timers and cues.

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
