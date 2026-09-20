-- Square minimap: Blizzard's Minimap inside a RikUI holder with the zone name above and the local
-- time and player coordinates below. Cluster art and buttons park through the shared hide helper;
-- the mail, queue and tracking frames move into the holder so they stay reachable. Every parent
-- and anchor write on a Blizzard frame runs through the combat queue.
local core, media, layout, ui = RikUI, RikUI.Media, RikUI.Layout, RikUI.UI
local minimap = { Parked = {}, Adopted = {} }
core.Minimap = minimap

local HOLDER_NAME, KEY = "RikUIMinimap", "minimap"
local SIZE, EDGE, TEXT_GAP = 198, 1, 4
local DEFAULTS = { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -16, y = -16 }
local SQUARE_MASK = "Interface\\BUTTONS\\WHITE8X8"
local BORDER = { 0.25, 0.28, 0.32, 1 }
local UPDATE_SECONDS, COORDS_FORMAT = 0.2, "%.1f, %.1f"
local MILITARY_CVAR, MILITARY_FORMAT, CIVIL_FORMAT = "timeMgrUseMilitaryTime", "%H:%M", "%I:%M %p"
local ZONE_EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }
-- Minimap_Update's colours on 69913; anything else keeps the gold of NORMAL_FONT_COLOR.
local PVP_COLORS = { sanctuary = { 0.41, 0.8, 0.94 }, arena = { 1, 0.1, 0.1 }, friendly = { 0.1, 1, 0.1 },
    hostile = { 1, 0.1, 0.1 }, contested = { 1, 0.7, 0 } }
local NEUTRAL = { 1, 0.82, 0 }
-- Paths from _G. Forever (game type camelot) loads the Mainline cluster plus Camelot/Skin.lua and
-- Diel.lua; the calendar, clock and world map buttons are listed for clients that still have them.
local ART = {
    { "MinimapCluster", "BorderTop" }, { "MinimapCluster", "ZoneTextButton" },
    { "MinimapCluster", "InstanceDifficulty" }, { "MinimapCluster", "DielFrame" },
    { "MinimapCluster", "MinimapContainer", "PlayerCoords" },
    { "Minimap", "ZoomIn" }, { "Minimap", "ZoomOut" }, { "MinimapBackdrop" },
    { "GameTimeFrame" }, { "TimeManagerClockButton" }, { "MiniMapWorldMapButton" },
}
local KEEP = {
    { path = { "MinimapCluster", "IndicatorFrame" }, point = "TOPRIGHT", x = -2, y = -2 },
    { path = { "QueueStatusButton" }, point = "BOTTOMLEFT", x = 2, y = 2 },
    -- The tracking dropdown anchors its menu to this frame, so it stays inside the holder, unseen.
    { path = { "MinimapCluster", "Tracking" }, point = "TOPLEFT", x = 0, y = 0, silent = true },
}
local TRACKING_BUTTON = { "MinimapCluster", "Tracking", "Button" }
local holder, warnings = nil, {}

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Minimap " .. operation .. ": " .. tostring(reason))
end

local function isFrame(value)
    local kind = type(value)
    return (kind == "table" or kind == "userdata") and type(value.SetParent) == "function"
end

local function resolve(path)
    local value = _G[path[1]]
    for index = 2, #path do
        local kind = type(value)
        if kind ~= "table" and kind ~= "userdata" then return nil end
        value = value[path[index]]
    end
    return isFrame(value) and value or nil
end

local function attach(frame, point, x, y)
    frame:SetParent(holder)
    frame:ClearAllPoints()
    frame:SetPoint(point, holder, point, x, y)
end

local function label(role, point, relativePoint, y)
    local region = holder:CreateFontString(nil, "OVERLAY")
    media.Font(region, role)
    region:SetPoint(point, holder, relativePoint, 0, y)
    return region
end

local function militaryTime()
    if type(C_CVar) ~= "table" or type(C_CVar.GetCVar) ~= "function" then return true end
    local ok, value = pcall(C_CVar.GetCVar, MILITARY_CVAR)
    return not ok or value ~= "0"
end

local function clockText()
    if militaryTime() then return date(MILITARY_FORMAT) end
    return (date(CIVIL_FORMAT):gsub("^0", ""))
end

local function readPosition()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    if not position then return nil end
    return position:GetXY()
end

local function readable(value)
    return not core.Secret.IsSecret(value) and type(value) == "number"
end

local function coordsText()
    local ok, x, y = pcall(readPosition)
    if not ok then warn("coords", x); return "" end
    if not readable(x) or not readable(y) then return "" end
    return string.format(COORDS_FORMAT, x * 100, y * 100)
end

function minimap.Tick(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < UPDATE_SECONDS then return end
    self.elapsed = 0
    self.clock:SetText(clockText())
    self.coords:SetText(coordsText())
end

local function readZone()
    local pvpType
    if type(C_PvP) == "table" and C_PvP.GetZonePVPInfo then pvpType = C_PvP.GetZonePVPInfo()
    elseif GetZonePVPInfo then pvpType = GetZonePVPInfo() end
    return GetMinimapZoneText(), pvpType
end

function minimap.UpdateZone()
    if not holder then return end
    local ok, name, pvpType = pcall(readZone)
    if not ok then warn("zone", name); name, pvpType = nil, nil end
    if core.Secret.IsSecret(name) or type(name) ~= "string" then name = "" end
    if core.Secret.IsSecret(pvpType) then pvpType = nil end
    holder.zone:SetText(name)
    holder.zone:SetTextColor(unpack(PVP_COLORS[pvpType] or NEUTRAL))
end

local function createHolder()
    holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    holder:SetSize(SIZE + 2 * EDGE, SIZE + 2 * EDGE)
    holder.rikBorder = ui.Edges(holder, EDGE, "BORDER")
    for _, line in ipairs(holder.rikBorder) do line:SetVertexColor(unpack(BORDER)) end
    holder.zone = label("label", "BOTTOM", "TOP", TEXT_GAP)
    holder.clock = label("small", "TOPLEFT", "BOTTOMLEFT", -TEXT_GAP)
    holder.coords = label("small", "TOPRIGHT", "BOTTOMRIGHT", -TEXT_GAP)
    holder.elapsed = 0
    holder:SetScript("OnUpdate", minimap.Tick)
    layout.Register(holder, KEY, DEFAULTS)
    minimap.Holder = holder
end

local function keepSquare()
    Minimap:SetMaskTexture(SQUARE_MASK)
    -- Camelot/Skin.lua restores the round atlas mask on every rotateMinimap change.
    hooksecurefunc(Minimap, "SetMaskTexture", function(_, texture)
        if texture ~= SQUARE_MASK then Minimap:SetMaskTexture(SQUARE_MASK) end
    end)
end

local function embed()
    attach(Minimap, "TOPLEFT", EDGE, -EDGE)
    Minimap:SetSize(SIZE, SIZE)
    keepSquare()
    -- The quest and dig-site blob rings assume a circle; a zero scalar draws them flat.
    pcall(Minimap.SetArchBlobRingScalar, Minimap, 0)
    pcall(Minimap.SetQuestBlobRingScalar, Minimap, 0)
end

local function keep(entry)
    local frame = resolve(entry.path)
    if not frame then return end
    attach(frame, entry.point, entry.x, entry.y)
    if entry.silent then
        frame:SetAlpha(0)
        local button = frame.Button
        if isFrame(button) then button:EnableMouse(false) end
    end
    minimap.Adopted[#minimap.Adopted + 1] = frame
end

-- The cluster is an Edit Mode system. Its header setting re-anchors the indicator frame, and a layout
-- apply may re-place the map's container; the frames RikUI keeps go back onto the holder after it.
local function reattach()
    attach(Minimap, "TOPLEFT", EDGE, -EDGE)
    for _, entry in ipairs(KEEP) do
        local frame = resolve(entry.path)
        if frame then attach(frame, entry.point, entry.x, entry.y) end
    end
end

local function park()
    for _, path in ipairs(ART) do
        local frame = resolve(path)
        -- No native handler must keep running: the holder draws the zone, clock and coordinates.
        if frame and core.Hide.Frame(frame, false) then minimap.Parked[#minimap.Parked + 1] = frame end
    end
end

local function zoom(_, delta)
    local levels, current = Minimap:GetZoomLevels(), Minimap:GetZoom()
    if type(levels) ~= "number" or type(current) ~= "number" then return end
    local target = current + (delta > 0 and 1 or -1)
    if target < 0 or target > levels - 1 then return end
    Minimap:SetZoom(target)
end

function minimap.OpenTracking()
    local button = resolve(TRACKING_BUTTON)
    if not button or type(button.OpenMenu) ~= "function" then
        warn("tracking", "menu unavailable on this client")
        return
    end
    local ok, reason = pcall(button.OpenMenu, button)
    if not ok then warn("tracking", reason) end
end

local function installMouse()
    local native = Minimap:GetScript("OnMouseUp")
    Minimap:EnableMouseWheel(true)
    Minimap:SetScript("OnMouseWheel", zoom)
    Minimap:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then minimap.OpenTracking() return end
        if native then native(self, button) end
    end)
end

local function build()
    if not holder then createHolder() end
    embed()
    for _, entry in ipairs(KEEP) do keep(entry) end
    park()
    installMouse()
    minimap.UpdateZone()
    if core.EditMode then core.EditMode.Guard(MinimapCluster, "minimap", reattach) end
end

function minimap:OnEnable()
    if not isFrame(Minimap) or not isFrame(MinimapCluster) then
        warn("cluster", "Minimap unavailable on this client")
        return
    end
    core.Combat.Queue(build)
    for _, event in ipairs(ZONE_EVENTS) do core:RegisterEvent(event, minimap.UpdateZone) end
end

function minimap:Debug(sample)
    core:Print("Minimap holder=" .. tostring(holder ~= nil) .. " parked=" .. #minimap.Parked
        .. " adopted=" .. #minimap.Adopted)
    sample("GetBestMapForUnit(player)", function() return C_Map.GetBestMapForUnit("player") end)
    sample("GetZonePVPInfo()", readZone)
end

core:RegisterModule("minimap", minimap)
