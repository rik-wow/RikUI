-- Forty fixed raid1-40 buttons from the shared unit frame factory, in raid index order.
-- Subgroup columns would mean re-pointing units in combat, which takes a secure group
-- header, and header snippets cannot run on 69913.
local core, layout, unitframes = RikUI, RikUI.Layout, RikUI.UnitFrames
local raid = { Frames = {}, FadeAlpha = 0.45 }
unitframes.Raid = raid

local MEMBERS, ROWS, SPACING, POLL_SECONDS = 40, 5, 4, 0.5
local COLUMNS = MEMBERS / ROWS
local SIZE = { width = 72, height = 30, health = 22, power = 5, font = "small", powerText = false }
-- The party holder's default: the party frames hide in a raid, so the spot is free.
local DEFAULT = { point = "LEFT", relativePoint = "LEFT", x = 20, y = 0 }
local LAYOUT_KEY, HOLDER_NAME = "raid", "RikUIRaid"
local VISIBILITY = "[@%s,exists] show; hide"
-- CompactRaidFrameManager stays: it holds the ready check, markers and raid settings.
local STOCK_FRAMES = { "CompactRaidFrameContainer" }

function raid.UpdateRange(frame)
    unitframes.FadeByRange(frame, raid.FadeAlpha)
end

local function eachMember(callback)
    for _, frame in ipairs(raid.Frames) do callback(frame) end
end

local function refresh()
    eachMember(unitframes.Update)
    eachMember(raid.UpdateRange)
end

local function createHolder()
    local holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    holder:SetSize(COLUMNS * SIZE.width + (COLUMNS - 1) * SPACING, ROWS * SIZE.height + (ROWS - 1) * SPACING)
    holder.elapsed = 0
    holder:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < POLL_SECONDS then return end
        self.elapsed = 0
        eachMember(raid.UpdateRange)
    end)
    layout.Register(holder, LAYOUT_KEY, DEFAULT)
    return holder
end

local function createMember(index)
    local unit = "raid" .. index
    local frame = unitframes.Build({ key = unit, unit = unit, size = SIZE, threat = { unit },
        visibility = VISIBILITY:format(unit) }, raid.Holder)
    local column, row = math.floor((index - 1) / ROWS), (index - 1) % ROWS
    frame:SetPoint("TOPLEFT", raid.Holder, "TOPLEFT", column * (SIZE.width + SPACING),
        -row * (SIZE.height + SPACING))
    -- A slot this small has room for the name only; the bar carries health.
    frame.health.text:Hide()
    frame.level:Hide()
    raid.Frames[index] = frame
end

local function hideStock()
    if not raid.Holder then return end
    for _, name in ipairs(STOCK_FRAMES) do
        -- RikUI frames own raid1-40 now, so no native handler needs to keep running.
        if _G[name] then core.Hide.Frame(_G[name], false) end
    end
end

local function create()
    if raid.Holder then return end
    raid.Holder = createHolder()
    for index = 1, MEMBERS do createMember(index) end
    refresh()
    hideStock()
end

-- Called from the unitframes module's OnEnable; that module routes the unit events.
function raid.Enable()
    core.Combat.Queue(create)
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
        core:RegisterEvent(event, function()
            refresh()
            hideStock()
        end)
    end
end
