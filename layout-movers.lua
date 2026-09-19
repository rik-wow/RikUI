-- Independent proxies have no protected children or anchors to secure targets.
local core, layout = RikUI, RikUI.Layout
local LABELS = { main = "Main bar", bar2 = "Bar 2", bar3 = "Bar 3", bar4 = "Bar 4",
    bar5 = "Bar 5", stance = "Stance bar", pet = "Pet bar", player = "Player frame",
    target = "Target frame", tot = "Target of target", petframe = "Pet frame",
    castplayer = "Player castbar", casttarget = "Target castbar" }
local LABEL_SIZE, MIN_SIZE = 12, 24
local moving = false
layout.Movers = {}

local function cancelDrag(mover)
    if not mover.dragProfile then return end
    mover.dragProfile = nil
    mover:StopMovingOrSizing()
end

function layout.StopMoving()
    moving = false
    for _, mover in pairs(layout.Movers) do cancelDrag(mover); mover:Hide() end
end

function layout.IsMoving() return moving end

local function syncMover(mover, key, group)
    cancelDrag(mover)
    local frame, saved = group.frames[1], layout.GetPosition(key)
    mover:SetScale(frame:GetEffectiveScale() / UIParent:GetEffectiveScale())
    mover:SetSize(math.max(MIN_SIZE, frame:GetWidth()), math.max(MIN_SIZE, frame:GetHeight()))
    mover:ClearAllPoints()
    mover:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    mover:Show()
end

local function saveDrop(mover)
    local profile = mover.dragProfile
    if not profile then return end
    cancelDrag(mover)
    if InCombatLockdown() or not moving or profile ~= core.Profile then return end
    local x, y = mover:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if not x or not y or not parentX or not parentY then
        core:Print("Frame position unavailable; drag cancelled.")
        layout.RefreshMovers()
        return
    end
    local ratio = UIParent:GetEffectiveScale() / mover:GetEffectiveScale()
    profile.positions[mover.key] = { point = "CENTER", relativePoint = "CENTER",
        x = x - parentX * ratio, y = y - parentY * ratio }
    layout.Apply()
end

local function decorateMover(mover, key)
    local background = mover:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.08, 0.3, 0.5, 0.8)
    local border = mover:CreateTexture(nil, "BORDER")
    border:SetAllPoints()
    border:SetTexture(core.Media.border)
    border:SetVertexColor(0.5, 0.8, 1, 1)
    mover.label = mover:CreateFontString(nil, "OVERLAY")
    mover.label:SetFont(core.Media.font, LABEL_SIZE, "OUTLINE")
    mover.label:SetPoint("CENTER")
    mover.label:SetText(LABELS[key] or key)
end

local function createMover(key)
    local mover = CreateFrame("Frame", nil, UIParent)
    mover.key = key
    mover:SetFrameStrata("DIALOG")
    mover:SetMovable(true)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    decorateMover(mover, key)
    mover:SetScript("OnDragStart", function()
        if InCombatLockdown() or not moving then return end
        mover.dragProfile = core.Profile
        mover:StartMoving()
    end)
    mover:SetScript("OnDragStop", saveDrop)
    mover:SetScript("OnHide", cancelDrag)
    layout.Movers[key] = mover
    return mover
end

function layout.RefreshMovers()
    if not moving or InCombatLockdown() then return end
    for key, group in pairs(layout.Groups) do
        syncMover(layout.Movers[key] or createMover(key), key, group)
    end
end

local function toggle()
    if InCombatLockdown() then core:Print("Cannot move frames in combat."); return end
    if not core.Profile then core:Print("Still loading."); return end
    if moving then layout.StopMoving(); core:Print("Frames locked."); return end
    moving = true
    layout.RefreshMovers()
    core:Print("Drag the labelled overlays, then /rik move to lock. /rik move reset restores defaults.")
end

core:RegisterCommand("move", function(args)
    if args == "" then toggle(); return end
    if args:lower() ~= "reset" then core:Print("Usage: /rik move [reset]"); return end
    local ok, reason = layout.Reset()
    core:Print(ok and "Frame positions reset." or reason)
end, "Drag frames, or restore defaults: /rik move [reset]")

core:RegisterCommand("scale", function(args)
    local ok, reason = layout.SetScale(tonumber(args))
    core:Print(ok and ("Frame scale: " .. core.Profile.scale) or reason)
end, "Scale every registered frame: /rik scale <0.25-3>")

core:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if moving then layout.StopMoving(); core:Print("Frames locked for combat; unfinished drag cancelled.") end
end)
core:RegisterEvent("UI_SCALE_CHANGED", layout.StopMoving)
core:RegisterEvent("DISPLAY_SIZE_CHANGED", layout.StopMoving)
