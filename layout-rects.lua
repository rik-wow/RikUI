-- The arrangement system's view of the layout groups: every group is a rectangle, and no two
-- rectangles overlap. A rectangle is computed from the saved position, the frame's size and the
-- layout scale, never read from the screen, so a group that is hidden right now (the target frame
-- without a target, the loot list) still has one and still blocks. Arithmetic lives in
-- layout-geometry.lua. Positions are only written through layout.Apply, which waits out combat.
local core, layout, geometry = RikUI, RikUI.Layout, RikUI.Geometry

-- The settle order: a group earlier in the list keeps its place, a later one gives way. Bars and
-- unit frames first, windows that come and go last. Groups not listed follow in alphabetical order.
local ORDER = { "main", "bar2", "bar3", "bar4", "bar5", "stance", "pet", "xpbar", "player", "target", "tot",
    "petframe", "focus", "castplayer", "casttarget", "castfocus", "castpet", "chat", "party", "raid", "minimap", "buffs",
    "debuffs", "questtimers", "questtracker", "micromenu", "damagemeter", "bags", "loot" }
local rank, settled, pending = {}, false, {}
for index, key in ipairs(ORDER) do rank[key] = index end

function layout.Screen()
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then return nil end
    return { width = width, height = height }
end

local function sizeOf(group)
    local frame = group.frames[1]
    local width, height = frame:GetWidth(), frame:GetHeight()
    if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then return nil end
    return width, height
end

-- nil for a group without a size yet, and on a client that does not report a screen size.
function layout.Rect(key)
    local group, screen = layout.Groups[key], layout.Screen()
    if not group or not screen or not core.Profile then return nil end
    local width, height = sizeOf(group)
    if not width then return nil end
    local scale, saved = layout.GetScale(), layout.GetPosition(key)
    local rect = geometry.FromAnchor({ point = saved.point, relativePoint = saved.relativePoint,
        x = saved.x * scale, y = saved.y * scale }, width * scale, height * scale, screen)
    rect.key = key
    return rect
end

local function blocks(group, other)
    if layout.Floats(group) or layout.Floats(other) then return false end
    return not (group.exclusive and group.exclusive == other.exclusive)
end

-- Every rectangle the group named by exceptKey must stay clear of.
function layout.Obstacles(exceptKey)
    local list, own = {}, layout.Groups[exceptKey]
    for key, group in pairs(layout.Groups) do
        local rect = key ~= exceptKey and (not own or blocks(own, group)) and layout.Rect(key) or nil
        if rect then list[#list + 1] = rect end
    end
    return list
end

-- Saved on the group's own anchor point: a tracker anchored by its top right corner keeps growing
-- downward after it was moved. scale is the frame's scale relative to UIParent.
function layout.SaveRect(key, rect, profile, scale)
    local group, screen = layout.Groups[key], layout.Screen()
    if not group or not screen then return false end
    scale = scale or layout.GetScale()
    local anchored = geometry.ToAnchor(rect, group.defaults.point, group.defaults.relativePoint, screen)
    profile.positions[key] = { point = anchored.point, relativePoint = anchored.relativePoint,
        x = anchored.x / scale, y = anchored.y / scale }
    return true
end

-- Without a screen size there are no rectangles; the drop is then kept as an offset from the screen
-- centre in the frame's own scale, which needs neither.
local function saveFromCenter(key, frame, profile, x, y)
    local parentX, parentY = UIParent:GetCenter()
    if not parentX or not parentY then return false end
    local ratio = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
    profile.positions[key] = { point = "CENTER", relativePoint = "CENTER", x = x - parentX * ratio, y = y - parentY * ratio }
    return true
end

-- For a frame that was dragged with StartMoving: where it was dropped becomes the group's position.
function layout.SaveCenter(key, frame, profile)
    local x, y = frame:GetCenter()
    if not x or not y then return false end
    local width, height = frame:GetWidth(), frame:GetHeight()
    if not layout.Screen() or type(width) ~= "number" or type(height) ~= "number" then
        return saveFromCenter(key, frame, profile, x, y)
    end
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local rect = geometry.Rect((x - width / 2) * scale, (y - height / 2) * scale, width * scale, height * scale)
    return layout.SaveRect(key, rect, profile, scale)
end

-- How much further a growing group may grow, in its frame's own units; nil for a group that does not.
function layout.Available(key)
    local group, screen = layout.Groups[key], layout.Screen()
    local rect = group and group.grow and screen and layout.Rect(key) or nil
    if not rect then return nil end
    return geometry.FreeExtent(rect, group.grow, layout.Obstacles(key), screen) / layout.GetScale()
end

function layout.NotifyLimits()
    for key, group in pairs(layout.Groups) do
        if type(group.onLimit) == "function" then
            local ok, reason = pcall(group.onLimit, layout.Available(key))
            if not ok then core:Print("Layout limit " .. key .. ": " .. tostring(reason)) end
        end
    end
end

local function ordered()
    local keys = {}
    for key in pairs(layout.Groups) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        local first, second = rank[a] or math.huge, rank[b] or math.huge
        if first ~= second then return first < second end
        return a < b
    end)
    return keys
end

-- Moves one group clear of the given rectangles; returns its rectangle and whether it moved.
local function makeRoom(key, rect, obstacles, screen)
    local onScreen = geometry.Clamp(rect, screen)
    local inPlace = onScreen.left == rect.left and onScreen.bottom == rect.bottom
    if inPlace and not geometry.AnyOverlap(rect, obstacles) then return rect, false end
    local spot, found = geometry.Nearest(rect, obstacles, screen)
    if not found then return rect, false end
    spot.key = key
    layout.SaveRect(key, spot, core.Profile)
    return spot, true
end

local function settleAll(screen)
    local placed, moved = {}, {}
    for _, key in ipairs(ordered()) do
        local group, rect = layout.Groups[key], layout.Rect(key)
        if rect and not layout.Floats(group) then
            local obstacles = {}
            for _, other in ipairs(placed) do
                if blocks(group, layout.Groups[other.key]) then obstacles[#obstacles + 1] = other end
            end
            local spot, didMove = makeRoom(key, rect, obstacles, screen)
            if didMove then moved[#moved + 1] = group.label or key end
            placed[#placed + 1] = spot
        end
    end
    return moved
end

local function settleOne(key, screen)
    local group, rect = layout.Groups[key], layout.Rect(key)
    if not rect or layout.Floats(group) then return {} end
    local _, didMove = makeRoom(key, rect, layout.Obstacles(key), screen)
    return didMove and { group.label or key } or {}
end

local function run(key)
    local screen = layout.Screen()
    if not screen or not core.Profile then return end
    local moved = key and settleOne(key, screen) or settleAll(screen)
    if #moved == 0 then return end
    core:Print("Made room on screen, moved: " .. table.concat(moved, ", ") .. ". /rik move rearranges.")
    layout.Apply()
end

-- Without a key: the whole screen, in order, which also marks the layout as settled. With a key:
-- only that group gives way, which is what a resize or a late registration asks for. Before the
-- first full pass a keyed call does nothing: frames are still registering. Waits out combat.
function layout.Settle(key)
    if key and not settled then return end
    local token = key or true
    if pending[token] then return end
    pending[token] = true
    core.Combat.Queue(function()
        pending[token] = nil
        if not key then settled = true end
        run(key)
    end)
end

core:RegisterEvent("PLAYER_ENTERING_WORLD", function() layout.Settle() end)
core:RegisterEvent("UI_SCALE_CHANGED", function() layout.Settle() end)
core:RegisterEvent("DISPLAY_SIZE_CHANGED", function() layout.Settle() end)
