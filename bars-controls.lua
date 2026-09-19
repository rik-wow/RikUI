-- Small secure stance and pet rows. Bindings remain Blizzard's native commands.
local core, bars = RikUI, RikUI.Bars
local SIZE, GAP, MAX_FORMS, PET_SLOTS = 30, 6, 10, 10
local STANCE_VISIBILITY = "[possessbar][overridebar] hide; show"
local PET_VISIBILITY = "[@pet,exists,nodead,nopossessbar,nooverridebar] show; hide"
local formsPending = false
bars.ControlFrames = {}

local function report(label, reason)
    core:Print("Bars " .. label .. ": " .. tostring(reason))
end

local function boolean(value)
    if core.Secret.IsSecret(value) then return value end
    return value == true
end

local function indicator(button, texture)
    local art = button:CreateTexture(nil, "OVERLAY")
    art:SetAllPoints()
    art:SetTexture(texture)
    art:SetAlphaFromBoolean(false, 1, 0)
    return art
end

local function autoCastArt(button)
    button.autoCastAllowed = indicator(button, core.Media.checked)
    button.autoCastAllowed:SetVertexColor(0.3, 0.8, 0.4, 1)
    button.autoCastAllowed:ClearAllPoints()
    button.autoCastAllowed:SetPoint("BOTTOMLEFT", 1, 1)
    button.autoCastAllowed:SetSize(7, 7)
    button.autoCastEnabled = indicator(button, core.Media.statusbar)
    button.autoCastEnabled:SetVertexColor(0.3, 1, 0.4, 1)
    button.autoCastEnabled:ClearAllPoints()
    button.autoCastEnabled:SetPoint("BOTTOMLEFT", 2, 2)
    button.autoCastEnabled:SetSize(5, 5)
end

local function createButton(bar, index, kind)
    local button = CreateFrame("Button", bar:GetName() .. "Button" .. index, bar, "SecureActionButtonTemplate")
    button.index = index
    button:SetID(0)
    button:SetAttribute("type1", kind)
    if kind == "pet" then button:SetAttribute("action", index) end
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetSize(SIZE, SIZE)
    button:SetPoint("TOPLEFT", bar, "TOPLEFT", (index - 1) * (SIZE + GAP), 0)
    bars.DecorateButton(button)
    button.hotkey = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.hotkey:SetPoint("TOPRIGHT", -2, -2)
    core.Media.Font(button.hotkey, "hotkey")
    button.bindingCommand = (kind == "pet" and "BONUSACTIONBUTTON" or "SHAPESHIFTBUTTON") .. index
    button.active = bars.CreateActiveTexture(button)
    if kind == "pet" then autoCastArt(button) end
    return button
end

local function createRow(name, count, kind)
    local bar = CreateFrame("Frame", "RikUIBar_" .. name, UIParent)
    bar.key, bar.buttons = name, {}
    bar:SetSize(count * (SIZE + GAP) - GAP, SIZE)
    bars.PositionFrame(bar)
    for index = 1, count do bar.buttons[index] = createButton(bar, index, kind) end
    bars.ControlFrames[name] = bar
    return bar
end

local function visibility(bar, driver)
    local ok, reason = pcall(RegisterStateDriver, bar, "visibility", driver)
    if ok then return end
    local removed, failure = pcall(UnregisterStateDriver, bar, "visibility")
    if not removed then report("visibility cleanup", failure) end
    bar:Hide()
    report("visibility unavailable", reason)
end

local function stanceArt(button)
    button.hotkey:SetText(core.Bindings.Label(button.bindingCommand))
    local ok, texture, active = core.Secret.Read(GetShapeshiftFormInfo, button.index)
    if not ok then report("stance", texture); texture, active = nil, false end
    button.icon:SetTexture(texture)
    button.active:SetAlphaFromBoolean(boolean(active), 1, 0)
end

local function refreshStances()
    local bar = bars.ControlFrames.stance
    if not bar then return end
    for index, button in ipairs(bar.buttons) do
        if index <= (bar.formCount or 0) then stanceArt(button)
        else button.icon:SetTexture(nil); button.active:SetAlphaFromBoolean(false, 1, 0) end
    end
end

local function configureStance(button, count)
    local spell
    if button.index <= count then
        local ok, texture, active, castable, id = core.Secret.Read(GetShapeshiftFormInfo, button.index)
        if not ok then report("stance spell", texture)
        elseif not core.Secret.IsSecret(id) and type(id) == "number" and id > 0 then spell = id end
    end
    button:SetAttribute("spell", spell)
    if spell then button:Show() else button:Hide() end
end

local function configureStances()
    local bar = bars.ControlFrames.stance
    local ok, count = core.Secret.Read(GetNumShapeshiftForms)
    if not ok or core.Secret.IsSecret(count) or type(count) ~= "number" or count < 0 or count > MAX_FORMS then
        report("forms", "known form count unavailable")
        visibility(bar, "hide")
        return
    end
    bar.formCount = count
    for _, button in ipairs(bar.buttons) do configureStance(button, count) end
    bar:SetSize(math.max(1, count) * (SIZE + GAP) - GAP, SIZE)
    visibility(bar, count > 0 and STANCE_VISIBILITY or "hide")
    refreshStances()
end

local function queueForms()
    if formsPending then return end
    formsPending = true
    core.Combat.Queue(function()
        formsPending = false
        if bars.ControlFrames.stance then configureStances() end
    end)
end

local function petArt(button)
    button.hotkey:SetText(core.Bindings.Label(button.bindingCommand))
    local ok, name, texture, token, active, allowed, enabled = core.Secret.Read(GetPetActionInfo, button.index)
    if not ok then
        report("pet action", name)
        texture, active, allowed, enabled = nil, false, false, false
    elseif not core.Secret.IsSecret(token) and token == true then
        if not core.Secret.IsSecret(texture) and type(texture) == "string" then texture = _G[texture] end
    end
    button.icon:SetTexture(texture)
    button.active:SetAlphaFromBoolean(boolean(active), 1, 0)
    button.autoCastAllowed:SetAlphaFromBoolean(boolean(allowed), 1, 0)
    button.autoCastEnabled:SetAlphaFromBoolean(boolean(enabled), 1, 0)
end

local function refreshPets()
    local bar = bars.ControlFrames.pet
    if not bar then return end
    for _, button in ipairs(bar.buttons) do petArt(button) end
end

function bars.EnableControls()
    core.Combat.Queue(function()
        createRow("stance", MAX_FORMS, "spell")
        local pet = createRow("pet", PET_SLOTS, "pet")
        configureStances()
        visibility(pet, PET_VISIBILITY)
        refreshPets()
    end)
    core:RegisterEvent("UPDATE_BINDINGS", function() refreshStances(); refreshPets() end)
    core:RegisterEvent("UPDATE_SHAPESHIFT_FORMS", queueForms)
    core:RegisterEvent("SPELLS_CHANGED", queueForms)
    for _, event in ipairs({ "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_USABLE" }) do
        core:RegisterEvent(event, refreshStances)
    end
    for _, event in ipairs({ "PET_BAR_UPDATE", "PET_UI_UPDATE", "PET_BAR_UPDATE_USABLE",
        "PLAYER_CONTROL_GAINED", "PLAYER_CONTROL_LOST" }) do core:RegisterEvent(event, refreshPets) end
    core:RegisterEvent("UNIT_PET", function(_, unit) if unit == "player" then refreshPets() end end)
    core:RegisterEvent("PLAYER_ENTERING_WORLD", function() queueForms(); refreshPets() end)
end
