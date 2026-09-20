-- Flat look for Blizzard's damage meter, which ships for this game type. Blizzard drives window
-- alpha, background opacity, bar height, text scale, colours and values from the meter's settings,
-- so none of those is written and no tween is added: the header art is faded behind a flat header,
-- strings take the RikUI typeface, and each entry gets the RikUI bar texture, faded shadow art and a
-- cropped icon. Entries are rows of a scroll box, so they are skinned as Blizzard hands them out.
local core, skin, media = RikUI, RikUI.Skin, RikUI.Media
local weak = { __mode = "k" }
local meter = { Headers = setmetatable({}, weak), Entries = setmetatable({}, weak) }
core.DamageMeter = meter

local OWNER, SETUP, WINDOW_PREFIX, MAX_WINDOWS = "DamageMeter", "SetupSessionWindow", "DamageMeterSessionWindow", 8
local CONTAINER, SOURCE, LIST, LOCAL_ENTRY = "MinimizeContainer", "SourceWindow", "ScrollBox", "LocalPlayerEntry"
-- Each string is named by the path of keys from the window down to it.
local WINDOW_TEXT = { { "SessionTimer" }, { "SessionDropdown", "SessionName" },
    { "DamageMeterTypeDropdown", "TypeName" }, { CONTAINER, "NotActive" } }
local ENTRY_TEXT, ENTRY_ART = { "GetName", "GetValue" }, { "GetBackground", "GetBackgroundEdge" }
local watched, failed, warnings = setmetatable({}, weak), setmetatable({}, weak), {}

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("DamageMeter " .. operation .. ": " .. tostring(reason))
end

local function part(entry, getter)
    return type(entry[getter]) == "function" and entry[getter](entry) or nil
end

local function applyEntry(entry)
    local bar = part(entry, "GetStatusBar")
    if skin.IsRegion(bar) and type(bar.SetStatusBarTexture) == "function" then bar:SetStatusBarTexture(media.statusbar) end
    for _, getter in ipairs(ENTRY_TEXT) do skin.Typeface(part(entry, getter)) end
    for _, getter in ipairs(ENTRY_ART) do
        local art = part(entry, getter)
        if skin.IsRegion(art) then art:SetAlpha(0) end
    end
    skin.CropIcon(part(entry, "GetIconTexture"))
end

-- A failed entry is not retried: the same write would fail on every refresh.
local function skinEntry(entry)
    if not skin.IsRegion(entry) or meter.Entries[entry] or failed[entry] then return end
    local ok, reason = pcall(applyEntry, entry)
    if ok then meter.Entries[entry] = true else failed[entry] = true; warn("entry", reason) end
end

local function acquiredEvent()
    local mixin = ScrollBoxListMixin
    return type(mixin) == "table" and type(mixin.Event) == "table" and mixin.Event.OnAcquiredFrame or nil
end

local function watch(list)
    local event = acquiredEvent()
    if not skin.IsRegion(list) or watched[list] then return end
    watched[list] = true
    if type(list.ForEachFrame) == "function" then list:ForEachFrame(skinEntry) end
    if event and type(list.RegisterCallback) == "function" then
        list:RegisterCallback(event, function(_, row) skinEntry(row) end, meter)
    end
end

local function resolve(owner, path)
    for _, key in ipairs(path) do
        if not skin.IsRegion(owner) then return nil end
        owner = owner[key]
    end
    return owner
end

-- The flat header is anchored to Blizzard's header texture, so it follows every resize.
local function header(window)
    local art = window.Header
    if not skin.IsRegion(art) then return end
    art:SetAlpha(0)
    local fill = window:CreateTexture(nil, "BACKGROUND", nil, -8)
    fill:SetTexture(skin.FLAT)
    fill:SetVertexColor(unpack(skin.CONTROL))
    fill:SetPoint("TOPLEFT", art, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", 0, 0)
    meter.Headers[window] = { fill = fill, edge = skin.Outline(window, nil, 0, art) }
end

local function applyWindow(window)
    header(window)
    for _, path in ipairs(WINDOW_TEXT) do skin.Typeface(resolve(window, path)) end
    local container = window[CONTAINER]
    if not skin.IsRegion(container) then return end
    watch(container[LIST])
    watch(resolve(container, { SOURCE, LIST }))
    skinEntry(container[LOCAL_ENTRY])
end

local function skinWindow(window)
    if not skin.IsRegion(window) or type(window.CreateTexture) ~= "function" then return end
    if meter.Headers[window] or failed[window] then return end
    local ok, reason = pcall(applyWindow, window)
    if not ok then failed[window] = true; warn("skin", reason) end
    if ok and core.Controls then core.Controls.Walk(window) end
end

local function count(set)
    local total = 0
    for _ in pairs(set) do total = total + 1 end
    return total
end

function meter:OnEnable()
    local owner = _G[OWNER]
    if not skin.IsRegion(owner) or type(owner[SETUP]) ~= "function" then return end
    hooksecurefunc(owner, SETUP, function(_, _, data)
        if type(data) == "table" then skinWindow(data.sessionWindow) end
    end)
    for index = 1, MAX_WINDOWS do skinWindow(_G[WINDOW_PREFIX .. index]) end
end

function meter:Debug()
    core:Print("DamageMeter windows=" .. count(meter.Headers) .. " failed=" .. count(failed))
end

core:RegisterModule("damagemeter", meter)
