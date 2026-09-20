-- RikUI design for Blizzard's damage meter, which ships for this game type. Blizzard keeps driving
-- the numbers, colours, bar height, text scale, window opacity and background opacity from the
-- meter's settings; none of those is written. What changes: a flat header with an accent rule and
-- flat glyph buttons, flat bars on an own track with an edge, cropped framed icons, the typeface, a
-- fade-in for new rows, a hover tween, and a RikUI holder so /rik move can drag the meter.
-- Two client facts shape the code. Entries restore their shadow art in UpdateBackground, so that
-- method is post-hooked per entry. Rows are handed out again on every data refresh, so only a newly
-- created row fades in; anything else would flicker through a whole fight.
local core, skin, media, motion = RikUI, RikUI.Skin, RikUI.Media, RikUI.Motion
local weak = { __mode = "k" }
local meter = { Headers = setmetatable({}, weak), Entries = setmetatable({}, weak), Buttons = setmetatable({}, weak) }
core.DamageMeter = meter

local OWNER, SETUP, ANCHOR, WINDOW_PREFIX, MAX_WINDOWS = "DamageMeter", "SetupSessionWindow", "ApplySystemAnchor",
    "DamageMeterSessionWindow", 8
local CONTAINER, SOURCE, LIST, LOCAL_ENTRY = "MinimizeContainer", "SourceWindow", "ScrollBox", "LocalPlayerEntry"
local HOLDER_NAME, LAYOUT_KEY = "RikUIDamageMeterHolder", "damagemeter"
-- Right edge, above the tooltip anchor, which ends at y=330.
local DEFAULTS = { point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT", x = -126, y = 60 }
-- Each string is named by the path of keys from the window down to it.
local WINDOW_TEXT = { { "SessionTimer" }, { "SessionDropdown", "SessionName" },
    { "DamageMeterTypeDropdown", "TypeName" }, { CONTAINER, "NotActive" } }
-- boxed buttons get a flat box behind the glyph; the type dropdown only swaps its arrow for a glyph.
local BUTTONS = { { key = "MinimizeButton", glyph = "-", boxed = true }, { key = "SettingsDropdown", glyph = "=", boxed = true },
    { key = "DamageMeterTypeDropdown", glyph = "v", art = "Arrow" } }
local STATE_TEXTURES = { "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }
local ENTRY_TEXT, ENTRY_ART = { "GetName", "GetValue" }, { "GetBackground", "GetBackgroundEdge" }
local TRACK, ACCENT, ACCENT_HEIGHT, BOX_INSET = { 0, 0, 0, 0.45 }, { 0.3, 0.75, 1, 1 }, 2, 2
local watched, failed, warnings = setmetatable({}, weak), setmetatable({}, weak), {}
local lastError

local function warn(operation, reason)
    lastError = operation .. ": " .. tostring(reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("DamageMeter " .. lastError)
end

local function part(owner, getter)
    return type(owner[getter]) == "function" and owner[getter](owner) or nil
end

local function resolve(owner, path)
    for _, key in ipairs(path) do
        if not skin.IsRegion(owner) then return nil end
        owner = owner[key]
    end
    return owner
end

local function hoverTween(frame, record)
    record.highlight = frame:CreateTexture(nil, "HIGHLIGHT")
    record.highlight:SetAllPoints(frame)
    record.highlight:SetTexture(media.highlight)
    record.hover = motion.Tween(record.highlight, 0, 1, skin.FADE_SECONDS)
    if type(frame.HookScript) == "function" then
        frame:HookScript("OnEnter", function() motion.Play(record.hover) end)
    end
end

-- Blizzard puts the shadow art back to full alpha whenever a setting reaches the entry.
local function fadeEntryArt(entry)
    for _, getter in ipairs(ENTRY_ART) do
        local art = part(entry, getter)
        if skin.IsRegion(art) then art:SetAlpha(0) end
    end
end

local function entryBar(entry, record)
    local bar = part(entry, "GetStatusBar")
    if not skin.IsRegion(bar) or type(bar.CreateTexture) ~= "function" then return end
    if type(bar.SetStatusBarTexture) == "function" then bar:SetStatusBarTexture(media.statusbar) end
    record.track = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    record.track:SetAllPoints(bar)
    record.track:SetTexture(skin.FLAT)
    record.track:SetVertexColor(unpack(TRACK))
    record.edge = skin.Outline(bar)
end

-- The entry clips its children and the icon sits on its left edge, so the icon's edge is drawn over
-- the icon at its own bounds instead of one pixel outside.
local function entryIcon(entry, record)
    local holder, icon = part(entry, "GetIcon"), part(entry, "GetIconTexture")
    if not skin.IsRegion(icon) or not skin.IsRegion(holder) or type(holder.CreateTexture) ~= "function" then return end
    skin.CropIcon(icon)
    record.iconEdge = skin.Outline(holder, nil, 0, icon, "OVERLAY")
end

local function applyEntry(entry)
    local record = {}
    fadeEntryArt(entry)
    if type(entry.UpdateBackground) == "function" then hooksecurefunc(entry, "UpdateBackground", fadeEntryArt) end
    entryBar(entry, record)
    entryIcon(entry, record)
    for _, getter in ipairs(ENTRY_TEXT) do skin.Typeface(part(entry, getter)) end
    hoverTween(entry, record)
    record.fade = motion.Tween(entry, 0, 1, skin.FADE_SECONDS)
    meter.Entries[entry] = record
end

-- A failed entry is not retried: the same write would fail on every refresh.
local function skinEntry(entry, isNew)
    if not skin.IsRegion(entry) or type(entry.CreateTexture) ~= "function" or failed[entry] then return end
    if not meter.Entries[entry] then
        local ok, reason = pcall(applyEntry, entry)
        if not ok then failed[entry] = true; return warn("entry", reason) end
    end
    if isNew then motion.Play(meter.Entries[entry].fade) end
end

local function acquiredEvent()
    local mixin = ScrollBoxListMixin
    return type(mixin) == "table" and type(mixin.Event) == "table" and mixin.Event.OnAcquiredFrame or nil
end

-- Registered before the walk: a list whose view is not ready cannot be walked yet, and that must not
-- cost the rows it hands out later.
local function watch(list)
    local event = acquiredEvent()
    if not skin.IsRegion(list) or watched[list] then return end
    watched[list] = true
    if event and type(list.RegisterCallback) == "function" then
        list:RegisterCallback(event, function(_, row, _, isNew) skinEntry(row, isNew == true) end, meter)
    end
    if type(list.ForEachFrame) == "function" then pcall(list.ForEachFrame, list, function(row) skinEntry(row, false) end) end
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
    local accent = window:CreateTexture(nil, "BORDER")
    accent:SetTexture(skin.FLAT)
    accent:SetVertexColor(unpack(ACCENT))
    accent:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", 0, 0)
    accent:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", 0, 0)
    accent:SetHeight(ACCENT_HEIGHT)
    meter.Headers[window] = { fill = fill, accent = accent, edge = skin.Outline(window, nil, 0, art) }
end

local function fadeButtonArt(button, spec)
    for _, getter in ipairs(STATE_TEXTURES) do
        local texture = part(button, getter)
        if skin.IsRegion(texture) then texture:SetAlpha(0) end
    end
    if spec.art then skin.Strip(button, { spec.art }) end
end

local function headerButton(window, spec)
    local button = window[spec.key]
    if not skin.IsRegion(button) or type(button.CreateFontString) ~= "function" or meter.Buttons[button] then return end
    fadeButtonArt(button, spec)
    local record = {}
    if spec.boxed then
        record.fill = skin.Fill(button, skin.BACKING, BOX_INSET)
        record.edge = skin.Outline(button, nil, BOX_INSET)
        hoverTween(button, record)
    end
    record.glyph = button:CreateFontString(nil, "OVERLAY")
    media.Font(record.glyph, "label")
    record.glyph:SetTextColor(unpack(skin.GOLD))
    local anchor = spec.art and skin.IsRegion(button[spec.art]) and button[spec.art] or button
    record.glyph:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    record.glyph:SetText(spec.glyph)
    meter.Buttons[button] = record
end

local function applyWindow(window)
    header(window)
    for _, spec in ipairs(BUTTONS) do headerButton(window, spec) end
    for _, path in ipairs(WINDOW_TEXT) do skin.Typeface(resolve(window, path)) end
    local container = window[CONTAINER]
    if not skin.IsRegion(container) then return end
    watch(container[LIST])
    watch(resolve(container, { SOURCE, LIST }))
    skinEntry(container[LOCAL_ENTRY], false)
end

local function skinWindow(window)
    if not skin.IsRegion(window) or type(window.CreateTexture) ~= "function" then return end
    if meter.Headers[window] or failed[window] then return end
    local ok, reason = pcall(applyWindow, window)
    if not ok then failed[window] = true; warn("skin", reason) end
    if ok and core.Controls then core.Controls.Walk(window) end
end

-- The primary window is anchored to the DamageMeter frame, which only Edit Mode moves. The frame is
-- hung on a RikUI holder that the shared layout owns. Edit Mode re-anchors its systems whenever a
-- layout applies, so the hang is repeated after it, except while Edit Mode is open.
local function hang(owner)
    if type(owner.IsEditing) == "function" and owner:IsEditing() then return end
    owner:ClearAllPoints()
    owner:SetPoint("TOPLEFT", meter.Holder, "TOPLEFT", 0, 0)
end

local function follow(owner)
    local width, height = owner:GetSize()
    if type(width) == "number" and type(height) == "number" and width > 0 and height > 0 then
        meter.Holder:SetSize(width, height)
    end
end

local function createHolder(owner)
    meter.Holder = CreateFrame("Frame", HOLDER_NAME, UIParent)
    follow(owner)
    core.Layout.Register(meter.Holder, LAYOUT_KEY, DEFAULTS)
    owner:HookScript("OnSizeChanged", follow)
    if type(owner[ANCHOR]) == "function" then hooksecurefunc(owner, ANCHOR, hang) end
    hang(owner)
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
    if core.Layout and type(owner.HookScript) == "function" then createHolder(owner) end
end

function meter:Debug()
    core:Print("DamageMeter windows=" .. count(meter.Headers) .. " entries=" .. count(meter.Entries)
        .. " lists=" .. count(watched) .. " failed=" .. count(failed) .. (lastError and ("; last error " .. lastError) or ""))
end

core:RegisterModule("damagemeter", meter)
