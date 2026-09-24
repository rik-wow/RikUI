-- Flat look for the centre-screen banners: the event toasts (the level-up display on 69913), the boss
-- kill banner, side history and objective tracker's top banner. Native frames own their animation;
-- addon card accents animate independently. Strings keep Blizzard's size and colour,
-- animated art is emptied instead of faded, and the toast icon gets the bars' crop and an edge.
local core, skin = RikUI, RikUI.Skin
-- Weak keys: pooled toasts are Blizzard's, the edge bookkeeping must not keep one alive.
local banners = { Hooked = {}, IconEdges = setmetatable({}, { __mode = "k" }) }
core.Banners = banners

local MANAGER, MANAGER_DISPLAY = "EventToastManagerFrame", "DisplayToast"
local TOAST_TEXT = { "Title", "SubTitle", "Description", "InstructionalText", "RarityValue" }
local LINE_KEYS, ICON_EDGE_INSET, CARD_PADDING = { "GLine", "GLine2" }, -1, 8
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

-- Normal title/subtitle toasts resize tightly around text. Their manager supplies the full
-- banner envelope. The host inherits pooled visibility/fades but cannot enlarge native layout.
local function cardHost(toast, manager)
    if not toast.rikCardHost then
        local host = CreateFrame("Frame", nil, toast)
        host.ignoreInLayout = true
        host:EnableMouse(false)
        host:SetPoint("TOPLEFT", manager, "TOPLEFT", -CARD_PADDING, CARD_PADDING)
        host:SetPoint("BOTTOMRIGHT", manager, "BOTTOMRIGHT", CARD_PADDING, -CARD_PADDING)
        toast.rikCardHost = host
    end
    toast.rikCardHost:SetFrameLevel(math.max(0, toast:GetFrameLevel() - 1))
    return toast.rikCardHost
end

local function skinToast(manager)
    local toast = manager.currentDisplayingToast
    if not skin.IsRegion(toast) then return end
    typefaces(toast, TOAST_TEXT)
    toastIcon(toast)
    toast.rikCard = skin.NotificationCard(cardHost(toast, manager), toast.Icon)
end

-- Native setup reassigns line atlases, RGB tint and animated scale/visibility. It does not
-- reset their alpha, so suppression survives the grow animation without changing its timing.
local function suppressLines(manager)
    skin.Blank(manager, LINE_KEYS)
    skin.Strip(manager, LINE_KEYS)
end

local function skinFrame(frame, target)
    skin.Blank(frame, target.art)
    typefaces(frame, target.text)
    frame.rikCard = skin.NotificationCard(frame, frame.Icon)
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

-- DisplayToast shows the manager, releases the old toast and shows a pooled one, whose Setup plays
-- the banner and so re-applies the line atlas, all in one call. The skin follows one frame later,
-- from the manager's OnShow and OnEvent and every toast's OnShow and OnHide. DisplayToast and
-- SetupGLineAtlas are not hooked: on 69977 a method hook on a Blizzard frame left the method nil for
-- Blizzard's callers. The toasts' own grow and fade-in start after a delay, so nothing gold shows.
local watchedToasts, skinPending = setmetatable({}, { __mode = "k" }), false

local function skinManager(manager)
    skinToast(manager)
    suppressLines(manager)
end

local scheduleSkin
local function watchToast(manager)
    local toast = manager.currentDisplayingToast
    if not skin.IsRegion(toast) or watchedToasts[toast] then return end
    watchedToasts[toast] = true
    core.Hooks.Script(toast, "OnShow", scheduleSkin)
    core.Hooks.Script(toast, "OnHide", scheduleSkin)
end

scheduleSkin = function()
    if skinPending then return end
    skinPending = true
    C_Timer.After(0, function()
        skinPending = false
        local manager = _G[MANAGER]
        guarded(MANAGER, skinManager, manager)
        watchToast(manager)
    end)
end

local function hookManager()
    local manager = _G[MANAGER]
    if not skin.IsRegion(manager) or type(manager[MANAGER_DISPLAY]) ~= "function" then return end
    banners.Hooked[MANAGER] = true
    core.Hooks.Script(manager, "OnShow", scheduleSkin)
    core.Hooks.Script(manager, "OnEvent", scheduleSkin)
end

local function hookFrame(target)
    local frame = _G[target.name]
    if not skin.IsRegion(frame) or type(frame.HookScript) ~= "function" then return end
    banners.Hooked[target.name] = true
    core.Hooks.Script(frame, "OnShow", function(self) guarded(target.name, skinFrame, self, target) end)
    if not target.rowSetup or type(_G[target.rowSetup]) ~= "function" then return end
    core.Hooks.Function(target.rowSetup, function(row) guarded(target.name, skinRow, row, target) end)
end

-- Rows arrive during native animations. Observe the published last row without method hooks.
local function hookSideDisplay()
    local side = _G.EventToastManagerSideDisplay
    if not skin.IsRegion(side) then return end
    local previous
    banners.Hooked.EventToastManagerSideDisplay = true
    core.Hooks.Script(side, "OnShow", function(self) skin.Blank(self, { "GoldBG" }) end)
    core.Hooks.Script(side, "OnHide", function() previous = nil end)
    core.Hooks.Script(side, "OnUpdate", function(self)
        local row = self.lastToastFrame
        if not skin.IsRegion(row) or row == previous then return end
        previous = row
        guarded("EventToastManagerSideDisplay", function()
            typefaces(row, TOAST_TEXT)
            toastIcon(row)
            row.rikCard = skin.NotificationCard(row, row.Icon)
        end)
    end)
end

local function count(set)
    local total = 0
    for _ in pairs(set) do total = total + 1 end
    return total
end

function banners:OnEnable()
    hookManager()
    hookSideDisplay()
    for _, target in ipairs(FRAMES) do hookFrame(target) end
end

function banners:Debug()
    core:Print("Banners hooked=" .. count(banners.Hooked) .. " failed=" .. count(failed))
end

core:RegisterModule("banners", banners)
