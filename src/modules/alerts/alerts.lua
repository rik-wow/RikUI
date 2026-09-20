-- Flat skin for the alert toasts: loot won, money, recipes, achievements and the rest. Every alert
-- subsystem ends in the global AlertFrame_ShowNewAlert, so one post-hook sees them all and the
-- skin is driven by the keys the templates share instead of by template names. Blizzard's intro and
-- outro animations are left alone, so a toast gets no tween of its own. Fill, edge, crop and
-- typeface are written once per toast; art is removed on every show, because a SetUp may restore a
-- background and Blizzard animates the alpha of glow and shine.
local core, skin = RikUI, RikUI.Skin
local alerts = {}
core.Alerts = alerts

local HOOK = "AlertFrame_ShowNewAlert"
local BACKGROUNDS = { "Background", "PvPBackground", "RatedPvPBackground", "BGAtlas", "IconBorder", "Border",
    "IconBG", "Watermark" }
local ANIMATED, ICON_ART = { "glow", "shine" }, { "Overlay", "Bling", "IconBorder", "Border" }
-- The toast art keeps a transparent margin around its panel; the flat panel sits inside it.
local INSET, ICON_EDGE_INSET = 8, -1
local skinned, failed = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local warnings, counts = {}, { hooked = false, skinned = 0, failed = 0 }

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Alerts " .. operation .. ": " .. tostring(reason))
end

-- The icon is a texture on the toast, a texture on its lootItem child, or a frame holding Texture.
local function findIcon(frame)
    local holder = skin.IsRegion(frame.lootItem) and frame.lootItem or frame
    local icon = holder.Icon
    if not skin.IsRegion(icon) then return nil, holder end
    if skin.IsRegion(icon.Texture) then return icon.Texture, icon end
    return icon, holder
end

local function typefaces(...)
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        if skin.IsRegion(region) and region:GetObjectType() == "FontString" then skin.Typeface(region) end
    end
end

local function removeArt(frame)
    skin.Strip(frame, BACKGROUNDS)
    skin.Blank(frame, ANIMATED)
    local _, holder = findIcon(frame)
    if holder ~= frame then skin.Strip(holder, ICON_ART) end
end

local function decorate(frame)
    frame.rikFill = skin.Fill(frame, skin.BACKING, INSET)
    frame.rikBorder = skin.Outline(frame, nil, INSET)
    local icon = findIcon(frame)
    if icon then
        skin.CropIcon(icon)
        -- One pixel outside the icon: the lines are in a lower layer and the icon would cover them.
        frame.rikIconBorder = skin.Outline(frame, nil, ICON_EDGE_INSET, icon)
    end
    typefaces(frame:GetRegions())
    if skin.IsRegion(frame.lootItem) then typefaces(frame.lootItem:GetRegions()) end
end

local function apply(frame)
    removeArt(frame)
    if skinned[frame] then return end
    decorate(frame)
    skinned[frame] = true
    counts.skinned = counts.skinned + 1
end

-- A failed toast is not retried: half a skin applied twice is worse than half a skin.
local function onShow(frame)
    if type(frame) ~= "table" or failed[frame] then return end
    local ok, reason = pcall(apply, frame)
    if ok then return end
    failed[frame] = true
    counts.failed = counts.failed + 1
    warn("skin", reason)
end

function alerts:OnEnable()
    if type(_G[HOOK]) ~= "function" then return end
    hooksecurefunc(HOOK, onShow)
    counts.hooked = true
end

function alerts:Debug()
    core:Print("Alerts hooked=" .. tostring(counts.hooked) .. " skinned=" .. counts.skinned
        .. " failed=" .. counts.failed)
end

core:RegisterModule("alerts", alerts)
