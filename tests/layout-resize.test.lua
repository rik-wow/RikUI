-- Resizing a group through the arrangement system: a group that declares resize bounds gets a grip
-- on its overlay; dragging it keeps the top left corner, respects the bounds, the screen and the other
-- groups, and saves size and place. The cursor is faked; the geometry is real. UIParent is 1365x768.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local restore = widgets.install()
    local NAMES = { "GetCursorPosition", "IsShiftKeyDown" }
    local saved = { width = UIParent.GetWidth, height = UIParent.GetHeight, scale = UIParent.GetEffectiveScale }
    for _, name in ipairs(NAMES) do saved[name] = _G[name] end
    UIParent.GetWidth, UIParent.GetHeight = function() return 1365 end, function() return 768 end
    UIParent.GetEffectiveScale = function() return 1 end
    local cursor = { 0, 0 }
    GetCursorPosition = function() return cursor[1], cursor[2] end
    IsShiftKeyDown = function() return false end

    local layout, window, neighbour, sizes, notes
    local function at(x, y) return { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = x, y = y } end
    local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.01 end
    local function box(width, height)
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:SetSize(width, height)
        return frame
    end
    local function load(combat)
        cursor, sizes, notes = { 0, 0 }, {}, {}
        widgets.loadAddon(env, { "src/ui/skin.lua", "src/layout/layout-unlock.lua", "src/layout/layout-drag.lua", "src/layout/layout-resize.lua" }, nil, combat)
        layout = RikUI.Layout
        window, neighbour = box(300, 200), box(100, 100)
        layout.Register(window, "window", at(100, 600), { label = "Window", onUnlock = function(open) notes[#notes + 1] = open end,
            resize = { minWidth = 200, minHeight = 100, maxWidth = 600, maxHeight = 400,
                apply = function(width, height) sizes[#sizes + 1] = { width, height }; window:SetSize(width, height) end } })
        layout.Register(neighbour, "neighbour", at(500, 600))
        env.fire("PLAYER_ENTERING_WORLD")
        env.printed = {}
    end
    local function tick() env.runScript(layout.ResizeDriver, "OnUpdate", 0.016) end

    local ok, reason = pcall(function()
        load()
        check("a single group can be unlocked from code and hears about it", layout.SetUnlocked("window", true) == true
            and layout.IsUnlocked("window") and not layout.IsUnlocked("neighbour") and notes[1] == true)
        layout.SetUnlocked("neighbour", true)
        local overlay, plain = layout.Overlays.window, layout.Overlays.neighbour
        check("a group with resize bounds gets a grip on its overlay's bottom right corner; others do not",
            overlay.grip ~= nil and overlay.grip:IsShown() and overlay.grip.points[1][1] == "BOTTOMRIGHT" and plain.grip == nil)

        cursor = { 400, 400 }
        env.runScript(overlay.grip, "OnMouseDown", "LeftButton")
        check("pressing the grip starts a resize, not a drag", layout.IsResizing() and not layout.IsDragging())
        cursor = { 450, 360 }
        tick()
        local rect = layout.Rect("window")
        check("the window grows right and down with the cursor and its top left corner stays", near(rect.left, 100)
            and near(rect.top, 600) and near(rect.right, 450) and near(rect.bottom, 360) and window.width == 350
            and window.height == 240 and overlay.width == 350)
        cursor = { 700, 400 }
        tick()
        rect = layout.Rect("window")
        check("it cannot grow into a neighbour: the width stops at the last free size and the edge turns red",
            rect.right <= 500 and not RikUI.Geometry.Overlaps(rect, layout.Rect("neighbour")) and overlay.blocked == true)
        cursor = { 400, -200 }
        tick()
        check("the height stops at its maximum", near(layout.Rect("window").top - layout.Rect("window").bottom, 400))
        cursor = { 0, 900 }
        tick()
        rect = layout.Rect("window")
        check("and width and height stop at their minimum", near(rect.right - rect.left, 200) and near(rect.top - rect.bottom, 100)
            and overlay.blocked == false)
        cursor = { 420, 380 }
        tick()
        env.runScript(overlay.grip, "OnMouseUp", "LeftButton")
        local position = RikUI.Profile.positions.window
        check("releasing saves the place on the group's own anchor and ends the resize", not layout.IsResizing()
            and position.point == "TOPLEFT" and near(position.x, 100) and near(position.y, 600)
            and near(sizes[#sizes][1], 320) and near(sizes[#sizes][2], 220))
        cursor = { 900, 100 }
        tick()
        check("the cursor no longer resizes once released", window.width == 320)

        env.runScript(overlay.grip, "OnMouseDown", "LeftButton")
        cursor = { 930, 80 }
        tick()
        env.inCombat = true
        env.fire("PLAYER_REGEN_DISABLED")
        check("combat ends a resize in flight at its last free size and locks", not layout.IsResizing()
            and not layout.IsMoving() and notes[#notes] == false)
        env.inCombat = false
        check("a group cannot be unlocked from code in combat", (function()
            env.inCombat = true
            local result = layout.SetUnlocked("window", true)
            env.inCombat = false
            return result == false and not layout.IsUnlocked("window")
        end)())
        check("an unknown group is refused", layout.SetUnlocked("nonsense", true) == false)
    end)
    UIParent.GetWidth, UIParent.GetHeight, UIParent.GetEffectiveScale = saved.width, saved.height, saved.scale
    for _, name in ipairs(NAMES) do _G[name] = saved[name] end
    restore()
    env.inCombat = false
    check("layout resize suite completes", ok, reason)
end
