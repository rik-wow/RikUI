-- Optional underlying mana during Cat/Bear; current/max go directly to native sinks when secret.
local core, skin, media, layout = RikUI, RikUI.Skin, RikUI.Media, RikUI.Layout
local mana = { title = "Druid mana" }
core.DruidMana = mana
local DEFAULTS = { point = "BOTTOM", relativePoint = "BOTTOM", x = 140, y = 348 }
local WIDTH, HEIGHT = 121, 18
local holder, bar

local function readableNumber(value)
    return not core.Secret.IsSecret(value) and type(value) == "number"
        and value == value and value ~= math.huge and value ~= -math.huge
end

local function enabled() return core.Profile.druidmana.show == true end

local function wanted()
    if not enabled() then return false end
    local ok, power = core.Secret.Read(UnitPowerType, "player")
    if not ok or core.Secret.IsSecret(power) then return false end
    return power == Enum.PowerType.Energy or power == Enum.PowerType.Rage
end

local function values()
    return UnitPower("player", Enum.PowerType.Mana), UnitPowerMax("player", Enum.PowerType.Mana)
end

local function fill(current, maximum)
    local secretCurrent, secretMax = core.Secret.IsSecret(current), core.Secret.IsSecret(maximum)
    if (not secretCurrent and not readableNumber(current)) or (not secretMax and
        (not readableNumber(maximum) or maximum <= 0)) then error("Mana unavailable") end
    bar:SetMinMaxValues(0, maximum)
    bar:SetValue(current)
    if secretCurrent or secretMax then
        bar.text:SetText("Mana")
    else
        bar.text:SetFormattedText("Mana %d / %d", current, maximum)
    end
end

function mana.Refresh()
    if not holder then return end
    local show = wanted()
    holder:SetShown(show)
    if not show then return end
    local ok = core.Secret.Apply(fill, values)
    if not ok then
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar.text:SetText("Mana unavailable")
    end
end

local function onPower(event, unit, power)
    if core.Secret.IsSecret(unit) or unit ~= "player" or core.Secret.IsSecret(power) then return end
    if event == "UNIT_DISPLAYPOWER" or power == nil or power == "MANA" then mana.Refresh() end
end

local function build()
    holder = CreateFrame("Frame", "RikUIDruidMana", UIParent)
    holder:SetSize(WIDTH, HEIGHT)
    holder:EnableMouse(false)
    skin.Fill(holder)
    skin.Outline(holder)
    bar = CreateFrame("StatusBar", nil, holder)
    bar:SetPoint("TOPLEFT", holder, "TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -1, 1)
    bar:SetStatusBarTexture(media.statusbar)
    bar:SetStatusBarColor(0.15, 0.4, 0.9)
    bar.text = bar:CreateFontString(nil, "OVERLAY")
    media.Font(bar.text, "small")
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    mana.Holder, mana.Bar = holder, bar
    layout.Register(holder, "druidmana", DEFAULTS)
    mana.Refresh()
end

function mana:OnEnable()
    local ok, _, class = core.Secret.Read(UnitClass, "player")
    if not ok or core.Secret.IsSecret(class) or class ~= "DRUID" then return end
    if not Enum or not Enum.PowerType or Enum.PowerType.Mana == nil
        or Enum.PowerType.Energy == nil or Enum.PowerType.Rage == nil
        or type(UnitPower) ~= "function" or type(UnitPowerMax) ~= "function"
        or type(UnitPowerType) ~= "function" then return end
    core.Combat.Queue(build)
    for _, event in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
        core:RegisterEvent(event, onPower)
    end
    core:RegisterEvent("PLAYER_ENTERING_WORLD", mana.Refresh)
    core:RegisterEvent("UPDATE_SHAPESHIFT_FORM", mana.Refresh)
    core.Hooks.Owned(core, "SetProfile", mana.Refresh)
end

-- Shown on the class settings page (options-class.lua) rather than as a page of its own.
mana.ClassSettings = {
    { type = "checkbox", key = "show", label = "Show mana in Cat and Bear",
        description = "Keep underlying mana visible alongside energy or rage. Move this strip with Move frames.",
        get = enabled, set = function(value) core.Profile.druidmana.show = value == true; mana.Refresh() end },
}
core:RegisterModule("druidmana", mana)

