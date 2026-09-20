-- Progress labels and details are readable-only; the primary bar still accepts opaque client values.
local core, xpbar, media, motion = RikUI, RikUI.XPBar, RikUI.Media, RikUI.Motion
local details = {}
xpbar.Details = details
local last, latestGain
local function settings() return core.Profile.xpbar end
local function number(value)
    return not core.Secret.IsSecret(value) and type(value) == "number"
        and value == value and value > -math.huge and value < math.huge
end
local function snapshot()
    local current, maximum, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if not number(current) or current < 0 or not number(maximum) or maximum <= 0
        or not number(level) or level < 1 then return end
    return { current = current, maximum = maximum, level = level }
end
function details.Height(key) return settings().compact and 8 or key == "xp" and 18 or 12 end
function details.Animated() return settings().animations end
function details.Gain()
    local ok, value = pcall(snapshot)
    if not ok or not value then last = nil; return false end
    local gain = 0
    if last and value.level == last.level and value.maximum == last.maximum then
        gain = value.current - last.current
    elseif last and value.level == last.level + 1 and value.current < last.current then
        gain = last.maximum - last.current + value.current
    end
    last = value
    if gain <= 0 then return false end
    latestGain = gain
    return true
end
local function label(parent, role)
    local font = parent:CreateFontString(nil, "OVERLAY")
    media.Font(font, role)
    font:SetWordWrap(false)
    return font
end
function details.Build(row, key)
    row.caption = label(row.bar, "small")
    row.caption:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.caption:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.caption:SetJustifyH("CENTER")
    row.ticks = {}
    for index = 1, 9 do
        local tick = row.bar:CreateTexture(nil, "OVERLAY")
        tick:SetTexture(media.border)
        tick:SetVertexColor(0.02, 0.025, 0.035, 0.7)
        tick:SetSize(1, 4)
        tick:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 498 * index / 10, 0)
        row.ticks[index] = tick
    end
    row.glint = row.bar:CreateTexture(nil, "OVERLAY")
    row.glint:SetTexture(media.highlight)
    row.glint:SetVertexColor(1, 0.82, 0.4, 0)
    row.glint:SetAllPoints(row)
    row.levelAnim = motion.Tween(row.glint, 0.8, 0, 0.8)
    row:SetScript("OnMouseUp", function(_, mouse)
        if mouse == "RightButton" then
            xpbar.SetOption("compact", not settings().compact)
        elseif mouse == "LeftButton" and key == "reputation" and type(ToggleCharacter) == "function" then
            if InCombatLockdown() then core:Print("Open reputation after combat."); return end
            local ok, reason = pcall(ToggleCharacter, "ReputationFrame")
            if not ok then core:Print("XP bar reputation panel: " .. tostring(reason)) end
        end
    end)
end
local function xpText()
    local value = snapshot()
    if not value then return "Experience" end
    local remaining = math.max(0, value.maximum - value.current)
    return string.format("Level %d   |   XP %.0f%%   |   %d to level", value.level,
        value.current / value.maximum * 100, remaining)
end
local function repText(faction)
    if not faction or core.Secret.IsSecret(faction.name) or type(faction.name) ~= "string" then return "Reputation" end
    if not number(faction.currentReactionThreshold) or not number(faction.nextReactionThreshold)
        or not number(faction.currentStanding) then return faction.name end
    local total = faction.nextReactionThreshold - faction.currentReactionThreshold
    if total <= 0 then return faction.name .. "  |  Maximum standing" end
    return string.format("%s  |  %.0f%%", faction.name,
        (faction.currentStanding - faction.currentReactionThreshold) / total * 100)
end
function details.Refresh(faction)
    if not last then local ok, value = pcall(snapshot); if ok then last = value end end
    for key, row in pairs(xpbar.Rows) do
        if row.caption then
            local ok, value = pcall(key == "xp" and xpText or repText, faction)
            row.caption:SetText(ok and value or key == "xp" and "Experience" or "Reputation")
            row.caption:SetShown(settings().text and not settings().compact)
            for _, tick in ipairs(row.ticks) do tick:SetShown(settings().ticks) end
        end
    end
end
function details.Tooltip(lines)
    local value = snapshot()
    if not value then return end
    local remaining = math.max(0, value.maximum - value.current)
    lines[#lines + 1] = string.format("To level %d: %d XP (%.1f%%)", value.level + 1, remaining, remaining / value.maximum * 100)
    if latestGain then
        lines[#lines + 1] = string.format("Last gain: %d XP", latestGain)
        lines[#lines + 1] = string.format("About %d similar gains to level", math.ceil(remaining / latestGain))
    end
    lines[#lines + 1] = "Right-click: compact / detailed"
end
function details.LevelUp()
    if details.Animated() and xpbar.Rows.xp and xpbar.Rows.xp:IsShown() then motion.Play(xpbar.Rows.xp.levelAnim) end
end
function xpbar.SetOption(key, value)
    if type(settings()[key]) ~= "boolean" or type(value) ~= "boolean" then return end
    settings()[key] = value
    if key == "animations" and not value then
        for _, row in pairs(xpbar.Rows) do
            motion.Stop(row.fade); motion.Stop(row.flashAnim); motion.Stop(row.levelAnim)
        end
    end
    core:Changed()
    xpbar.Refresh()
end
xpbar.Options = { title = "Experience", settings = {} }
for _, spec in ipairs({ { "compact", "Compact bars" }, { "text", "Show progress labels" },
    { "animations", "Animate gains and level ups" }, { "ticks", "Show 10% progress ticks" } }) do
    local key, title = unpack(spec)
    table.insert(xpbar.Options.settings, { type = "checkbox", key = "xpbar." .. key, label = title,
        get = function() return settings()[key] end, set = function(value) xpbar.SetOption(key, value) end })
end
