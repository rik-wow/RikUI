-- Applying a whole-screen layout: every position written, frames re-anchored, the chat sized for the
-- screen unless the player sized it, one step of undo, and the same layout through setup Apply.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local restore = widgets.install()
    local savedWidth, savedHeight = UIParent.GetWidth, UIParent.GetHeight
    local FILES = { "data/spells.lua", "data/cvars.lua", "presets/warrior.lua", "src/character/macros.lua", "src/character/macros-undo.lua", "src/character/bindings.lua",
        "src/setup/setup-actions.lua", "src/setup/setup-snapshot.lua", "src/setup/setup-undo.lua", "data/layouts.lua", "src/layout/layout-audit.lua", "src/ui/skin.lua", "src/layout/layout-unlock.lua", "src/layout/layout-drag.lua", "src/layout/layout-presets.lua" }
    local layout, player
    local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.01 end
    local function load(profile, width)
        UIParent.GetWidth, UIParent.GetHeight = function() return width or 1365 end, function() return 768 end
        widgets.loadAddon(env, FILES, profile)
        layout = RikUI.Layout
        player = CreateFrame("Frame", nil, UIParent)
        player:SetSize(220, 44)
        layout.Register(player, "player", nil, { label = "Player frame" })
        env.fire("PLAYER_ENTERING_WORLD")
        env.printed = {}
    end
    local function count(values)
        local total = 0
        for _ in pairs(values) do total = total + 1 end
        return total
    end

    local ok, reason = pcall(function()
        load()
        check("a group's default place is the Centered layout's", layout.Groups.player.defaults.point == "BOTTOM"
            and near(layout.Groups.player.defaults.x, -139) and layout.MatchingPreset() == "centered")
        local choices = layout.PresetChoices()
        check("the four layouts are offered in order with their labels", #choices == 4 and choices[1].value == "centered"
            and choices[2].text == "Classic" and choices[4].value == "healer")

        layout.UnlockAll()
        local applied, why = layout.ApplyPreset("classic")
        local positions = RikUI.Profile.positions
        check("applying a layout writes every position and says so", applied == true and why == nil
            and count(positions) == count(RikUI.Layouts.Sizes) and positions.player.point == "TOPLEFT"
            and near(positions.player.x, 16) and widgets.printedContains(env, "Layout: Classic"))
        check("the frames move at once and nothing stays unlocked", player.points[#player.points][1] == "TOPLEFT"
            and near(player.points[#player.points][4], 16) and not layout.IsMoving())
        check("the applied layout is recognised", layout.MatchingPreset() == "classic")
        check("positions are copies, not the layout's own tables",
            positions.player ~= RikUI.Layouts.classic.positions.player)
        local size = RikUI.Profile.chat.size
        check("the chat gets the width that fits between the margin and the bars on this screen",
            size.width == 405 and size.height == 136 and near(positions.chat.x, 16 + 413 / 2)
            and positions.chat.point == "CENTER")

        positions.player.x = 40
        check("a moved frame makes the arrangement a custom one", layout.MatchingPreset() == nil)
        env.printed = {}
        check("undo restores what was there before the layout", layout.UndoPreset() == true and RikUI.Profile.positions.player == nil
            and RikUI.Profile.chat.size == nil and player.points[#player.points][1] == "BOTTOM"
            and widgets.printedContains(env, "Layout undone"))
        local again, none = layout.UndoPreset()
        check("there is one step of undo", again == nil and none == "Nothing to undo.")

        RikUI.DB.profiles.Source = { positions = { player = {point="TOPLEFT", relativePoint="TOPLEFT", x=35, y=-40} },
            chat = {size={width=500,height=220}}, scale=2, reducedMotion=true }
        local active, oldScale = RikUI.Profile, RikUI.Profile.scale
        check("layout copies from another profile", layout.CopyProfile("Source") == true)
        check("layout copy preserves other settings and identity", RikUI.Profile == active and active.scale == oldScale
            and active.reducedMotion == false and active.chat.size.width == 500)
        check("copied geometry is independent", active.positions.player ~= RikUI.DB.profiles.Source.positions.player
            and active.chat.size ~= RikUI.DB.profiles.Source.chat.size)
        check("layout copy supports undo", layout.UndoPreset() and active.positions.player == nil and active.chat.size == nil)
        RikUI.DB.profiles.Source.positions.player.x = 0/0
        local oldPositions = active.positions
        check("invalid source geometry is atomic", not layout.CopyProfile("Source") and active.positions == oldPositions)
        RikUI.DB.profiles.Source.positions.player.x = 35
        env.inCombat = true
        check("layout copying refuses combat", not layout.CopyProfile("Source") and active.positions == oldPositions)
        env.inCombat = false
        local unknown, unknownReason = layout.ApplyPreset("nonsense")
        check("an unknown layout is refused by name", unknown == nil and unknownReason:find("nonsense", 1, true) ~= nil
            and RikUI.Profile.positions.player == nil)
        env.inCombat = true
        local fighting, combatReason = layout.ApplyPreset("hud")
        check("combat refuses a layout", fighting == nil and combatReason:find("combat", 1, true) ~= nil
            and RikUI.Profile.positions.player == nil)
        env.inCombat = false

        load({ chat = { size = { width = 500, height = 220 } } }, 1228)
        layout.ApplyPreset("hud")
        check("the chat is part of a layout: it gets the layout's size", RikUI.Profile.chat.size.width == 337)
        layout.UndoPreset()
        check("and undo brings the player's own size back", RikUI.Profile.chat.size.width == 500
            and RikUI.Profile.chat.size.height == 220)
        load(nil, 1228)
        layout.ApplyPreset("hud")
        check("on 16:10 the chat narrows to the room beside the bars", RikUI.Profile.chat.size.width == 337
            and near(RikUI.Profile.positions.chat.x, 16 + 345 / 2))
        load(nil, 1820)
        layout.ApplyPreset("hud")
        check("on a wide screen the chat stops at Blizzard's width", RikUI.Profile.chat.size.width == 430)

        for _, height in ipairs({ 768, 1440, 2160 / 0.85 }) do
            load(nil, height * 16 / 9)
            UIParent.GetHeight = function() return height end
            layout.ApplyPreset("hud")
            local rect = layout.Rect("player")
            check("HUD follows screen centre at height " .. height,
                math.abs((rect.top + rect.bottom) / 2 - height / 2) < 100)
            for _, key in ipairs({ "bagspace", "cooldownessential", "cooldownutility", "cooldownbuffs", "cooldownbars" }) do
                check("HUD places " .. key, type(RikUI.Profile.positions[key]) == "table")
            end
        end

        load()
        SlashCmdList.RIKUI("layout list")
        check("/rik layout list names the layouts and marks the current one", widgets.printedContains(env, "centered (current)")
            and widgets.printedContains(env, "healer"))
        SlashCmdList.RIKUI("layout healer")
        check("/rik layout <name> applies it", RikUI.Profile.positions.raid.point == "BOTTOM" and layout.MatchingPreset() == "healer")
        SlashCmdList.RIKUI("layout undo")
        check("/rik layout undo reverts it", RikUI.Profile.positions.raid == nil)
        env.printed = {}
        SlashCmdList.RIKUI("layout nonsense")
        check("/rik layout with an unknown name says what exists", widgets.printedContains(env, "nonsense")
            and widgets.printedContains(env, "centered, classic, hud, healer"))
        env.printed = {}
        SlashCmdList.RIKUI("layout")
        check("/rik layout alone still reports the arrangement state", widgets.printedContains(env, "Layout groups=1"))

        local option = layout.PresetOption()
        check("the options panel gets a dropdown of the layouts", option.type == "dropdown" and option.key == "layoutPreset"
            and #option.values() == 4 and option.get() == "centered")
        option.set("classic")
        check("choosing one applies it", layout.MatchingPreset() == "classic" and option.get() == "classic")

        local merged = RikUI.Setup.LayoutPositions({ positions = { main = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 99 } } }, "hud")
        check("setup merges defaults, then the chosen layout, then the class preset's own positions",
            merged.main.y == 99 and merged.player.point == "BOTTOM" and near(merged.player.x, -230)
            and near(merged.chat.x, 16 + 413 / 2))
        load()
        local only = { macros = false, bars = false, binds = false, cvars = false, layoutPreset = "hud" }
        local result = RikUI.Setup.Apply("WARRIOR", nil, only)
        check("setup Apply with a layout writes that layout's positions", type(result) == "table" and result.status == "applied"
            and near(RikUI.Profile.positions.player.x, -230) and layout.MatchingPreset() == "hud", result and result.error)
        SlashCmdList.RIKUI("undo")
        check("/rik undo puts the old positions back", RikUI.Profile.positions.player == nil
            and layout.MatchingPreset() == "centered")
        load()
        local heard
        local priest = { allowEmpty = true, macros = false, bars = false, binds = false, cvars = false, layoutPreset = "classic",
            onComplete = function(outcome) heard = outcome end }
        result = RikUI.Setup.Apply("PRIEST", nil, priest)
        check("a class without a preset still gets its layout, and the caller hears when setup ends",
            type(result) == "table" and heard == result and result.status == "applied" and layout.MatchingPreset() == "classic"
            and RikUICharDB.applied == nil)
        check("without allowEmpty a class without a preset is refused as before",
            RikUI.Setup.Apply("PRIEST", nil, { layoutPreset = "classic" }) == nil)
        heard = nil
        local broken = RikUI.Setup.Apply("WARRIOR", "nonsense", { onComplete = function(outcome) heard = outcome end })
        check("a refusal before setup starts is a return value, not a callback", broken == nil and heard == nil)
        check("setup refuses a callback that is not a function",
            RikUI.Setup.ValidateOptions({ onComplete = "soon" }) == "onComplete must be a function")
        check("setup refuses a layout that does not exist",
            RikUI.Setup.ValidateOptions({ layoutPreset = "nonsense" }) == "layoutPreset must name a layout"
            and RikUI.Setup.ValidateOptions({ layoutPreset = "hud" }) == nil)
    end)
    UIParent.GetWidth, UIParent.GetHeight = savedWidth, savedHeight
    restore()
    env.inCombat = false
    check("layout presets suite completes", ok, reason)
end
