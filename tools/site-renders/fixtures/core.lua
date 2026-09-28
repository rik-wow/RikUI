-- Development fixture only; never loaded by RikUI. Loaded first by every capture: startup state, capture
-- helpers and shared measurement. Other fixture modules join the script only when a scenario uses them.

assert(A_Admin and RikUI and RikUI.Runtime.loggedIn, "RikUI did not finish startup")
RikUI.Wizard.Close()
if GameMenuFrame then GameMenuFrame:Hide() end
-- Clocks read the wall time; captures show one moment instead of the render's time of day: the
-- world plates' capture time, 2026-09-27 12:07 in the render machine's zone.
local osDate = date
date = function(format, value) return osDate(format, value or 1790536026) end

function RikRenderCenter(frame, scale)
    assert(frame, "Missing preview frame")
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetScale(scale or 1)
end

-- The headless simulator does not emit OnSizeChanged. Deliver the actual
-- callbacks using calculated sizes, leaving RikUI's layout code untouched.
function RikRenderResize(root)
    local previous = {}
    -- Secure aura frames refuse readouts from this tainted fixture; they lay themselves out.
    local function visit(frame)
        local readable, width, height = pcall(frame.GetSize, frame)
        if not readable then return end
        local old = previous[frame]
        if not old or old[1] ~= width or old[2] ~= height then
            previous[frame] = { width, height }
            local callback = frame:GetScript("OnSizeChanged")
            if callback then callback(frame, width, height) end
        end
        local listed, children = pcall(function() return { frame:GetChildren() } end)
        if not listed then return end
        for _, child in ipairs(children) do visit(child) end
    end
    for pass = 1, 6 do visit(root) end
end

function RikRenderCheck(root)
    assert(root, "Scenario root is missing")
    for _, entry in ipairs(RikUI:GetErrors()) do
        error(entry.context .. ": " .. entry.detail)
    end
    CreateFrame("Frame", "RIK_RENDER_OK", root):Hide()
end

-- A capture root for several top-level frames: the simulator renders one frame's subtree, so the
-- frames are re-parented to a holder covering the crop while keeping their screen anchors.
function RikRenderGroup(name, frames, left, bottom, width, height)
    local holder = CreateFrame("Frame", name, UIParent)
    holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    holder:SetSize(width, height)
    for _, frame in ipairs(frames) do
        assert(frame, "Missing frame for " .. name)
        frame:SetParent(holder)
    end
    return holder
end

-- The whole combat HUD as one capture root, laid out by RikUI; the holder matches the crop.
local HUD_FRAMES = { "RikUICooldowns", "RikUICombatResource", "RikUICast_player", "RikUISwingTimer",
    "RikUIClassAuras_player", "RikUIClassAuras_target", "RikUIUnit_player", "RikUIUnit_target", "RikUIUnit_focus" }

function RikRenderHUDGroup(name, left, bottom, width, height, names)
    local frames = {}
    for _, global in ipairs(names or HUD_FRAMES) do frames[#frames + 1] = _G[global] end
    local holder = RikRenderGroup(name, frames, left, bottom, width, height)
    RikRenderResize(holder)
    return holder
end

-- Apply one settings value through the option spec RikUI's settings panel uses, so a sequence
-- frame shows exactly what the control would do.
function RikRenderSetOption(pageId, key, value)
    for _, page in ipairs(RikUI.Options.Pages()) do
        if page.id == pageId then
            for _, spec in ipairs(page.specs) do
                if spec.key == key then
                    assert(type(spec.set) == "function", pageId .. "." .. key .. " has no setter")
                    local ok, reason = spec.set(value)
                    assert(ok ~= false, pageId .. "." .. key .. ": " .. tostring(reason))
                    return
                end
            end
            error("No setting " .. key .. " on page " .. pageId)
        end
    end
    error("No settings page " .. pageId)
end

-- The game clock some seconds ahead, for timers that read GetTime.
function RikRenderAdvanceClock(seconds)
    local base = GetTime
    local started = base()
    GetTime = function() return base() - started + started + seconds end
end

-- The screen point of a creature in the world plate, by name (the nth match), one yard above its feet.
function RikRenderActor(name, nth)
    assert(RikRenderWorld, "This scenario has no world plate")
    local seen = 0
    for _, actor in ipairs(RikRenderWorld.actors) do
        if actor.name == name then
            seen = seen + 1
            if seen == (nth or 1) then return actor end
        end
    end
    error("No actor named " .. name .. " in plate " .. RikRenderWorld.plate)
end

-- The simulator measures a font string when its text is set; RikUI changes fonts afterwards, so a
-- string keeps a stale width until its text is set again. This sets every string again, in place.
function RikRenderRemeasure(root)
    local function visit(frame)
        local listed, regions = pcall(function() return { frame:GetRegions() } end)
        if listed then
            for _, region in ipairs(regions) do
                if type(region.GetText) == "function" and type(region.SetText) == "function" then
                    local text = region:GetText()
                    if text and text ~= "" then region:SetText(text) end
                end
            end
        end
        local ok, children = pcall(function() return { frame:GetChildren() } end)
        if not ok then return end
        for _, child in ipairs(children) do visit(child) end
    end
    visit(root)
end
