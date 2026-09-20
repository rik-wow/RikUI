-- Applying a whole-screen layout from data/layouts.lua: every position is written to the profile, the
-- frames move at once, and one step of undo keeps what was there before. The chat window's width is
-- fitted to the screen (the room between the left margin and the bar stack) unless the player sized it.
local core, layout, layouts, setup = RikUI, RikUI.Layout, RikUI.Layouts, RikUI.Setup

local BAR_HALF_WIDTH, CHAT_MAX_WIDTH = 249, 430
local NOTHING_TO_UNDO = "Nothing to undo."
local copy = setup.CopyState

local function names() return table.concat(layouts.Order, ", ") end

-- The widest message area whose whole rectangle still leaves GAP to the bar stack, between the
-- audited width and Blizzard's.
function layout.ChatSize(screen)
    local foot = layouts.ChatFootprint
    local room = screen and math.floor(screen.width / 2 - BAR_HALF_WIDTH - layouts.GAP - layouts.MARGIN
        - foot.left - foot.right) or 0
    local width = math.max(layouts.ChatSize.width, math.min(CHAT_MAX_WIDTH, room))
    return { width = width, height = layouts.ChatSize.height }
end

-- A copy of a layout's positions for this screen: the chat holder is the window's centre, so its
-- place follows the width a layout gives the chat here.
function layout.PresetPositions(name)
    local entry = layouts[name]
    if type(entry) ~= "table" or type(entry.positions) ~= "table" then return nil end
    local positions = copy(entry.positions)
    local foot = layouts.ChatFootprint
    positions.chat.x = layouts.MARGIN + (layout.ChatSize(layout.Screen()).width + foot.left + foot.right) / 2
    return positions
end

local function samePlace(a, b)
    return a.point == b.point and a.relativePoint == b.relativePoint and math.abs(a.x - b.x) < 0.5
        and math.abs(a.y - b.y) < 0.5
end

-- The layout the saved positions amount to; nil once a frame was moved by hand. A key without a saved
-- position stands at its default, which is the Centered layout's.
function layout.MatchingPreset()
    if not core.Profile then return nil end
    local defaults = layout.PresetPositions(layouts.Order[1])
    for _, name in ipairs(layouts.Order) do
        local matches = true
        for key, wanted in pairs(layout.PresetPositions(name)) do
            local saved = core.Profile.positions[key]
            if not samePlace(type(saved) == "table" and saved or defaults[key], wanted) then matches = false; break end
        end
        if matches then return name end
    end
    return nil
end

function layout.PresetChoices()
    local choices = {}
    for _, name in ipairs(layouts.Order) do choices[#choices + 1] = { value = name, text = layouts[name].label } end
    return choices
end

local function chatSettings()
    core.Profile.chat = type(core.Profile.chat) == "table" and core.Profile.chat or {}
    return core.Profile.chat
end

-- The chat module adopts its window once a position exists and sizes it from the profile.
local function refreshChat()
    local chat = core.Chat
    if type(chat) ~= "table" or chat.enabled == false then return end
    if type(chat.Restore) == "function" then chat.Restore() end
    if type(chat.ApplySize) == "function" then chat.ApplySize() end
end

local function refresh()
    layout.LockAll()
    refreshChat()
    layout.Apply()
    layout.Settle()
end

function layout.ApplyPreset(name)
    if InCombatLockdown() then return nil, "Cannot change the layout in combat." end
    if not core.Profile then return nil, "Still loading." end
    local positions = layout.PresetPositions(name)
    if not positions then return nil, "Unknown layout " .. tostring(name) .. ". Layouts: " .. names() .. "." end
    local chat = chatSettings()
    core.Profile.layoutUndo = { positions = copy(core.Profile.positions), chatSize = copy(chat.size) or false }
    for key, position in pairs(positions) do core.Profile.positions[key] = position end
    -- The chat is part of a layout: it gets the layout's size, and undo brings the old one back.
    chat.size = layout.ChatSize(layout.Screen())
    refresh()
    core:Print("Layout: " .. layouts[name].label .. ". /rik layout undo reverts it; hold the lock key to move a frame.")
    return true
end

function layout.UndoPreset()
    if InCombatLockdown() then return nil, "Cannot change the layout in combat." end
    local undo = core.Profile and core.Profile.layoutUndo
    if type(undo) ~= "table" or type(undo.positions) ~= "table" then return nil, NOTHING_TO_UNDO end
    core.Profile.positions = undo.positions
    chatSettings().size = undo.chatSize or nil
    core.Profile.layoutUndo = nil
    refresh()
    core:Print("Layout undone.")
    return true
end

-- The row the options panel shows; a hand-moved arrangement reads as no selection.
function layout.PresetOption()
    return { type = "dropdown", key = "layoutPreset", label = "Layout preset", protected = true,
        values = layout.PresetChoices, get = layout.MatchingPreset,
        set = function(name)
            local ok, reason = layout.ApplyPreset(name)
            if not ok then core:Print(reason) end
            return ok, reason
        end }
end

local function list()
    local current = layout.MatchingPreset()
    for _, name in ipairs(layouts.Order) do
        core:Print(name .. (name == current and " (current)" or "") .. ": " .. layouts[name].description)
    end
end

-- /rik layout list|undo|<name>; the bare command stays the report in layout-unlock.lua.
function layout.PresetCommand(args)
    local action = args:lower()
    if action == "list" then return list() end
    local ok, reason
    if action == "undo" then ok, reason = layout.UndoPreset() else ok, reason = layout.ApplyPreset(action) end
    if not ok then core:Print(reason) end
end
