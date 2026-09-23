-- Flat skin for Blizzard's group loot roll frames. Only art, the timer texture and the name font
-- change; the need, greed and pass buttons and every script stay Blizzard's.
local core, media, ui = RikUI, RikUI.Media, RikUI.UI
local loot = core.Loot

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
    iconFrame.rikBorder = ui.Edges(iconFrame, EDGE, "OVERLAY")
    for _, line in ipairs(iconFrame.rikBorder) do line:SetVertexColor(unpack(BORDER)) end
end

local function skinRoll(frame)
    for _, key in ipairs(ART) do
        if isRegion(frame[key]) then frame[key]:SetAlpha(0) end
    end
    loot.Flat(frame, "BACKGROUND")
    skinIcon(frame.IconFrame)
    if isRegion(frame.Timer) then frame.Timer:SetStatusBarTexture(media.statusbar) end
    if isRegion(frame.Name) then
        frame.Name:SetFont(media.font, media.sizes.label, "OUTLINE")
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
