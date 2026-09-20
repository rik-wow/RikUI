-- Cosmetic action state; secure attributes and native bindings remain owned by src/modules/bars/bars.lua.
local core, bars = RikUI, RikUI.Bars

local PREFIXES = { main = "ACTIONBUTTON", bar2 = "MULTIACTIONBAR1BUTTON",
    bar3 = "MULTIACTIONBAR2BUTTON", bar4 = "MULTIACTIONBAR3BUTTON", bar5 = "MULTIACTIONBAR4BUTTON" }
local NATIVE_BARS = { MultiBarBottomLeft = "bar2", MultiBarBottomRight = "bar3",
    MultiBarRight = "bar4", MultiBarLeft = "bar5" }
local WHITE, RED, BLUE, GREY = { 1, 1, 1 }, { 1, 0.2, 0.2 }, { 0.2, 0.4, 1 }, { 0.4, 0.4, 0.4 }
local warnings, pressed, rangeSlots = {}, {}, {}
local stateEnabled = false

local function warnOnce(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Bars " .. operation .. ": " .. tostring(reason))
end

local function readableBoolean(value)
    if core.Secret.IsSecret(value) then return nil end
    if value == true or value == 1 then return true end
    if value == false or value == 0 then return false end
end

local function reader(name, legacy)
    return C_ActionBar and C_ActionBar[name] or legacy
end

local function updateTint(button, occupied)
    local color = WHITE
    if occupied then
        local ok, range = core.Secret.Read(reader("IsActionInRange", IsActionInRange), button.action, "target")
        local usableOK, usable, resource = core.Secret.Read(reader("IsUsableAction", IsUsableAction), button.action)
        if ok and readableBoolean(range) == false then color = RED
        elseif usableOK and readableBoolean(resource) == true then color = BLUE
        elseif usableOK and readableBoolean(usable) == false then color = GREY end
        if not ok then warnOnce("range", range) end
        if not usableOK then warnOnce("usable", usable) end
    end
    button.icon:SetVertexColor(unpack(color))
end

local function updateCooldown(widget, api, slot, occupied)
    if not occupied then widget:Clear(); return end
    local ok, reason = core.Secret.Apply(function(duration)
        if not core.Secret.IsSecret(duration) and duration == nil then widget:Clear()
        else widget:SetCooldownFromDurationObject(duration, true) end
    end, reader(api), slot)
    if not ok then widget:Clear(); warnOnce(api, reason) end
end

local function activeTexture(texture, api, legacy, slot, occupied)
    if not occupied then texture:SetAlphaFromBoolean(false, 1, 0); return end
    local ok, reason = core.Secret.Apply(function(value) texture:SetAlphaFromBoolean(value, 1, 0) end,
        reader(api, legacy), slot)
    if not ok then texture:SetAlphaFromBoolean(false, 1, 0); warnOnce(api, reason) end
end

local function updateActive(button)
    activeTexture(button.current, "IsCurrentAction", IsCurrentAction, button.action, button.stateOccupied)
    activeTexture(button.repeating, "IsAutoRepeatAction", IsAutoRepeatAction, button.action, button.stateOccupied)
end

function bars.RefreshButtonState(button, occupied)
    if not button.cooldown then return end
    button.stateOccupied = occupied
    updateCooldown(button.cooldown, "GetActionCooldownDuration", button.action, occupied)
    updateCooldown(button.chargeCooldown, "GetActionChargeDuration", button.action, occupied)
    updateTint(button, occupied)
    updateActive(button)
    button.hotkey:SetText(core.Bindings.Label(button.bindingCommand))
    if not occupied then button.pressedFlash:SetAlpha(0) end
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
    if charge then
        local font = widget:GetCountdownFontString()
        font:ClearAllPoints()
        font:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
        font:SetFontObject("NumberFontNormalSmall")
    end
    return widget
end

local function overlay(button)
    local frame = CreateFrame("Frame", nil, button)
    frame:SetAllPoints(button)
    frame:EnableMouse(false)
    frame:SetFrameLevel(math.max(button.cooldown:GetFrameLevel(), button.chargeCooldown:GetFrameLevel()) + 1)
    button.count:SetParent(frame)
    return frame
end

function bars.CreateButtonState(button, bar, index)
    local prefix = PREFIXES[bar.positionKey or bar.key]
    button.bindingCommand = prefix and prefix .. index or ""
    button.cooldown, button.chargeCooldown = cooldown(button, false), cooldown(button, true)
    button.stateOverlay = overlay(button)
    button.hotkey = button.stateOverlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.hotkey:SetPoint("TOPRIGHT", -2, -2)
    button.pressedFlash = button.stateOverlay:CreateTexture(nil, "ARTWORK")
    button.pressedFlash:SetAllPoints()
    button.pressedFlash:SetColorTexture(1, 1, 1, 0.45)
    button.pressedFlash:SetAlpha(0)
    bars.SkinButtonState(button)
    button:HookScript("OnHide", function() button.pressedFlash:SetAlpha(0) end)
    if not rangeSlots[button.action] then
        local ok, reason = pcall(reader("EnableActionRangeCheck"), button.action, true)
        if ok then rangeSlots[button.action] = true else warnOnce("range notifications", reason) end
    end
end

local function eachButton(callback, slot)
    if core.Secret.IsSecret(slot) then slot = nil end
    for _, bar in pairs(bars.Frames) do
        for _, button in ipairs(bar.buttons) do
            if button.cooldown and (not slot or slot == 0 or slot == button.action) then callback(button) end
        end
    end
end

local function refreshTints(slot)
    eachButton(function(button) updateTint(button, button.stateOccupied) end, slot)
end

local function refreshCooldowns()
    eachButton(function(button)
        updateCooldown(button.cooldown, "GetActionCooldownDuration", button.action, button.stateOccupied)
        updateCooldown(button.chargeCooldown, "GetActionChargeDuration", button.action, button.stateOccupied)
    end)
end

local function release(command)
    for _, button in ipairs(pressed[command] or {}) do button.pressedFlash:SetAlpha(0) end
    pressed[command] = nil
end

local function press(command, native)
    release(command)
    local action = native and native.action
    if core.Secret.IsSecret(action) or type(action) ~= "number" then return end
    pressed[command] = {}
    eachButton(function(button)
        if button.bindingCommand == command and button.stateOccupied and button:IsVisible()
            and button:GetEffectiveAlpha() > 0 then
            button.pressedFlash:SetAlpha(1)
            table.insert(pressed[command], button)
        end
    end, action)
end

local function mainPress(id, down)
    if core.Secret.IsSecret(id) or type(id) ~= "number" then return end
    local command = "ACTIONBUTTON" .. id
    if not down then release(command); return end
    if C_PetBattles and C_PetBattles.IsInBattle() then return end
    local ok, native = pcall(GetActionButtonForID, id)
    if ok then press(command, native) else warnOnce("main key feedback", native) end
end

local function multiPress(name, id, down)
    if core.Secret.IsSecret(name) or core.Secret.IsSecret(id)
        or type(name) ~= "string" or type(id) ~= "number" then return end
    local key = NATIVE_BARS[name]
    if not key then return end
    local command = PREFIXES[key] .. id
    if not down then release(command); return end
    local nativeBar = _G[name]
    press(command, nativeBar and nativeBar.actionButtons and nativeBar.actionButtons[id])
end

local function hook(name, callback)
    local ok, reason = pcall(hooksecurefunc, name, callback)
    if not ok then warnOnce(name, reason) end
end

local function keepRangeNotifications()
    if not C_ActionBar or type(C_ActionBar.EnableActionRangeCheck) ~= "function" then return end
    local ok, reason = pcall(hooksecurefunc, C_ActionBar, "EnableActionRangeCheck", function(slot, enabled)
        if core.Secret.IsSecret(slot) or readableBoolean(enabled) ~= false or not rangeSlots[slot] then return end
        -- Native OnHide disables this global slot subscription when we park stock bars.
        local restored, failure = pcall(C_ActionBar.EnableActionRangeCheck, slot, true)
        if not restored then warnOnce("range notifications", failure) end
    end)
    if not ok then warnOnce("range notification hook", reason) end
end

function bars.EnableButtonState()
    if stateEnabled then return end
    stateEnabled = true
    keepRangeNotifications()
    hook("ActionButtonDown", function(id) mainPress(id, true) end)
    hook("ActionButtonUp", function(id) mainPress(id, false) end)
    hook("MultiActionButtonDown", function(name, id) multiPress(name, id, true) end)
    hook("MultiActionButtonUp", function(name, id) multiPress(name, id, false) end)
    core:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN", refreshCooldowns)
    core:RegisterEvent("ACTIONBAR_UPDATE_STATE", function() eachButton(updateActive) end)
    core:RegisterEvent("ACTION_USABLE_CHANGED", function() refreshTints() end)
    core:RegisterEvent("ACTION_RANGE_CHECK_UPDATE", function(_, slot) refreshTints(slot) end)
    core:RegisterEvent("PLAYER_TARGET_CHANGED", function() refreshTints() end)
    core:RegisterEvent("UNIT_POWER_UPDATE", function(_, unit) if unit == "player" then refreshTints() end end)
    for _, event in ipairs({ "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_BINDINGS",
        "PLAYER_ENTERING_WORLD" }) do
        core:RegisterEvent(event, function()
            for command in pairs(pressed) do release(command) end
        end)
    end
end

local function diagnosticSlot()
    if bars.DebugSlot then return bars.DebugSlot end
    local slot = ActionButton1 and ActionButton1.action
    if not core.Secret.IsSecret(slot) and type(slot) == "number" then return slot end
    return 1
end

function bars:Debug(report)
    local slot = diagnosticSlot()
    core:Print("Bars sample: slot=" .. slot .. " combat=" .. tostring(InCombatLockdown()))
    report("GetActionCooldown", GetActionCooldown, slot)
    report("GetActionCount", GetActionCount, slot)
    report("IsUsableAction", IsUsableAction, slot)
    report("IsActionInRange", IsActionInRange, slot, "target")
    local ok, value = core.Secret.Read(IsActionInRange, slot, "target")
    if ok and not core.Secret.IsSecret(value) then core:Print("Bars sample: range=" .. tostring(value)) end
    if C_ActionBar and C_ActionBar.HasRangeRequirements then
        local readable, hasRange = core.Secret.Read(C_ActionBar.HasRangeRequirements, slot)
        if readable and not core.Secret.IsSecret(hasRange) then
            core:Print("Bars sample: hasRange=" .. tostring(hasRange))
        end
    end
end

core:RegisterCommand("bardebug", function(args)
    local slot = args:match("^%d+$") and tonumber(args)
    if not slot or slot < 1 or slot >= math.huge then
        core:Print("Usage: /rik bardebug <absolute action slot>; then /rik debug in combat.")
        return
    end
    bars.DebugSlot = slot
    core:Debug()
end, "Select an action slot for /rik debug")
