-- Recording widgets for suites that check geometry, colours and animations. install() wraps
-- CreateFrame so frames answer unknown lowercase fields with nil (the shared stub answers a no-op
-- function, which makes absent regions look present) and returns a function that undoes the wrap.
local stub = {}

function stub.animationGroup()
    local group = { plays = 0 }
    function group:CreateAnimation(kind)
        local animation = { kind = kind }
        function animation:SetFromAlpha(value) self.from = value end
        function animation:SetToAlpha(value) self.to = value end
        function animation:SetDuration(value) self.duration = value end
        group.animation = animation
        return animation
    end
    function group:SetLooping(mode) self.looping = mode end
    function group:Stop() self.playing = false end
    function group:Play() self.plays, self.playing = self.plays + 1, true end
    function group:IsPlaying() return self.playing == true end
    return group
end

local function recordCommon(value)
    function value:SetSize(w, h) self.width, self.height = w, h end
    function value:SetHeight(h) self.height = h end
    function value:SetWidth(w) self.width = w end
    function value:GetHeight() return self.height end
    function value:GetWidth() return self.width end
    function value:GetSize() return self.width, self.height end
    -- stub.center stands in for a laid-out frame's position; nil means the client has none yet.
    function value:GetCenter()
        if not stub.center then return nil end
        return stub.center[1], stub.center[2]
    end
    function value:GetEffectiveScale() return 1 end
    function value:ClearAllPoints() self.points = {} end
    function value:SetPoint(...)
        -- rawget: a region keeps the shared metatable, which answers unknown fields with a function.
        local points = rawget(self, "points") or {}
        points[#points + 1] = { ... }
        self.points = points
        self.point = { ... }
    end
    function value:SetAlpha(alpha) self.alpha = alpha end
    function value:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function value:CreateAnimationGroup() return stub.animationGroup() end
    return value
end

function stub.region(value)
    recordCommon(value)
    value.shown = true
    function value:SetTexture(texture) self.texture = texture end
    function value:SetVertexColor(...) self.color = { ... } end
    function value:SetTextColor(...) self.textColor = { ... } end
    function value:SetFont(path, size) self.fontPath, self.fontSize = path, size; return true end
    function value:SetWordWrap(wrap) self.wordWrap = wrap end
    function value:SetJustifyH(justify) self.justify = justify end
    return value
end

local function wrapFrame(frame)
    local methods = getmetatable(frame).__index
    setmetatable(frame, { __index = function(t, key)
        if key:match("^[A-Z]") then return methods(t, key) end
    end })
    recordCommon(frame)
    function frame:SetParent(value)
        assert(not InCombatLockdown(), "frame reparented in combat")
        self.parent = value
    end
    function frame:GetParent() return self.parent end
    function frame:SetAttribute(key, value)
        assert(not InCombatLockdown(), "attribute written in combat")
        self.attributes[key] = value
    end
    function frame:SetMinMaxValues(low, high) self.low, self.high = low, high end
    function frame:SetValue(value, easing) self.value, self.easing = value, easing end
    function frame:SetStatusBarTexture(texture) self.texture = texture end
    function frame:SetStatusBarColor(...) self.color = { ... } end
    local texture, font = frame.CreateTexture, frame.CreateFontString
    function frame:CreateTexture(...) return stub.region(texture(self, ...)) end
    function frame:CreateFontString(...) return stub.region(font(self, ...)) end
    return frame
end

-- Fresh addon load for a furniture suite: resets the environment, loads the shared files and the
-- module's own, then logs in. prepare() runs before the files load, to install or remove client API.
local SHARED_FILES = { "core.lua", "hide.lua", "media.lua", "motion.lua", "setup.lua", "setup-apply.lua",
    "layout.lua", "unitframes.lua", "unitframes-status.lua" }

function stub.loadAddon(env, files, profile, combat, prepare)
    env.frames, env.printed, env.inCombat, env.hooks = {}, {}, false, {}
    if prepare then prepare() end
    profile = profile or {}
    profile.modules = profile.modules or {}
    if profile.modules.unitframes == nil then profile.modules.unitframes = false end
    RikUI, RikUIDB, RikUICharDB = nil, { profiles = { Default = profile } }, nil
    for _, list in ipairs({ SHARED_FILES, files }) do
        for _, file in ipairs(list) do assert(loadfile(file))("RikUI", {}) end
    end
    env.fire("ADDON_LOADED", "RikUI")
    env.inCombat = combat == true
    env.fire("PLAYER_LOGIN")
end

function stub.printedContains(env, text)
    for _, line in ipairs(env.printed) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

function stub.install()
    local original = CreateFrame
    CreateFrame = function(kind, name, parent, template)
        return wrapFrame(original(kind, name, parent, template))
    end
    return function() CreateFrame = original end
end

return stub
