-- Tooltip lines, colours and the unit health bar through TooltipDataProcessor post-calls.
-- Every value is guarded by issecretvalue before it is compared or formatted. The health bar is
-- Blizzard's GUID-watched GameTooltip.StatusBar: its SetWatch is written for tainted callers and
-- its secure mixin feeds SetValue, so nothing here reads UnitHealth or writes a bar value.
local core, media, ui, tooltip = RikUI, RikUI.Media, RikUI.UI, RikUI.Tooltip
local ITEM_LEVEL_FORMAT, SPELL_ID_FORMAT = "Item level %d", "Spell ID %d"
local LINE_COLOR, GUILD_COLOR = { r = 0.7, g = 0.7, b = 0.7 }, { r = 0.55, g = 0.75, b = 1 }
local HANDLER_TYPES = { "Unit", "Item", "Spell" } -- Enum.TooltipDataType keys
local warnings = {}

local function warnOnce(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Tooltip " .. operation .. ": " .. tostring(reason))
end

local function readable(value, kind)
    return not core.Secret.IsSecret(value) and type(value) == kind
end

local function api(namespace, name)
    local holder = namespace and _G[namespace] or _G
    if type(holder) == "table" and type(holder[name]) == "function" then return holder[name] end
    return function() error(name .. " unavailable", 0) end
end

local function line(frame, index)
    if type(frame.GetLeftLine) == "function" then return frame:GetLeftLine(index) end
    local name = frame:GetName()
    return name and _G[name .. "TextLeft" .. index] or nil
end

local function tint(region, color)
    if region then region:SetTextColor(color.r, color.g, color.b) end
end

-- The unit token behind the tooltip, or nil when it is secret, missing or unreadable.
local function unitToken(frame, guid)
    if readable(guid, "string") then
        local ok, unit = core.Secret.Read(api(nil, "UnitTokenFromGUID"), guid)
        if not ok then warnOnce("unit token", unit); return nil end
        return readable(unit, "string") and unit or nil
    end
    if type(frame.GetUnit) ~= "function" then return nil end
    local ok, _, unit = core.Secret.Read(frame.GetUnit, frame)
    return ok and readable(unit, "string") and unit or nil
end

local function tintGuild(frame, unit)
    local ok, guild = core.Secret.Read(api(nil, "GetGuildInfo"), unit)
    if not ok then warnOnce("guild", guild); return end
    if not readable(guild, "string") or guild == "" then return end
    local region = line(frame, 2)
    local text = region and region:GetText()
    if readable(text, "string") and text:find(guild, 1, true) then tint(region, GUILD_COLOR) end
end

local function styleBar(bar)
    if bar.rikStyled == true then return end
    bar.rikStyled, bar.lockColor = true, true -- lockColor stops HealthBar_OnValueChanged recolouring it
    bar:SetStatusBarTexture(media.statusbar)
    bar.rikBackground = bar:CreateTexture(nil, "BACKGROUND")
    bar.rikBackground:SetAllPoints()
    bar.rikBackground:SetColorTexture(0, 0, 0, 0.4)
end

-- SetWatch is the sanctioned tainted entry: it stores the guid and the secure mixin fills the bar.
local function watchHealth(frame, guid, unit)
    local bar = tooltip.Child(frame, "StatusBar")
    if not bar or type(bar.SetWatch) ~= "function" then return end
    styleBar(bar)
    local color = unit and ui.HealthColor(unit) or ui.Colors.neutral
    bar:SetStatusBarColor(color.r, color.g, color.b)
    if not readable(guid, "string") or bar:IsShown() then return end
    local ok, reason = pcall(bar.SetWatch, bar, guid)
    if not ok then warnOnce("health", reason) end
end

local function onUnit(frame, data)
    if tooltip.HideInCombat() and InCombatLockdown() then frame:Hide(); return end
    local guid = type(data) == "table" and data.guid or nil
    local unit = unitToken(frame, guid)
    if unit then
        tint(line(frame, 1), ui.HealthColor(unit))
        tintGuild(frame, unit)
    end
    if guid ~= nil then watchHealth(frame, guid, unit) end
end

local function itemLevel(data)
    local item = data.hyperlink
    if item == nil then item = data.id end
    if item == nil or core.Secret.IsSecret(item) then return nil end
    local ok, level = core.Secret.Read(api("C_Item", "GetDetailedItemLevelInfo"), item)
    if not ok then warnOnce("item level", level); return nil end
    if readable(level, "number") and level > 0 then return level end
    return nil
end

local function onItem(frame, data)
    if type(data) ~= "table" then return end
    local level = itemLevel(data)
    if level then frame:AddLine(string.format(ITEM_LEVEL_FORMAT, level), LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b) end
end

local function onSpell(frame, data)
    if type(data) ~= "table" or not readable(data.id, "number") then return end
    frame:AddLine(string.format(SPELL_ID_FORMAT, data.id), LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b)
end

local HANDLERS = { Unit = onUnit, Item = onItem, Spell = onSpell }

-- The client runs insecure post-calls through a delegate; a failure here must not reach it.
local function guarded(name, handler)
    return function(frame, data)
        if not tooltip.enabled then return end
        local ok, reason = pcall(handler, frame, data)
        if not ok then warnOnce(name:lower() .. " data", reason) end
    end
end

function tooltip.RegisterData()
    local processor = TooltipDataProcessor
    local types = type(Enum) == "table" and Enum.TooltipDataType
    if type(processor) ~= "table" or type(processor.AddTooltipPostCall) ~= "function" or type(types) ~= "table" then
        tooltip.Warn("data processor", "unavailable; unit colours, item level and spell ID lines are off")
        return false
    end
    for _, name in ipairs(HANDLER_TYPES) do
        if types[name] ~= nil then processor.AddTooltipPostCall(types[name], guarded(name, HANDLERS[name])) end
    end
    tooltip.DataReady = true
    return true
end
