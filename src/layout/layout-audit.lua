-- Checks a whole-screen layout (data/layouts.lua) with plain numbers: every key placed, nothing off
-- screen or closer than MARGIN to an edge, no overlap, neighbours at least GAP apart. No WoW API, so
-- the suite proves the four layouts clean on several aspect ratios without a client.
local core = RikUI
local layouts, geometry = core.Layouts, core.Geometry

local EDGES = { { "left", "the left edge" }, { "bottom", "the bottom edge" }, { "right", "the right edge" },
    { "top", "the top edge" } }

-- The rectangle a key takes in a layout: its nominal size plus the room its labels, tabs or edit box
-- need outside the frame.
function layouts.Rect(name, key, screen, positions)
    local entry = layouts[name]
    local position = positions and positions[key] or type(entry) == "table" and entry.positions[key] or nil
    local size = position and entry.sizes and entry.sizes[key] or layouts.Sizes[key]

    if not position or not size then return nil end
    local rect = geometry.FromAnchor(position, size.width, size.height, screen)
    local pad = layouts.Pads[key]
    if pad then rect.top, rect.bottom = rect.top + (pad.top or 0), rect.bottom - (pad.bottom or 0) end
    rect.key = key
    return rect
end

local function sortedKeys(values)
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

-- Windows that float over the screen (the tooltip anchor, the bag window) are placed but block nothing;
-- party and raid share a place because they are never shown together.
local function blocks(first, second)
    if layouts.Floating[first] or layouts.Floating[second] then return false end
    local tag = layouts.Exclusive[first]
    return not (tag and tag == layouts.Exclusive[second])
end

local function distance(a, b)
    local dx = math.max(a.left - b.right, b.left - a.right, 0)
    local dy = math.max(a.bottom - b.top, b.bottom - a.top, 0)
    return math.max(dx, dy)
end

local function edgeIssues(rect, screen, issues)
    local room = { left = rect.left, bottom = rect.bottom, right = screen.width - rect.right, top = screen.height - rect.top }
    for _, edge in ipairs(EDGES) do
        local value = room[edge[1]]
        if value < 0 then issues[#issues + 1] = rect.key .. " is off screen at " .. edge[2]
        elseif value < layouts.MARGIN then
            issues[#issues + 1] = string.format("%s is %d from %s", rect.key, value, edge[2])
        end
    end
end

local function pairIssue(first, second)
    if geometry.Overlaps(first, second) then return first.key .. " overlaps " .. second.key end
    local apart = distance(first, second)
    if apart < layouts.GAP then return string.format("%s is %d from %s", second.key, apart, first.key) end
end

-- Fit complete presets before applying them. Combat frames keep their intended places;
-- supporting windows yield as screen dimensions and widget footprints change.
local PRIORITY = { "main", "bar2", "bar3", "bar4", "bar5", "stance", "pet", "xpbar",
    "swingtimer", "combatresource", "cooldowns", "castplayer",
    "raid", "party", "chat", "minimap", "micromenu", "bagspace" }
local rank = {}
for index, key in ipairs(PRIORITY) do rank[key] = index end

local function copyPositions(source)
    local positions = {}
    for key, value in pairs(source) do
        positions[key] = { point=value.point, relativePoint=value.relativePoint, x=value.x, y=value.y }
    end
    return positions
end

local function orderedKeys(name, positions)
    local keys = sortedKeys(positions)
    table.sort(keys, function(a, b)
        local first, second = rank[a] or math.huge, rank[b] or math.huge
        if first ~= second then return first < second end
        local sa, sb = layouts.Sizes[a], layouts.Sizes[b]
        local aa, ab = sa and sa.width*sa.height or 0, sb and sb.width*sb.height or 0
        if aa ~= ab then return aa > ab end
        return a < b
    end)
    return keys
end

local function obstaclesFor(key, placed)
    local obstacles, margin = {}, layouts.MARGIN
    for _, other in ipairs(placed) do
        if blocks(key, other.key) then
            obstacles[#obstacles+1] = { left=other.left-margin-layouts.GAP,
                right=other.right-margin+layouts.GAP, bottom=other.bottom-margin-layouts.GAP,
                top=other.top-margin+layouts.GAP }
        end
    end
    return obstacles
end

local function fitPositions(name, screen, positions)
    local placed, margin = {}, layouts.MARGIN
    local available = { width=screen.width-2*margin, height=screen.height-2*margin }
    for _, key in ipairs(orderedKeys(name, positions)) do
        local rect = layouts.Rect(name, key, screen, positions)
        if rect and not layouts.Floating[key] then
            local obstacles = obstaclesFor(key, placed)
            local wanted = geometry.Move(rect, -margin, -margin)
            local fitted, found = geometry.Nearest(wanted, obstacles, available)
            if found then
                fitted = geometry.Move(fitted, margin, margin)
                positions[key].x = positions[key].x + fitted.left - rect.left
                positions[key].y = positions[key].y + fitted.bottom - rect.bottom
                fitted.key = key
                rect = fitted
            end
            placed[#placed+1] = rect
        end
    end
    return positions
end

-- Registration asks for defaults repeatedly. Cache only the last viewport per preset,
-- and always return a copy so setup, undo and hand edits cannot mutate the cached recipe.
local fitted = {}
function layouts.Positions(name, screen)
    local entry = layouts[name]
    if not entry or not entry.positions then return nil end
    if not screen then return copyPositions(entry.positions) end
    local cached = fitted[name]
    if not cached or cached.width ~= screen.width or cached.height ~= screen.height then
        cached = { width=screen.width, height=screen.height,
            positions=fitPositions(name, screen, copyPositions(entry.positions)) }
        fitted[name] = cached
    end
    return copyPositions(cached.positions)
end

function layouts.Audit(name, screen)
    if type(layouts[name]) ~= "table" or type(layouts[name].positions) ~= "table" then
        return { tostring(name) .. ": unknown layout" }
    end
    local issues, rects = {}, {}
    local positions = layouts.Positions(name, screen)
    for _, key in ipairs(sortedKeys(layouts.Sizes)) do
        local rect = layouts.Rect(name, key, screen, positions)
        if rect then rects[#rects + 1] = rect else issues[#issues + 1] = key .. ": not placed" end
    end
    for index, rect in ipairs(rects) do
        edgeIssues(rect, screen, issues)
        for other = index + 1, #rects do
            local issue = blocks(rect.key, rects[other].key) and pairIssue(rect, rects[other]) or nil
            if issue then issues[#issues + 1] = issue end
        end
    end
    table.sort(issues)
    return issues
end
