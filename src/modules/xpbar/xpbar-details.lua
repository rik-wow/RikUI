-- Progress labels and details are readable-only; the primary bar still accepts opaque client values.
local core, xpbar, media, motion = RikUI, RikUI.XPBar, RikUI.Media, RikUI.Motion
local details = {}
xpbar.Details = details
local last, latestGain
local sessionStart, sessionGain, sessionIncomplete = nil, 0, false
local RATE_MIN_SECONDS, SECONDS_PER_HOUR = 60, 3600
local function settings() return core.Profile.xpbar end
local function number(value)
    return not core.Secret.IsSecret(value) and type(value) == "number"
        and value == value and value > -math.huge and value < math.huge
end
local function clock()
    local ok, value = pcall(GetTime)
    if ok and number(value) and value >= 0 then return value end
end
local function startSession()
    if sessionStart == nil then sessionStart = clock() end
end
local function snapshot()
    local current, maximum, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if not number(current) or current < 0 or not number(maximum) or maximum <= 0
        or current > maximum or not number(level) or level < 1 then return end
    return { current = current, maximum = maximum, level = level }
end
function details.Height(key) return settings().compact and 8 or key == "xp" and 18 or 12 end
function details.Animated() return settings().animations and not motion.Reduced() end
function details.Gain()
    local ok, value = pcall(snapshot)
    if not ok or not value then last = nil; sessionIncomplete = true; return false end
    startSession()
    local gain = 0
    if last and value.level == last.level and value.maximum == last.maximum then
        gain = value.current - last.current
    elseif last and value.level == last.level + 1 and value.current < last.current then
        gain = last.maximum - last.current + value.current
    end
    last = value
    if gain <= 0 then return false end
    latestGain = gain
    sessionGain = sessionGain + gain
    return true, gain
end
local function label(parent, role)
    local font = parent:CreateFontString(nil, "OVERLAY")
    media.Font(font, role)
    font:SetWordWrap(false)
    return font
end
local GAIN_SECONDS, GAIN_RISE = 0.85, 14
local function clearGain(row)
    motion.Stop(row.gainAnim)
    if row.gainText then row.gainText:SetAlpha(0) end
end
function details.ShowGain(row, amount)
    if not number(amount) or amount <= 0 or not details.Animated()
        or settings().compact or not settings().text then return end
    if not row.gainText then
        row.gainText = label(row.bar, "label")
        row.gainText:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT", -6, 2)
        row.gainText:SetTextColor(0.8, 0.65, 1)
        row.gainText:SetAlpha(0)
        row.gainAnim = motion.Tween(row.gainText, 1, 0, GAIN_SECONDS)
        if row.gainAnim then
            local rise = row.gainAnim:CreateAnimation("Translation")
            rise:SetOffset(0, GAIN_RISE)
            rise:SetDuration(GAIN_SECONDS)
        end
        row:HookScript("OnHide", function() clearGain(row) end)
    end
    row.gainText:SetText(string.format("+%d XP", amount))
    motion.Play(row.gainAnim)
end

local function placeTicks(row, width)
    width = width or row:GetWidth()
    if width <= 0 then width = row:GetParent():GetWidth() end
    for index, tick in ipairs(row.ticks) do
        tick:ClearAllPoints()
        tick:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", width * index / 10, 0)
    end
end

function details.Build(row, key)
    row:HookScript("OnHide", function() motion.Stop(row.flashAnim); motion.Stop(row.levelAnim) end)
    row.captionBacking = row.bar:CreateTexture(nil, "ARTWORK", nil, 1)
    row.captionBacking:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    row.captionBacking:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 3)
    row.captionBacking:SetColorTexture(0.025, 0.03, 0.045, 0.6)
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
        row.ticks[index] = tick
    end
    row:HookScript("OnSizeChanged", placeTicks)
    placeTicks(row)
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
local function sessionRate()
    if sessionIncomplete then return nil, "Pace: gaps; reset session" end
    local at = clock()
    if not at or not sessionStart or at < sessionStart then return nil, "Pace unavailable" end
    if at - sessionStart < RATE_MIN_SECONDS or sessionGain <= 0 then return nil, "Pace: gathering XP" end
    local rate = sessionGain / (at - sessionStart) * SECONDS_PER_HOUR
    if not number(rate) or rate <= 0 then return nil, "Pace unavailable" end
    return rate
end
local function xpText()
    local value = snapshot()
    if not value then return settings().pace and "Pace unavailable" or "Experience" end
    local remaining = math.max(0, value.maximum - value.current)
    if settings().pace then
        local rate, status = sessionRate()
        if not rate then return string.format("Level %d   |   %s", value.level, status) end
        local minutes = remaining / rate * 60
        if not number(minutes) then return "Pace unavailable" end
        local eta = minutes > 9999 and ">9999m" or "~" .. math.ceil(minutes) .. "m"
        local hourly = rate > 1000000000 and ">1B" or string.format("%.0f", rate)
        return string.format("Level %d   |   %s XP/h   |   %s to level", value.level, hourly, eta)
    end
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
local function paceTick(row, elapsed)
    row.paceElapsed = (row.paceElapsed or 0) + elapsed
    if row.paceElapsed < 1 then return end
    row.paceElapsed = 0
    local ok, text = pcall(xpText)
    row.caption:SetText(ok and text or "Pace unavailable")
end
local previousFaction
local REP_GAIN_COLOR = { 0.3, 1, 0.6 }
local function reputationGain(faction)
    local row = xpbar.Rows.reputation
    if not faction or not number(faction.factionID) or faction.factionID <= 0
        or not number(faction.currentStanding) then previousFaction = nil; return end
    local before = previousFaction
    previousFaction = { id = faction.factionID, standing = faction.currentStanding }
    if not before or before.id ~= faction.factionID or faction.currentStanding <= before.standing then return end
    if row and row:IsShown() and details.Animated() then
        row.flash:SetVertexColor(unpack(REP_GAIN_COLOR))
        row.flash:SetAlpha(0)
        motion.Play(row.flashAnim)
    end
end
function details.Refresh(faction)
    reputationGain(faction)
    startSession()
    if not last then local ok, value = pcall(snapshot); if ok then last = value end end
    for key, row in pairs(xpbar.Rows) do
        if row.caption then
            local ok, value = pcall(key == "xp" and xpText or repText, faction)
            row.caption:SetText(ok and value or key == "xp" and (settings().pace and "Pace unavailable" or "Experience") or "Reputation")
            if key == "xp" then
                if not details.Animated() or settings().compact or not settings().text then clearGain(row) end
                local active = settings().pace and settings().text and not settings().compact and row:IsShown()
                row:SetScript("OnUpdate", active and paceTick or nil)
                if not active then row.paceElapsed = 0 end
            end
            row.caption:SetShown(settings().text and not settings().compact)
            row.captionBacking:SetShown(settings().text and not settings().compact)
            for _, tick in ipairs(row.ticks) do tick:SetShown(settings().ticks) end
        end
    end
end
function details.ResetSession()
    sessionStart, sessionGain, sessionIncomplete, latestGain = clock(), 0, false, nil
    local ok, value = pcall(snapshot)
    last = ok and value or nil
    xpbar.Refresh()
end

local function sessionTooltip(lines, remaining)
    lines[#lines + 1] = string.format("Session: %d XP observed", sessionGain)
    if sessionIncomplete then lines[#lines + 1] = "Session has unreadable gaps; rate unavailable."; return end
    local rate = sessionRate()
    if not rate then return end
    lines[#lines + 1] = string.format("%.0f XP/hour (includes idle time)", rate)
    lines[#lines + 1] = string.format("About %d minutes to level at this pace", math.ceil(remaining / rate * 60))
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
    sessionTooltip(lines, remaining)
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
xpbar.Options = { title = "Experience", settings = {
    { type = "button", key = "resetSession", label = "Session XP statistics", text = "Reset session",
        description = "Start a new session total and pace estimate. Includes idle time; nothing is saved.", action = details.ResetSession },
} }
for _, spec in ipairs({ { "compact", "Compact bars" }, { "text", "Show progress labels" },
    { "pace", "Show session pace in XP label" }, { "animations", "Animate gains and level ups" }, { "ticks", "Show 10% progress ticks" } }) do
    local key, title = unpack(spec)
    table.insert(xpbar.Options.settings, { type = "checkbox", key = "xpbar." .. key, label = title,
        get = function() return settings()[key] end, set = function(value) xpbar.SetOption(key, value) end })
end
