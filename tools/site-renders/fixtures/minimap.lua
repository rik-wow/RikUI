-- Minimap tiles and the indicators around it.

-- The simulator's Minimap widget draws a fixed placeholder picture. The client's own minimap tiles
-- for the ground around Goldshire go over it: Azeroth tiles 30-32 x 48-50, 533 yards and 256 pixels
-- each, placed so the Lion's Pride Inn sits under the player dot at the centre.
local TILE_PIXELS = 256

local PLAYER_TILE = { column = 31, row = 49, fx = 0.80, fy = 0.74 }

local function placeTile(parent, size, tx, ty, path)
    local x0, y0 = math.max(0, tx), math.max(0, ty)
    local x1, y1 = math.min(size, tx + TILE_PIXELS), math.min(size, ty + TILE_PIXELS)
    if x1 <= x0 or y1 <= y0 then return end
    local tex = parent:CreateTexture(nil, "BACKGROUND")
    tex:SetTexture(path)
    tex:SetPoint("TOPLEFT", parent, "TOPLEFT", x0, -y0)
    tex:SetSize(x1 - x0, y1 - y0)
    tex:SetTexCoord((x0 - tx) / TILE_PIXELS, (x1 - tx) / TILE_PIXELS, (y0 - ty) / TILE_PIXELS, (y1 - ty) / TILE_PIXELS)
end

function RikRenderMinimapTiles()
    local holder = RikUIMinimap
    assert(holder, "Minimap holder missing")
    local tiles = CreateFrame("Frame", "RikRenderMinimapTiles", holder)
    tiles:SetAllPoints(Minimap)
    tiles:SetFrameLevel(Minimap:GetFrameLevel() + 1)
    local size = Minimap:GetWidth()
    local originX = size / 2 - PLAYER_TILE.fx * TILE_PIXELS
    local originY = size / 2 - PLAYER_TILE.fy * TILE_PIXELS
    for column = PLAYER_TILE.column - 1, PLAYER_TILE.column + 1 do
        for row = PLAYER_TILE.row - 1, PLAYER_TILE.row + 1 do
            placeTile(tiles, size, originX + (column - PLAYER_TILE.column) * TILE_PIXELS,
                originY + (row - PLAYER_TILE.row) * TILE_PIXELS, "World/Minimaps/Azeroth/map" .. column .. "_" .. row)
        end
    end
    -- The client draws the indicator and queue frames over the map; keep them above the mosaic.
    for _, frame in ipairs(RikUI.Minimap.Adopted) do
        if frame:GetFrameLevel() <= tiles:GetFrameLevel() then frame:SetFrameLevel(tiles:GetFrameLevel() + 1) end
    end
    -- The clock and coordinates refresh from the holder's own tick.
    RikUI.Minimap.Tick(holder, 1)
    return tiles
end

-- Performance readout: the simulator answers a flat 60 FPS and no latency; these are ordinary values.
function RikRenderPerformance(fps, latency)
    GetFramerate = function() return fps end
    GetNetStats = function() return 1.2, 0.4, latency, latency end
    RikRenderSetOption("minimap", "performance", true)
end

-- New mail: the client raises UPDATE_PENDING_MAIL and answers HasNewMail.
function RikRenderMail()
    HasNewMail = function() return true end
    A_Admin.FireEvent("UPDATE_PENDING_MAIL")
    -- The icon shows when the reminder animation finishes; the simulator never finishes it.
    if MiniMapMailIcon then MiniMapMailIcon:SetShown(HasNewMail()) end
end

-- A listed premade group: the queue eye's status frame reads C_LFGList for it.
function RikRenderQueueStatus(name, applicants)
    -- The simulator reports a pet battle queue of its own; none is wanted here. The client resolves
    -- the |4 plural token in the applicant line when it draws it; the resolved text is supplied.
    C_PetBattles.GetPVPMatchmakingInfo = function() return nil end
    LFG_LIST_PENDING_APPLICANTS = "%d Pending Applicants"
    C_LFGList.HasActiveEntryInfo = function() return true end
    C_LFGList.GetActiveEntryInfo = function() return { name = name, activityIDs = { 1 }, censored = false } end
    C_LFGList.GetNumApplicants = function() return applicants, applicants end
    QueueStatusFrame:Update()
    QueueStatusFrame:Show()
    return QueueStatusFrame
end

-- Tracking menu: the minimap's own tracking dropdown, opened the way a right-click does.
function RikRenderTrackingMenu()
    RikUI.Minimap.OpenTracking()
end
