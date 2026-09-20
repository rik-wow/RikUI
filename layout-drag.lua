-- The overlay of an unlocked group and the drag engine. The overlay is the "indeterminate" state:
-- a tinted panel with a pulsing edge and a band sweeping across it. The engine does not use
-- StartMoving, because the client would put the frame wherever the cursor goes: every frame of a
-- drag it builds the rectangle the cursor asks for, snaps it, resolves it against the other groups
-- through layout-geometry.lua and places the group there, so a drag can never end in an overlap.
-- Dragging only happens out of combat; when combat starts, the last free place is kept.
local core, layout, geometry = RikUI, RikUI.Layout, RikUI.Geometry
local skin, media, motion = RikUI.Skin, RikUI.Media, RikUI.Motion
layout.Overlays, layout.Guides = {}, {}

local TINT, ACCENT, BLOCKED = { 0.3, 0.75, 1, 0.16 }, { 0.3, 0.75, 1, 1 }, { 1, 0.3, 0.25, 1 }
local SNAP_THRESHOLD, SNAP_GAP, BAND_WIDTH, SWEEP_SECONDS, PULSE_SECONDS, PULSE_LOW = 8, 4, 64, 1.6, 0.8, 0.35
local drag

function layout.IsDragging() return drag ~= nil end

local function place(frame, rect)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", rect.left, rect.bottom)
    frame:SetSize(rect.right - rect.left, rect.top - rect.bottom)
end

-- The band lives in a clipping child so it is only seen while it crosses the overlay.
local function sweepBand(overlay)
    local clip = CreateFrame("Frame", nil, overlay)
    clip:SetAllPoints(overlay)
    if type(clip.SetClipsChildren) == "function" then clip:SetClipsChildren(true) end
    local band = clip:CreateTexture(nil, "ARTWORK")
    band:SetTexture(media.highlight)
    band:SetPoint("TOPRIGHT", clip, "TOPLEFT", 0, 0)
    band:SetPoint("BOTTOMRIGHT", clip, "BOTTOMLEFT", 0, 0)
    band:SetWidth(BAND_WIDTH)
    overlay.band = band
    return band
end

local function paintEdge(overlay, color)
    for _, line in ipairs(overlay.edge) do line:SetVertexColor(unpack(color)) end
end

local function newOverlay(key)
    local overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetFrameStrata("DIALOG")
    overlay:EnableMouse(true)
    overlay.fill = skin.Fill(overlay, TINT)
    overlay.rim = CreateFrame("Frame", nil, overlay)
    overlay.rim:SetAllPoints(overlay)
    overlay.edge = skin.Outline(overlay.rim, ACCENT)
    overlay.pulse = motion.Pulse(overlay.rim, 1, PULSE_LOW, PULSE_SECONDS)
    overlay.label = overlay:CreateFontString(nil, "OVERLAY")
    media.Font(overlay.label, "small")
    overlay.label:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    overlay.label:SetText(layout.Label(key))
    overlay.blocked = false
    overlay:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then layout.BeginDrag(key) end end)
    overlay:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then layout.EndDrag() end end)
    overlay:Hide()
    layout.Overlays[key] = overlay
    return overlay
end

local function startMotion(overlay, rect)
    motion.Play(overlay.pulse)
    local band = overlay.band or sweepBand(overlay)
    motion.Stop(overlay.sweep)
    overlay.sweep = motion.Sweep(band, rect.right - rect.left + BAND_WIDTH, SWEEP_SECONDS)
    motion.Play(overlay.sweep)
end

-- Shows, moves or hides a group's overlay to match its lock state and its rectangle.
function layout.RefreshOverlay(key)
    local overlay = layout.Overlays[key]
    if not layout.IsUnlocked(key) then
        if overlay then
            motion.Stop(overlay.pulse)
            motion.Stop(overlay.sweep)
            overlay:Hide()
        end
        return
    end
    local rect = layout.Rect(key)
    if not rect then return end
    overlay = overlay or newOverlay(key)
    place(overlay, rect)
    if overlay:IsShown() then return end
    overlay:Show()
    startMotion(overlay, rect)
end

local function guide(axis)
    local line = layout.Guides[axis]
    if line then return line end
    line = UIParent:CreateTexture(nil, "OVERLAY")
    line:SetTexture(skin.FLAT)
    line:SetVertexColor(unpack(ACCENT))
    line:Hide()
    layout.Guides[axis] = line
    return line
end

local function showGuides(guides, screen)
    guide("x"):Hide()
    guide("y"):Hide()
    for _, entry in ipairs(guides) do
        local line = guide(entry.axis)
        line:ClearAllPoints()
        if entry.axis == "x" then
            line:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", entry.at, 0)
            line:SetSize(1, screen.height)
        else
            line:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, entry.at)
            line:SetSize(screen.width, 1)
        end
        line:Show()
    end
end

local function cursorPosition()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return x / scale, y / scale
end

-- The real frames follow at once: all of this runs out of combat, where a secure frame may be moved.
local function follow(key, rect)
    layout.SaveRect(key, rect, core.Profile)
    local saved, scale = layout.GetPosition(key), layout.GetScale()
    for _, frame in ipairs(layout.Groups[key].frames) do
        frame:SetScale(scale)
        frame:ClearAllPoints()
        frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    end
    if layout.Overlays[key] then place(layout.Overlays[key], rect) end
end

local function step()
    if not drag or InCombatLockdown() then return end
    local x, y = cursorPosition()
    local wanted = geometry.Move(drag.start, x - drag.cursorX, y - drag.cursorY)
    local guides = {}
    if not IsShiftKeyDown() then
        local dx, dy
        dx, dy, guides = geometry.Snap(wanted, drag.obstacles, drag.screen, SNAP_THRESHOLD, SNAP_GAP)
        wanted = geometry.Move(wanted, dx, dy)
    end
    local rect = geometry.Resolve(drag.last, wanted, drag.obstacles, drag.screen)
    local target = geometry.Clamp(wanted, drag.screen)
    local blocked = math.abs(rect.left - target.left) > 0.5 or math.abs(rect.bottom - target.bottom) > 0.5
    drag.last = rect
    showGuides(blocked and {} or guides, drag.screen)
    follow(drag.key, rect)
    local overlay = layout.Overlays[drag.key]
    if overlay and overlay.blocked ~= blocked then
        overlay.blocked = blocked
        paintEdge(overlay, blocked and BLOCKED or ACCENT)
    end
end

-- Starts dragging a group by the cursor. The overlay calls this, and so do frames that are dragged
-- by a handle of their own (the bag header, the chat tab).
function layout.BeginDrag(key)
    local rect, screen = layout.Rect(key), layout.Screen()
    if drag or InCombatLockdown() or not rect or not screen or not core.Profile then return false end
    local x, y = cursorPosition()
    drag = { key = key, start = rect, last = rect, cursorX = x, cursorY = y, screen = screen,
        obstacles = layout.Obstacles(key) }
    return true
end

-- Ends the drag where the group stands: that place is free by construction, in or out of combat.
function layout.EndDrag()
    if not drag then return end
    local key, rect = drag.key, drag.last
    drag = nil
    guide("x"):Hide()
    guide("y"):Hide()
    local overlay = layout.Overlays[key]
    if overlay and overlay.blocked then
        overlay.blocked = false
        paintEdge(overlay, ACCENT)
    end
    layout.SaveRect(key, rect, core.Profile)
    layout.Apply()
end

layout.DragDriver = CreateFrame("Frame", nil, UIParent)
layout.DragDriver:SetScript("OnUpdate", step)
