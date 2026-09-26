-- Flat skin for the controls inside Blizzard's windows: push buttons, check boxes, edit boxes,
-- sliders, both scrollbar generations and dropdown buttons. A frame does not report its template, so
-- a control is recognised by its object type and the region keys its template defines. Walk runs
-- over a window's children on every show; each control is skinned once. Only region alpha, fonts,
-- thumb textures and new child regions are written and scripts are hooked, never set, so a walk in
-- combat is safe. Protected and forbidden frames are skipped whole.
local core, skin, media, motion = RikUI, RikUI.Skin, RikUI.Media, RikUI.Motion
local controls = {}
core.Controls = controls

local MAX_DEPTH, HOVER_SECONDS = 8, 0.12
local BUTTON_INSET, CHECK_INSET, CHECK_MAX_WIDTH = 1, 4, 32
local TRACK_HEIGHT, THUMB_WIDTH, THUMB_HEIGHT, SCROLL_THUMB_WIDTH, SCROLL_THUMB_HEIGHT = 4, 10, 16, 8, 24
local DISABLED_THUMB, DISABLED_ICON_ALPHA = { 0.2, 0.22, 0.25, 0.5 }, 0.35
local FIELD, THUMB, ACCENT = { 0.03, 0.035, 0.045, 0.8 }, { 0.35, 0.39, 0.45, 1 }, { 0.3, 0.75, 1, 1 }
local SLICES, TRACK_ART = { "Left", "Middle", "Right", "Center" }, { "Begin", "Middle", "End" }
local FIELD_ART = { "Left", "Middle", "Right", "TopLeftTex", "TopRightTex", "TopTex", "BottomLeftTex",
    "BottomRightTex", "BottomTex", "LeftTex", "RightTex", "MiddleTex", "NineSlice" }
local STATE_TEXTURES = { "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }
local ICON_KEYS = { "icon", "Icon", "IconTexture" }
local STEP_ICONS, STEP_ICON_SIZE = { ScrollUpButton = "chevron-up", ScrollDownButton = "chevron-down" }, 8
local skinned, failed = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local watched = setmetatable({}, { __mode = "k" })
local warnings, counts = {}, { skinned = 0, failed = 0 }

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Controls " .. operation .. ": " .. tostring(reason))
end

local function hasAll(frame, ...)
    for index = 1, select("#", ...) do
        if not skin.IsRegion(frame[select(index, ...)]) then return false end
    end
    return true
end

local function fadeStates(button)
    for _, getter in ipairs(STATE_TEXTURES) do
        local texture = type(button[getter]) == "function" and button[getter](button) or nil
        if skin.IsRegion(texture) then texture:SetAlpha(0) end
    end
end

local function disabled(frame)
    return type(frame.IsEnabled) == "function" and frame:IsEnabled() == false
end

-- The HIGHLIGHT layer already shows only under the cursor; the tween makes it arrive, not pop.
local function hover(button)
    button.rikHover = button:CreateTexture(nil, "HIGHLIGHT")
    button.rikHover:SetAllPoints(button)
    button.rikHover:SetTexture(media.highlight)
    button.rikHoverFade = motion.Tween(button.rikHover, 0, 1, HOVER_SECONDS)
    local function sync()
        motion.Stop(button.rikHoverFade)
        button.rikHover:SetAlpha(disabled(button) and 0 or 1)
    end
    sync()
    core.Hooks.Script(button, "OnEnter", function()
        if not disabled(button) then motion.Play(button.rikHoverFade) end
    end)
    core.Hooks.Script(button, "OnLeave", sync)
    core.Hooks.Script(button, "OnHide", sync)
    core.Hooks.Script(button, "OnDisable", sync)
    core.Hooks.Script(button, "OnEnable", sync)
end

local function box(frame, color, inset)
    frame.rikFill = skin.Fill(frame, color, inset)
    frame.rikBorder = skin.Outline(frame, nil, inset)
end

local function pushButton(button)
    fadeStates(button)
    skin.Strip(button, SLICES)
    box(button, skin.CONTROL, BUTTON_INSET)
    hover(button)
    motion.BindPress(button)
    skin.ButtonFonts(button)
end

-- Blizzard's tick is a glyph with no box around it, so it stays.
local function checkBox(button)
    fadeStates(button)
    box(button, FIELD, CHECK_INSET)
    hover(button)
    motion.BindPress(button)
end

local function paint(lines, color)
    for _, line in ipairs(lines) do line:SetVertexColor(unpack(color)) end
end

local FOCUS_ALPHA, FOCUS_SECONDS = 0.1, 0.16
local function focusHalo(edit)
    local region = edit:CreateTexture(nil, "ARTWORK")
    region:SetAllPoints(edit)
    region:SetTexture(skin.FLAT)
    region:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
    region:SetAlpha(0)
    local halo = { region = region, enter = motion.Tween(region, 0, FOCUS_ALPHA, FOCUS_SECONDS) }
    edit.rikFocus = halo
    local function clear()
        motion.Stop(halo.enter)
        region:SetAlpha(0)
        paint(edit.rikBorder, skin.LINE)
    end
    edit:HookScript("OnEditFocusGained", function()
        region:SetAlpha(FOCUS_ALPHA)
        if not motion.Reduced() then motion.Play(halo.enter) end
    end)
    edit:HookScript("OnEditFocusLost", clear)
    edit:HookScript("OnHide", clear)
end

local function editBox(edit)
    skin.Strip(edit, FIELD_ART)
    box(edit, FIELD, 0)
    skin.Typeface(edit)
    focusHalo(edit)
    edit:HookScript("OnEditFocusGained", function(self) paint(self.rikBorder, ACCENT) end)
    edit:HookScript("OnEditFocusLost", function(self) paint(self.rikBorder, skin.LINE) end)
end

local function thumbFeedback(slider, thumb)
    local hovering, pressed = false, false
    local function paintThumb()
        local color = disabled(slider) and DISABLED_THUMB or pressed and { 1, 0.82, 0, 1 } or hovering and ACCENT or THUMB
        thumb:SetVertexColor(unpack(color))
    end
    local function reset() hovering, pressed = false, false; paintThumb() end
    slider:HookScript("OnEnter", function() hovering = not disabled(slider); paintThumb() end)
    slider:HookScript("OnLeave", function() hovering = false; paintThumb() end)
    slider:HookScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or disabled(slider) then return end
        pressed = true; paintThumb()
    end)
    slider:HookScript("OnMouseUp", function() pressed = false; paintThumb() end)
    slider:HookScript("OnHide", reset)
    core.Hooks.Script(slider, "OnDisable", reset)
    core.Hooks.Script(slider, "OnEnable", reset)
    reset()
end

local function flatThumb(slider, width, height)
    local thumb = type(slider.GetThumbTexture) == "function" and slider:GetThumbTexture() or nil
    if not skin.IsRegion(thumb) or type(thumb.SetTexture) ~= "function" then return end
    thumb:SetTexture(skin.FLAT)
    thumb:SetVertexColor(unpack(THUMB))
    thumb:SetSize(width, height)
    thumbFeedback(slider, thumb)
end

local function slider(frame)
    skin.Strip(frame, FIELD_ART)
    frame.rikTrack = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.rikTrack:SetTexture(skin.FLAT)
    frame.rikTrack:SetVertexColor(unpack(skin.LINE))
    local vertical = type(frame.GetOrientation) == "function" and frame:GetOrientation() == "VERTICAL"
    local first, last = vertical and "TOP" or "LEFT", vertical and "BOTTOM" or "RIGHT"
    frame.rikTrack:SetPoint(first, frame, first, 0, 0)
    frame.rikTrack:SetPoint(last, frame, last, 0, 0)
    if vertical then frame.rikTrack:SetWidth(TRACK_HEIGHT) else frame.rikTrack:SetHeight(TRACK_HEIGHT) end
    flatThumb(frame, vertical and THUMB_HEIGHT or THUMB_WIDTH, vertical and THUMB_WIDTH or THUMB_HEIGHT)
end

local function stepButton(button, glyph)
    if not skin.IsRegion(button) or type(button.CreateTexture) ~= "function" then return end
    fadeStates(button)
    box(button, skin.CONTROL, BUTTON_INSET)
    hover(button)
    motion.BindPress(button)
    button.rikIcon = media.Icon(button, glyph, STEP_ICON_SIZE, "OVERLAY")
    button.rikIcon:SetPoint("CENTER", button, "CENTER", 0, 0)
    local function sync() button.rikIcon:SetAlpha(disabled(button) and DISABLED_ICON_ALPHA or 1) end
    core.Hooks.Script(button, "OnDisable", sync)
    core.Hooks.Script(button, "OnEnable", sync)
    sync()
end

local function legacyScrollBar(bar)
    flatThumb(bar, SCROLL_THUMB_WIDTH, SCROLL_THUMB_HEIGHT)
    for key, glyph in pairs(STEP_ICONS) do stepButton(bar[key], glyph) end
end

-- Blizzard swaps the thumb's atlases for hover and press; faded pieces stay faded through that.
local function scrollBar(bar)
    skin.Strip(bar.Track, TRACK_ART)
    local thumb = bar.Track.Thumb
    if not skin.IsRegion(thumb) or type(thumb.CreateTexture) ~= "function" then return end
    skin.Strip(thumb, TRACK_ART)
    thumb.rikFill = skin.Fill(thumb, THUMB, BUTTON_INSET)
    hover(thumb)
end

local function dropdown(button)
    skin.Strip(button, { "Background" })
    box(button, skin.CONTROL, BUTTON_INSET)
    hover(button)
    motion.BindPress(button)
    skin.Typeface(button.Text)
end

local function tabButton(tab)
    if core.Panels and core.Panels.Skin.Tab then core.Panels.Skin.Tab(tab, tab.isSelected == true) end
end

local KINDS = { tab = tabButton, button = pushButton, check = checkBox, edit = editBox, slider = slider,
    legacy = legacyScrollBar, scroll = scrollBar, dropdown = dropdown }

-- Action, spell and item buttons are CheckButtons or Buttons too; an icon or a large face gives them away.
local function isCheckBox(frame)
    for _, key in ipairs(ICON_KEYS) do
        if skin.IsRegion(frame[key]) then return false end
    end
    local width = type(frame.GetWidth) == "function" and frame:GetWidth() or nil
    return type(width) ~= "number" or width <= CHECK_MAX_WIDTH
end

local function classify(frame)
    local kind = frame:GetObjectType()
    if kind == "EditBox" then return "edit" end
    if kind == "Slider" then return hasAll(frame, "ScrollUpButton") and "legacy" or "slider" end
    if kind == "CheckButton" then return isCheckBox(frame) and "check" or nil end
    if hasAll(frame, "Track", "Back", "Forward") then return "scroll" end
    if kind ~= "Button" and kind ~= "DropdownButton" then return nil end
    if hasAll(frame, "LeftActive", "MiddleActive", "RightActive") then return "tab" end
    if hasAll(frame, "Left", "Middle", "Right") then return "button" end
    if hasAll(frame, "Background", "Arrow") then return "dropdown" end
    return nil
end

local function refuses(frame, method)
    return type(frame[method]) == "function" and frame[method](frame) == true
end

local function isFrame(value)
    return skin.IsRegion(value) and type(value.GetObjectType) == "function"
end

-- A failed control is not retried: half a skin applied twice is worse than half a skin.
function controls.Skin(frame)
    if skinned[frame] or failed[frame] then return end
    local kind = classify(frame)
    if not kind then return end
    local ok, reason = pcall(KINDS[kind], frame)
    local record = ok and skinned or failed
    record[frame] = true
    counts[ok and "skinned" or "failed"] = counts[ok and "skinned" or "failed"] + 1
    if not ok then warn("skin " .. kind, reason) end
end

local visit

local function acquiredEvent()
    local mixin = ScrollBoxListMixin
    return type(mixin) == "table" and type(mixin.Event) == "table" and mixin.Event.OnAcquiredFrame or nil
end

-- A scroll list builds rows as it scrolls, long after the window's show. Blizzard's own row
-- decoration listens for the same event. A refused registration is not tried again.
local function watchRows(frame)
    local event = acquiredEvent()
    if watched[frame] or not event or type(frame.RegisterCallback) ~= "function"
        or type(frame.ForEachFrame) ~= "function" then return end
    watched[frame] = true
    local ok, reason = pcall(frame.RegisterCallback, frame, event, function(_, row)
        if controls.enabled then visit(row, 0) end
    end, controls)
    if not ok then warn("watch", reason) end
end

function visit(frame, depth)
    if not isFrame(frame) or refuses(frame, "IsForbidden") then return end
    if core.Panels and core.Panels.FrameEnabled and not core.Panels.FrameEnabled(frame) then return end
    if not refuses(frame, "IsProtected") then controls.Skin(frame) end
    watchRows(frame)
    if depth >= MAX_DEPTH or type(frame.GetChildren) ~= "function" then return end
    for _, child in ipairs({ frame:GetChildren() }) do visit(child, depth + 1) end
end

function controls.Walk(frame)
    if not controls.enabled then return end
    visit(frame, 0)
end

function controls:Debug()
    core:Print("Controls skinned=" .. counts.skinned .. " failed=" .. counts.failed)
end

core:RegisterModule("controls", controls)
