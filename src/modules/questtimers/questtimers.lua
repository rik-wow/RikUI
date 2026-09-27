-- A flat list of quest timers. Blizzard's QuestTimerFrame is a child of ObjectiveTrackerFrame,
-- which the quest tracker module parks, so without this a timed quest shows no countdown. The
-- client answers C_QuestLog.GetQuestTimers with the seconds left per quest; that is quest log
-- state, not a unit value, so it is formatted here, under pcall. The list is read on
-- QUEST_LOG_UPDATE and once a second while it is not empty. Rows are unprotected and show and
-- hide in combat.
local core, media, layout, skin, motion = RikUI, RikUI.Media, RikUI.Layout, RikUI.Skin, RikUI.Motion
local timers = { Rows = {} }
core.QuestTimers = timers

local HOLDER_NAME, KEY = "RikUIQuestTimers", "questtimers"
local WIDTH, HEIGHT, GAP, TEXT_INSET, MAX_ROWS = 220, 18, 2, 5, 5
-- The quest tracker starts at y = -260; two rows fit above it.
local DEFAULTS = { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -126, y = -218 }
local LOW_COLOR, TIME_COLOR = { 1, 0.15, 0.15 }, { 1, 0.82, 0 }
local TICK_SECONDS, LOW_SECONDS, PULSE_SECONDS, PULSE_ALPHA = 1, 30, 0.4, 0.45
local holder, warnings, sinceTick = nil, {}, 0

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Quest timers " .. operation .. ": " .. tostring(reason))
end

local function describe(seconds)
    seconds = math.max(0, math.floor(seconds))
    local hours, minutes = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
    if hours > 0 then return string.format("%d:%02d:%02d", hours, minutes, seconds % 60) end
    return string.format("%d:%02d", minutes, seconds % 60)
end

local FINAL_SECONDS, FINAL_PULSE_SECONDS, QUIET_ALPHA = 10, 0.18, 0.12
local function setLow(row, low, critical)
    critical = critical == true
    local quiet = motion.Reduced()
    if row.isLow == low and row.isCritical == critical and row.quiet == quiet then return end
    row.isLow, row.isCritical, row.quiet = low, critical, quiet
    row.time:SetTextColor(unpack(critical and LOW_COLOR or TIME_COLOR))
    row.severity:SetVertexColor(unpack(critical and LOW_COLOR or low and TIME_COLOR or skin.LINE))
    motion.Stop(row.pulse)
    row.low:SetAlpha(low and quiet and QUIET_ALPHA or 0)
    if not low or quiet then return end
    row.pulse = row.pulse or motion.Pulse(row.low, 0, PULSE_ALPHA, PULSE_SECONDS)
    if row.pulse then row.pulse.rikAlpha:SetDuration(critical and FINAL_PULSE_SECONDS or PULSE_SECONDS) end
    motion.Play(row.pulse)
end

local function text(row, justify, point, x)
    local value = row:CreateFontString(nil, "OVERLAY")
    media.Font(value, "small")
    value:SetJustifyH(justify)
    value:SetWordWrap(false)
    value:SetPoint(point, row, point, x, 0)
    return value
end

local function timerChrome(row)
    row.timeBacking = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.timeBacking:SetPoint("TOPRIGHT", row, "TOPRIGHT", -1, -1)
    row.timeBacking:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    row.timeBacking:SetWidth(72)
    row.timeBacking:SetColorTexture(0.025, 0.035, 0.05, 0.85)
    row.severity = row:CreateTexture(nil, "OVERLAY")
    row.severity:SetTexture(skin.FLAT)
    row.severity:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    row.severity:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 1)
    row.severity:SetWidth(2)
end

local function createRow(index)
    local row = CreateFrame("Frame", nil, holder)
    row:SetHeight(HEIGHT)
    local offset = (index - 1) * (HEIGHT + GAP)
    row:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -offset)
    row:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -offset)
    row.rikFill, row.rikBorder = skin.Fill(row, skin.BACKING), skin.Outline(row)
    row.low = row:CreateTexture(nil, "ARTWORK")
    row.low:SetAllPoints(row)
    row.low:SetTexture(skin.FLAT)
    row.low:SetVertexColor(unpack(LOW_COLOR))
    row.low:SetAlpha(0)
    timerChrome(row)
    row.title, row.time = text(row, "LEFT", "LEFT", TEXT_INSET), text(row, "RIGHT", "RIGHT", -TEXT_INSET)
    row.time:SetWidth(64)
    row.title:SetPoint("RIGHT", row.time, "LEFT", -10, 0)
    row.time:SetTextColor(unpack(TIME_COLOR))
    row.fade = motion.Tween(row, 0, 1, skin.FADE_SECONDS)
    row.pulse = motion.Pulse(row.low, 0, PULSE_ALPHA, PULSE_SECONDS)
    row:HookScript("OnHide", function()
        setLow(row, false)
        motion.Stop(row.fade)
        row.questID = nil
    end)
    row:Hide()
    timers.Rows[index] = row
    return row
end

local function title(questID)
    local ok, value = pcall(C_QuestLog.GetTitleForQuestID, questID)
    return ok and type(value) == "string" and value or ""
end

local function fill(row, info)
    local appearing = not row:IsShown() or row.questID ~= info.questID
    if appearing then setLow(row, false) end
    row.questID = info.questID
    row.title:SetText(title(info.questID))
    row.time:SetText(describe(info.questTimer))
    row:Show()
    setLow(row, info.questTimer <= LOW_SECONDS, info.questTimer <= FINAL_SECONDS)
    if appearing and not motion.Reduced() then motion.Play(row.fade) end
end

local function render(list)
    local count = math.min(#list, MAX_ROWS)
    for index = 1, count do fill(timers.Rows[index] or createRow(index), list[index]) end
    for index = count + 1, #timers.Rows do
        setLow(timers.Rows[index], false)
        timers.Rows[index]:Hide()
    end
    return count
end

local function read()
    local list = C_QuestLog.GetQuestTimers()
    return render(type(list) == "table" and list or {})
end

local function onUpdate(_, elapsed)
    sinceTick = sinceTick + elapsed
    if sinceTick < TICK_SECONDS then return end
    timers.Refresh()
end

-- The ticker only runs while a timer is showing.
function timers.Refresh()
    if not holder then return end
    sinceTick = 0
    local ok, count = pcall(read)
    if not ok then
        warn("read", count)
        count = render({})
    end
    holder:SetScript("OnUpdate", count > 0 and onUpdate or nil)
end

local function build()
    holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    holder:SetSize(WIDTH, HEIGHT)
    layout.Register(holder, KEY, DEFAULTS)
    timers.Holder = holder
    timers.Refresh()
end

function timers:OnEnable()
    if type(C_QuestLog) ~= "table" or type(C_QuestLog.GetQuestTimers) ~= "function" then return end
    core.Combat.Queue(build)
    core:RegisterEvent("QUEST_LOG_UPDATE", timers.Refresh)
    core:RegisterEvent("PLAYER_ENTERING_WORLD", timers.Refresh)
end

function timers:Debug()
    local shown = 0
    for _, row in ipairs(timers.Rows) do
        if row:IsShown() then shown = shown + 1 end
    end
    core:Print("Quest timers holder=" .. tostring(holder ~= nil) .. " shown=" .. shown)
end

core:RegisterModule("questtimers", timers)
