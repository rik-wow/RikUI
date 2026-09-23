-- Region-only skin: Blizzard owns resource values, colours, predictions, layout and visibility.
local core, skin, media = RikUI, RikUI.Skin, RikUI.Media
local weak = { __mode = "k" }
local resource = { title = "Personal resource", Parts = setmetatable({}, weak) }
core.PersonalResource = resource

local BACKGROUND_ATLAS = "UI-HUD-CoolDownManager-Bar-BG"
local FONT_KEYS = { "TextString", "Text", "LeftText", "RightText" }
local hooked, failed = setmetatable({}, weak), setmetatable({}, weak)
local counts, warnings = { bars = 0, failed = 0 }, {}

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Personal resource " .. operation .. ": " .. tostring(reason))
end

local function usable(frame)
    if not skin.IsRegion(frame) then return false end
    if type(frame.IsForbidden) ~= "function" then return true end
    local ok, forbidden = pcall(frame.IsForbidden, frame)
    return ok and not forbidden
end

-- The template's decorative background has no parentKey. Match only its atlas:
-- absorb, heal prediction, mana-cost prediction and feedback regions remain intact.
local function stripBackground(bar)
    if type(bar.GetRegions) ~= "function" then return end
    for _, region in ipairs({ bar:GetRegions() }) do
        if type(region.GetAtlas) == "function" and region:GetAtlas() == BACKGROUND_ATLAS then
            region:SetAlpha(0)
        end
    end
end

local function apply(bar)
    bar:SetStatusBarTexture(media.statusbar)
    stripBackground(bar)
    for _, key in ipairs(FONT_KEYS) do skin.Font(bar[key], "small") end
    if resource.Parts[bar] then return end
    resource.Parts[bar] = {
        backing = skin.Fill(bar),
        edge = skin.Outline(bar, nil, 0, nil, "OVERLAY"),
    }
    counts.bars = counts.bars + 1
end

local function skinBar(bar)
    if not usable(bar) or type(bar.SetStatusBarTexture) ~= "function" or failed[bar] then return end
    local ok, reason = pcall(apply, bar)
    if ok then return end
    failed[bar], counts.failed = true, counts.failed + 1
    warn("skin", reason)
end

local function refresh(frame)
    if not usable(frame) then return end
    local container = frame.HealthBarsContainer
    if usable(container) then skinBar(container.healthBar) end
    skinBar(frame.PowerBar)
    skinBar(frame.AlternatePowerBar)
end

local function discover()
    local frame = _G.PersonalResourceDisplayFrame
    if not usable(frame) or hooked[frame] then return end
    -- Mark attempted hooks as well: a rejected hook must not be retried on every addon load.
    hooked[frame] = true
    if not core.Hooks.Script(frame, "OnShow", refresh) then
        warn("hook", "OnShow unavailable")
        return
    end
    if frame:IsShown() then refresh(frame) end
end

function resource:OnEnable()
    discover()
    core:RegisterEvent("ADDON_LOADED", discover)
    core:RegisterEvent("PLAYER_ENTERING_WORLD", discover)
end

function resource:Debug()
    core:Print("Personal resource bars=" .. counts.bars .. " failed=" .. counts.failed)
end

core:RegisterModule("personalresource", resource)
