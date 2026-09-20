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
local LOCK_SIZE, LOCK_ICON, LOCK_INSET, LOCK_HOVER, LOCK_FADE = 18, 12, 2, 0.35, 0.12
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

local function lockTip(button, key)
    button.glow:SetAlpha(LOCK_HOVER)
    motion.Play(button.glow.fade)
    if type(GameTooltip) ~= "table" then return end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText("Lock " .. layout.Label(key))
    GameTooltip:Show()
end

-- The overlay covers the whole frame, so a lock control the frame has of its own (the chat's padlock)
-- lies under it. Every overlay therefore carries its own lock button: a child of the overlay, which the
-- client gives the click before the overlay, whatever else is on screen.
local function addLock(overlay, key)
    local button = CreateFrame("Button", nil, overlay)
    button:SetSize(LOCK_SIZE, LOCK_SIZE)
    button:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", -LOCK_INSET, -LOCK_INSET)
    skin.Fill(button, skin.BACKING)
    skin.Outline(button, ACCENT)
    button.icon = media.Icon(button, "lock-open", LOCK_ICON, "ARTWORK")
    button.icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.icon:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
    button.glow = button:CreateTexture(nil, "OVERLAY")
    button.glow:SetAllPoints(button)
    button.glow:SetTexture(media.highlight)
    button.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
    button.glow:SetAlpha(0)
    button.glow.fade = motion.Tween(button.glow, 0, LOCK_HOVER, LOCK_FADE)
    button:SetScript("OnEnter", function(self) lockTip(self, key) end)
    button:SetScript("OnLeave", function(self)
        self.glow:SetAlpha(0)
        if type(GameTooltip) == "table" then GameTooltip:Hide() end
    end)
    button:SetScript("OnClick", function() layout.SetUnlocked(key, false) end)
    overlay.lock = button
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
    addLock(overlay, key)
    if layout.AddGrip then layout.AddGrip(overlay, key) end
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

layout.Follow = follow

-- The overlay's edge turns red while something is in the way of a drag or a resize.
function layout.MarkBlocked(key, blocked)
    local overlay = layout.Overlays[key]
    if not overlay or overlay.blocked == blocked then return end
    overlay.blocked = blocked
    paintEdge(overlay, blocked and BLOCKED or ACCENT)
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
    layout.MarkBlocked(drag.key, blocked)
end

-- Starts dragging a group by the cursor. The overlay calls this, and so do frames that are dragged
-- by a handle of their own (the bag header, the chat tab).
function layout.BeginDrag(key)
    local rect, screen = layout.Rect(key), layout.Screen()
    if drag or (layout.IsResizing and layout.IsResizing()) or InCombatLockdown() or not rect or not screen or not core.Profile then return false end
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
    layout.MarkBlocked(key, false)
    layout.SaveRect(key, rect, core.Profile)
    layout.Apply()
end

layout.DragDriver = CreateFrame("Frame", nil, UIParent)
layout.DragDriver:SetScript("OnUpdate", step)
