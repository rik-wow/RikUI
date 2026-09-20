-- Combo point pips for rogues and druids. Blizzard's ComboFrame hangs off the TargetFrame that
-- src/modules/unitframes/unitframes.lua parks, and it compares the count per pip, which a secret value forbids. Here pip i
-- is a StatusBar with the range i-1..i and every pip gets the same raw count: the widget clamps it,
-- so the right pips light with no comparison in Lua. Which pip changed is never known, so the
-- flash follows the power event, not the value.
local core, media, layout, ui, motion = RikUI, RikUI.Media, RikUI.Layout, RikUI.UI, RikUI.Motion
local combo = { Pips = {} }
core.ComboPoints = combo

local HOLDER_NAME, KEY = "RikUIComboPoints", "combopoints"
local PIPS, PIP_SIZE, GAP, EDGE = 5, 10, 2, 1
-- The 60px gap between the player and target frames; the target's aura rows own the space above it.
local DEFAULTS = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 317 }
local BACKGROUND, BORDER, WHITE = { 0.06, 0.07, 0.09, 0.9 }, { 0.25, 0.28, 0.32, 1 }, { 1, 1, 1, 1 }
local BUILDER_COLOR, FINISHER_COLOR = { 1, 0.82, 0.1 }, { 0.95, 0.25, 0.15 }
local FLAT = "Interface\\BUTTONS\\WHITE8X8"
local FADE_SECONDS, FLASH_SECONDS, FLASH_ALPHA = 0.15, 0.2, 0.5
local CLASSES = { ROGUE = true, DRUID = true }
local POWER_TOKEN, PLAYER, TARGET = "COMBO_POINTS", "player", "target"
local holder, warnings = nil, {}

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Combo points " .. operation .. ": " .. tostring(reason))
end

local function readPoints() return GetComboPoints(PLAYER, TARGET) end

local function fill(easing)
    local ok, reason = core.Secret.Apply(function(points)
        for _, pip in ipairs(combo.Pips) do pip.bar:SetValue(points, easing) end
    end, readPoints)
    if not ok then warn("read", reason) end
end

local function readAttackable() return UnitExists(TARGET) == true and UnitCanAttack(PLAYER, TARGET) ~= false end

-- A failed or secret answer shows the row: empty pips cost less than missing ones.
local function wanted()
    local ok, attackable = pcall(readAttackable)
    return not ok or attackable
end

-- The holder is unprotected, so it shows and hides in combat. A row that was hidden shows another
-- target's count, so its first fill does not ease.
local function targetChanged()
    if not holder then return end
    local show, visible = wanted(), holder:IsShown()
    holder:SetShown(show)
    if not show then return end
    fill(motion.Interpolation("Immediate"))
    if not visible then motion.Play(combo.Fade) end
end

local function powerChanged(_, unit, token)
    if not holder or core.Secret.IsSecret(unit) or unit ~= PLAYER or token ~= POWER_TOKEN then return end
    fill(motion.Interpolation("ExponentialEaseOut"))
    if holder:IsShown() then motion.Play(combo.Flash) end
end

local function createPip(index)
    local pip = CreateFrame("Frame", nil, holder)
    pip:SetSize(PIP_SIZE, PIP_SIZE)
    pip:SetPoint("LEFT", holder, "LEFT", (index - 1) * (PIP_SIZE + GAP), 0)
    local background = pip:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(pip)
    background:SetTexture(FLAT)
    background:SetVertexColor(unpack(BACKGROUND))
    pip.rikBorder = ui.Edges(pip, EDGE, "BORDER")
    for _, line in ipairs(pip.rikBorder) do line:SetVertexColor(unpack(BORDER)) end
    pip.bar = CreateFrame("StatusBar", nil, pip)
    pip.bar:SetAllPoints(pip)
    pip.bar:SetStatusBarTexture(media.statusbar)
    pip.bar:SetStatusBarColor(unpack(index == PIPS and FINISHER_COLOR or BUILDER_COLOR))
    pip.bar:SetMinMaxValues(index - 1, index)
    combo.Pips[index] = pip
end

local function build()
    holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    holder:SetSize(PIPS * PIP_SIZE + (PIPS - 1) * GAP, PIP_SIZE)
    for index = 1, PIPS do createPip(index) end
    local flash = CreateFrame("Frame", nil, holder)
    flash:SetAllPoints(holder)
    local glow = flash:CreateTexture(nil, "OVERLAY")
    glow:SetAllPoints(flash)
    glow:SetTexture(FLAT)
    glow:SetVertexColor(unpack(WHITE))
    glow:SetAlpha(0)
    combo.Fade = motion.Tween(holder, 0, 1, FADE_SECONDS)
    combo.Flash = motion.Tween(glow, FLASH_ALPHA, 0, FLASH_SECONDS)
    layout.Register(holder, KEY, DEFAULTS)
    combo.Holder = holder
    holder:Hide()
    targetChanged()
end

local function usesComboPoints()
    local ok, _, class = pcall(UnitClass, PLAYER)
    return ok and CLASSES[class] == true
end

function combo:OnEnable()
    if type(GetComboPoints) ~= "function" or not usesComboPoints() then return end
    core.Combat.Queue(build)
    core:RegisterEvent("UNIT_POWER_FREQUENT", powerChanged)
    core:RegisterEvent("PLAYER_TARGET_CHANGED", targetChanged)
    core:RegisterEvent("PLAYER_ENTERING_WORLD", targetChanged)
end

function combo:Debug()
    core:Print("Combo points holder=" .. tostring(holder ~= nil) .. " shown="
        .. tostring(holder ~= nil and holder:IsShown()))
end

core:RegisterModule("combopoints", combo)
