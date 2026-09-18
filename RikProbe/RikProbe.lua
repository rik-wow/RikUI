-- RikProbe: throwaway addon that reports what the WoW Forever beta client
-- actually allows, so RikUI (see SDD.md) is designed around facts.
-- Every registration, template, hook and unit read is wrapped in pcall:
-- one missing API must never abort this file.
local ADDON = ...

local PREFIX = "|cff33ccffRikProbe|r: "
local MAX_LOG = 300
local NOISY_EVENT_LIMIT = 3
local SLOTS_PER_BAR = 12
local BONUS_BAR_FIRST_SLOT = 73 -- vanilla bonus bar 1 is action page 7
local FIXED_ACTION_SLOT = 73
local SNAPSHOT_DELAY = 0.5

RikProbe = {
    results = {
        api = {}, events = {}, eventCounts = {}, offsets = {},
        savedVars = {}, secrets = {}, secretValues = {}, secretsAt = {},
        visibility = {},
    },
    log = {},
}
local P = RikProbe
local R = P.results
local isSecret = issecretvalue or function() return false end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function S(value)
    if isSecret(value) then return "<secret>" end
    return tostring(value)
end

local function Print(msg)
    print(PREFIX .. msg)
end

local function CombatTag()
    return InCombatLockdown() and "combat" or "safe"
end

local function Log(msg)
    local line = string.format("[%s %s] %s", date("%H:%M:%S"), CombatTag(), msg)
    table.insert(P.log, line)
    if #P.log > MAX_LOG then table.remove(P.log, 1) end
    print(PREFIX .. line)
end

-- Call fn under pcall; log and return false, err on failure.
local function Try(label, fn, ...)
    if type(fn) ~= "function" then
        Log(label .. " skipped: not a function")
        return false, "not a function"
    end
    local results = { pcall(fn, ...) }
    if not results[1] then Log(label .. " failed: " .. tostring(results[2])) end
    return unpack(results)
end

-- Call fn under pcall; return its results, or nothing on failure.
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
    return nil
end

local function Resolve(path)
    local value = _G
    for part in path:gmatch("[^.]+") do
        if type(value) ~= "table" then return nil end
        value = value[part]
    end
    return value
end

local function DescribeArgs(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = S((select(i, ...))) end
    return table.concat(parts, ", ")
end

local function SpellLabel(spellID)
    if type(spellID) ~= "number" or isSecret(spellID) then return S(spellID) end
    local name = Call(Resolve("C_Spell.GetSpellName"), spellID)
    return string.format("%d (%s)", spellID, S(name))
end

------------------------------------------------------------------------
-- 1. API presence and secure snippets
------------------------------------------------------------------------
local API_NAMES = {
    -- secure machinery
    "loadstring_untainted", "issecretvalue", "hooksecurefunc",
    "RegisterStateDriver", "UnregisterStateDriver",
    "SecureHandlerExecute", "SecureHandlerWrapScript",
    -- action bars
    "ActionButton1", "ActionButtonDown", "MainMenuBar", "PickupAction",
    "GetNumShapeshiftForms",
    "GetActionBarPage", "GetActionCooldown", "GetActionCount", "GetActionInfo",
    "GetBonusBarOffset", "GetShapeshiftForm", "HasAction",
    "IsActionInRange", "IsUsableAction",
    "C_ActionBar", "C_Spell.GetSpellCooldownDuration", "C_Spell.GetSpellName",
    "C_Spell.GetSpellTexture",
    -- setup engine
    "ClearCursor", "CreateMacro", "EditMacro", "PickupItem", "PickupMacro",
    "PickupSpell", "PlaceAction", "GetBindingKey", "SaveBindings", "SetBinding",
    "C_CVar.GetCVarInfo", "C_CVar.SetCVar", "C_Item.GetItemInfo", "C_Item.PickupItem",
    "C_Macro", "C_Spell.PickupSpell",
    -- unit frames and auras
    "C_Secrets.ShouldAurasBeSecret", "C_UnitAuras.GetAuraDataByIndex",
    "C_Timer.After", "EditModeManagerFrame",
}

local function ProbeApiPresence()
    for _, name in ipairs(API_NAMES) do
        R.api[name] = type(Resolve(name))
    end
end

local function ProbeSecureSnippets()
    local report = "loadstring_untainted is " .. type(loadstring_untainted)
    local ok, header = pcall(CreateFrame, "Frame", "RikProbeSnippetHeader", UIParent, "SecureHandlerStateTemplate")
    if not ok then
        R.snippets = report .. "; SecureHandlerStateTemplate: error: " .. tostring(header)
        return
    end
    local ran, err = pcall(SecureHandlerExecute, header, "self:SetAttribute('rikprobe', 1)")
    if not ran then
        R.snippets = report .. "; SecureHandlerExecute: error: " .. tostring(err)
        return
    end
    local applied = header:GetAttribute("rikprobe") == 1
    R.snippets = report .. "; SecureHandlerExecute: " .. (applied and "ran and set the attribute" or "returned without effect")
end

------------------------------------------------------------------------
-- 2. Saved variables
------------------------------------------------------------------------
local function CharacterName()
    return S(Call(UnitName, "player")) .. "-" .. S(Call(GetRealmName))
end

local function SeedSavedVar(existing)
    local db = type(existing) == "table" and existing or {}
    local status
    if type(existing) == "table" then
        status = string.format("survived: seeded %s by %s, loads=%d",
            tostring(db.seededAt), tostring(db.seededBy), (db.loads or 0) + 1)
    else
        status = "fresh: nothing loaded this login (expected on first install; on a later login it means saved variables do not load)"
    end
    db.loads = (db.loads or 0) + 1
    db.seededAt = db.seededAt or date("%Y-%m-%d %H:%M:%S")
    db.seededBy = db.seededBy or CharacterName()
    db.lastLoadAt = date("%Y-%m-%d %H:%M:%S")
    return db, status
end

local function SeedSavedVars()
    RikProbeDB, R.savedVars.RikProbeDB = SeedSavedVar(RikProbeDB)
    RikProbeCharDB, R.savedVars.RikProbeCharDB = SeedSavedVar(RikProbeCharDB)
    Print("RikProbeDB " .. R.savedVars.RikProbeDB)
    Print("RikProbeCharDB " .. R.savedVars.RikProbeCharDB)
end

------------------------------------------------------------------------
-- 3. Visibility state drivers
------------------------------------------------------------------------
local VISIBILITY_CONDITIONS = {
    "[bonusbar:1] show; hide", "[bonusbar:2] show; hide", "[bonusbar:3] show; hide",
    "[stance:1] show; hide", "[stance:2] show; hide", "[stance:3] show; hide",
    "[combat] show; hide",
}

local function CreateVisibilityFrame(index, condition)
    local frame = CreateFrame("Frame", "RikProbeVisibility" .. index, UIParent)
    frame:SetSize(180, 16)
    frame:SetPoint("TOP", UIParent, "TOP", -220, -60 - (index - 1) * 18)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0.6, 0, 0.7)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetAllPoints()
    label:SetText(condition)
    local entry = R.visibility[condition]
    frame:SetScript("OnShow", function()
        entry.toggles = entry.toggles + 1
        Log("visibility " .. condition .. " -> shown")
    end)
    frame:SetScript("OnHide", function()
        entry.toggles = entry.toggles + 1
        Log("visibility " .. condition .. " -> hidden")
    end)
    return frame
end

local function SetupVisibilityDrivers()
    for index, condition in ipairs(VISIBILITY_CONDITIONS) do
        local entry = { toggles = 0 }
        R.visibility[condition] = entry
        local ok, frame = pcall(CreateVisibilityFrame, index, condition)
        if ok then
            entry.frame = frame
            local registered, err = Try("RegisterStateDriver " .. condition, RegisterStateDriver, frame, "visibility", condition)
            entry.status = registered and "registered" or ("error: " .. tostring(err))
        else
            entry.status = "CreateFrame error: " .. tostring(frame)
        end
    end
end

------------------------------------------------------------------------
-- 4. Fixed action button (type=action, action=73)
------------------------------------------------------------------------
local function DescribeSlot(slot)
    if Call(HasAction, slot) ~= true then return "empty" end
    local actionType, id, subType = Call(GetActionInfo, slot)
    if actionType == "spell" then return "spell " .. SpellLabel(id) end
    return string.format("%s %s %s", S(actionType), S(id), S(subType))
end

local function CreateActionButton()
    local ok, button = pcall(CreateFrame, "Button", "RikProbeAction" .. FIXED_ACTION_SLOT, UIParent, "SecureActionButtonTemplate")
    if not ok then
        R.action73 = "CreateFrame SecureActionButtonTemplate error: " .. tostring(button)
        return
    end
    button:SetSize(36, 36)
    button:SetPoint("TOP", UIParent, "TOP", 0, -60)
    button:SetAttribute("type", "action")
    button:SetAttribute("action", FIXED_ACTION_SLOT)
    Try("RegisterForClicks", button.RegisterForClicks, button, "AnyUp", "AnyDown")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(Call(GetActionTexture, FIXED_ACTION_SLOT) or "Interface/Icons/INV_Misc_QuestionMark")
    P.action73Icon = icon
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
    label:SetText(tostring(FIXED_ACTION_SLOT))
    R.action73Clicks = 0
    button:HookScript("PostClick", function(_, mouseButton)
        R.action73Clicks = R.action73Clicks + 1
        Log(string.format("action %d button clicked (%s); slot holds %s. Did that cast?",
            FIXED_ACTION_SLOT, S(mouseButton), DescribeSlot(FIXED_ACTION_SLOT)))
    end)
    R.action73 = "created at top centre; click it and check what fires"
end

local function RefreshFixedIcon()
    if not P.action73Icon then return end
    P.action73Icon:SetTexture(Call(GetActionTexture, FIXED_ACTION_SLOT) or "Interface/Icons/INV_Misc_QuestionMark")
end

-- Copy the spell in slot 1 into the fixed slot so the button has something to fire.
local function FillFixedSlot()
    if InCombatLockdown() then
        Print("fill: cannot place actions in combat")
        return
    end
    local actionType, id = Call(GetActionInfo, 1)
    if actionType ~= "spell" or type(id) ~= "number" or isSecret(id) then
        Print("fill: slot 1 does not hold a spell; drag one there first")
        return
    end
    local pickup = Resolve("C_Spell.PickupSpell") or PickupSpell
    if not Try("pickup spell " .. id, pickup, id) then return end
    Try("PlaceAction " .. FIXED_ACTION_SLOT, PlaceAction, FIXED_ACTION_SLOT)
    Try("ClearCursor", ClearCursor)
    RefreshFixedIcon()
    Log(string.format("fill: slot %d now holds %s", FIXED_ACTION_SLOT, DescribeSlot(FIXED_ACTION_SLOT)))
end

------------------------------------------------------------------------
-- 5. Stance state and native ACTIONBUTTON1 paging
------------------------------------------------------------------------
local function RecordStance()
    local form = Call(GetShapeshiftForm)
    local offset = Call(GetBonusBarOffset)
    local page = Call(GetActionBarPage)
    if type(form) == "number" and not isSecret(form) and not isSecret(offset) then
        R.offsets[form] = offset
    end
    return string.format("GetShapeshiftForm()=%s GetBonusBarOffset()=%s GetActionBarPage()=%s",
        S(form), S(offset), S(page)), offset, page
end

local function ExpectedOverlaySlot(offset, page)
    if isSecret(offset) or isSecret(page) then return nil end
    if type(page) == "number" and page > 1 then return (page - 1) * SLOTS_PER_BAR + 1 end
    if type(offset) == "number" and offset > 0 then return BONUS_BAR_FIRST_SLOT + (offset - 1) * SLOTS_PER_BAR end
    return 1
end

local function ResolveButtonAction(button)
    local action = button.action
    if action == nil then action = Call(button.CalculateAction, button) end
    if action == nil then action = Call(button.GetAttribute, button, "action") end
    return action
end

local function LogButton1Mapping(source)
    if not ActionButton1 then
        Log("ACTIONBUTTON1 " .. source .. ": ActionButton1 does not exist")
        return
    end
    local stance, offset, page = RecordStance()
    local resolved = ResolveButtonAction(ActionButton1)
    local expected = ExpectedOverlaySlot(offset, page)
    local verdict = "UNKNOWN"
    if not isSecret(resolved) and expected ~= nil then
        verdict = (resolved == expected) and "MATCH" or "MISMATCH"
    end
    Log(string.format("ACTIONBUTTON1 %s: resolved slot %s, expected %s, %s (%s)",
        source, S(resolved), S(expected), verdict, stance))
    R.nativePaging = string.format("last: resolved %s expected %s %s", S(resolved), S(expected), verdict)
end

local function HookActionButton1()
    if not ActionButton1 then
        R.nativePaging = "ActionButton1 not found"
        return
    end
    Try("HookScript ActionButton1 PostClick", ActionButton1.HookScript, ActionButton1, "PostClick", function(_, mouseButton)
        LogButton1Mapping("clicked (" .. S(mouseButton) .. ")")
    end)
    Try("hooksecurefunc ActionButtonDown", hooksecurefunc, "ActionButtonDown", function(id)
        if id == 1 then Log("ActionButtonDown(1): the ACTIONBUTTON1 key was pressed") end
    end)
    R.nativePaging = "hooked; press the key bound to ACTIONBUTTON1 in each stance"
end

------------------------------------------------------------------------
-- 6. Secret values
------------------------------------------------------------------------
local SECRET_PROBES = {
    { name = "GetActionCooldown(slot)", call = function(slot) return GetActionCooldown(slot) end },
    { name = "IsUsableAction(slot)", call = function(slot) return IsUsableAction(slot) end },
    { name = "IsActionInRange(slot)", call = function(slot) return IsActionInRange(slot) end },
    { name = "GetActionCount(slot)", call = function(slot) return GetActionCount(slot) end },
    { name = "UnitHealth(player)", call = function() return UnitHealth("player") end },
    { name = "UnitHealthMax(player)", call = function() return UnitHealthMax("player") end },
    { name = "UnitPower(player)", call = function() return UnitPower("player") end },
    { name = "UnitHealth(target)", call = function() return UnitHealth("target") end },
    { name = "UnitHealthMax(target)", call = function() return UnitHealthMax("target") end },
}

local function FirstUsedSlot()
    for slot = 1, SLOTS_PER_BAR do
        if Call(HasAction, slot) == true then return slot end
    end
    return 1
end

-- Returns (secretFlag, valuesText). secretFlag is true/false, or the error text.
local function DescribeReturns(ok, ...)
    if not ok then return "error: " .. tostring((...)), "" end
    local secret, parts = false, {}
    for i = 1, select("#", ...) do
        local value = (select(i, ...))
        if isSecret(value) then secret = true end
        parts[i] = S(value)
    end
    return secret, table.concat(parts, ", ")
end

local function SnapshotSecrets(label)
    local slot = FirstUsedSlot()
    local flags, values = {}, {}
    for _, probe in ipairs(SECRET_PROBES) do
        flags[probe.name], values[probe.name] = DescribeReturns(pcall(probe.call, slot))
    end
    R.secrets[label] = flags
    R.secretValues[label] = values
    R.secretsAt[label] = string.format("%s, slot %d, target %s", date("%H:%M:%S"), slot,
        Call(UnitExists, "target") and "present" or "none")
    Log("secret snapshot taken: " .. label)
end

local function ScheduleSnapshot(label)
    local after = Resolve("C_Timer.After")
    if type(after) == "function" then
        after(SNAPSHOT_DELAY, function() SnapshotSecrets(label) end)
    else
        SnapshotSecrets(label)
    end
end

------------------------------------------------------------------------
-- 7. Design events
------------------------------------------------------------------------
local DESIGN_EVENTS = {
    "ACTIONBAR_PAGE_CHANGED", "ACTIONBAR_SLOT_CHANGED", "CHARACTER_POINTS_CHANGED",
    "LEARNED_SPELL_IN_SKILL_LINE", "LEARNED_SPELL_IN_TAB", "PLAYER_LOGOUT",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TALENT_UPDATE",
    "SPELLS_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM",
    "UPDATE_SHAPESHIFT_FORMS",
}
local NOISY_EVENTS = { ACTIONBAR_SLOT_CHANGED = true, SPELLS_CHANGED = true }
local STANCE_EVENTS = {
    ACTIONBAR_PAGE_CHANGED = true, UPDATE_BONUS_ACTIONBAR = true,
    UPDATE_SHAPESHIFT_FORM = true, UPDATE_SHAPESHIFT_FORMS = true,
}
local LEARNED_EVENTS = { LEARNED_SPELL_IN_SKILL_LINE = true, LEARNED_SPELL_IN_TAB = true }

local eventsFrame = CreateFrame("Frame", "RikProbeEvents")

local function RegisterDesignEvents()
    for _, event in ipairs(DESIGN_EVENTS) do
        local ok, err = pcall(eventsFrame.RegisterEvent, eventsFrame, event)
        R.events[event] = ok and "ok" or ("error: " .. tostring(err))
    end
end

local function OnStanceEvent(event)
    Log(event .. ": " .. (RecordStance()))
    local after = Resolve("C_Timer.After")
    if type(after) == "function" then
        after(0.1, function() LogButton1Mapping("after " .. event) end)
    end
end

local function OnDesignEvent(_, event, ...)
    R.eventCounts[event] = (R.eventCounts[event] or 0) + 1
    if STANCE_EVENTS[event] then return OnStanceEvent(event) end
    if event == "PLAYER_REGEN_DISABLED" then return ScheduleSnapshot("in combat") end
    if event == "PLAYER_REGEN_ENABLED" then return ScheduleSnapshot("out of combat") end
    if event == "ACTIONBAR_SLOT_CHANGED" and (...) == FIXED_ACTION_SLOT then RefreshFixedIcon() end
    if NOISY_EVENTS[event] and R.eventCounts[event] > NOISY_EVENT_LIMIT then return end
    if LEARNED_EVENTS[event] then
        Log(event .. ": spell " .. SpellLabel((...)) .. " args " .. DescribeArgs(...))
        return
    end
    Log(event .. " " .. DescribeArgs(...))
end

eventsFrame:SetScript("OnEvent", function(self, event, ...)
    local ok, err = pcall(OnDesignEvent, self, event, ...)
    if not ok then Log(event .. " handler error: " .. tostring(err)) end
end)

------------------------------------------------------------------------
-- Report
------------------------------------------------------------------------
local function PrintHeader()
    local version, build, _, toc = Call(GetBuildInfo)
    Print(string.format("report: client %s build %s toc %s (%s)", S(version), S(build), S(toc), CombatTag()))
    local _, class = Call(UnitClass, "player")
    Print(string.format("character: %s level %s, GetNumShapeshiftForms()=%s",
        S(class), S(Call(UnitLevel, "player")), S(Call(GetNumShapeshiftForms))))
    Print("secure snippets: " .. tostring(R.snippets))
end

local function PrintApi()
    Print("API presence (type):")
    for _, name in ipairs(API_NAMES) do
        print("  " .. name .. " = " .. tostring(R.api[name]))
    end
    local shouldAurasBeSecret = Call(Resolve("C_Secrets.ShouldAurasBeSecret"))
    print("  C_Secrets.ShouldAurasBeSecret() = " .. S(shouldAurasBeSecret))
end

local function PrintSavedVars()
    Print("saved variables:")
    print("  RikProbeDB " .. tostring(R.savedVars.RikProbeDB))
    print("  RikProbeCharDB " .. tostring(R.savedVars.RikProbeCharDB))
end

local function PrintVisibility()
    Print("visibility state drivers (green labels left of top centre; watch them as you change stance):")
    for _, condition in ipairs(VISIBILITY_CONDITIONS) do
        local entry = R.visibility[condition] or {}
        local shown = entry.frame and Call(entry.frame.IsShown, entry.frame)
        print(string.format("  %s: %s, shown=%s, toggles=%d",
            condition, tostring(entry.status), S(shown), entry.toggles or 0))
    end
end

local function PrintStance()
    Print("stance: " .. (RecordStance()))
    local seen = {}
    for form, offset in pairs(R.offsets) do
        table.insert(seen, string.format("form %s -> offset %s", S(form), S(offset)))
    end
    table.sort(seen)
    print("  offsets seen so far: " .. (#seen > 0 and table.concat(seen, ", ") or "none"))
    local formCount = Call(GetNumShapeshiftForms) or 0
    for index = 1, formCount do
        local _, active, castable, spellID = Call(GetShapeshiftFormInfo, index)
        print(string.format("  form %d: %s active=%s castable=%s", index, SpellLabel(spellID), S(active), S(castable)))
    end
    Print("fixed action button: " .. tostring(R.action73) .. "; slot " .. FIXED_ACTION_SLOT
        .. " holds " .. DescribeSlot(FIXED_ACTION_SLOT) .. "; clicks=" .. tostring(R.action73Clicks or 0))
    Print("native ACTIONBUTTON1 paging: " .. tostring(R.nativePaging))
    LogButton1Mapping("now")
end

local function PrintSecrets()
    Print("secret values (issecretvalue on each return):")
    for _, label in ipairs({ "login", "out of combat", "in combat" }) do
        local flags = R.secrets[label]
        if flags then
            print(string.format("  %s (%s):", label, R.secretsAt[label]))
            for _, probe in ipairs(SECRET_PROBES) do
                print(string.format("    %s secret=%s values=%s", probe.name,
                    tostring(flags[probe.name]), R.secretValues[label][probe.name]))
            end
        else
            print("  " .. label .. ": no snapshot yet")
        end
    end
end

local function PrintEvents()
    Print("event registration (count seen):")
    for _, event in ipairs(DESIGN_EVENTS) do
        print(string.format("  %s: %s (%d)", event, tostring(R.events[event]), R.eventCounts[event] or 0))
    end
end

local function PrintReport()
    PrintHeader()
    PrintApi()
    PrintSavedVars()
    PrintVisibility()
    PrintStance()
    PrintSecrets()
    PrintEvents()
    Print("end of report. /probe log shows the event log.")
end

local function PrintHelp()
    Print("commands:")
    print("  /probe           full report")
    print("  /probe log       print the event log (stance changes, visibility toggles, clicks)")
    print("  /probe clear     clear the event log")
    print("  /probe secrets   take a secret-value snapshot now and print it")
    print("  /probe stance    log the current stance state and ACTIONBUTTON1 mapping")
    print("  /probe fill      copy the spell in slot 1 into slot 73 (out of combat)")
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------
local function OnLogin()
    Try("API presence", ProbeApiPresence)
    Try("secure snippet probe", ProbeSecureSnippets)
    Try("visibility drivers", SetupVisibilityDrivers)
    Try("fixed action button", CreateActionButton)
    Try("ActionButton1 hook", HookActionButton1)
    Try("event registration", RegisterDesignEvents)
    Try("login stance", function() Log("login " .. (RecordStance())) end)
    Try("login secret snapshot", SnapshotSecrets, "login")
    Print("loaded. /probe for the report, /probe help for commands.")
end

local mainFrame = CreateFrame("Frame", "RikProbeMain")
mainFrame:RegisterEvent("ADDON_LOADED")
mainFrame:RegisterEvent("PLAYER_LOGIN")
mainFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        Try("saved variables", SeedSavedVars)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        Try("login", OnLogin)
    end
end)

------------------------------------------------------------------------
-- Slash command
------------------------------------------------------------------------
SLASH_RIKPROBE1 = "/probe"
SlashCmdList.RIKPROBE = function(input)
    local cmd = (input or ""):match("^(%S*)"):lower()
    if cmd == "" or cmd == "report" then
        Try("report", PrintReport)
    elseif cmd == "log" then
        for _, line in ipairs(P.log) do print(PREFIX .. line) end
    elseif cmd == "clear" then
        P.log = {}
        Print("log cleared")
    elseif cmd == "secrets" then
        Try("snapshot", SnapshotSecrets, InCombatLockdown() and "in combat" or "out of combat")
        Try("print secrets", PrintSecrets)
    elseif cmd == "stance" then
        Try("stance", LogButton1Mapping, "now")
    elseif cmd == "fill" then
        Try("fill", FillFixedSlot)
    else
        PrintHelp()
    end
end
