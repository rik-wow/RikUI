-- The four whole-screen layouts are data; this suite is what keeps them clean: every key placed, no
-- overlap, neighbours at least GAP apart and everything at least MARGIN from the screen edge, on
-- three aspect ratios. UIParent is always 768 high at the default UI scale, so only the width moves.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local restore = widgets.install()
    local savedWidth, savedHeight = UIParent.GetWidth, UIParent.GetHeight
    local SCREENS = { { name = "16:9", width = 1365, height = 768 }, { name = "16:10", width = 1228, height = 768 },
        { name = "21:9", width = 1820, height = 768 } }
    local NARROW = { name = "4:3", width = 1024, height = 768 }
    -- Frames whose registered size is one row of something that grows; the nominal size is the room kept.
    local GROWS = { loot = true, bags = true, chat = true }
    local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.01 end

    local function loadData()
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        RikUI, RikUIDB, RikUICharDB = nil, nil, nil
        for _, file in ipairs({ "core.lua", "layout-geometry.lua", "data/layouts.lua", "layout-audit.lua" }) do
            assert(loadfile(file))("RikUI", {})
        end
        return RikUI.Layouts
    end
    local function loadEverything(width)
        UIParent.GetWidth, UIParent.GetHeight = function() return width end, function() return 768 end
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        -- Fresh chat frames: the ones other suites leave behind carry hooks of addon instances long gone.
        require("chat_stub").install(env)
        RikUI, RikUIDB, RikUICharDB = nil, nil, nil
        for line in io.lines("RikUI.toc") do
            line = line:gsub("\r", "")
            if line:match("%.lua$") then assert(loadfile(line))("RikUI", {}) end
        end
        env.fire("ADDON_LOADED", "RikUI")
        env.fire("PLAYER_LOGIN")
        return RikUI.Layouts, RikUI.Layout
    end

    local ok, reason = pcall(function()
        local layouts = loadData()
        check("four layouts ship, Centered first", #layouts.Order == 4 and layouts.Order[1] == "centered"
            and layouts.Order[2] == "classic" and layouts.Order[3] == "hud" and layouts.Order[4] == "healer")
        for _, name in ipairs(layouts.Order) do
            local entry = layouts[name]
            check(name .. " has a label and a description", type(entry) == "table" and type(entry.label) == "string"
                and type(entry.description) == "string" and #entry.description > 20)
            local missing = {}
            for key in pairs(layouts.Sizes) do
                if type(entry.positions[key]) ~= "table" then missing[#missing + 1] = key end
            end
            table.sort(missing)
            check(name .. " places every key that has a size", #missing == 0, table.concat(missing, ", "))
            for _, screen in ipairs(SCREENS) do
                local issues = layouts.Audit(name, screen)
                check(name .. " is clean on " .. screen.name, #issues == 0, table.concat(issues, "; "))
            end
        end
        check("the audit names an unknown layout", layouts.Audit("nonsense", SCREENS[1])[1] == "nonsense: unknown layout")

        local broken = { label = "Broken", description = "two frames on one spot, one off screen",
            positions = { player = { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = 100, y = 100 },
                target = { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = 110, y = 100 },
                focus = { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = 332, y = 100 },
                tot = { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = 4, y = 400 } } }
        layouts.broken = broken
        local text = table.concat(layouts.Audit("broken", SCREENS[1]), "; ")
        check("the audit reports an overlap, a gap under four, a margin under sixteen and a missing key",
            text:find("player overlaps target", 1, true) and text:find("target is 2 from focus", 1, true)
            and text:find("tot is 4 from the left edge", 1, true) and text:find("main: not placed", 1, true), text)
        layouts.broken = nil

        local player, bar = layouts.Rect("centered", "player", SCREENS[1]), layouts.Rect("centered", "main", SCREENS[1])
        local target = layouts.Rect("centered", "target", SCREENS[1])
        check("Centered: player and target are flush with the ends of the bar stack", near(player.left, bar.left)
            and near(target.right, bar.right) and near(player.bottom, target.bottom))
        local tracker, timers = layouts.Rect("centered", "questtracker", SCREENS[1]), layouts.Rect("centered", "questtimers", SCREENS[1])
        local meter, menu = layouts.Rect("centered", "damagemeter", SCREENS[1]), layouts.Rect("centered", "micromenu", SCREENS[1])
        check("the right column shares one right edge: timers, tracker, damage meter, micro menu",
            near(tracker.right, timers.right) and near(tracker.right, meter.right) and near(tracker.right, menu.right))
        local classic = layouts.Rect("classic", "player", SCREENS[1])
        check("Classic: the player frame sits in the top left corner at the margin", near(classic.left, 16)
            and near(classic.top, 768 - 16))
        local raid, healer = layouts.Rect("healer", "raid", SCREENS[1]), layouts.Rect("healer", "player", SCREENS[1])
        check("Healer: the raid grid is centred over the bars and the player frame starts at its left end",
            near((raid.left + raid.right) / 2, 1365 / 2) and near(healer.left, raid.left) and healer.bottom > raid.top)
        local hudPlayer, hudTarget = layouts.Rect("hud", "player", SCREENS[1]), layouts.Rect("hud", "target", SCREENS[1])
        check("HUD: player and target mirror each other about the screen centre", near(1365 - hudTarget.right, hudPlayer.left)
            and near(hudPlayer.bottom, hudTarget.bottom) and hudPlayer.bottom >= 300)

        -- The whole addon: nominal sizes are the real ones, and the defaults are the Centered layout.
        local everything, layout = loadEverything(1365)
        local wrong, drift, groups = {}, {}, 0
        for key, group in pairs(layout.Groups) do
            groups = groups + 1
            local size, frame = everything.Sizes[key], group.frames[1]
            if not size then wrong[#wrong + 1] = key .. " has no nominal size"
            elseif not GROWS[key] and (not near(size.width, frame:GetWidth()) or not near(size.height, frame:GetHeight())) then
                wrong[#wrong + 1] = string.format("%s is %sx%s, nominal %dx%d", key, tostring(frame:GetWidth()),
                    tostring(frame:GetHeight()), size.width, size.height)
            end
            local wanted, default = layout.PresetPositions("centered")[key], group.defaults
            if wanted and (wanted.point ~= default.point or wanted.relativePoint ~= default.relativePoint
                or not near(wanted.x, default.x) or not near(wanted.y, default.y)) then
                drift[#drift + 1] = string.format("%s default %s/%s %s,%s", key, default.point, default.relativePoint,
                    tostring(default.x), tostring(default.y))
            end
        end
        table.sort(wrong)
        table.sort(drift)
        check("every registered group has a nominal size equal to its real size", groups >= 20 and #wrong == 0,
            table.concat(wrong, "; "))
        check("every module default is the Centered layout's position", #drift == 0, table.concat(drift, "; "))

        for _, name in ipairs(everything.Order) do
            everything, layout = loadEverything(NARROW.width)
            for key, position in pairs(everything[name].positions) do
                if layout.Groups[key] then RikUI.Profile.positions[key] = RikUI.Setup.CopyState(position) end
            end
            env.fire("PLAYER_ENTERING_WORLD")
            local overlaps = {}
            for key in pairs(layout.Groups) do
                local own = layout.Rect(key)
                for _, other in ipairs(own and layout.Obstacles(key) or {}) do
                    -- The 604-wide raid grid is left out: a 1024-wide screen has no free place for it beside
                    -- a full chat, and it only exists in a raid. Everything else must settle clear.
                    if key < other.key and key ~= "raid" and other.key ~= "raid" and RikUI.Geometry.Overlaps(own, other) then
                        overlaps[#overlaps + 1] = key .. "x" .. other.key
                    end
                end
                if own and (own.left < 0 or own.bottom < 0 or own.right > NARROW.width or own.top > 768) then
                    overlaps[#overlaps + 1] = key .. " off screen"
                end
            end
            table.sort(overlaps)
            check(name .. " settles on 4:3 without an overlap and with everything on screen", #overlaps == 0,
                table.concat(overlaps, " "))
        end
    end)
    UIParent.GetWidth, UIParent.GetHeight = savedWidth, savedHeight
    restore()
    env.inCombat = false
    check("layouts suite completes", ok, reason)
end
