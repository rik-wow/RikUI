-- The registry side of the arrangement system: rectangles from saved positions, anchor-preserving
-- saves, obstacles, growth room and the settle pass. UIParent is given the 16:9 size (1365x768) the
-- real client reports at a 768-unit height. The last part loads the whole addon from the TOC and
-- checks that the defaults which register under the stubs settle without a single move.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local restore = widgets.install()
    local savedWidth, savedHeight = UIParent.GetWidth, UIParent.GetHeight
    UIParent.GetWidth, UIParent.GetHeight = function() return 1365 end, function() return 768 end

    local function box(width, height)
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:SetSize(width, height)
        return frame
    end
    local function load(profile, combat)
        widgets.loadAddon(env, {}, profile, combat)
        return RikUI.Layout
    end
    local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.01 end
    local TOPRIGHT = { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -16, y = -260 }

    local ok, reason = pcall(function()
        local layout = load()
        local tracker = box(240, 100)
        layout.Register(tracker, "tracker", TOPRIGHT, { label = "Quest tracker", grow = "DOWN" })
        local rect = layout.Rect("tracker")
        check("a group's rectangle comes from its saved position and its frame's size, not from the screen",
            near(rect.right, 1349) and near(rect.top, 508) and near(rect.left, 1109) and near(rect.bottom, 408)
            and rect.key == "tracker")
        layout.SaveRect("tracker", RikUI.Geometry.Move(rect, -100, -50), RikUI.Profile)
        local saved = RikUI.Profile.positions.tracker
        check("a moved group is saved on its own anchor point, so a growing frame keeps its direction",
            saved.point == "TOPRIGHT" and saved.relativePoint == "TOPRIGHT" and near(saved.x, -116) and near(saved.y, -310))
        tracker:SetSize(240, 300)
        rect = layout.Rect("tracker")
        check("after the move it still grows downward from the same top edge", near(rect.top, 458) and near(rect.bottom, 158))

        local below = box(200, 60)
        layout.Register(below, "below", { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -116, y = -700 })
        check("Available is the room along the growth direction up to the next group",
            near(layout.Available("tracker"), 158 - 68) and layout.Available("below") == nil)
        local anchor = box(250, 150)
        layout.Register(anchor, "anchor", { point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -116, y = -500 },
            { floating = true })
        check("a floating group neither blocks growth nor appears among the obstacles",
            near(layout.Available("tracker"), 158 - 68) and #layout.Obstacles("tracker") == 1)
        local party, raid = box(150, 186), box(604, 166)
        layout.Register(party, "party", { point = "LEFT", relativePoint = "LEFT", x = 20, y = 0 }, { exclusive = "group" })
        layout.Register(raid, "raid", { point = "LEFT", relativePoint = "LEFT", x = 20, y = 0 }, { exclusive = "group" })
        local seesRaid = false
        for _, obstacle in ipairs(layout.Obstacles("party")) do
            if obstacle.key == "raid" then seesRaid = true end
        end
        check("groups that are never shown together do not block each other", not seesRaid)

        layout = load()
        local first, second = box(200, 100), box(200, 100)
        local spot = { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = 300, y = 300 }
        layout.Register(first, "main", spot, { label = "Main bar" })
        layout.Register(second, "bags", spot, { label = "Bags" })
        local limits = {}
        local grower = box(100, 50)
        layout.Register(grower, "grower", { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 300, y = 700 },
            { grow = "DOWN", onLimit = function(limit) limits[#limits + 1] = limit end })
        check("nothing is settled before the world is entered: frames are still registering",
            RikUI.Profile.positions.bags == nil)
        env.printed = {}
        env.fire("PLAYER_ENTERING_WORLD")
        local a, b = layout.Rect("main"), layout.Rect("bags")
        check("entering the world settles overlapping groups: the later one in the order moves, the earlier stays",
            not RikUI.Geometry.Overlaps(a, b) and RikUI.Profile.positions.main == nil
            and RikUI.Profile.positions.bags ~= nil)
        check("the move is announced once by label", #env.printed == 1 and env.printed[1]:find("Bags", 1, true) ~= nil
            and env.printed[1]:find("Main bar", 1, true) == nil)
        check("a growing group is told its room after the pass", #limits >= 1 and near(limits[#limits], 700 - 50 - 400))

        env.printed = {}
        local mainBefore = layout.Rect("main")
        second:SetSize(200, 400)
        env.runScript(second, "OnSizeChanged")
        local mainAfter, bagsAfter = layout.Rect("main"), layout.Rect("bags")
        check("a group that resizes into a neighbour moves itself; the neighbour never moves",
            not RikUI.Geometry.Overlaps(mainAfter, bagsAfter) and near(mainAfter.left, mainBefore.left)
            and near(mainAfter.bottom, mainBefore.bottom))
        local late = box(200, 100)
        layout.Register(late, "late", spot, { label = "Late frame" })
        check("a group that registers after the world was entered is settled on arrival",
            not RikUI.Geometry.AnyOverlap(layout.Rect("late"), layout.Obstacles("late")))

        layout = load({ scale = 2 })
        local scaled = box(100, 50)
        layout.Register(scaled, "scaled", { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = 10, y = 20 })
        rect = layout.Rect("scaled")
        check("the layout scale multiplies size and offsets", near(rect.left, 20) and near(rect.bottom, 40)
            and near(rect.right, 220) and near(rect.top, 140))
        layout.SaveRect("scaled", RikUI.Geometry.Move(rect, 100, 0), RikUI.Profile)
        check("and is divided out again when a rectangle is saved", near(RikUI.Profile.positions.scaled.x, 60))

        layout = load(nil, true)
        local one, two = box(200, 100), box(200, 100)
        layout.Register(one, "main", spot)
        layout.Register(two, "bags", spot)
        env.fire("PLAYER_ENTERING_WORLD")
        check("in combat the settle pass waits", RikUI.Profile.positions.bags == nil)
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")
        check("and runs when combat ends", RikUI.Profile.positions.bags ~= nil)

        -- Defaults audit: the whole addon, as the TOC loads it.
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        RikUI, RikUIDB, RikUICharDB = nil, nil, nil
        for line in io.lines("RikUI.toc") do
            line = line:gsub("\r", "")
            if line:match("%.lua$") then assert(loadfile(line))("RikUI", {}) end
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        local pairsFound = {}
        for key in pairs(RikUI.Layout.Groups) do
            local own = RikUI.Layout.Rect(key)
            for _, other in ipairs(own and RikUI.Layout.Obstacles(key) or {}) do
                if key < other.key and RikUI.Geometry.Overlaps(own, other) then
                    pairsFound[#pairsFound + 1] = string.format("%s[%d..%d,%d..%d]x%s[%d..%d,%d..%d]", key, own.left,
                        own.right, own.bottom, own.top, other.key, other.left, other.right, other.bottom, other.top)
                end
            end
        end
        table.sort(pairsFound)
        env.fire("PLAYER_ENTERING_WORLD")
        local groups, moved = 0, {}
        for key in pairs(RikUI.Layout.Groups) do
            groups = groups + 1
            if RikUI.Profile.positions[key] ~= nil then moved[#moved + 1] = key end
        end
        table.sort(moved)
        check("every default that registers under the stubs settles without a move on a 16:9 screen",
            groups >= 20 and #moved == 0, "moved: " .. table.concat(moved, ", ") .. "; overlapping: "
            .. table.concat(pairsFound, " "))
    end)
    UIParent.GetWidth, UIParent.GetHeight = savedWidth, savedHeight
    restore()
    env.inCombat = false
    check("layout rects suite completes", ok, reason)
end
