-- Blizzard owns pooled item state, timing, visibility and internal layout.
-- Do not hook viewer/item methods: the 69977 client can lose them to tainted callers.
local core, skin, media = RikUI, RikUI.Skin, RikUI.Media
local viewer = {}
core.CooldownViewer = viewer

local VIEWERS = {
    EssentialCooldownViewer = false, UtilityCooldownViewer = false,
    BuffIconCooldownViewer = false, BuffBarCooldownViewer = true,
}
local ADDON, SCAN_SECONDS, EDGE_INSET = "Blizzard_CooldownViewer", 0.25, -1
local MASK, OVERLAY = "UI-HUD-CoolDownManager-Mask", "UI-HUD-CoolDownManager-IconOverlay"
local weak = { __mode = "k" }
local watched, edges = setmetatable({}, weak), setmetatable({}, weak)
local failedItems, failedViewers = setmetatable({}, weak), setmetatable({}, weak)
local counts, warnings = { viewers = 0, items = 0, failed = 0 }, {}
local scanning = false

local function readable(value)
    return type(issecretvalue) ~= "function" or not issecretvalue(value)
end

local function region(value)
    return readable(value) and skin.IsRegion(value)
end

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("CooldownViewer " .. operation .. ": " .. tostring(reason))
end

local function atlasIs(texture, atlas)
    if not region(texture) or type(texture.GetAtlas) ~= "function" then return false end
    local value = texture:GetAtlas()
    return readable(value) and value == atlas
end

local function unmask(icon)
    if type(icon.GetNumMaskTextures) ~= "function" or type(icon.GetMaskTexture) ~= "function"
        or type(icon.RemoveMaskTexture) ~= "function" then return end
    local count = icon:GetNumMaskTextures()
    if not readable(count) or type(count) ~= "number" then return end
    for index = count, 1, -1 do
        local mask = icon:GetMaskTexture(index)
        if atlasIs(mask, MASK) then icon:RemoveMaskTexture(mask) end
    end
end

local function stripOverlay(owner)
    if type(owner.GetRegions) ~= "function" then return end
    for _, texture in ipairs({ owner:GetRegions() }) do
        if atlasIs(texture, OVERLAY) then texture:SetAlpha(0) end
    end
end

local function fontIn(owner, key)
    if region(owner) then skin.Font(owner[key], "count") end
end

local function iconNumbers(item)
    fontIn(item.ChargeCount, "Current")
    fontIn(item.Applications, "Applications")
    local cooldown = item.Cooldown
    if region(cooldown) and type(cooldown.GetCountdownFontString) == "function" then
        skin.Font(cooldown:GetCountdownFontString(), "cooldown")
    end
end

local function buffBar(item)
    local bar = item.Bar
    if not region(bar) then return end
    if type(bar.GetStatusBarTexture) == "function" then
        local fill = bar:GetStatusBarTexture()
        if region(fill) then fill:SetTexture(media.statusbar) end
    end
    if region(bar.BarBG) then
        bar.BarBG:SetTexture(skin.FLAT)
        bar.BarBG:SetVertexColor(unpack(skin.BACKING))
    end
    skin.Typeface(bar.Name)
    skin.Typeface(bar.Duration)
end

local function borderColor()
    local bars = core.Bars
    local color = bars and type(bars.BorderColor) == "function" and bars.BorderColor() or skin.LINE
    return { color[1], color[2], color[3], 1 }
end

local function apply(item, isBar)
    local owner = isBar and item.Icon or item
    if not region(owner) then return end
    local icon = owner.Icon
    if not region(icon) or type(icon.SetTexCoord) ~= "function" then return end
    skin.CropIcon(icon)
    unmask(icon)
    stripOverlay(owner)
    if isBar then fontIn(owner, "Applications"); buffBar(item) else iconNumbers(item) end
    local color = borderColor()
    if not edges[item] then
        edges[item] = skin.Outline(owner, color, EDGE_INSET, icon)
        counts.items = counts.items + 1
    end
    for _, line in ipairs(edges[item]) do line:SetVertexColor(unpack(color)) end
    if viewer.DecorateItem then viewer.DecorateItem(item, owner, icon, isBar) end
    -- DebuffBorder, OutOfRange, cooldown swipe, Pip and all native values stay client-owned.
end

local function skinItem(item, isBar)
    if not region(item) or failedItems[item] then return end
    local ok, reason = pcall(apply, item, isBar)
    if ok then return end
    failedItems[item], counts.failed = true, counts.failed + 1
    warn("skin", reason)
end

local function scanViewer(frame, isBar)
    local shown = frame:IsShown()
    if not readable(shown) or shown ~= true then return false end
    local pool = frame.itemFramePool
    if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
        for item in pool:EnumerateActive() do skinItem(item, isBar) end
    end
    return true
end

local function scanVisible()
    if viewer.RefreshLayout then viewer.RefreshLayout() end
    local visible = false
    for frame, isBar in pairs(watched) do
        if not failedViewers[frame] then
            local ok, shown = pcall(scanViewer, frame, isBar)
            if ok then
                visible = visible or shown
            else
                failedViewers[frame], counts.failed = true, counts.failed + 1
                warn("scan", shown)
            end
        end
    end
    return visible
end

local function scanLoop()
    if scanVisible() then C_Timer.After(SCAN_SECONDS, scanLoop) else scanning = false end
end

local function refresh()
    local visible = scanVisible()
    if scanning or not visible then return end
    scanning = true
    C_Timer.After(SCAN_SECONDS, scanLoop)
end

local function discover()
    for name, isBar in pairs(VIEWERS) do
        local frame = _G[name]
        if region(frame) and watched[frame] == nil then
            if core.Hooks.Script(frame, "OnShow", refresh) then
                watched[frame], counts.viewers = isBar, counts.viewers + 1
                if viewer.Track then viewer.Track(name, frame) end
            end
        end
    end
    refresh()
end

function viewer:OnEnable()
    if viewer.EnableLayout then viewer.EnableLayout() end
    core:RegisterEvent("ADDON_LOADED", function(_, name) if name == ADDON then discover() end end, viewer)
    discover()
end

function viewer:Debug()
    core:Print("CooldownViewer viewers=" .. counts.viewers .. " items=" .. counts.items .. " failed=" .. counts.failed)
end

core:RegisterModule("cooldownviewer", viewer)
