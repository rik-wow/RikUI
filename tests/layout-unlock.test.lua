-- The part of the arrangement system the player touches: the hold key, the lock tags, the animated
-- overlay and the drag engine. The cursor, the modifier keys and the binding are faked; the geometry
-- underneath is real. UIParent is 1365x768.
return function(check)
    local env = require("wow_stub")
    local widgets = require("widget_stub")
    local restore = widgets.install()
    local NAMES = { "GetCursorPosition", "IsShiftKeyDown", "IsControlKeyDown", "IsAltKeyDown", "GetBindingKey" }
    local saved = { width = UIParent.GetWidth, height = UIParent.GetHeight, scale = UIParent.GetEffectiveScale }
    for _, name in ipairs(NAMES) do saved[name] = _G[name] end
    UIParent.GetWidth, UIParent.GetHeight = function() return 1365 end, function() return 768 end
    UIParent.GetEffectiveScale = function() return 1 end
    local cursor, keys, bound = { 0, 0 }, {}, nil
    GetCursorPosition = function() return cursor[1], cursor[2] end
    IsShiftKeyDown = function() return keys.shift == true end
    IsControlKeyDown = function() return keys.ctrl == true end
    IsAltKeyDown = function() return keys.alt == true end
    GetBindingKey = function() return bound end

    local function box(width, height)
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:SetSize(width, height)
        return frame
    end
    local function at(x, y) return { point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT", x = x, y = y } end
    local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.01 end
    local layout, player, target
    local function load(combat)
        keys, bound, cursor = {}, nil, { 0, 0 }
        widgets.loadAddon(env, { "skin.lua", "layout-unlock.lua", "layout-drag.lua" }, nil, combat)
        layout = RikUI.Layout
        player, target = box(200, 50), box(200, 50)
        layout.Register(player, "player", at(100, 300), { label = "Player frame" })
        layout.Register(target, "target", at(500, 300), { label = "Target frame" })
        env.fire("PLAYER_ENTERING_WORLD")
        env.printed = {}
    end
    local function chord(down)
        keys.shift, keys.ctrl, keys.alt = down, down, down
        env.fire("MODIFIER_STATE_CHANGED")
    end
    local function tick() env.runScript(layout.DragDriver, "OnUpdate", 0.016) end

    local ok, reason = pcall(function()
        load()
        check("nothing is shown and nothing is unlocked at rest", not layout.IsHeld() and not layout.IsMoving()
            and next(layout.Tags) == nil)
        chord(true)
        local tag = layout.Tags.player
        check("holding Ctrl+Alt+Shift shows a lock tag on every group and a master tag", layout.IsHeld()
            and tag ~= nil and tag:IsShown() and layout.Tags.target:IsShown() and layout.MasterTag:IsShown())
        check("a tag names its group, sits on the group's top left corner and fades in",
            tag.label.text == "Player frame" and near(tag.points[1][4], 100) and near(tag.points[1][5], 350)
            and tag.fade.plays == 1)
        chord(false)
        check("releasing hides the tags again", not layout.IsHeld() and not tag:IsShown() and not layout.MasterTag:IsShown())
        bound = "F8"
        chord(true)
        check("once the binding has a key the modifier chord is ignored", not layout.IsHeld())
        chord(false)
        layout.HoldKey("down")
        check("the bound key's down and up drive the hold", layout.IsHeld() and tag:IsShown())
        env.runScript(tag, "OnClick")
        local overlay = layout.Overlays.player
        check("clicking a tag unlocks that group only and gives it the animated overlay",
            layout.IsUnlocked("player") and not layout.IsUnlocked("target") and overlay ~= nil and overlay:IsShown()
            and overlay.pulse.plays == 1 and overlay.pulse.looping == "BOUNCE" and overlay.sweep ~= nil
            and layout.Overlays.target == nil)
        check("the overlay covers the group's rectangle", near(overlay.points[1][4], 100) and near(overlay.points[1][5], 300)
            and overlay.width == 200 and overlay.height == 50)
        layout.HoldKey("up")
        check("an unlocked group stays unlocked and keeps its overlay after the key is released",
            not layout.IsHeld() and layout.IsUnlocked("player") and overlay:IsShown() and layout.IsMoving())

        cursor = { 150, 320 }
        env.runScript(overlay, "OnMouseDown", "LeftButton")
        cursor = { 160, 440 }
        tick()
        local rect = layout.Rect("player")
        check("dragging the overlay moves the group live, by the cursor's travel", near(rect.left, 110) and near(rect.bottom, 420)
            and near(player.points[#player.points][4], 110))
        cursor = { 160, 320 }
        tick()
        cursor = { 550, 320 }
        tick()
        rect = layout.Rect("player")
        check("a drag pushed into another group stops flush against it and marks the overlay as blocked",
            near(rect.right, 500) and not RikUI.Geometry.Overlaps(rect, layout.Rect("target")) and overlay.blocked == true)
        cursor = { 150, 323 }
        tick()
        rect = layout.Rect("player")
        check("near another group's edge the drag snaps to it and shows a guide", near(rect.bottom, 300)
            and layout.Guides.y:IsShown() and overlay.blocked == false,
            "bottom=" .. tostring(rect.bottom) .. " guide=" .. tostring(layout.Guides.y:IsShown())
            .. " blocked=" .. tostring(overlay.blocked))
        keys.shift = true
        tick()
        rect = layout.Rect("player")
        check("holding Shift drags without snapping and without guides", near(rect.bottom, 303) and not layout.Guides.y:IsShown())
        keys.shift = false
        cursor = { 153, 500 }
        tick()
        env.runScript(overlay, "OnMouseUp", "LeftButton")
        check("releasing the mouse saves the position on the group's own anchor and hides the guides",
            RikUI.Profile.positions.player.point == "BOTTOMLEFT" and near(RikUI.Profile.positions.player.y, 480)
            and not layout.Guides.x:IsShown() and not layout.IsDragging())
        cursor = { 400, 400 }
        tick()
        check("the cursor no longer moves the group once the drag ended", near(layout.Rect("player").bottom, 480))

        layout.LockAll()
        layout.HoldKey("down")
        check("with nothing unlocked the master tag offers to unlock", layout.MasterTag.label.text == "Unlock all")
        env.runScript(layout.MasterTag, "OnClick")
        check("the master tag unlocks every group", layout.IsUnlocked("target") and layout.Overlays.target:IsShown()
            and layout.MasterTag.label.text == "Lock all")
        env.runScript(layout.MasterTag, "OnClick")
        check("and locks them all again", not layout.IsMoving() and not overlay:IsShown()
            and layout.MasterTag.label.text == "Unlock all")
        layout.HoldKey("up")

        SlashCmdList.RIKUI("move")
        check("/rik move unlocks everything without the key", layout.IsUnlocked("player") and layout.IsUnlocked("target"))
        cursor = { 150, 500 }
        env.runScript(overlay, "OnMouseDown", "LeftButton")
        cursor = { 250, 600 }
        tick()
        env.inCombat = true
        env.fire("PLAYER_REGEN_DISABLED")
        local kept = RikUI.Profile.positions.player
        check("combat locks everything and keeps the last free place of a drag in flight", not layout.IsMoving()
            and not layout.IsDragging() and not overlay:IsShown() and near(kept.x, 203) and near(kept.y, 580))
        layout.HoldKey("down")
        check("holding the key in combat shows only the master tag, which says why",
            not tag:IsShown() and layout.MasterTag:IsShown() and layout.MasterTag.label.text:find("combat", 1, true) ~= nil)
        env.runScript(layout.MasterTag, "OnClick")
        check("and nothing can be unlocked", not layout.IsMoving())
        layout.HoldKey("up")
        env.inCombat = false
        env.fire("PLAYER_REGEN_ENABLED")

        SlashCmdList.RIKUI("move reset")
        check("/rik move reset still restores the defaults", near(layout.Rect("player").bottom, 300))
        SlashCmdList.RIKUI("scale 2")
        check("/rik scale still scales the groups", RikUI.Profile.scale == 2)
        layout.StopMoving()
        SlashCmdList.RIKUI("layout")
        check("/rik layout reports the arrangement state", widgets.printedContains(env, "Layout groups=2 unlocked=0"))
    end)
    UIParent.GetWidth, UIParent.GetHeight, UIParent.GetEffectiveScale = saved.width, saved.height, saved.scale
    for _, name in ipairs(NAMES) do _G[name] = saved[name] end
    restore()
    env.inCombat = false
    check("layout unlock suite completes", ok, reason)
end
