-- Flat look for the centre-screen banners: the event toasts (the level-up display on 69913), the boss
-- kill banner and the objective tracker's top banner. Blizzard animates all three, so this file adds
-- no tween, point, size or script: strings take the RikUI typeface at Blizzard's size and colour,
-- animated art is emptied instead of faded, and the toast icon gets the bars' crop and an edge.
local core, skin = RikUI, RikUI.Skin
-- Weak keys: pooled toasts are Blizzard's, the edge bookkeeping must not keep one alive.
local banners = { Hooked = {}, IconEdges = setmetatable({}, { __mode = "k" }) }
core.Banners = banners

local MANAGER, MANAGER_DISPLAY, MANAGER_LINES = "EventToastManagerFrame", "DisplayToast", "SetupGLineAtlas"
local TOAST_TEXT = { "Title", "SubTitle", "Description", "InstructionalText", "RarityValue" }
local LINE_KEYS, LINE_HEIGHT, ICON_EDGE_INSET = { "GLine", "GLine2" }, 1, -1
-- Every piece below has its alpha driven by the banner's own animation groups.
local FRAMES = {
    -- Loot rows are made while the banner plays; rowSetup is the global that fills one.
    { name = "BossBanner", text = { "Title", "SubTitle" }, rowSetup = "BossBanner_ConfigureLootFrame",
        rowText = { "ItemName", "SetName", "PlayerName", "Count" },
        art = { "BannerTop", "BannerTopGlow", "BannerBottom", "BannerBottomGlow", "BannerMiddle", "BannerMiddleGlow",
            "SkullCircle", "LootCircle", "BottomFillagree", "SkullSpikes", "RightFillagree", "LeftFillagree",
            "FlashBurst", "FlashBurstLeft", "FlashBurstCenter", "RedFlash" } },
    { name = "ObjectiveTrackerTopBannerFrame", text = { "Title", "Subtitle" },
        art = { "Filigree", "FiligreeGlow", "Spark" } },
}
local failed, warnings = {}, {}

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Banners " .. operation .. ": " .. tostring(reason))
end

local function typefaces(owner, keys)
    for _, key in ipairs(keys) do skin.Typeface(owner[key]) end
end

local function toastIcon(toast)
    local icon = toast.Icon
    if not skin.IsRegion(icon) or type(icon.SetTexCoord) ~= "function" then return end
    skin.CropIcon(icon)
    skin.Strip(toast, { "IconBorder" })
    if banners.IconEdges[toast] or type(toast.CreateTexture) ~= "function" then return end
    -- One pixel outside the icon: the lines are in a lower layer than the icon and would be covered.
    banners.IconEdges[toast] = skin.Outline(toast, nil, ICON_EDGE_INSET, icon)
end

local function skinToast(manager)
    local toast = manager.currentDisplayingToast
    if not skin.IsRegion(toast) then return end
    typefaces(toast, TOAST_TEXT)
    toastIcon(toast)
end

-- Blizzard re-applies the gold bar atlas for every toast; its grow animation and tint still apply.
local function flattenLines(manager)
    for _, key in ipairs(LINE_KEYS) do
        local line = manager[key]
        if skin.IsRegion(line) and type(line.SetTexture) == "function" then
            line:SetTexture(skin.FLAT)
            line:SetVertexColor(unpack(skin.GOLD))
            line:SetHeight(LINE_HEIGHT)
        end
    end
end

local function skinFrame(frame, target)
    skin.Blank(frame, target.art)
    typefaces(frame, target.text)
end

local function skinRow(row, target)
    if not skin.IsRegion(row) then return end
    typefaces(row, target.rowText)
    skin.CropIcon(row.Icon)
end

-- A failed banner is not retried: the same write would fail on every show.
local function guarded(name, callback, ...)
    if failed[name] then return end
    local ok, reason = pcall(callback, ...)
    if ok then return end
    failed[name] = true
    warn("skin " .. name, reason)
end

local function hookManager()
    local manager = _G[MANAGER]
    if not skin.IsRegion(manager) or type(manager[MANAGER_DISPLAY]) ~= "function" then return end
    banners.Hooked[MANAGER] = true
    hooksecurefunc(manager, MANAGER_DISPLAY, function(self) guarded(MANAGER, skinToast, self) end)
    if type(manager[MANAGER_LINES]) ~= "function" then return end
    hooksecurefunc(manager, MANAGER_LINES, function(self) guarded(MANAGER, flattenLines, self) end)
end

local function hookFrame(target)
    local frame = _G[target.name]
    if not skin.IsRegion(frame) or type(frame.HookScript) ~= "function" then return end
    banners.Hooked[target.name] = true
    frame:HookScript("OnShow", function(self) guarded(target.name, skinFrame, self, target) end)
    if not target.rowSetup or type(_G[target.rowSetup]) ~= "function" then return end
    hooksecurefunc(target.rowSetup, function(row) guarded(target.name, skinRow, row, target) end)
end

local function count(set)
    local total = 0
    for _ in pairs(set) do total = total + 1 end
    return total
end

function banners:OnEnable()
    hookManager()
    for _, target in ipairs(FRAMES) do hookFrame(target) end
end

function banners:Debug()
    core:Print("Banners hooked=" .. count(banners.Hooked) .. " failed=" .. count(failed))
end

core:RegisterModule("banners", banners)
