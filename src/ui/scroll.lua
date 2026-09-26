-- Bounded mouse-wheel and thumb scrolling shared by the shell and configuration.
local scroll, skin = {}, RikUI.Skin
RikUI.Scroll = scroll
local BAR_WIDTH, BAR_GAP, WHEEL_STEP, THUMB_HEIGHT = 8, 6, 36, 28

function scroll.SetOffset(pane, offset)
    pane.offset = math.max(0, math.min(pane.range or 0, offset))
    pane.view:SetVerticalScroll(pane.offset)
    pane.updating = true
    pane.bar:SetValue(pane.offset)
    pane.updating = false
    if pane.moreAbove then
        pane.moreAbove:SetShown(pane.offset > 0)
        pane.moreBelow:SetShown(pane.offset < (pane.range or 0))
    end
    if pane.OnScroll then pane.OnScroll() end
end

local function updateRange(pane)
    pane.range = math.max(0, (pane.contentHeight or 1) - (pane.height or 1))
    pane.updating = true
    pane.bar:SetMinMaxValues(0, pane.range)
    pane.updating = false
    pane.bar:SetShown(pane.range > 0)
    local height = pane.height or 1
    pane.thumbHeight = math.min(height, math.max(THUMB_HEIGHT, height * height / math.max(height, pane.contentHeight or 1)))
    local thumb = pane.bar:GetThumbTexture()
    if thumb then thumb:SetHeight(pane.thumbHeight) end
    scroll.SetOffset(pane, pane.offset or 0)
end

function scroll.Resize(pane, width, height)
    width, height = math.max(1, width), math.max(1, height)
    pane.width, pane.height = width, height
    pane.resizing = true
    pane.view:SetSize(math.max(1, width - BAR_WIDTH - BAR_GAP), height)
    pane.content:SetWidth(math.max(1, width - BAR_WIDTH - BAR_GAP))
    if pane.OnResize then pane.OnResize(pane.content:GetWidth()) end
    pane.resizing = false
    updateRange(pane)
end

function scroll.SetContentHeight(pane, height)
    pane.contentHeight = math.max(1, height)
    pane.content:SetHeight(pane.contentHeight)
    if not pane.resizing then updateRange(pane) end
end

function scroll.Reveal(pane, top, height)
    -- Hidden panes may be sized before OnSizeChanged populates our layout cache.
    local width, viewportHeight = math.max(1, pane:GetWidth() or 1), math.max(1, pane:GetHeight() or 1)
    if pane.width ~= width or pane.height ~= viewportHeight then scroll.Resize(pane, width, viewportHeight) end
    local offset = pane.offset or 0
    if top < offset or height > pane.height then scroll.SetOffset(pane, top)
    elseif top + height > offset + pane.height then scroll.SetOffset(pane, top + height - pane.height) end
end

local function createBar(pane)
    local bar = CreateFrame("Slider", nil, pane)
    bar:SetWidth(BAR_WIDTH)
    bar:SetPoint("TOPRIGHT")
    bar:SetPoint("BOTTOMRIGHT")
    bar:SetOrientation("VERTICAL")
    bar:SetValueStep(1)
    bar:SetThumbTexture(skin.FLAT)
    local thumb = bar:GetThumbTexture()
    if thumb then thumb:SetSize(BAR_WIDTH, THUMB_HEIGHT); thumb:SetVertexColor(0.3, 0.55, 0.68, 1) end
    skin.Fill(bar, skin.CONTROL)
    bar:SetScript("OnValueChanged", function(_, value)
        if not pane.updating then scroll.SetOffset(pane, value) end
    end)
    return bar
end

local function overflowCue(pane, edge)
    local cue = pane.view:CreateTexture(nil, "OVERLAY")
    cue:SetColorTexture(0.35, 0.65, 0.8, 0.65)
    cue:SetPoint(edge .. "LEFT", pane.view, edge .. "LEFT")
    cue:SetPoint(edge .. "RIGHT", pane.view, edge .. "RIGHT")
    cue:SetHeight(2); cue:Hide()
    return cue
end

function scroll.Create(parent)
    local pane = CreateFrame("Frame", nil, parent)
    pane.view = CreateFrame("ScrollFrame", nil, pane)
    pane.view:SetPoint("TOPLEFT")
    pane.view:SetClipsChildren(true)
    pane.content = CreateFrame("Frame", nil, pane.view)
    pane.content:SetSize(1, 1)
    pane.view:SetScrollChild(pane.content)
    pane.bar = createBar(pane)
    pane.moreAbove, pane.moreBelow = overflowCue(pane, "TOP"), overflowCue(pane, "BOTTOM")
    pane:EnableMouseWheel(true)
    pane.view:EnableMouseWheel(true)
    local wheel = function(_, delta) scroll.SetOffset(pane, (pane.offset or 0) - delta * WHEEL_STEP) end
    pane:SetScript("OnMouseWheel", wheel)
    pane.view:SetScript("OnMouseWheel", wheel)
    pane:SetScript("OnSizeChanged", function(_, width, height) scroll.Resize(pane, width, height) end)
    return pane
end
