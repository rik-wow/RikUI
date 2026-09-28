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
-- spellbook. RikUI's class-driven modules read the class through the normal unit APIs.
function RikRenderPlayer(class, level)
    class = class or "PALADIN"
    A_Admin.SetPlayerClass(assert(CLASS_IDS[class], "Unknown class " .. class))
    if level then A_Admin.SetPlayerLevel(level) end
    RikRenderSpellbook(class)
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

-- The paladin's combat HUD mid-fight: three abilities cooling down, a seal up, the HUD arranged,
-- the strip rebuilt and the (always present) simulator pet frame hidden.
function RikRenderHUDState()
    RikRenderCooldowns({ { id = 853, duration = 60, elapsed = 19.1 }, { id = 1022, duration = 300, elapsed = 268.1 },
        { id = 498, duration = 300, elapsed = 255.1 } })
    A_Admin.AddBuff(20287, "Seal of Righteousness", 132325, 30, 0)
    assert(RikUI.Layout.ApplyCombatHUD())
    RikUI.Cooldowns.Rebuild()
    RikUI.UnitFrames.Refresh()
    RikUIUnit_petframe:Hide()
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
