-- Thin experience and reputation rows replacing the stock status tracking bars. Whether these
-- numbers are secret for addon code on 69913 is unverified, so they go reader-to-sink into the
-- StatusBars and every sum or comparison runs inside pcall: a secret drops the rested segment or
-- the tooltip numbers instead of raising. StatusTrackingBarManager parks only once the bar exists.
local core, media, layout, ui, motion = RikUI, RikUI.Media, RikUI.Layout, RikUI.UI, RikUI.Motion
local xpbar = { Rows = {} }
core.XPBar = xpbar

local HOLDER_NAME, KEY = "RikUIXPBar", "xpbar"
local WIDTH, ROW_HEIGHT, GAP, EDGE = 498, 8, 2, 1
local DEFAULTS = { point = "TOP", relativePoint = "BOTTOM", x = 0, y = 36 }
local BACKGROUND, BORDER, WHITE = { 0.06, 0.07, 0.09, 0.9 }, { 0.25, 0.28, 0.32, 1 }, { 1, 1, 1, 1 }
local XP_COLOR, RESTED_COLOR, NEUTRAL_COLOR = { 0.58, 0.35, 0.85 }, { 0.2, 0.45, 0.9 }, { 0.9, 0.7, 0 }
-- Hated to exalted, the client's reaction index.
local REACTION_COLORS = { { 0.8, 0.13, 0.13 }, { 0.8, 0.13, 0.13 }, { 0.75, 0.4, 0.13 }, NEUTRAL_COLOR,
    { 0.2, 0.7, 0.2 }, { 0.2, 0.7, 0.2 }, { 0.2, 0.7, 0.2 }, { 0.2, 0.75, 0.65 } }
local FLAT = "Interface\\BUTTONS\\WHITE8X8"
local FADE_SECONDS, FLASH_SECONDS, FLASH_ALPHA = 0.15, 0.25, 0.5
local ORDER = { "xp", "reputation" }
local STOCK = { "StatusTrackingBarManager" }
local holder, warnings = nil, {}

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("XP bar " .. operation .. ": " .. tostring(reason))
end

local function isFrame(value)
    local kind = type(value)
    return (kind == "table" or kind == "userdata") and type(value.SetParent) == "function"
end

local function statusBar(row, color)
    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetAllPoints(row)
    bar:SetStatusBarTexture(media.statusbar)
    bar:SetStatusBarColor(unpack(color))
    return bar
end

local function hideTooltip() GameTooltip:Hide() end

local function createRow(key, color, tooltip)
    local row = CreateFrame("Frame", nil, holder)
    row:SetHeight(ROW_HEIGHT)
    local background = row:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(row)
    background:SetTexture(FLAT)
    background:SetVertexColor(unpack(BACKGROUND))
    row.rikBorder = ui.Edges(row, EDGE, "BORDER")
    for _, line in ipairs(row.rikBorder) do line:SetVertexColor(unpack(BORDER)) end
    if key == "xp" then row.rested = statusBar(row, RESTED_COLOR) end
    row.bar = statusBar(row, color)
    row.flash = row.bar:CreateTexture(nil, "OVERLAY")
    row.flash:SetAllPoints(row.bar)
    row.flash:SetTexture(FLAT)
    row.flash:SetVertexColor(unpack(WHITE))
    row.flash:SetAlpha(0)
    row.flashAnim = motion.Tween(row.flash, FLASH_ALPHA, 0, FLASH_SECONDS)
    row.fade = motion.Tween(row, 0, 1, FADE_SECONDS)
    row:EnableMouse(true)
    row:SetScript("OnEnter", tooltip)
    row:SetScript("OnLeave", hideTooltip)
    row:Hide()
    xpbar.Rows[key] = row
    return row
end

-- The holder and its rows are unprotected, so showing, hiding and resizing are safe in combat.
local function arrange(wanted)
    local offset = 0
    for _, key in ipairs(ORDER) do
        local row = xpbar.Rows[key]
        local appearing = wanted[key] and not row:IsShown()
        row:SetShown(wanted[key] == true)
        if wanted[key] then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -offset)
            row:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -offset)
            offset = offset + ROW_HEIGHT + GAP
        end
        if appearing then motion.Play(row.fade) end
    end
    holder:SetShown(offset > 0)
    if offset > 0 then holder:SetSize(WIDTH, offset - GAP) end
end

local function levelling()
    if type(IsXPUserDisabled) == "function" and IsXPUserDisabled() == true then return false end
    local rules = GameRulesUtil
    if type(rules) ~= "table" or type(rules.IsPlayerAtEffectiveMaxLevel) ~= "function" then return true end
    local ok, capped = pcall(rules.IsPlayerAtEffectiveMaxLevel)
    return not (ok and capped == true)
end

local function readFaction()
    local data = C_Reputation.GetWatchedFactionData()
    if type(data) ~= "table" or data.factionID == 0 then return nil end
    return data
end

local function watchedFaction()
    if type(C_Reputation) ~= "table" or type(C_Reputation.GetWatchedFactionData) ~= "function" then return nil end
    local ok, data = pcall(readFaction)
    if not ok then warn("reputation", data); return nil end
    return data
end

local function readXP() return UnitXP("player"), UnitXPMax("player") end

-- A secret makes the sum throw, which is the signal to leave the segment out.
local function readRested()
    local rested = GetXPExhaustion()
    if not rested or rested <= 0 then return nil end
    return UnitXP("player") + rested, UnitXPMax("player")
end

local function feedRested(row, easing)
    local ok, total, maximum = pcall(readRested)
    local drawn = ok and total ~= nil
    row.rested:SetShown(drawn)
    if not drawn then return end
    row.rested:SetMinMaxValues(0, maximum)
    row.rested:SetValue(total, easing)
end

local function feedXP(row, easing)
    local ok, reason = core.Secret.Apply(function(current, maximum)
        row.bar:SetMinMaxValues(0, maximum)
        row.bar:SetValue(current, easing)
    end, readXP)
    if not ok then warn("experience", reason) end
    feedRested(row, easing)
end

local function isCapped(data) return data.nextReactionThreshold <= data.currentReactionThreshold end

local function feedReputation(row, data, easing)
    local ok, capped = pcall(isCapped, data)
    if ok and capped then
        row.bar:SetMinMaxValues(0, 1)
        row.bar:SetValue(1, easing)
    else
        row.bar:SetMinMaxValues(data.currentReactionThreshold, data.nextReactionThreshold)
        row.bar:SetValue(data.currentStanding, easing)
    end
    local color = not core.Secret.IsSecret(data.reaction) and REACTION_COLORS[data.reaction] or NEUTRAL_COLOR
    row.bar:SetStatusBarColor(unpack(color))
end

-- A row that was hidden shows another moment's value, so its first fill does not ease.
local function easingFor(row)
    return motion.Interpolation(row:IsShown() and "ExponentialEaseOut" or "Immediate")
end

function xpbar.Refresh()
    if not holder then return end
    local faction = watchedFaction()
    local wanted = { xp = levelling(), reputation = faction ~= nil }
    if wanted.xp then feedXP(xpbar.Rows.xp, easingFor(xpbar.Rows.xp)) end
    if faction then feedReputation(xpbar.Rows.reputation, faction, easingFor(xpbar.Rows.reputation)) end
    arrange(wanted)
end

local function gained()
    if not holder then return end
    local row = xpbar.Rows.xp
    local visible = row:IsShown()
    xpbar.Refresh()
    if visible and row:IsShown() then motion.Play(row.flashAnim) end
end

local function experienceLines()
    local current, maximum, rested = UnitXP("player"), UnitXPMax("player"), GetXPExhaustion()
    local percent = maximum > 0 and math.floor(current / maximum * 100 + 0.5) or 0
    local lines = { string.format("%d / %d (%d%%)", current, maximum, percent) }
    if rested and rested > 0 then lines[2] = string.format("Rested %d", rested) end
    return lines
end

local function reputationLines()
    local data = readFaction()
    if not data then return {} end
    local low = data.currentReactionThreshold
    local label = _G["FACTION_STANDING_LABEL" .. data.reaction]
    local lines = { string.format("%d / %d", data.currentStanding - low, data.nextReactionThreshold - low) }
    if type(label) == "string" then table.insert(lines, 1, label) end
    return lines, data.name
end

-- Unreadable numbers leave the title alone in the tooltip.
local function showTooltip(row, title, reader)
    local ok, lines, name = pcall(reader)
    GameTooltip:SetOwner(row, "ANCHOR_TOP")
    GameTooltip:SetText(ok and type(name) == "string" and name or title)
    for _, line in ipairs(ok and lines or {}) do GameTooltip:AddLine(line, 1, 1, 1) end
    GameTooltip:Show()
end

local function experienceTooltip(row) showTooltip(row, "Experience", experienceLines) end
local function reputationTooltip(row) showTooltip(row, "Reputation", reputationLines) end

function xpbar.UpdateStock()
    if not holder or not core.Profile then return end
    local hidden = core.Profile.showStockBars ~= true
    for _, name in ipairs(STOCK) do
        local frame = _G[name]
        if isFrame(frame) then
            if hidden then core.Hide.Frame(frame, true)
            elseif core.Hide.IsHidden(frame) then core.Hide.Restore(frame) end
        end
    end
end

local function build()
    holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    holder:SetSize(WIDTH, ROW_HEIGHT)
    createRow("xp", XP_COLOR, experienceTooltip)
    createRow("reputation", NEUTRAL_COLOR, reputationTooltip)
    layout.Register(holder, KEY, DEFAULTS)
    xpbar.Holder = holder
    xpbar.Refresh()
    xpbar.UpdateStock()
end

function xpbar:OnEnable()
    core.Combat.Queue(build)
    core:RegisterEvent("PLAYER_XP_UPDATE", gained)
    for _, event in ipairs({ "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "PLAYER_UPDATE_RESTING", "UPDATE_FACTION",
        "PLAYER_ENTERING_WORLD" }) do
        core:RegisterEvent(event, xpbar.Refresh)
    end
    local bars = core.Bars
    if type(bars) == "table" and type(bars.UpdateStockVisibility) == "function" then
        hooksecurefunc(bars, "UpdateStockVisibility", xpbar.UpdateStock)
    end
end

function xpbar:Debug()
    local rows = xpbar.Rows
    core:Print("XP bar holder=" .. tostring(holder ~= nil) .. " xp=" .. tostring(rows.xp ~= nil and rows.xp:IsShown())
        .. " reputation=" .. tostring(rows.reputation ~= nil and rows.reputation:IsShown()))
end

core:RegisterModule("xpbar", xpbar)
