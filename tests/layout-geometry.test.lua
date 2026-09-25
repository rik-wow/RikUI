-- The geometry layer has no WoW API, so everything here is plain numbers. The property test at the
-- end is the proof of the arrangement system's invariant: whatever the scene and whatever the move,
-- Resolve and Nearest hand back a rectangle that is on screen and overlaps nothing.
return function(check)
    local savedAddon = RikUI
    RikUI = {}
    assert(loadfile("src/layout/layout-geometry.lua"))("RikUI", {})
    local g = RikUI.Geometry
    local SCREEN = { width = 1365, height = 768 }
    local POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
    local function near(a, b) return math.abs(a - b) < 0.001 end
    local function same(a, b)
        return near(a.left, b.left) and near(a.right, b.right) and near(a.bottom, b.bottom) and near(a.top, b.top)
    end
    local function inside(rect)
        return rect.left >= -0.001 and rect.bottom >= -0.001 and rect.right <= SCREEN.width + 0.001
            and rect.top <= SCREEN.height + 0.001
    end

    local ok, reason = pcall(function()
        local rect = g.FromAnchor({ point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -16, y = -260 }, 240, 100, SCREEN)
        check("an anchored position becomes a rectangle in screen units", near(rect.right, 1349) and near(rect.top, 508)
            and near(rect.left, 1109) and near(rect.bottom, 408))
        rect = g.FromAnchor({ point = "BOTTOM", relativePoint = "BOTTOM", x = -140, y = 300 }, 220, 44, SCREEN)
        check("a bottom-centre anchor centres the rectangle on its offset", near(rect.left, 1365 / 2 - 140 - 110)
            and near(rect.bottom, 300) and near(rect.top, 344))

        local roundTrips = true
        for _, point in ipairs(POINTS) do
            for _, relative in ipairs(POINTS) do
                local position = { point = point, relativePoint = relative, x = 37.5, y = -12.25 }
                local made = g.FromAnchor(position, 130, 70, SCREEN)
                local back = g.ToAnchor(made, point, relative, SCREEN)
                if not (near(back.x, 37.5) and near(back.y, -12.25) and back.point == point
                    and back.relativePoint == relative) then roundTrips = false end
            end
        end
        check("FromAnchor and ToAnchor round-trip for all nine points against all nine", roundTrips)
        local grown = g.FromAnchor(g.ToAnchor(g.Rect(1109, 408, 240, 100), "TOPRIGHT", "TOPRIGHT", SCREEN), 240, 300, SCREEN)
        check("a rectangle saved on its top-right anchor grows downward when its height changes",
            near(grown.top, 508) and near(grown.right, 1349) and near(grown.bottom, 208))

        local a, b = g.Rect(100, 100, 50, 50), g.Rect(150, 100, 50, 50)
        check("rectangles that only touch do not overlap", not g.Overlaps(a, b))
        check("rectangles that share area overlap", g.Overlaps(a, g.Rect(149, 149, 10, 10)))
        check("AnyOverlap names the obstacle", g.AnyOverlap(g.Rect(140, 110, 20, 20), { b }) == b
            and g.AnyOverlap(g.Rect(0, 0, 10, 10), { a, b }) == nil)
        check("Clamp pulls a rectangle back onto the screen and keeps its size",
            same(g.Clamp(g.Rect(-30, 760, 100, 40), SCREEN), g.Rect(0, 728, 100, 40)))

        local wall = g.Rect(300, 0, 100, 768)
        local start = g.Rect(100, 300, 80, 80)
        local stopped = g.Resolve(start, g.Rect(340, 300, 80, 80), { wall }, SCREEN)
        check("a move into an obstacle stops flush against it", near(stopped.right, 300) and near(stopped.bottom, 300))
        local tunnel = g.Resolve(start, g.Rect(600, 300, 80, 80), { wall }, SCREEN)
        check("a large move cannot tunnel through an obstacle", near(tunnel.right, 300))
        local block = g.Rect(300, 300, 100, 100)
        local slid = g.Resolve(start, g.Rect(340, 500, 80, 80), { block }, SCREEN)
        check("a diagonal move slides along the obstacle instead of stopping dead", near(slid.bottom, 500)
            and not g.Overlaps(slid, block))
        local free = g.Resolve(start, g.Rect(500, 600, 80, 80), {}, SCREEN)
        check("a free move lands exactly where asked", same(free, g.Rect(500, 600, 80, 80)))
        check("a move off the screen is clamped", inside(g.Resolve(start, g.Rect(-500, 9000, 80, 80), {}, SCREEN)))

        local spot, found = g.Nearest(g.Rect(310, 310, 60, 60), { block }, SCREEN)
        check("Nearest moves an overlapping rectangle to the closest free place", found
            and not g.Overlaps(spot, block) and inside(spot)
            and math.abs(spot.left - 310) + math.abs(spot.bottom - 310) <= 70)
        local untouched = g.Nearest(g.Rect(10, 10, 60, 60), { block }, SCREEN)
        check("Nearest leaves a free rectangle where it is", same(untouched, g.Rect(10, 10, 60, 60)))
        local _, fits = g.Nearest(g.Rect(0, 0, 1365, 768), { block }, SCREEN)
        check("Nearest says so when nothing fits", fits == false)

        -- The only opening is fractional and requires moving along both axes.
        local opening = { g.Rect(0, 0, 40.25, 100), g.Rect(50.25, 0, 49.75, 100),
            g.Rect(40.25, 0, 10, 30.5), g.Rect(40.25, 40.5, 10, 59.5) }
        local exact, exactFits = g.Nearest(g.Rect(0, 0, 10, 10), opening, { width=100, height=100 })
        check("Nearest finds fractional gaps smaller than a coarse search step",
            exactFits and near(exact.left, 40.25) and near(exact.bottom, 30.5))

        local dx, dy, guides = g.Snap(g.Rect(405, 297, 80, 80), { block }, SCREEN, 8, 4)
        check("a rectangle near an obstacle snaps to the gap beside it and to its bottom edge",
            near(dx, -1) and near(dy, 3) and #guides == 2)
        dx, dy = g.Snap(g.Rect(640, 5, 80, 80), {}, SCREEN, 8, 4)
        check("a rectangle snaps to the screen's centre line and bottom edge",
            near(640 + dx + 40, 1365 / 2) and near(5 + dy, 0))
        dx, dy, guides = g.Snap(g.Rect(800, 500, 80, 80), { block }, SCREEN, 8, 4)
        check("nothing within the threshold means no snap and no guide", dx == 0 and dy == 0 and #guides == 0)

        local tracker = g.Rect(1109, 408, 240, 100)
        local below = g.Rect(1100, 200, 200, 60)
        check("FreeExtent measures the room down to the next frame below", near(g.FreeExtent(tracker, "DOWN", { below }, SCREEN), 148))
        check("an obstacle beside the growth path does not count",
            near(g.FreeExtent(tracker, "DOWN", { g.Rect(100, 200, 200, 60) }, SCREEN), 408))
        check("growth upward, left and right end at the screen edge", near(g.FreeExtent(tracker, "UP", {}, SCREEN), 260)
            and near(g.FreeExtent(tracker, "LEFT", {}, SCREEN), 1109) and near(g.FreeExtent(tracker, "RIGHT", {}, SCREEN), 16))

        -- Property test. A small linear congruential generator keeps the scenes identical on every run.
        local seed = 20260920
        local function random(low, high)
            seed = (seed * 1103515245 + 12345) % 2147483648
            return low + (seed / 2147483648) * (high - low)
        end
        local failures, scenes, moves = 0, 2000, 0
        for _ = 1, scenes do
            local obstacles = {}
            for _ = 1, math.floor(random(1, 30)) do
                local placed, fitsHere = g.Nearest(g.Rect(random(0, 1300), random(0, 700), random(20, 260), random(20, 200)),
                    obstacles, SCREEN)
                if fitsHere then
                    if g.AnyOverlap(placed, obstacles) or not inside(placed) then failures = failures + 1 end
                    obstacles[#obstacles + 1] = placed
                end
            end
            local mover, moverFits = g.Nearest(g.Rect(random(0, 1300), random(0, 700), random(20, 200), random(20, 120)),
                obstacles, SCREEN)
            if moverFits then
                for _ = 1, 5 do
                    local wanted = g.Rect(random(-200, 1500), random(-200, 900), mover.right - mover.left, mover.top - mover.bottom)
                    mover = g.Resolve(mover, wanted, obstacles, SCREEN)
                    moves = moves + 1
                    if g.AnyOverlap(mover, obstacles) or not inside(mover) then failures = failures + 1 end
                end
            end
        end
        check("over 2,000 seeded scenes no Nearest or Resolve result overlaps or leaves the screen",
            failures == 0 and moves > 5000, "failures=" .. failures .. " moves=" .. moves)
    end)
    RikUI = savedAddon
    check("layout geometry suite completes", ok, reason)
end
