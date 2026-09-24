-- Bounded decoration of known window interiors. Native frames keep their handlers and attributes.
local core, skin, motion = RikUI, RikUI.Skin, RikUI.Motion
local interiors = { Adapters = {}, Roots = {} }
core.Interiors = interiors
local states, watched, shown, refused = {}, {}, {}, {}
for _, set in ipairs({ states, watched, shown, refused }) do setmetatable(set, { __mode = "k" }) end
local MAX_DEPTH, HOVER_ALPHA, HOVER_SECONDS = 10, 0.12, 0.12
local ROW_ART = { "Background", "Bg", "BgTop", "BgMiddle", "BgBottom", "Stripe", "IconSlot" }
local LABELS = { "Label", "Value", "Name", "Title", "Text", "text", "Count", "SubText" }

local function enabled() return not core.Panels or core.Panels.enabled ~= false end
function interiors.State(frame) return states[frame] end
function interiors.IsFrame(frame)
    return skin.IsRegion(frame) and type(frame.GetChildren) == "function"
end

function interiors.Warn(frame, reason)
    if refused[frame] then return end
    refused[frame] = true
    core:Print("Interiors client limit: " .. tostring(reason))
end

local function allowed(frame)
    if not interiors.IsFrame(frame) or refused[frame] then return false end
    if type(frame.IsForbidden) == "function" and frame:IsForbidden() then
        -- Forbidden frames are an expected client boundary, not a skin failure.
        refused[frame] = true
        return false
    end
    return true
end

function interiors.Icon(frame)
    for _, key in ipairs({ "icon", "Icon", "IconTexture", "iconTexture" }) do
        local value = frame[key]
        if skin.IsRegion(value) and type(value.SetTexCoord) == "function" then return value end
    end
    local name = type(frame.GetName) == "function" and frame:GetName()
    return type(name) == "string" and _G[name .. "IconTexture"] or nil
end

local function hover(frame, state)
    state.hover = skin.Fill(frame, { 1, 0.82, 0, 0 }, 1)
    state.hover:SetDrawLayer("OVERLAY")
    state.enter = motion.Tween(state.hover, 0, HOVER_ALPHA, HOVER_SECONDS)
    state.leave = motion.Tween(state.hover, HOVER_ALPHA, 0, HOVER_SECONDS)
    core.Hooks.Script(frame, "OnEnter", function()
        motion.Stop(state.leave); state.hover:SetAlpha(HOVER_ALPHA); motion.Play(state.enter)
    end)
    core.Hooks.Script(frame, "OnLeave", function()
        motion.Stop(state.enter); state.hover:SetAlpha(0); motion.Play(state.leave)
    end)
    core.Hooks.Script(frame, "OnHide", function()
        motion.Stop(state.enter); motion.Stop(state.leave); state.hover:SetAlpha(0)
    end)
end

function interiors.Labels(frame)
    for _, key in ipairs(LABELS) do skin.Typeface(frame[key]) end
end

function interiors.Quality(frame)
    if not states[frame] then return end
    local border, icon = frame.IconBorder, interiors.Icon(frame)
    if not skin.IsRegion(border) or not skin.IsRegion(icon) then return end
    -- Reuse the native quality region: Blizzard retains colour, visibility and empty-slot resets.
    border:SetTexture(skin.FLAT)
    border:SetTexCoord(0, 1, 0, 1)
    border:ClearAllPoints()
    border:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
    border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    border:SetHeight(2)
end

function interiors.Item(frame)
    local icon = interiors.Icon(frame)
    if not skin.IsRegion(icon) then return end
    skin.CropIcon(icon)
    if not states[frame] then
        local state = { edge = skin.Outline(frame, nil, 0, icon, "OVERLAY") }
        states[frame] = state
        hover(frame, state)
        for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
            local region = type(frame[getter]) == "function" and frame[getter](frame)
            if skin.IsRegion(region) then region:SetAlpha(0) end
        end
    end
    local state = states[frame]
    if not state.edge then state.edge = skin.Outline(frame, nil, 0, icon, "OVERLAY") end
    if not state.hover then hover(frame, state) end
    interiors.Labels(frame)
    interiors.Quality(frame)
end

function interiors.Row(frame)
    if not states[frame] then
        local state = { fill = skin.Fill(frame, skin.CONTROL, 1) }
        states[frame] = state
        hover(frame, state)
    end
    local state = states[frame]
    if not state.fill then state.fill = skin.Fill(frame, skin.CONTROL, 1) end
    if not state.hover then hover(frame, state) end
    skin.Strip(frame, ROW_ART)
    interiors.Labels(frame)
end

-- LargeSideTabButtonTemplate is a Frame, with native mouse handlers and a mask.
function interiors.SideTab(frame)
    if not skin.IsRegion(frame.Mask) or not skin.IsRegion(frame.SelectedTexture)
        or not skin.IsRegion(frame.Icon) then return false end
    interiors.Item(frame)
    local state = states[frame]
    if state.sideTab then return true end
    state.sideTab = true
    skin.Strip(frame, { "Background" })
    frame.Icon:RemoveMaskTexture(frame.Mask)
    for _, key in ipairs({ "SelectedTexture", "TabGlow", "HighlightTexture" }) do
        local region = frame[key]
        if skin.IsRegion(region) then
            region:SetTexture(skin.FLAT)
            region:ClearAllPoints()
            region:SetPoint("BOTTOMLEFT", frame.Icon, "BOTTOMLEFT", 0, 0)
            region:SetPoint("BOTTOMRIGHT", frame.Icon, "BOTTOMRIGHT", 0, 0)
            region:SetHeight(2)
            region:SetVertexColor(0.3, 0.75, 1)
        end
    end
    return true
end

function interiors.Surface(frame, art)
    if not states[frame] then states[frame] = { fill = skin.Fill(frame, skin.BACKING, 0) } end
    skin.Strip(frame, art)
    interiors.Labels(frame)
end

local visit
local function watch(frame, family)
    if watched[frame] or type(frame.RegisterCallback) ~= "function"
        or type(frame.ForEachFrame) ~= "function" then return end
    local events = type(ScrollBoxListMixin) == "table" and ScrollBoxListMixin.Event
    if type(events) ~= "table" or not events.OnAcquiredFrame then return end
    watched[frame] = true
    local function row(_, value) if enabled() then visit(value, family, 0, {}) end end
    for _, key in ipairs({ "OnAcquiredFrame", "OnInitializedFrame" }) do
        if events[key] then
            local ok, reason = pcall(frame.RegisterCallback, frame, events[key], row, interiors)
            if not ok then interiors.Warn(frame, reason); return end
        end
    end
end

local function decorate(frame, family)
    local adapter = interiors.Adapters[family]
    if adapter then adapter(frame) end
end

function visit(frame, family, depth, seen)
    if not allowed(frame) or seen[frame] then return end
    seen[frame] = true
    local ok, reason = pcall(decorate, frame, family)
    if not ok then interiors.Warn(frame, reason); return end
    watch(frame, family)
    if not shown[frame] then
        shown[frame] = true
        core.Hooks.Script(frame, "OnShow", function(self)
            if enabled() then visit(self, family, 0, {}) end
        end)
    end
    if depth >= MAX_DEPTH then return end
    for _, child in ipairs({ frame:GetChildren() }) do visit(child, family, depth + 1, seen) end
end

function interiors.Walk(frame, family)
    if not enabled() then return end
    visit(frame, family, 0, {})
end

function interiors.Register(family, names, adapter)
    interiors.Adapters[family] = adapter
    for _, name in ipairs(names) do interiors.Roots[name] = family end
end

function interiors.Discover()
    if not enabled() then return end
    for name, family in pairs(interiors.Roots) do
        local frame = _G[name]
        if allowed(frame) then
            if not shown[frame] then
                shown[frame] = true
                core.Hooks.Script(frame, "OnShow", function(self) interiors.Walk(self, family) end)
            end
            if frame:IsShown() then interiors.Walk(frame, family) end
        end
    end
end

local refreshers = {}
function interiors.Refresh(family)
    if not enabled() then return end
    for name, kind in pairs(interiors.Roots) do
        local frame = _G[name]
        -- Visibility queries are forbidden too; use the same guard as discovery and walking.
        if kind == family and allowed(frame) and frame:IsShown() then interiors.Walk(frame, family) end
    end
end

function interiors.RegisterRefresh(family, events, globals, extra)
    refreshers[#refreshers + 1] = function()
        local pending = false
        local function refresh()
            pending = false
            interiors.Refresh(family)
            if enabled() and extra then extra() end
        end
        local function queue()
            if pending or not enabled() then return end
            pending = true
            if C_Timer and type(C_Timer.After) == "function" then C_Timer.After(0, refresh) else refresh() end
        end
        for _, event in ipairs(events or {}) do core:RegisterEvent(event, queue) end
        for _, name in ipairs(globals or {}) do core.Hooks.Function(name, refresh) end
        queue()
    end
end

function interiors.Enable()
    for _, start in ipairs(refreshers) do start() end
    interiors.Discover()
    core:RegisterEvent("ADDON_LOADED", interiors.Discover)
    core.Hooks.Function("SetItemButtonQuality", function(frame)
        if states[frame] then
            local ok, reason = pcall(interiors.Quality, frame)
            if not ok then interiors.Warn(frame, reason) end
        end
    end)
end

