-- Fake of the 69913 minimap cluster RikUI touches. Forever (game type camelot) loads the Mainline
-- Minimap files plus Camelot/Skin.lua, so the cluster has BorderTop, the zone text button, the
-- tracking dropdown, the mail indicator, the day/night indicator, the instance difficulty flag and
-- a MinimapContainer holding the Minimap (zoom buttons, backdrop with the compass art) and the
-- native player coordinates. Zoom, mask, ping and menu calls are recorded so a test can read them.
local stub = { ROUND_MASK = "ui-hud-minimap-frame-generic-mask", ZOOM_LEVELS = 6 }

local function installMinimap(container)
    local map = CreateFrame("Minimap", "Minimap", container)
    container.Minimap = map
    map.zoom = 0
    function map:GetZoom() return self.zoom end
    function map:SetZoom(level) self.zoom = level end
    function map:GetZoomLevels() return stub.ZOOM_LEVELS end
    function map:SetMaskTexture(texture) self.mask = texture end
    function map:EnableMouseWheel(enabled) self.wheel = enabled end
    -- MinimapMixin:OnClick pings for every mouse button.
    map:SetScript("OnMouseUp", function(self) self.pings = (rawget(self, "pings") or 0) + 1 end)
    map.ZoomIn = CreateFrame("Button", nil, map)
    map.ZoomOut = CreateFrame("Button", nil, map)
    MinimapBackdrop = CreateFrame("Frame", "MinimapBackdrop", map)
    MinimapCompassTexture = MinimapBackdrop:CreateTexture()
    return map
end

local function installCluster()
    local cluster = CreateFrame("Frame", "MinimapCluster", UIParent)
    cluster.BorderTop = CreateFrame("Frame", nil, cluster)
    cluster.ZoneTextButton = CreateFrame("Button", nil, cluster)
    MinimapZoneText = cluster.ZoneTextButton:CreateFontString()
    cluster.Tracking = CreateFrame("Frame", nil, cluster)
    cluster.Tracking.Button = CreateFrame("DropdownButton", nil, cluster.Tracking)
    function cluster.Tracking.Button:OpenMenu() self.opened = (rawget(self, "opened") or 0) + 1 end
    cluster.IndicatorFrame = CreateFrame("Frame", nil, cluster)
    cluster.IndicatorFrame.MailFrame = CreateFrame("Frame", nil, cluster.IndicatorFrame)
    cluster.InstanceDifficulty = CreateFrame("Frame", nil, cluster)
    cluster.DielFrame = CreateFrame("Frame", nil, cluster)
    cluster.MinimapContainer = CreateFrame("Frame", nil, cluster)
    cluster.MinimapContainer.PlayerCoords = CreateFrame("Frame", nil, cluster.MinimapContainer)
    installMinimap(cluster.MinimapContainer)
    QueueStatusButton = CreateFrame("Button", "QueueStatusButton", cluster)
    return cluster
end

local function installGlobals()
    function GetMinimapZoneText() return stub.zone end
    C_PvP = { GetZonePVPInfo = function() return stub.pvpType, false, nil end }
    C_Map = {
        GetBestMapForUnit = function() return stub.mapID end,
        GetPlayerMapPosition = function()
            if stub.positionError then error(stub.positionError) end
            local position = stub.position
            if not position then return nil end
            return { GetXY = function() return position[1], position[2] end }
        end,
    }
    function GetCursorPosition() return 0, 0 end
end

-- Fresh cluster, globals and recorders; call again for every scenario that reloads the addon.
function stub.install(env)
    stub.env = env
    stub.zone, stub.pvpType, stub.mapID, stub.position, stub.positionError = "Northshire Valley", "friendly", 1429, { 0.5, 0.5 }, nil
    installCluster()
    installGlobals()
end

return stub
