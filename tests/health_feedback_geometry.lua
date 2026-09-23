-- Evaluate the recorded native anchors and clipping rectangles; production Lua
-- never performs this geometry arithmetic or reads a StatusBar value back.
return function(check, motion, secret)
    local originalCreate = CreateFrame
    local function node(kind, parent)
        local value = { kind = kind, parent = parent, points = {} }
        function value:SetAllPoints(target) self.all = target end
        function value:SetPoint(point, target, relative) self.points[point] = { target, relative } end
        function value:EnableMouse(enabled) self.mouse = enabled end
        function value:SetClipsChildren(enabled) self.clips = enabled end
        function value:CreateTexture() return node("Texture", self) end
        function value:SetTexture(texture) self.texture = texture end
        function value:SetStatusBarTexture(texture) self.fillTexture = texture end
        function value:SetStatusBarColor(...) self.color = { ... } end
        function value:SetVertexColor(...) self.color = { ... } end
        function value:SetAlpha(alpha) self.alpha = alpha end
        function value:SetMinMaxValues(min, max) self.min, self.max = min, max end
        function value:SetValue(current, easing) self.value, self.easing = current, easing end
        function value:GetValue() error("health feedback must not read status values") end
        function value:HookScript(name, fn) self[name] = fn end
        function value:CreateAnimationGroup()
            local group = { plays = 0 }
            function group:CreateAnimation()
                return { SetFromAlpha = function() end, SetToAlpha = function() end,
                    SetDuration = function() end }
            end
            function group:Play() self.plays, self.playing = self.plays + 1, true end
            function group:Stop() self.playing = false end
            return group
        end
        return value
    end
    local bounds
    local function anchor(point)
        local left, right = bounds(point[1])
        return point[2]:find("RIGHT") and right or left
    end
    bounds = function(value)
        if value.root then return 0, 100 end
        if value.all then return bounds(value.all) end
        if value.parent and value.parent.fillTexture == value then
            local left, right = bounds(value.parent)
            local fraction = math.max(0, math.min(1, value.parent.value / value.parent.max))
            return left, left + (right - left) * fraction
        end
        if value.points.TOPLEFT then return anchor(value.points.TOPLEFT), anchor(value.points.BOTTOMRIGHT) end
        return bounds(value.parent)
    end
    local function visibleWidth(region)
        local left, right = bounds(region)
        local parent = region.parent
        while parent do
            if parent.clips then
                local clipLeft, clipRight = bounds(parent)
                left, right = math.max(left, clipLeft), math.min(right, clipRight)
            end
            parent = parent.parent
        end
        return math.max(0, right - left)
    end
    CreateFrame = function(kind, _, parent) return node(kind, parent) end
    local ok, reason = pcall(function()
        local owner = node("StatusBar")
        owner.root = true
        local feedback = motion.HealthFeedback(owner)
        local function spans(label, damage, heal)
            check(label .. " loss span", math.abs(visibleWidth(feedback.damage.region) - damage) < 0.001)
            check(label .. " gain span", math.abs(visibleWidth(feedback.heal.region) - heal) < 0.001)
        end
        motion.UpdateHealthFeedback(feedback, 80, 100, false)
        spans("initial", 0, 0)
        check("initial geometry never flashes", feedback.damage.group.plays == 0)
        motion.UpdateHealthFeedback(feedback, 50, 100, true)
        spans("80 to 50 damage", 30, 0)
        check("geometry fades start synchronously", feedback.damage.group.plays == 1
            and feedback.heal.group.plays == 1)
        motion.UpdateHealthFeedback(feedback, 70, 100, true)
        spans("50 to 70 healing", 0, 20)
        motion.UpdateHealthFeedback(feedback, 70, 100, true)
        spans("unchanged health", 0, 0)
        motion.UpdateHealthFeedback(feedback, 0, 100, true)
        spans("death", 70, 0)
        motion.UpdateHealthFeedback(feedback, 100, 100, true)
        spans("full heal", 0, 100)
        motion.UpdateHealthFeedback(feedback, 100, 200, false)
        spans("maximum change reset", 0, 0)
        motion.StopHealthFeedback(feedback)
        local plays = feedback.damage.group.plays
        motion.UpdateHealthFeedback(feedback, 40, 100, true)
        spans("recycled baseline", 0, 0)
        check("recycled baseline does not flash", feedback.damage.group.plays == plays)
        motion.UpdateHealthFeedback(feedback, secret, secret, true)
        motion.UpdateHealthFeedback(feedback, secret, secret, true)
        check("opaque values reach previous and current native sinks without arithmetic",
            feedback.previous.value == secret and feedback.current.value == secret
            and feedback.previous.max == secret and feedback.current.max == secret)
        check("geometry frames cannot intercept mouse input", feedback.previous.mouse == false
            and feedback.current.mouse == false and feedback.damage.clip.mouse == false
            and feedback.damage.region.parent.mouse == false)
        owner.OnHide()
        check("owner hiding stops both fades and clears baseline", not feedback.damage.group.playing
            and not feedback.heal.group.playing and not feedback.initialized)
    end)
    CreateFrame = originalCreate
    check("native health geometry suite completes", ok, reason)
end
