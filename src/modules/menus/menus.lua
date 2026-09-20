-- Flat backing for every Blizzard_Menu frame: context menus, dropdown lists and their submenus.
-- MenuProxyMixin announces each menu through EventRegistry. While a menu is open its compositor
-- asserts on CreateTexture and CreateAnimationGroup on the menu frame and on SetFont on its font
-- strings, so nothing is created on the menu: the backing is an own frame from a pool, anchored to
-- the menu and placed one level under it. Blizzard's background is a pooled texture that
-- SetToDefaults resets on release, so its alpha is written on every show.
local core, skin, motion = RikUI, RikUI.Skin, RikUI.Motion
local menus = { Active = {} }
core.Menus = menus

local SHOW_EVENT, HIDE_EVENT = "MenuProxy.OnShow", "MenuProxy.OnHide"
local BACKGROUND_ATLAS = "common-dropdown-bg"
-- MenuStyle1Mixin insets its content by 8 and by 15 at the bottom; lifting the backing's bottom
-- edge by the difference leaves the same padding on every side.
local BOTTOM_LIFT, DEFAULT_LEVEL = 7, 1
local pool, warnings, counts = {}, {}, { shown = 0 }

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Menus " .. operation .. ": " .. tostring(reason))
end

local function isBackground(region)
    if not skin.IsRegion(region) or type(region.GetAtlas) ~= "function" then return false end
    local ok, atlas = pcall(region.GetAtlas, region)
    return ok and atlas == BACKGROUND_ATLAS
end

local function fadeBackground(...)
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        if isBackground(region) then region:SetAlpha(0) end
    end
end

local function createBacking()
    local backing = CreateFrame("Frame", nil, UIParent)
    backing.rikFill = skin.Fill(backing, skin.BACKING)
    backing.rikBorder = skin.Outline(backing)
    backing.rikFade = motion.Tween(backing, 0, 1, skin.FADE_SECONDS)
    return backing
end

-- The backing is not a child of the menu, so it takes the menu's strata and the level under it.
local function place(backing, menu)
    local level, strata = menu:GetFrameLevel(), menu:GetFrameStrata()
    if type(strata) == "string" then backing:SetFrameStrata(strata) end
    backing:SetFrameLevel(math.max((type(level) == "number" and level or DEFAULT_LEVEL) - 1, 0))
    backing:ClearAllPoints()
    backing:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, 0)
    backing:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", 0, BOTTOM_LIFT)
end

local function apply(menu)
    fadeBackground(menu:GetRegions())
    local backing = table.remove(pool) or createBacking()
    menus.Active[menu] = backing
    place(backing, menu)
    backing:Show()
    motion.Play(backing.rikFade)
    counts.shown = counts.shown + 1
end

local function onShow(_, menu)
    if type(menu) ~= "table" or menus.Active[menu] then return end
    local ok, reason = pcall(apply, menu)
    if not ok then warn("skin", reason) end
end

local function onHide(_, menu)
    local backing = menu and menus.Active[menu]
    if not backing then return end
    menus.Active[menu] = nil
    backing:Hide()
    backing:ClearAllPoints()
    pool[#pool + 1] = backing
end

function menus:OnEnable()
    if type(EventRegistry) ~= "table" or type(EventRegistry.RegisterCallback) ~= "function" then return end
    EventRegistry:RegisterCallback(SHOW_EVENT, onShow, menus)
    EventRegistry:RegisterCallback(HIDE_EVENT, onHide, menus)
end

function menus:Debug()
    local active = 0
    for _ in pairs(menus.Active) do active = active + 1 end
    core:Print("Menus shown=" .. counts.shown .. " active=" .. active .. " pooled=" .. #pool)
end

core:RegisterModule("menus", menus)
