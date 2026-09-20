-- Resizing a group through the arrangement system. A group that registers with
-- resize = { minWidth, minHeight, maxWidth, maxHeight, apply(width, height) } gets a grip on the bottom
-- right corner of its overlay. Dragging it keeps the group's top left corner where it is and grows or
-- shrinks the rest: first the height, then the width, each stopping flush at the first group in the
-- way or at the screen edge, so a resize can no more end in an overlap than a drag can. apply() is the
-- module's: it sizes its own frames and keeps the size. The place is saved on the group's own anchor.
local core, layout, geometry = RikUI, RikUI.Layout, RikUI.Geometry
local skin = RikUI.Skin

local GRIP_SIZE, DOT, DOT_STEP = 16, 2, 4
local ACCENT = { 0.3, 0.75, 1, 1 }
-- Three rows of dots stepping down to the corner, the usual grip shape.
local DOTS = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 1, 1 }, { 2, 1 }, { 2, 2 } }
local resize

function layout.IsResizing() return resize ~= nil end

local function cursorPosition()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return x / scale, y / scale
end

local function clamp(value, low, high) return math.max(low, math.min(high, value)) end

-- Grows one side from the last free rectangle, stopping flush at whatever is in the way.
local function grow(rect, direction, wanted, current)
    if wanted <= current then return wanted, false end
    local room = geometry.FreeExtent(rect, direction, resize.obstacles, resize.screen)
    local size = math.min(wanted, current + room)
    return size, size < wanted
end

local function sized(left, top, width, height)
    local rect = geometry.Rect(left, top - height, width, height)
    rect.key = resize.key
    return rect
end

local function nextRect(wantedWidth, wantedHeight)
    local last = resize.last
    local left, top = last.left, last.top
    local width, height = last.right - last.left, last.top - last.bottom
    local newHeight, blockedDown = grow(last, "DOWN", wantedHeight, height)
    local tall = sized(left, top, math.min(width, wantedWidth), newHeight)
    local newWidth, blockedRight = grow(tall, "RIGHT", wantedWidth, tall.right - tall.left)
    return sized(left, top, newWidth, newHeight), blockedDown or blockedRight
end

local function step()
    if not resize or InCombatLockdown() then return end
    local x, y = cursorPosition()
    local bounds, scale = resize.bounds, resize.scale
    local width = clamp(resize.startWidth + x - resize.cursorX, bounds.minWidth * scale, bounds.maxWidth * scale)
    local height = clamp(resize.startHeight - (y - resize.cursorY), bounds.minHeight * scale, bounds.maxHeight * scale)
    local rect, blocked = nextRect(width, height)
    resize.last = rect
    bounds.apply((rect.right - rect.left) / scale, (rect.top - rect.bottom) / scale)
    layout.Follow(resize.key, rect)
    layout.MarkBlocked(resize.key, blocked)
end

function layout.BeginResize(key)
    local group, rect, screen = layout.Groups[key], layout.Rect(key), layout.Screen()
    if resize or layout.IsDragging() or InCombatLockdown() or not rect or not screen then return false end
    if not group or type(group.resize) ~= "table" or not core.Profile then return false end
    local x, y = cursorPosition()
    resize = { key = key, bounds = group.resize, last = rect, cursorX = x, cursorY = y, screen = screen,
        startWidth = rect.right - rect.left, startHeight = rect.top - rect.bottom, scale = layout.GetScale(),
        obstacles = layout.Obstacles(key) }
    return true
end

-- Ends where the group stands, which is free by construction.
function layout.EndResize()
    if not resize then return end
    local key, rect = resize.key, resize.last
    resize = nil
    layout.MarkBlocked(key, false)
    layout.SaveRect(key, rect, core.Profile)
    layout.Apply()
end

local function dots(grip)
    for _, dot in ipairs(DOTS) do
        local texture = grip:CreateTexture(nil, "OVERLAY")
        texture:SetTexture(skin.FLAT)
        texture:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        texture:SetSize(DOT, DOT)
        texture:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -2 - (2 - dot[1]) * DOT_STEP, 2 + dot[2] * DOT_STEP)
    end
end

-- Called by src/layout/layout-drag.lua for every new overlay.
function layout.AddGrip(overlay, key)
    local group = layout.Groups[key]
    if not group or type(group.resize) ~= "table" then return end
    local grip = CreateFrame("Button", nil, overlay)
    grip:SetSize(GRIP_SIZE, GRIP_SIZE)
    grip:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, 0)
    dots(grip)
    grip:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then layout.BeginResize(key) end end)
    grip:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then layout.EndResize() end end)
    overlay.grip = grip
end

layout.ResizeDriver = CreateFrame("Frame", nil, UIParent)
layout.ResizeDriver:SetScript("OnUpdate", step)
