-- Fixed-slot secure buttons. Native key bindings still own keyboard execution.
local core, setup = RikUI, RikUI.Setup
local bars = { Frames = {} }
core.Bars = bars
local BUTTONS, BUTTON_SIZE, BUTTON_GAP = 12, 36, 6
local FADE_SECONDS, LEAVE_DELAY = 0.2, 0.05
local BAR_ORDER = { "main", "bar2", "bar3", "bar4", "bar5" }
local pending, layoutPending = {}, false

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function report(operation, reason)
    core:Print("Bars " .. operation .. ": " .. tostring(reason))
end

local function updateCount(button)
    if C_ActionBar and C_ActionBar.GetActionDisplayCount then
        local ok, reason = core.Secret.Apply(function(value) button.count:SetText(value) end,
            C_ActionBar.GetActionDisplayCount, button.action)
        if not ok then button.count:SetText(""); report("count", reason) end
        return
    end
    local reader = C_ActionBar and C_ActionBar.GetActionUseCount or GetActionCount
    local ok, count = core.Secret.Read(reader, button.action)
    if not ok then button.count:SetText(""); report("count", count); return end
    if core.Secret.IsSecret(count) then
        button.count:SetFormattedText("%d", count)
    elseif type(count) == "number" and count > 1 then
        button.count:SetFormattedText("%d", count)
    else
        button.count:SetText("")
    end
end

local function updateButton(button)
    local reader = C_ActionBar and C_ActionBar.GetActionTexture or GetActionTexture
    local ok, texture = core.Secret.Read(reader, button.action)
    if not ok then report("icon", texture); return end
    button.icon:SetTexture(texture)
    button.icon:SetShown(texture ~= nil)
    button.empty:SetShown(texture == nil)
    if bars.RefreshButtonState then bars.RefreshButtonState(button, texture ~= nil) end
    if texture == nil then button.count:SetText(""); return end
    updateCount(button)
end

function bars.Refresh(slot)
    for _, bar in pairs(bars.Frames) do
        for _, button in ipairs(bar.buttons) do
            if not slot or slot == 0 or slot == button.action then updateButton(button) end
        end
    end
end

local function drag(button, receive)
    -- A cursor is transient: rejecting combat drags is safer than replaying them.
    if InCombatLockdown() then return end
    local ok, reason = pcall(function()
        if receive then
            if not GetCursorInfo() then return end
            PlaceAction(button.action)
        else
            if C_CVar.GetCVar("lockActionBars") == "1" and not IsModifiedClick("PICKUPACTION") then return end
            PickupAction(button.action)
        end
        -- Leave any displaced action on the cursor for the user to place.
        updateButton(button)
    end)
    if not ok then report("drag", reason) end
end

local function reveal(bar)
    bar.fadeOut:Stop()
    bar:SetAlpha(1)
end

local function updateFade(bar)
    if InCombatLockdown() or bar:IsMouseOver() then reveal(bar); return end
    if bar:GetAlpha() > 0 and not bar.fadeOut:IsPlaying() then bar.fadeOut:Play() end
end

local function fadeHandlers(bar, frame)
    frame:HookScript("OnEnter", function() reveal(bar) end)
    frame:HookScript("OnLeave", function()
        C_Timer.After(LEAVE_DELAY, function() updateFade(bar) end)
    end)
end

local function configureFade(bar)
    bar:EnableMouse(true)
    bar.fadeOut = bar:CreateAnimationGroup()
    local alpha = bar.fadeOut:CreateAnimation("Alpha")
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(0)
    alpha:SetDuration(FADE_SECONDS)
    bar.fadeOut:SetScript("OnFinished", function()
        if InCombatLockdown() or bar:IsMouseOver() then reveal(bar) else bar:SetAlpha(0) end
    end)
    fadeHandlers(bar, bar)
    for _, button in ipairs(bar.buttons) do fadeHandlers(bar, button) end
    bar:SetAlpha(bar:IsMouseOver() and 1 or 0)
end

local function position(bar)
    local key = bar.positionKey or bar.key
    core.Layout.Register(bar, key, setup.DefaultPositions[key] or setup.DefaultPositions.main)
    bars.UpdateGryphons(bar)
end

-- Kept for companion factories and callers that also refresh gryphon art.
bars.PositionFrame = position

function bars.ApplyLayout()
    if layoutPending or not core.Profile then return end
    layoutPending = true
    core.Combat.Queue(function()
        layoutPending = false
        core.Layout.Apply()
        for _, bar in pairs(bars.Frames) do bars.UpdateGryphons(bar) end
    end)
end

local function createButton(bar, index, opts)
    local button = CreateFrame("Button", bar:GetName() .. "Button" .. index, bar, "SecureActionButtonTemplate")
    button.action = bar.firstAction + index - 1
    -- A positive frame ID would make CalculateAction use the current page.
    button:SetID(0)
    button:SetAttribute("type", "action")
    button:SetAttribute("action", button.action)
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:RegisterForDrag("LeftButton", "RightButton")
    button:SetSize(opts.size, opts.size)
    local offset = (index - 1) * (opts.size + opts.spacing)
    button:SetPoint("TOPLEFT", bar, "TOPLEFT", opts.vertical and 0 or offset, opts.vertical and -offset or 0)
    bars.DecorateButton(button)
    if bars.CreateButtonState then bars.CreateButtonState(button, bar, index) end
    button:SetScript("OnDragStart", function(self) drag(self, false) end)
    button:SetScript("OnReceiveDrag", function(self) drag(self, true) end)
    updateButton(button)
    return button
end

local function createBar(name, firstAction, opts)
    local bar = CreateFrame("Frame", "RikUIBar_" .. name, UIParent)
    bar.key, bar.firstAction, bar.buttons = name, firstAction, {}
    bar.positionKey = opts.positionKey
    local length = BUTTONS * opts.size + (BUTTONS - 1) * opts.spacing
    bar:SetSize(opts.vertical and opts.size or length, opts.vertical and length or opts.size)
    position(bar)
    for i = 1, BUTTONS do bar.buttons[i] = createButton(bar, i, opts) end
    if opts.fade then configureFade(bar) end
    bars.Frames[name] = bar
    return bar
end

local function options(opts)
    if opts == nil then opts = {} end
    if type(opts) ~= "table" then return nil, "layout options must be a table" end
    local size, spacing = opts.size or BUTTON_SIZE, opts.spacing or BUTTON_GAP
    if not finite(size) or size <= 0 or not finite(spacing) or spacing < 0 then
        return nil, "button size must be positive and spacing nonnegative"
    end
    for _, key in ipairs({ "vertical", "fade" }) do
        if opts[key] ~= nil and type(opts[key]) ~= "boolean" then return nil, key .. " must be a boolean" end
    end
    if opts.positionKey ~= nil and (type(opts.positionKey) ~= "string" or not setup.DefaultPositions[opts.positionKey]) then
        return nil, "unknown position key"
    end
    return { size = size, spacing = spacing, vertical = opts.vertical, fade = opts.fade, positionKey = opts.positionKey }
end

function bars.Create(name, firstAction, layoutOpts)
    if not core.Profile then return nil, "Still loading" end
    if type(name) ~= "string" or not name:match("^[%a][%w_]*$") then return nil, "invalid bar name" end
    if not finite(firstAction) or firstAction < 1 or firstAction % 1 ~= 0 then return nil, "invalid first action" end
    local existing = bars.Frames[name] or pending[name]
    if existing then
        if existing.firstAction ~= firstAction then return nil, "bar already owns a different action range" end
        if bars.Frames[name] then return bars.Frames[name] end
        return nil, "queued"
    end
    local opts, reason = options(layoutOpts)
    if not opts then return nil, reason end
    pending[name] = { firstAction = firstAction }
    local ok, failure = core.Combat.Queue(function()
        pending[name] = nil
        createBar(name, firstAction, opts)
    end)
    if not ok then return nil, failure or "bar creation failed" end
    if bars.Frames[name] then return bars.Frames[name] end
    return nil, "queued"
end

local function refreshFades()
    for _, bar in pairs(bars.Frames) do
        if bar.fadeOut then updateFade(bar) end
    end
end

function bars:OnEnable()
    if bars.EnableButtonState then bars.EnableButtonState() end
    for _, name in ipairs(BAR_ORDER) do
        bars.Create(name, setup.SlotToAction(name, 1), {
            vertical = name == "bar4" or name == "bar5", fade = name == "bar3",
        })
    end
    if bars.EnablePaging then bars.EnablePaging() end
    if bars.EnableControls then bars.EnableControls() end
    bars.UpdateStockVisibility()
    core:RegisterEvent("ACTIONBAR_SLOT_CHANGED", function(_, slot) bars.Refresh(slot) end)
    core:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        bars.Refresh(); bars.ApplyLayout(); refreshFades(); bars.UpdateStockVisibility()
    end)
    for _, event in ipairs({ "UPDATE_BINDINGS", "SPELL_UPDATE_CHARGES", "UPDATE_INVENTORY_ALERTS",
        "BAG_UPDATE_DELAYED", "SPELL_UPDATE_ICON" }) do
        core:RegisterEvent(event, function() bars.Refresh() end)
    end
    core:RegisterEvent("PLAYER_REGEN_DISABLED", refreshFades)
    core:RegisterEvent("PLAYER_REGEN_ENABLED", refreshFades)
end

core:RegisterModule("bars", bars)
