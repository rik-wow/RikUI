local loadfile = dofile("tests/load_addon.lua").Loadfile
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
        function animation:SetStartDelay(value) self.delay = value end
        function animation:SetOffset(x, y) self.offset = { x, y } end
        group.animation = animation
        return animation
    end
    function group:SetLooping(mode) self.looping = mode end
    function group:Stop() self.playing = false end
    function group:Play() self.plays, self.playing = self.plays + 1, true end
    function group:IsPlaying() return self.playing == true end
    return group
end

-- The client runs OnSizeChanged (and its hooks) after a size that really changed.
local function resize(self, w, h)
    if self.width == w and self.height == h then return end
    self.width, self.height = w, h
    if type(rawget(self, "scripts")) == "table" then require("wow_stub").runScript(self, "OnSizeChanged", w, h) end
end

local function recordCommon(value)
    function value:SetSize(w, h) resize(self, w, h) end
    function value:SetHeight(h) resize(self, self.width, h) end
    function value:SetWidth(w) resize(self, w, self.height) end
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
    -- On the client the fourth component IS the region's alpha: SetVertexColor(r, g, b, 1) undoes an
    -- earlier SetAlpha(0). Modelled here so a suite sees a texture that was meant to stay invisible.
    function value:SetVertexColor(...)
        self.color = { ... }
        if select("#", ...) >= 4 then self.alpha = (select(4, ...)) end
    end
    function value:SetTexCoord(...) self.coords = { ... } end
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
    function frame:SetEnabled(value) self.enabled=value end
    function frame:SetClipsChildren(value) self.clips=value end
    function frame:SetScrollChild(child) self.scrollChild=child end
    function frame:SetVerticalScroll(value) self.scrollOffset=value end
    function frame:EnableMouse(value) self.mouseEnabled=value end
    function frame:IsEnabled() return self.enabled~=false end
    function frame:SetFrameLevel(level) self.level = level end
    function frame:SetFrameStrata(strata) self.strata = strata end
    function frame:SetAttribute(key, value)
        assert(not InCombatLockdown(), "attribute written in combat")
        self.attributes[key] = value
    end
    function frame:SetMinMaxValues(low, high) self.low, self.high = low, high end
    function frame:SetValue(value, easing) self.value, self.easing = value, easing end
    function frame:SetStatusBarTexture(texture) self.texture = texture end
    function frame:SetStatusBarColor(...) self.color = { ... } end
    function frame:GetStatusBarTexture()
        self.fill = self.fill or stub.region({ kind = "Texture" })
        return self.fill
    end
    local texture, font = frame.CreateTexture, frame.CreateFontString
    -- The draw layer is recorded: an edge under an icon and an edge over it differ only in that.
    function frame:CreateTexture(name, layer, ...)
        local region = stub.region(texture(self, name, layer, ...))
        region.layer = layer
        return region
    end
    function frame:CreateFontString(...) return stub.region(font(self, ...)) end
    return frame
end

-- Fresh addon load for a furniture suite: resets the environment, loads the shared files and the
-- module's own, then logs in. prepare() runs before the files load, to install or remove client API.
local SHARED_FILES = { "src/core/core.lua", "src/platform/hooks.lua", "src/platform/tutorials.lua", "src/platform/hide.lua", "src/ui/media.lua", "src/ui/motion.lua", "src/setup/setup.lua", "src/setup/setup-apply.lua",
    "src/layout/layout-geometry.lua", "src/layout/layout.lua", "src/layout/layout-rects.lua", "src/modules/unitframes/unitframes.lua", "src/modules/unitframes/unitframes-status.lua" }

function stub.loadAddon(env, files, profile, combat, prepare)
    env.frames, env.printed, env.inCombat, env.hooks, env.timers = {}, {}, false, {}, {}
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
