-- Primary resource for the combat HUD. The client chooses the active power type.
local core, skin, media = RikUI, RikUI.Skin, RikUI.Media
local resource = { title = "Combat resource" }
core.CombatResource = resource
local WIDTH, HEIGHT = 280, 18

local function valid(value)
    return core.Secret.IsSecret(value) or (type(value) == "number" and value == value
        and value >= 0 and value < math.huge)
end

local function values()
    return UnitPower("player"), UnitPowerMax("player")
end

local function fill(current, maximum)
    if not valid(current) or not valid(maximum)
        or (not core.Secret.IsSecret(maximum) and maximum <= 0) then error("Resource unavailable") end
    local bar = resource.Bar
    bar:SetMinMaxValues(0, maximum)
    bar:SetValue(current)
    bar.text:SetFormattedText("%d / %d", current, maximum)
end

function resource.Refresh()
    local bar = resource.Bar
    if not bar then return end
    local color = core.UI.PowerColor("player")
    bar:SetStatusBarColor(color.r, color.g, color.b)
    local ok = core.Secret.Apply(fill, values)
    if ok then return end
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar.text:SetText("Resource unavailable")
end

local function onPower(_, unit)
    if core.Secret.IsSecret(unit) or unit ~= "player" then return end
    resource.Refresh()
end

local function build()
    local holder = CreateFrame("Frame", "RikUICombatResource", UIParent)
    holder:SetSize(WIDTH, HEIGHT)
    holder:EnableMouse(false)
    skin.Fill(holder)
    skin.Outline(holder)
    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetPoint("TOPLEFT", holder, "TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -1, 1)
    bar:SetStatusBarTexture(media.statusbar)
    bar.text = bar:CreateFontString(nil, "OVERLAY")
    media.Font(bar.text, "small")
    bar.text:SetPoint("CENTER", bar, "CENTER")
    resource.Holder, resource.Bar = holder, bar
    core.Layout.Register(holder, "combatresource",
        { point="BOTTOM", relativePoint="BOTTOM", x=0, y=274 }, { label="Combat resource" })
    resource.Refresh()
end

function resource:OnEnable()
    if type(UnitPower) ~= "function" or type(UnitPowerMax) ~= "function" then return end
    core.Combat.Queue(build)
    for _, event in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
        core:RegisterEvent(event, onPower)
    end
    core:RegisterEvent("PLAYER_ENTERING_WORLD", resource.Refresh)
    core:RegisterEvent("UPDATE_SHAPESHIFT_FORM", resource.Refresh)
end

core:RegisterModule("combatresource", resource)
