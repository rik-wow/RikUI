-- Learned class abilities with native cooldown rendering; no combat-state inference.
local core = RikUI
local panel = { title = "Class cooldowns", Buttons = {} }
core.ClassCooldowns = panel
core.ClassCooldownProfiles = core.ClassCooldownProfiles or {}
local SIZE, GAP, COLUMNS, MAX_BUTTONS = 28, 4, 6, 12
local WIDTH, HEIGHT = COLUMNS * (SIZE + GAP) - GAP, 2 * (SIZE + GAP) - GAP
-- Standing in for the native Essential row: 188x60 scaled into the Essential and Utility band
-- (50 + 4 + 30 in data/layouts.lua).
local STAND_IN_KEY, STAND_IN_SCALE, NATIVE_ADDON = "cooldownessential", 1.4, "Blizzard_CooldownViewer"
local warnings, pool = {}, {}

local function warn(key, reason)
    if warnings[key] then return end
    warnings[key] = true
    core:Print("Class cooldowns " .. key .. ": " .. tostring(reason))
end

local function validID(id)
    return not core.Secret.IsSecret(id) and type(id) == "number"
        and id > 0 and id < math.huge and id % 1 == 0
end

-- Resolve the entire profile before changing any visible slot.
function panel.Resolve(class, names)
    if type(names) ~= "table" then return nil, "profile must be a spell list" end
    local count, seen, result = 0, {}, {}
    for key in pairs(names) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > MAX_BUTTONS then
            return nil, "profile must contain at most 12 ordered spells"
        end
        count = count + 1
    end
    if count ~= #names then return nil, "profile has a missing slot" end
    for _, name in ipairs(names) do
        local entry = type(name) == "string" and core.Spells.Entry(name, class)
        if not entry or seen[name] then return nil, "unknown or duplicate class spell" end
        seen[name] = true
        local id, reason = core.Spells.HighestKnownRank(name, class)
        if reason then return nil, reason end
        if core.Secret.IsSecret(id) then return nil, "unreadable learned spell ID" end
        if id ~= nil then
            if not validID(id) then return nil, "unreadable learned spell ID" end
            result[#result + 1] = { id = id, name = name, icon = entry.icon }
        end
    end
    return result
end

local function duration(widget, api, id, ignoreGCD)
    local ok, reason = core.Secret.Apply(function(value)
        if not core.Secret.IsSecret(value) and value == nil then widget:Clear()
        else widget:SetCooldownFromDurationObject(value, true) end
    end, C_Spell and C_Spell[api], id, ignoreGCD)
    if not ok then widget:Clear(); warn(api, reason) end
    return ok
end

local function refreshButton(button)
    local cooldownOK = duration(button.cooldown, "GetSpellCooldownDuration", button.spellID, true)
    local chargeOK = duration(button.recharge, "GetSpellChargeDuration", button.spellID)
    local countOK, reason = core.Secret.Apply(function(value) button.count:SetText(value) end,
        C_Spell and C_Spell.GetSpellDisplayCount, button.spellID)
    if not countOK then button.count:SetText(""); warn("count", reason) end
    button.unknown:SetShown(not cooldownOK or not chargeOK or not countOK)
end

function panel.Refresh()
    for _, button in ipairs(panel.Buttons) do
        local ok, reason = pcall(refreshButton, button)
        if not ok then warn("render", reason) end
    end
end

local function cooldown(button, charge)
    local widget = CreateFrame("Cooldown", nil, button)
    widget:SetAllPoints(button)
    widget:EnableMouse(false)
    widget:SetDrawSwipe(not charge)
    widget:SetDrawEdge(charge)
    widget:SetDrawBling(false)
    widget:SetHideCountdownNumbers(false)
    widget:SetMinimumCountdownDuration(0)
    widget:SetCountdownFont(charge and "NumberFontNormalSmall" or "NumberFontNormal")
    widget:SetSwipeColor(0, 0, 0, 0.8)
    local font = widget:GetCountdownFontString()
    if font then
        font:SetFont(core.Media.font, charge and 11 or 16, "OUTLINE")
        if charge then font:ClearAllPoints(); font:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2) end
    end
    return widget
end

local function tooltip(button)
    if not button.spellID then return end
    local ok, reason = pcall(function()
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(button.spellID)
        GameTooltip:Show()
    end)
    if not ok then warn("tooltip", reason) end
end

-- Blizzard's Essential and Utility rows own the middle of the HUD. When the client configures
-- nothing there for this character (a level 4 paladin: zero entries in every category) or the
-- manager is off, this row takes the Essential row's place so the class still has its cooldowns
-- where every other class sees them.
local function standsIn()
    local viewer = core.CooldownViewer
    if not viewer or type(viewer.NativeEmpty) ~= "function" then return false end
    return viewer.NativeEmpty("Essential") == true and viewer.NativeEmpty("Utility") == true
end

local function standInPosition()
    if core.Layout.Groups[STAND_IN_KEY] then return core.Layout.GetPosition(STAND_IN_KEY) end
    local combat = core.Layouts and core.Layouts.CombatPositions
    return combat and combat[STAND_IN_KEY] or nil
end

-- Rows are left-aligned in the panel's own place and centred when standing in, as the native row is.
local function arrange()
    local count = #panel.Buttons
    for index, button in ipairs(panel.Buttons) do
        local row, column = math.floor((index - 1) / COLUMNS), (index - 1) % COLUMNS
        local inRow = math.min(COLUMNS, count - row * COLUMNS)
        local lead = panel.standingIn and (WIDTH - (inRow * (SIZE + GAP) - GAP)) / 2 or 0
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", panel.Frame, "TOPLEFT", lead + column * (SIZE + GAP), -row * (SIZE + GAP))
    end
end

-- Layout applies the saved place; standing in re-anchors to the Essential row's place afterwards,
-- and leaving it restores the saved place outside a layout pass.
local function place(frame)
    if not core.Profile then return end
    local target = standsIn() and standInPosition() or nil
    panel.standingIn = target ~= nil
    local saved = target or core.Layout.GetPosition("classcooldowns")
    frame:ClearAllPoints()
    frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    frame:SetScale(core.Layout.GetScale() * (target and STAND_IN_SCALE or 1))
    arrange()
end

local function createButton(index)
    local button = CreateFrame("Frame", nil, panel.Frame)
    button:SetSize(SIZE, SIZE)
    button:EnableMouse(true)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.cooldown, button.recharge = cooldown(button, false), cooldown(button, true)
    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints(button)
    overlay:EnableMouse(false)
    overlay:SetFrameLevel(math.max(button.cooldown:GetFrameLevel(), button.recharge:GetFrameLevel()) + 1)
    core.UI.Edges(overlay, 1, "OVERLAY")
    button.count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.count:SetPoint("BOTTOMRIGHT", -2, 2)
    button.count:SetFont(core.Media.font, 12, "OUTLINE")
    button.unknown = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.unknown:SetPoint("TOPLEFT", 2, -2)
    button.unknown:SetText("?")
    button:SetScript("OnEnter", tooltip)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return button
end

local function createFrame()
    panel.Frame = CreateFrame("Frame", "RikUIClassCooldowns", UIParent)
    panel.Frame:SetSize(WIDTH, HEIGHT)
    panel.Frame:EnableMouse(false)
    core.Layout.Register(panel.Frame, "classcooldowns",
        { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 560 }, { label = "Class cooldowns", onApply = place })
end

local function icon(button, entry)
    button.icon:SetTexture(entry.icon)
    local ok, reason = core.Secret.Apply(function(value)
        if core.Secret.IsSecret(value) or value ~= nil then button.icon:SetTexture(value) end
    end, C_Spell and C_Spell.GetSpellTexture, entry.id)
    if not ok then warn("texture", reason) end
end

local function apply(entries)
    if #entries > 0 and not panel.Frame then createFrame() end
    panel.Buttons = {}
    for index, entry in ipairs(entries) do
        local button = pool[index] or createButton(index)
        pool[index], panel.Buttons[index] = button, button
        button.spellID, button.spellName = entry.id, entry.name
        icon(button, entry)
        button:Show()
    end
    for index = #entries + 1, #pool do
        pool[index].spellID = nil
        pool[index].cooldown:Clear()
        pool[index].recharge:Clear()
        pool[index]:Hide()
    end
    if panel.Frame then panel.Frame:SetShown(#entries > 0); place(panel.Frame) end
    panel.Refresh()
end

local function rebuild()
    if panel.enabled == false then return end
    local ok, _, class = core.Secret.Read(UnitClass, "player")
    if not ok or core.Secret.IsSecret(class) or type(class) ~= "string" then return end
    local profile = core.ClassCooldownProfiles[class]
    if profile == nil then apply({}); return end
    local resolved, entries, reason = pcall(panel.Resolve, class, profile)
    if not resolved then warn("spellbook", entries); return end
    if not entries then warn("spellbook", reason); return end
    apply(entries)
end

local function schedule()
    core.Combat.Queue(rebuild, "classcooldowns-rebuild")
end

function panel:OnEnable()
    schedule()
    for _, event in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_TALENT_UPDATE",
        "TRAIT_CONFIG_UPDATED", "ACTIVE_COMBAT_CONFIG_CHANGED", "PLAYER_ENTERING_WORLD",
        "UPDATE_SHAPESHIFT_FORM", "SPELL_UPDATE_ICON" }) do
        core:RegisterEvent(event, schedule)
    end
    for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_USES",
        "BAG_UPDATE_DELAYED" }) do
        core:RegisterEvent(event, panel.Refresh)
    end
    -- The native settings provider (what the middle will hold) exists once Blizzard's viewer loads.
    core:RegisterEvent("ADDON_LOADED", function(_, name) if name == NATIVE_ADDON then schedule() end end)
end

function panel:Debug()
    core:Print("Class cooldowns: " .. #panel.Buttons .. " learned abilities; native durations, no readiness inference"
        .. (panel.standingIn and "; standing in for the empty native Essential row" or ""))
end

core:RegisterModule("classcooldowns", panel)

