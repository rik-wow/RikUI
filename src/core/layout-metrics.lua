-- Pure geometry shared by native controls and Studio's trusted Lua engine.
local metrics = {}
RikUI.LayoutMetrics = metrics
metrics.BarKeys = { "main", "bar2", "bar3", "bar4", "bar5", "stance", "pet" }
local barKeys = {}
for _, key in ipairs(metrics.BarKeys) do barKeys[key] = true end
local castWidths = { castplayer=280, casttarget=220, castfocus=160, castpet=110 }
local function valid(value, low, high)
    return type(value) == "number" and value >= low and value <= high and value % 1 == 0
end
function metrics.BarOptions(key, profile, fallback)
    fallback = fallback or {}
    local control = key == "stance" or key == "pet"
    local saved = profile and profile.barLayout and profile.barLayout[key] or {}
    return {
        columns = saved.columns or fallback.columns or (fallback.vertical and 1) or ((key == "bar4" or key == "bar5") and 1) or (control and 10 or 12),
        size = saved.size or fallback.size or (control and 30 or 36),
        spacing = saved.spacing or fallback.spacing or 6,
    }
end
function metrics.IsBar(key) return barKeys[key] == true end
function metrics.Grid(count, options)
    local columns = math.min(math.max(1, count), options.columns)
    local rows = math.ceil(math.max(1, count) / columns)
    return {
        width=columns * options.size + (columns - 1) * options.spacing,
        height=rows * options.size + (rows - 1) * options.spacing,
        columns=columns, rows=rows, count=count, size=options.size, spacing=options.spacing,
    }
end
function metrics.Cell(index, grid)
    local step = grid.size + grid.spacing
    return ((index - 1) % grid.columns) * step, -math.floor((index - 1) / grid.columns) * step
end
function metrics.ValidateBar(value, key)
    if not barKeys[key] or type(value) ~= "table" or getmetatable(value) then return false end
    for name, setting in pairs(value) do
        if name == "columns" then if not valid(setting, 1, (key == "pet" or key == "stance") and 10 or 12) then return false end
        elseif name == "size" then if not valid(setting, 24, 64) then return false end
        elseif name == "spacing" then if not valid(setting, 0, 16) then return false end
        else return false end
    end
    return true
end
function metrics.Cast(key, profile)
    local settings = profile and profile.castbars or {}
    return math.floor(castWidths[key] * (settings.widthScale or 1) + 0.5), settings.height or 22
end

-- Historical/custom rectangles remain authoritative unless a supported setting changes.
-- Content-dependent frames retain the source observation, never private content.
function metrics.Measure(key, profile, group, source)
    source = source or {}
    local result = { width=group.width, height=group.height, kind="observed", padding={left=0,right=0,top=0,bottom=0} }
    if barKeys[key] and (group.native or (profile.barLayout and profile.barLayout[key])) then
        local count = group.cells or (key == "pet" and 10 or key == "stance" and math.max(1, math.min(10, math.floor((group.width + 6) / 36))) or 12)
        if key == "stance" and not group.cells then
            local prior = metrics.BarOptions(key, source)
            count = math.max(1, math.min(10, math.floor((group.width + prior.spacing) / (prior.size + prior.spacing) + 0.5)))
        end
        local grid = metrics.Grid(count, metrics.BarOptions(key, profile))
        result.width, result.height, result.grid, result.kind = grid.width, grid.height, grid, key == "stance" and "content" or "configured"
    elseif castWidths[key] and (group.native or profile.castbars) then
        local width, height = metrics.Cast(key, profile)
        local oldWidth, oldHeight = metrics.Cast(key, source)
        result.width = group.native and width or math.max(1, group.width + width - oldWidth)
        result.height = group.native and height or math.max(1, group.height + height - oldHeight)
        result.kind = "configured"
    elseif key == "chat" and profile.chat and profile.chat.size then
        result.width, result.height = profile.chat.size.width + 8, profile.chat.size.height + 78
        result.kind = "configured"
    elseif key == "bags" then
        local columns = profile.bags and profile.bags.columns or 10
        local oldColumns = source.bags and source.bags.columns or 10
        local rows = math.max(1, math.ceil((group.height - 172) / 38))
        result.width = group.width + (columns - oldColumns) * 38
        if columns ~= oldColumns then result.height = math.ceil(rows * oldColumns / columns) * 38 + 172 end
        result.kind, result.note = "content", "Bag height reserves the observed slot rows; inventory capacity can change."
    elseif key == "questtracker" then
        result.height = profile.questtracker and profile.questtracker.collapsed and 24 or group.height
        result.kind, result.note = "content", "Quest and planner content grows within the available screen space."
    elseif key == "xpbar" then
        local compact = (profile.xpbar and profile.xpbar.compact) == true
        local oldCompact = (source.xpbar and source.xpbar.compact) == true
        if compact ~= oldCompact then
            -- Native XP/reputation rows are 18/12 detailed or 8 compact, with a 2-unit gap.
            local heights = compact and {[18]=8,[12]=8,[32]=18} or {[8]=18,[18]=32}
            result.height = heights[group.height] or math.max(8, group.height + (compact and -10 or 10))
        end
        result.kind, result.note = "content", "XP, honor and reputation rows depend on the character."
    elseif key == "cooldowns" or key == "damagemeter" or key == "loot" then
        result.kind, result.note = "content", "Content can change this frame's height; this is the source reservation."
    end
    if key == "main" and profile.gryphons then result.padding = {left=88,right=88,top=math.max(0,84-result.height),bottom=12} end
    return result
end
