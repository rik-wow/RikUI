-- Checks a whole-screen layout (data/layouts.lua) with plain numbers: every key placed, nothing off
-- screen or closer than MARGIN to an edge, no overlap, neighbours at least GAP apart. No WoW API, so
-- the suite proves the four layouts clean on several aspect ratios without a client.
local core = RikUI
local layouts, geometry = core.Layouts, core.Geometry

local EDGES = { { "left", "the left edge" }, { "bottom", "the bottom edge" }, { "right", "the right edge" },
    { "top", "the top edge" } }

-- The rectangle a key takes in a layout: its nominal size plus the room its labels, tabs or edit box
-- need outside the frame.
function layouts.Rect(name, key, screen)
    local entry = layouts[name]
    local position = type(entry) == "table" and entry.positions[key] or nil
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

function layouts.Audit(name, screen)
    if type(layouts[name]) ~= "table" or type(layouts[name].positions) ~= "table" then
        return { tostring(name) .. ": unknown layout" }
    end
    local issues, rects = {}, {}
    for _, key in ipairs(sortedKeys(layouts.Sizes)) do
        local rect = layouts.Rect(name, key, screen)
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
