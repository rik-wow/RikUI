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
local DEFAULTS = { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -16, y = -218 }
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

local function setLow(row, low)
    if row.isLow == low then return end
    row.isLow = low
    if low then motion.Play(row.pulse) return end
    motion.Stop(row.pulse)
    row.low:SetAlpha(0)
end

local function text(row, justify, point, x)
    local value = row:CreateFontString(nil, "OVERLAY")
    media.Font(value, "small")
    value:SetJustifyH(justify)
    value:SetWordWrap(false)
    value:SetPoint(point, row, point, x, 0)
    return value
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
    row.title, row.time = text(row, "LEFT", "LEFT", TEXT_INSET), text(row, "RIGHT", "RIGHT", -TEXT_INSET)
    row.time:SetTextColor(unpack(TIME_COLOR))
    row.fade = motion.Tween(row, 0, 1, skin.FADE_SECONDS)
    row.pulse = motion.Pulse(row.low, 0, PULSE_ALPHA, PULSE_SECONDS)
    row:Hide()
    timers.Rows[index] = row
    return row
end

local function title(questID)
    local ok, value = pcall(C_QuestLog.GetTitleForQuestID, questID)
    return ok and type(value) == "string" and value or ""
end

local function fill(row, info)
    local wasShown = row:IsShown()
    row.title:SetText(title(info.questID))
    row.time:SetText(describe(info.questTimer))
    setLow(row, info.questTimer <= LOW_SECONDS)
    row:Show()
    if not wasShown then motion.Play(row.fade) end
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
