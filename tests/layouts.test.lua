local loadfile = dofile("tests/load_addon.lua").Loadfile
-- The four whole-screen layouts are data; this suite is what keeps them clean: every key placed, no
-- overlap, neighbours at least GAP apart and everything at least MARGIN from the screen edge, on
-- three aspect ratios. UIParent is always 768 high at the default UI scale, so only the width moves.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local restore = widgets.install()
    local savedWidth, savedHeight, savedClass = UIParent.GetWidth, UIParent.GetHeight, UnitClass
    local SCREENS = { { name = "16:9", width = 1365, height = 768 }, { name = "16:10", width = 1228, height = 768 },
        { name = "21:9", width = 1820, height = 768 },
        { name = "4K at 85%", width = 3840 / 0.85, height = 2160 / 0.85 },
        { name = "4K with a 1440-unit UI", width = 2560, height = 1440 } }
    local NARROW = { name = "4:3", width = 1024, height = 768 }
    -- Frames whose registered size is one row of something that grows; the nominal size is the room kept.
    local GROWS = { loot = true, bags = true, chat = true, micromenu = true }
    local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.01 end

    local function loadData()
        env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
        RikUI, RikUIDB, RikUICharDB = nil, nil, nil
        for _, file in ipairs({ "src/core/core.lua", "src/layout/layout-geometry.lua", "data/layouts.lua", "src/layout/layout-audit.lua" }) do
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

        -- The combat column's unit row depends on the class: only the supporting rows a class shows keep room.
        for _, class in ipairs({ "PALADIN", "WARRIOR", "ROGUE", "SHAMAN", "DRUID" }) do
            for _, name in ipairs({ "centered", "hud" }) do
                for _, screen in ipairs(SCREENS) do
                    local issues = layouts.Audit(name, screen, class)
                    check(name .. " is clean for a " .. class:lower() .. " on " .. screen.name, #issues == 0, table.concat(issues, "; "))
                end
            end
        end
        local paladin = layouts.Positions("hud", SCREENS[1], "PALADIN")
        local paladinTarget = layouts.Rect("hud", "target", SCREENS[1], paladin)
        local paladinCast = layouts.Rect("hud", "casttarget", SCREENS[1], paladin)
        local strip = layouts.Rect("hud", "cooldowns", SCREENS[1], paladin)
        check("a class without supporting rows keeps only the target cast bar between the strip and its unit frames",
            near(paladinCast.bottom, strip.top + layouts.GAP) and near(paladinTarget.bottom, paladinCast.top + layouts.GAP))
        -- No class shows all three rows: an unknown class keeps the tallest stack a class has.
        check("a druid keeps combo points and form mana under its unit frames, an unknown class keeps the tallest class's rows",
            near(layouts.CombatUnitRow("DRUID"), layouts.CombatUnitRow("ROGUE") + layouts.Sizes.druidmana.height + layouts.GAP)
            and layouts.CombatUnitRow("DRUID") > layouts.CombatUnitRow("PALADIN")
            and near(layouts.CombatUnitRow(nil), layouts.CombatUnitRow("DRUID"))
            and layouts.CombatUnitRow(nil) >= layouts.CombatUnitRow("SHAMAN")
            and near(layouts.Positions("hud", nil).player.y, layouts.CombatUnitRow(nil)))
        local shaman, druid = layouts.Positions("hud", nil, "SHAMAN"), layouts.Positions("hud", nil, "DRUID")
        check("a class's supporting rows close down onto the strip", near(shaman.totems.y, layouts.CombatPositions.combopoints.y)
            and near(druid.druidmana.y, druid.combopoints.y + layouts.Sizes.combopoints.height + layouts.GAP))
        local rogue = layouts.Positions("centered", SCREENS[3], "ROGUE")
        local rogueTarget, pips = layouts.Rect("centered", "target", SCREENS[3], rogue), layouts.Rect("centered", "combopoints", SCREENS[3], rogue)
        check("a rogue's unit row clears the combo points and the target cast bar", rogueTarget.bottom >= pips.top + layouts.GAP
            and near(rogueTarget.bottom, layouts.Rect("centered", "casttarget", SCREENS[3], rogue).top + layouts.GAP))
        check("classic and healer layouts ignore the class", near(layouts.Positions("classic", SCREENS[1], "PALADIN").player.y,
            layouts.Positions("classic", SCREENS[1]).player.y))

        local broken = { label = "Broken", description = "two frames on one spot, one off screen",
            positions = { player = { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = 100, y = 100 },
                target = { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = 110, y = 100 },
                focus = { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = 332, y = 100 },
                tot = { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = 4, y = 400 } } }
        layouts.broken = broken
        local fit = layouts.Positions
        layouts.Positions = function(name) return layouts[name].positions end
        local text = table.concat(layouts.Audit("broken", SCREENS[1]), "; ")
        layouts.Positions = fit
        check("the audit reports an overlap, a gap under four, a margin under sixteen and a missing key",
            text:find("player overlaps target", 1, true) and text:find("target is 2 from focus", 1, true)
            and text:find("tot is 4 from the left edge", 1, true) and text:find("main: not placed", 1, true), text)
        layouts.broken = nil

        local player, bar = layouts.Rect("centered", "player", SCREENS[1]), layouts.Rect("centered", "main", SCREENS[1])
        local target = layouts.Rect("centered", "target", SCREENS[1])
        local swing = layouts.Rect("centered", "swingtimer", SCREENS[1])
        check("Centered weapon timers join the central stack below target auras",
            near((swing.left+swing.right)/2, SCREENS[1].width/2) and swing.top < target.bottom
            and swing.top-swing.bottom==76)
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

        -- The packer fits a recipe to the screen, and a clean audit only says nothing overlaps afterwards.
        -- On a 768-high screen the combat cluster must stay where the recipe put it: group frames and
        -- the side columns are the ones that yield.
        local CLUSTER = { "player", "target", "tot", "focus", "petframe", "castplayer", "casttarget", "castfocus",
            "castpet", "swingtimer", "combatresource", "cooldowns", "classbuffs", "classeffects", "combopoints",
            "totems", "druidmana" }
        local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
        local function hidden(key, class)
            for _, row in ipairs(layouts.SupportingRows) do
                if row.key == key then return not row.classes[class] end
            end
            return false
        end
        for _, name in ipairs({ "centered", "hud" }) do
            for index = 1, 3 do
                local screen = SCREENS[index]
                for _, class in ipairs(CLASSES) do
                    local recipe, fitted = layouts.Recipe(name, screen, class), layouts.Positions(name, screen, class)
                    local moved = {}
                    for _, key in ipairs(CLUSTER) do
                        if not hidden(key, class) and (not near(recipe[key].x, fitted[key].x)
                            or not near(recipe[key].y, fitted[key].y)) then
                            moved[#moved + 1] = string.format("%s %+d,%+d", key, fitted[key].x - recipe[key].x,
                                fitted[key].y - recipe[key].y)
                        end
                    end
                    check(name .. " keeps a " .. class:lower() .. "'s combat cluster in place on " .. screen.name,
                        #moved == 0, table.concat(moved, "; "))
                    local player = layouts.Rect(name, "player", screen, fitted)
                    local target = layouts.Rect(name, "target", screen, fitted)
                    check(name .. " mirrors a " .. class:lower() .. "'s player and target on " .. screen.name,
                        near(screen.width - target.right, player.left) and near(player.bottom, target.bottom))
                end
            end
        end

        -- A clean packed audit must not conceal a displaced preset combat row.
        for _, name in ipairs({ "classic", "healer" }) do
            for _, screen in ipairs(SCREENS) do
                for _, class in ipairs(CLASSES) do
                    local recipe, fitted = layouts.Recipe(name, screen, class), layouts.Positions(name, screen, class)
                    local moved = {}
                    local keys = {}
                    for _, key in ipairs(CLUSTER) do keys[#keys + 1] = key end
                    if name == "healer" then keys[#keys + 1], keys[#keys + 2] = "raid", "party" end
                    for _, key in ipairs(keys) do
                        if not hidden(key, class) and (not near(recipe[key].x, fitted[key].x)
                            or not near(recipe[key].y, fitted[key].y)) then
                            moved[#moved + 1] = string.format("%s %+d,%+d", key, fitted[key].x - recipe[key].x,
                                fitted[key].y - recipe[key].y)
                        end
                    end
                    check(name .. " keeps a " .. class:lower() .. "'s preset combat places on " .. screen.name,
                        #moved == 0, table.concat(moved, "; "))
                end
            end
        end

        for _, name in ipairs(layouts.Order) do
            for _, screen in ipairs({ SCREENS[4], SCREENS[5] }) do
                local positions = layouts.Positions(name, screen)
                local pet = layouts.Rect(name, "pet", screen, positions)
                local previous = pet
                for _, key in ipairs({ "swingtimer", "castplayer", "combatresource", "cooldowns" }) do
                    local rect = layouts.Rect(name, key, screen, positions)
                    check(name .. " centres " .. key .. " above bars on " .. screen.name,
                        near((rect.left + rect.right) / 2, screen.width / 2)
                        and near(rect.bottom, previous.top + layouts.GAP)
                        and rect.top < screen.height / 2 - 100)
                    previous = rect
                end
                for _, key in ipairs({ "classbuffs", "classeffects" }) do
                    local rect = layouts.Rect(name, key, screen, positions)
                    check(name .. " keeps " .. key .. " beside combat column on " .. screen.name,
                        rect.bottom >= pet.top and rect.top < screen.height / 2 - 100
                        and (key == "classbuffs" and near(rect.right, screen.width / 2 - 144)
                            or key == "classeffects" and near(rect.left, screen.width / 2 + 144)))
                end
            end
        end

        -- Check the fitted recipe too: the packer must not move the combat cluster back to centre.
        for _, screen in ipairs({ SCREENS[4], SCREENS[5] }) do
            local positions = layouts.Positions("hud", screen)
            local stackTop = layouts.Rect("hud", "pet", screen, positions).top
            for _, key in ipairs({ "player", "target", "focus", "petframe", "tot", "castplayer",
                "casttarget", "castfocus", "castpet", "swingtimer", "combopoints", "totems",
                "druidmana", "classbuffs", "classeffects", "cooldowns" }) do
                local rect = layouts.Rect("hud", key, screen, positions)
                check("HUD " .. key .. " leaves character clear on " .. screen.name,
                    rect.bottom >= stackTop and rect.top < screen.height / 2 - 100)
            end
        end

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

        -- The client registers the totem row and the form mana row for every class, and a hidden group
        -- still has a rectangle. Rows no class shows together share room in the recipe, so the screen's
        -- own settling must not move them apart: a fresh profile is the Centered layout.
        everything, layout = loadEverything(2048)
        UIParent.GetHeight = function() return 1152 end
        for _, key in ipairs({ "combopoints", "totems", "druidmana" }) do
            if not layout.Groups[key] then
                local frame = CreateFrame("Frame", nil, UIParent)
                frame:SetSize(everything.Sizes[key].width, everything.Sizes[key].height)
                layout.Register(frame, key, everything.centered.positions[key])
            end
        end
        env.fire("PLAYER_ENTERING_WORLD")
        local settledRows = {}
        for _, key in ipairs({ "combopoints", "totems", "druidmana" }) do
            if RikUI.Profile.positions[key] then settledRows[#settledRows + 1] = key end
        end
        check("settling leaves rows that share room where the recipe put them", #settledRows == 0
            and layout.MatchingPreset() == "centered", table.concat(settledRows, ", "))
        local totemRect, comboRect = layout.Rect("totems"), layout.Rect("combopoints")
        local seen = false
        for _, other in ipairs(layout.Obstacles("totems")) do
            if other.key == "combopoints" or other.key == "druidmana" then seen = true end
        end
        check("rows no class shows together are not each other's obstacles", not seen
            and RikUI.Geometry.Overlaps(totemRect, comboRect))
        local stubClass = UnitClass
        UnitClass = function() return "Druid", "DRUID", 11 end
        seen = false
        for _, other in ipairs(layout.Obstacles("druidmana")) do
            if other.key == "combopoints" then seen = true end
            if other.key == "totems" then seen = false; break end
        end
        check("rows a class shows together block each other, a row it never shows does not", seen)
        UnitClass = stubClass
        seen = false
        for _, other in ipairs(layout.Obstacles("player")) do
            if other.key == "combopoints" or other.key == "totems" or other.key == "druidmana" then seen = true end
        end
        check("a warrior's frames have no supporting row in their way", not seen)

        -- The checks below grow the cooldown strip into the row above it, which only a class with
        -- combo points has.
        UnitClass = function() return "Rogue", "ROGUE", 4 end

        -- Populate the optional native widgets too: minimal stubs used to omit these,
        -- and a five-bag-only micro menu concealed the real client's much wider controls.
        everything, layout = loadEverything(3840 / 0.85)
        UIParent.GetHeight = function() return 2160 / 0.85 end
        for key, size in pairs(everything.Sizes) do
            if not layout.Groups[key] then
                local frame = CreateFrame("Frame", nil, UIParent)
                frame:SetSize(size.width, size.height)
                layout.Register(frame, key, everything.centered.positions[key],
                    { floating=everything.Floating[key], exclusive=everything.Exclusive[key] })
            end
        end
        layout.Groups.damagemeter.frames[1]:SetSize(400, 132)
        layout.Groups.micromenu.frames[1]:SetSize(238, 70)
        for _, scale in ipairs({ 0.65, 0.85, 1, 1.2 }) do
            RikUI.Profile.scale = scale
            for _, name in ipairs(everything.Order) do
                layout.ApplyPreset(name)
                local issues = {}
                for key in pairs(layout.Groups) do
                    local own = layout.Rect(key)
                    for _, other in ipairs(layout.Obstacles(key)) do
                        if key < other.key and RikUI.Geometry.Overlaps(own, other) then
                            issues[#issues+1] = key .. " x " .. other.key
                        end
                    end
                    if own.left < 0 or own.bottom < 0 or own.right > 3840/0.85 or own.top > 2160/0.85 then
                        issues[#issues+1] = key .. " off screen"
                    end
                end
                check(name .. " has no runtime collisions at 4K, layout scale " .. scale,
                    #issues == 0, table.concat(issues, "; "))
                for _, key in ipairs({ "cooldowns", "classbuffs", "classeffects" }) do
                    local rect, main = layout.Rect(key), layout.Rect("main")
                    check(name .. " keeps " .. key .. " near bars at scale " .. scale,
                        rect.bottom >= layout.Rect("pet").top and rect.top < UIParent:GetHeight() / 2 - 100
                        and rect.right >= main.left - 120 * scale and rect.left <= main.right + 120 * scale
                        and (key ~= "cooldowns" or near((rect.left + rect.right) / 2, UIParent:GetWidth() / 2)))
                end
                if name == "hud" then
                    local stackTop = layout.Rect("pet").top
                    for _, key in ipairs({ "player", "target", "focus", "petframe", "tot", "castplayer",
                        "casttarget", "castfocus", "castpet", "swingtimer", "combopoints", "totems",
                        "druidmana", "classbuffs", "classeffects", "cooldowns" }) do
                        local rect = layout.Rect(key)
                        check("HUD " .. key .. " stays above bars and below character at scale " .. scale,
                            rect.bottom >= stackTop and rect.top < UIParent:GetHeight() / 2 - 100)
                    end
                end
                local strip = layout.Groups.cooldowns.frames[1]
                local beforeGrowth = layout.Rect("cooldowns")
                strip:SetSize(280, 116)
                local grown, above = layout.Rect("cooldowns"), layout.Rect("combopoints")
                check(name .. " keeps a growing cooldown strip central at scale " .. scale,
                    near((grown.left + grown.right) / 2, UIParent:GetWidth() / 2)
                    and near(grown.bottom, beforeGrowth.bottom)
                    and not RikUI.Geometry.Overlaps(grown, above))
                strip:SetSize(280, 76)
                layout.ApplyPreset(name)
                local foot = everything.ChatFootprint
                local inputBottom = layout.Rect("chat").bottom
                    + (foot.bottom - 4 - 2 - 18 - 2 - 24) * scale
                check(name .. " reserves input below the message area at scale " .. scale, inputBottom >= 0)
            end
        end
        UnitClass = stubClass

        for _, name in ipairs(everything.Order) do
            everything, layout = loadEverything(NARROW.width)
            -- Player aura proxies are obstacles even when minimal stubs lack containers.
            for _, key in ipairs({ "buffs", "debuffs" }) do
                if not layout.Groups[key] then
                    local frame = CreateFrame("Frame", nil, UIParent)
                    frame:SetSize(everything.Sizes[key].width, everything.Sizes[key].height)
                    layout.Register(frame, key, everything.centered.positions[key])
                end
            end
            -- Use the real preset path, including compact recipes and fitting to this screen.
            assert(layout.ApplyPreset(name))
            env.fire("PLAYER_ENTERING_WORLD")
            local overlaps = {}
            for key in pairs(layout.Groups) do
                local own = layout.Rect(key)
                for _, other in ipairs(own and layout.Obstacles(key) or {}) do
                    -- The 604-wide raid grid is left out: a 1024-wide screen has no free place for it beside
                    -- a full chat, and it only exists in a raid. Everything else must settle clear.
                    if key < other.key and key ~= "raid" and other.key ~= "raid" and RikUI.Geometry.Overlaps(own, other) then
                        overlaps[#overlaps + 1] = string.format("%s(%.0f,%.0f %.0fx%.0f)x%s(%.0f,%.0f %.0fx%.0f)",
                            key, own.left, own.bottom, own.right-own.left, own.top-own.bottom,
                            other.key, other.left, other.bottom, other.right-other.left, other.top-other.bottom)
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
    UIParent.GetWidth, UIParent.GetHeight, UnitClass = savedWidth, savedHeight, savedClass
    restore()
    env.inCombat = false
    check("layouts suite completes", ok, reason)
end
