-- Tooltip lines, colours and the unit health bar through TooltipDataProcessor post-calls.
-- Every value is guarded by issecretvalue before it is compared or formatted. The health bar is
-- Blizzard's GUID-watched GameTooltip.StatusBar: its SetWatch is written for tainted callers and
-- its secure mixin feeds SetValue, so nothing here reads UnitHealth or writes a bar value.
local core, media, ui, tooltip = RikUI, RikUI.Media, RikUI.UI, RikUI.Tooltip
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

local function validCount(value)
    return readable(value, "number") and value >= 0 and value < math.huge and value == math.floor(value)
end

local function ownedText(data)
    if core.Profile.tooltip.ownedCounts == false or not C_Item or type(C_Item.GetItemCount) ~= "function" then return end
    local item = data.id
    if not readable(item, "number") then item = data.hyperlink end
    if not readable(item, "number") and not readable(item, "string") then return end
    local ok, carried = pcall(C_Item.GetItemCount, item, false, false, false, false)
    if not ok or not validCount(carried) then return end
    local bankOk, total = pcall(C_Item.GetItemCount, item, true, false, false, false)
    local text = "Carried/equipped: " .. carried
    if bankOk and validCount(total) and total >= carried then text = text .. "  Bank: " .. (total - carried) end
    return text
end

local function addOwnership(frame, data)
    local text = ownedText(data)
    if not text then return end
    for index = 1, frame:NumLines() do
        local region = line(frame, index)
        local current = region and region:GetText()
        if readable(current, "string") and current:find("Carried/equipped: ", 1, true) == 1 then
            region:SetText(text)
            return
        end
    end
    frame:AddLine(text, LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b)
end

local function metadata(frame, prefix, value)
    if not readable(value, "number") or value <= 0 or value >= math.huge or value % 1 ~= 0 then return end
    local text = prefix .. string.format("%d", value)
    for index = 1, frame:NumLines() do
        local region = line(frame, index)
        local current = region and region:GetText()
        if readable(current, "string") and current:find(prefix, 1, true) == 1 then
            region:SetText(text)
            return
        end
    end
    frame:AddLine(text, LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b)
end

local function moneyText(value)
    local gold, silver, copper = math.floor(value / 10000), math.floor(value / 100) % 100, value % 100
    if gold > 0 then return string.format("%dg %ds %dc", gold, silver, copper) end
    if silver > 0 then return string.format("%ds %dc", silver, copper) end
    return string.format("%dc", copper)
end

local function vendorText(data)
    if core.Profile.tooltip.vendorValues ~= true or not C_Item or type(C_Item.GetItemInfo) ~= "function" then return end
    local item = data.hyperlink
    if not readable(item, "string") then item = data.id end
    if not readable(item, "string") and not validCount(item) then return end
    local ok, _, _, _, _, _, _, _, stack, _, _, price = core.Secret.Read(C_Item.GetItemInfo, item)
    if not ok or not validCount(price) or price <= 0 or price > 1000000000000 then return end
    local text = "Vendor each: " .. moneyText(price)
    if validCount(stack) and stack > 1 and stack <= 100000 and price * stack <= 1000000000000 then
        text = text .. "  Full stack (" .. stack .. "): " .. moneyText(price * stack)
    end
    return text
end

local function addVendorValue(frame, data)
    local text = vendorText(data)
    if not text then return end
    for index = 1, frame:NumLines() do
        local region = line(frame, index)
        local current = region and region:GetText()
        if readable(current, "string") and current:find("Vendor each: ", 1, true) == 1 then
            region:SetText(text)
            return
        end
    end
    frame:AddLine(text, LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b)
end

local function onItem(frame, data)
    if type(data) ~= "table" then return end
    if core.Profile.tooltip.itemLevel ~= false then metadata(frame, "Item level ", itemLevel(data)) end
    if core.Profile.tooltip.itemID == true then metadata(frame, "Item ID ", data.id) end
    addOwnership(frame, data)
    addVendorValue(frame, data)
end

local function onSpell(frame, data)
    if type(data) ~= "table" or not readable(data.id, "number") then return end
    if core.Profile.tooltip.spellID ~= false then metadata(frame, "Spell ID ", data.id) end
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
