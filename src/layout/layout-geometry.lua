-- Rectangle arithmetic for the frame arrangement system. No WoW API: everything is plain numbers in
-- UIParent units, so the invariant the system rests on (no two layout groups overlap) is checked by
-- tests without a client. A rect is { left, bottom, right, top }; a screen is { width, height }.
-- Rectangles that only touch do not overlap.
local geometry = {}
RikUI.Geometry = geometry

local EPSILON = 0.001
-- Where an anchor point sits inside a rectangle, as fractions of its width and height.
local FRACTIONS = {
    TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
    LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
    BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}
-- Exact obstacle edges keep narrow but valid gaps available at fractional UI scales.
-- low and high edge names per axis, and the axis a growth direction runs along.
local AXES = { x = { "left", "right", "width" }, y = { "bottom", "top", "height" } }
local DIRECTIONS = { LEFT = { "x", -1 }, RIGHT = { "x", 1 }, DOWN = { "y", -1 }, UP = { "y", 1 } }

function geometry.Rect(left, bottom, width, height)
    return { left = left, bottom = bottom, right = left + width, top = bottom + height }
end

function geometry.Move(rect, dx, dy)
    return { left = rect.left + dx, bottom = rect.bottom + dy, right = rect.right + dx, top = rect.top + dy }
end

function geometry.FromAnchor(position, width, height, screen)
    local own, relative = FRACTIONS[position.point], FRACTIONS[position.relativePoint]
    local x = relative[1] * screen.width + position.x
    local y = relative[2] * screen.height + position.y
    return geometry.Rect(x - own[1] * width, y - own[2] * height, width, height)
end

function geometry.ToAnchor(rect, point, relativePoint, screen)
    local own, relative = FRACTIONS[point], FRACTIONS[relativePoint]
    local x = rect.left + own[1] * (rect.right - rect.left)
    local y = rect.bottom + own[2] * (rect.top - rect.bottom)
    return { point = point, relativePoint = relativePoint,
        x = x - relative[1] * screen.width, y = y - relative[2] * screen.height }
end

function geometry.Overlaps(a, b)
    return a.left < b.right - EPSILON and b.left < a.right - EPSILON
        and a.bottom < b.top - EPSILON and b.bottom < a.top - EPSILON
end

function geometry.AnyOverlap(rect, obstacles)
    for _, obstacle in ipairs(obstacles) do
        if geometry.Overlaps(rect, obstacle) then return obstacle end
    end
    return nil
end

local function fits(rect, screen)
    return rect.left >= -EPSILON and rect.bottom >= -EPSILON
        and rect.right <= screen.width + EPSILON and rect.top <= screen.height + EPSILON
end

-- A rectangle larger than the screen is aligned to the left and bottom edges.
function geometry.Clamp(rect, screen)
    local dx = math.max(0, -rect.left) + math.min(0, screen.width - rect.right)
    local dy = math.max(0, -rect.bottom) + math.min(0, screen.height - rect.top)
    if rect.right - rect.left > screen.width then dx = -rect.left end
    if rect.top - rect.bottom > screen.height then dy = -rect.bottom end
    return geometry.Move(rect, dx, dy)
end

local function spansCross(rect, obstacle, axis)
    local low, high = AXES[axis == "x" and "y" or "x"][1], AXES[axis == "x" and "y" or "x"][2]
    return rect[low] < obstacle[high] - EPSILON and obstacle[low] < rect[high] - EPSILON
end

-- How far rect can travel along one axis (delta is signed) before it touches an obstacle that lies in
-- its path. Every obstacle in the path counts, so a large move cannot tunnel through one.
local function travel(rect, axis, delta, obstacles)
    local low, high = AXES[axis][1], AXES[axis][2]
    local allowed = delta
    for _, obstacle in ipairs(obstacles) do
        if spansCross(rect, obstacle, axis) then
            if delta > 0 and obstacle[low] >= rect[high] - EPSILON then
                allowed = math.min(allowed, obstacle[low] - rect[high])
            elseif delta < 0 and obstacle[high] <= rect[low] + EPSILON then
                allowed = math.max(allowed, obstacle[high] - rect[low])
            end
        end
    end
    return delta > 0 and math.max(0, allowed) or math.min(0, allowed)
end

local function shift(rect, axis, delta)
    if axis == "x" then return geometry.Move(rect, delta, 0) end
    return geometry.Move(rect, 0, delta)
end

-- Moves from last (which must be free) towards desired, one axis after the other, so a blocked
-- diagonal move slides along the obstacle. The result is on screen and overlaps nothing.
function geometry.Resolve(last, desired, obstacles, screen)
    local target = geometry.Clamp(desired, screen)
    if geometry.AnyOverlap(last, obstacles) or not fits(last, screen) then
        local spot, found = geometry.Nearest(target, obstacles, screen)
        return found and spot or last
    end
    local rect = shift(last, "x", travel(last, "x", target.left - last.left, obstacles))
    return shift(rect, "y", travel(rect, "y", target.bottom - rect.bottom, obstacles))
end

local function distance(a, b)
    return math.abs(a.left - b.left) + math.abs(a.bottom - b.bottom)
end

-- Places flush against each side of each obstacle, keeping the other coordinate.
local function flushCandidates(rect, obstacles)
    local width, height, list = rect.right - rect.left, rect.top - rect.bottom, {}
    for _, obstacle in ipairs(obstacles) do
        list[#list + 1] = geometry.Rect(obstacle.left - width, rect.bottom, width, height)
        list[#list + 1] = geometry.Rect(obstacle.right, rect.bottom, width, height)
        list[#list + 1] = geometry.Rect(rect.left, obstacle.bottom - height, width, height)
        list[#list + 1] = geometry.Rect(rect.left, obstacle.top, width, height)
    end
    return list
end

local function edgeCandidates(rect, obstacles, screen)
    local width, height, list = rect.right - rect.left, rect.top - rect.bottom, {}
    local xs, ys = { 0, screen.width-width, rect.left }, { 0, screen.height-height, rect.bottom }
    for _, obstacle in ipairs(obstacles) do
        xs[#xs+1], xs[#xs+2] = obstacle.left-width, obstacle.right
        ys[#ys+1], ys[#ys+2] = obstacle.bottom-height, obstacle.top
    end
    for _, left in ipairs(xs) do
        for _, bottom in ipairs(ys) do list[#list+1] = geometry.Rect(left, bottom, width, height) end
    end
    return list
end

local function closestFree(origin, candidates, obstacles, screen)
    local best, bestDistance
    for _, candidate in ipairs(candidates) do
        if fits(candidate, screen) and not geometry.AnyOverlap(candidate, obstacles) then
            local away = distance(origin, candidate)
            if not bestDistance or away < bestDistance then best, bestDistance = candidate, away end
        end
    end
    return best
end

-- The closest free place for a rectangle: where it is, else flush against an obstacle, else the
-- closest intersection of obstacle edges. The second result is false when the screen has no room.
function geometry.Nearest(rect, obstacles, screen)
    local origin = geometry.Clamp(rect, screen)
    if fits(origin, screen) and not geometry.AnyOverlap(origin, obstacles) then return origin, true end
    local spot = closestFree(origin, flushCandidates(origin, obstacles), obstacles, screen)
        or closestFree(origin, edgeCandidates(origin, obstacles, screen), obstacles, screen)
    if spot then return spot, true end
    return origin, false
end

-- Snap targets for one axis: each entry pairs a value on the moving rectangle with the line it may
-- land on. Edges align with edges, centres with centres, and facing edges meet at the gap.
local function axisTargets(rect, axis, obstacles, screen, gap)
    local low, high, size = AXES[axis][1], AXES[axis][2], screen[AXES[axis][3]]
    local middle = (rect[low] + rect[high]) / 2
    local targets = { { rect[low], 0 }, { rect[high], size }, { middle, size / 2 } }
    for _, obstacle in ipairs(obstacles) do
        targets[#targets + 1] = { rect[low], obstacle[high] + gap }
        targets[#targets + 1] = { rect[high], obstacle[low] - gap }
        targets[#targets + 1] = { rect[low], obstacle[low] }
        targets[#targets + 1] = { rect[high], obstacle[high] }
        targets[#targets + 1] = { middle, (obstacle[low] + obstacle[high]) / 2 }
    end
    return targets
end

local function snapAxis(rect, axis, obstacles, screen, threshold, gap)
    local best, line
    for _, target in ipairs(axisTargets(rect, axis, obstacles, screen, gap)) do
        local delta = target[2] - target[1]
        if math.abs(delta) <= threshold and (not best or math.abs(delta) < math.abs(best)) then
            best, line = delta, target[2]
        end
    end
    return best or 0, line
end

-- The offset that lands rect on the nearest snap line per axis, and the lines to draw as guides.
function geometry.Snap(rect, obstacles, screen, threshold, gap)
    local guides = {}
    local dx, lineX = snapAxis(rect, "x", obstacles, screen, threshold, gap)
    local dy, lineY = snapAxis(rect, "y", obstacles, screen, threshold, gap)
    if lineX then guides[#guides + 1] = { axis = "x", at = lineX } end
    if lineY then guides[#guides + 1] = { axis = "y", at = lineY } end
    return dx, dy, guides
end

-- How far rect may grow in a direction before the next obstacle in its path, or the screen edge.
function geometry.FreeExtent(rect, direction, obstacles, screen)
    local axis, sign = DIRECTIONS[direction][1], DIRECTIONS[direction][2]
    local low, high, size = AXES[axis][1], AXES[axis][2], screen[AXES[axis][3]]
    local room = sign > 0 and size - rect[high] or rect[low]
    return math.abs(travel(rect, axis, sign * math.max(0, room), obstacles))
end
