-- Flat skin for Blizzard's group loot roll frames. Only art, the timer texture and the name font
-- change; the need, greed and pass buttons and every script stay Blizzard's.
local core, media, ui = RikUI, RikUI.Media, RikUI.UI
local loot, skin = core.Loot, core.Skin
local styled = setmetatable({}, { __mode = "k" })

local ROLL_PREFIX, ROLL_FRAMES, EDGE = "GroupLootFrame", 4, 1
local BORDER = { 0.25, 0.28, 0.32, 1 }
-- GroupLootFrameBaseTemplate's toast art on 69913, plus the dialog panel's nine-slice when present.
local ART = { "Background", "Border", "NineSlice" }

local function isRegion(value)
    local kind = type(value)
    return (kind == "table" or kind == "userdata") and type(value.SetAlpha) == "function"
end

local function skinIcon(iconFrame)
    if not isRegion(iconFrame) then return end
    if isRegion(iconFrame.Border) then iconFrame.Border:SetAlpha(0) end
    skin.CropIcon(iconFrame.Icon)
    iconFrame.rikBacking = skin.Fill(iconFrame, skin.CONTROL, -2)
    iconFrame.rikBorder = ui.Edges(iconFrame, EDGE, "OVERLAY")
    for _, line in ipairs(iconFrame.rikBorder) do line:SetVertexColor(unpack(BORDER)) end
end

local function skinTimer(timer)
    if not isRegion(timer) then return end
    timer:SetStatusBarTexture(media.statusbar)
    timer.rikTrack = skin.Fill(timer, { 0.025, 0.035, 0.05, 1 })
    timer.rikEdge = skin.Outline(timer, BORDER, 0, nil, "OVERLAY")
end

local function skinRoll(frame)
    if styled[frame] then return end
    styled[frame] = true
    for _, key in ipairs(ART) do
        if isRegion(frame[key]) then frame[key]:SetAlpha(0) end
    end
    frame.rikChrome = skin.WindowChrome(frame, 48, 12)
    frame.rikBorder = frame.rikChrome.edge
    skinIcon(frame.IconFrame)
    skinTimer(frame.Timer)
    if isRegion(frame.Name) then
        frame.Name:SetFont(media.font, media.Size("label"), "OUTLINE")
    end
    core.Motion.BindEntrance(frame)
    loot.SkinnedRolls[#loot.SkinnedRolls + 1] = frame
end

function loot.SkinRolls()
    for index = 1, ROLL_FRAMES do
        local frame = _G[ROLL_PREFIX .. index]
        if isRegion(frame) then skinRoll(frame) end
    end
end
