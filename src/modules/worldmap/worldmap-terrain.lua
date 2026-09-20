-- A separate, reversible terrain layer; never marks an area explored or replaces a provider.
local core, map = RikUI, RikUI.WorldMap
local terrain, records = {}, setmetatable({}, { __mode = "k" })
map.Terrain = terrain
local MAX_TILES = 256
local function key(w, h, x, y) return table.concat({ w, h, x, y }, ":") end
local function hide(record)
    for _, texture in ipairs(record.textures) do texture:Hide() end
end
local function fileSize(size)
    local result = 16
    while result < size do result = result * 2 end
    return result
end
local function explored(mapID)
    local set = {}
    local list = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures(mapID)
    for _, info in ipairs(list or {}) do
        set[key(info.textureWidth, info.textureHeight, info.offsetX, info.offsetY)] = true
    end
    return set
end
local function tile(pin, record, overlay, asset, layer, count)
    if count > MAX_TILES then return end
    local row, col, file = unpack(asset)
    local width = math.min(layer.tileWidth, overlay[1] - col * layer.tileWidth)
    local height = math.min(layer.tileHeight, overlay[2] - row * layer.tileHeight)
    if width <= 0 or height <= 0 then return end
    local texture = record.textures[count]
    if not texture then
        texture = pin:CreateTexture(nil, "BACKGROUND", nil, -1)
        record.textures[count] = texture
        pin:GetMap():AddMaskableTexture(texture)
    end
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", pin, "TOPLEFT", overlay[3] + col * layer.tileWidth, -overlay[4] - row * layer.tileHeight)
    texture:SetSize(width, height)
    texture:SetTexCoord(0, width / fileSize(width), 0, height / fileSize(height))
    texture:SetTexture(file, nil, nil, "TRILINEAR")
    texture:SetVertexColor(0.75, 0.82, 0.9, 1)
    texture:Show()
end
local function draw(pin, record)
    hide(record)
    if core.Profile.worldmap.fog then return end
    local frame = pin:GetMap()
    local id = frame:GetMapID()
    local art = C_Map.GetMapArtID(id)
    local overlays = core.Data.MapTerrain[art]
    if not overlays then return end
    local index = frame:GetCanvasContainer():GetCurrentLayerIndex()
    if index ~= 1 then return end -- metadata is the base art layer
    local layers = C_Map.GetMapArtLayers(id)
    local layer = layers and layers[index]
    if not layer or layer.tileWidth <= 0 or layer.tileHeight <= 0 then return end
    local seen, count = explored(id), 0
    for _, overlay in ipairs(overlays) do
        if not seen[key(overlay[1], overlay[2], overlay[3], overlay[4])] then
            for _, asset in ipairs(overlay[5]) do
                count = count + 1
                tile(pin, record, overlay, asset, layer, count)
            end
        end
    end
end
local function refreshPin(pin)
    local record = records[pin]
    if not record then return end
    local ok, reason = pcall(draw, pin, record)
    if not ok then
        hide(record)
        if not record.warned then core:Print("World map terrain: " .. tostring(reason)); record.warned = true end
    end
end
function terrain.Refresh(frame)
    if type(frame.EnumeratePinsByTemplate) ~= "function" then return end
    for pin in frame:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
        if not records[pin] then
            records[pin] = { textures = {} }
            hooksecurefunc(pin, "RefreshOverlays", refreshPin)
        end
        refreshPin(pin)
    end
end
function terrain.Available(frame)
    local ok, available = pcall(function()
        local art = C_Map.GetMapArtID(frame:GetMapID())
        return core.Data.MapTerrain[art] ~= nil
    end)
    return ok and available
end
