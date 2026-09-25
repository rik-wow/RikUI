-- Widgets of the quest list: a flat header plaque and pooled quest blocks with fixed row heights,
-- so the holder's height follows from the row count and nothing measures text. A long title or
-- objective truncates. A quest seen for the first time fades in, a changed objective flashes its
-- line and a quest that turns complete glows once; an unchanged render replays nothing.
local core, media, ui, motion = RikUI, RikUI.Media, RikUI.UI, RikUI.Motion
local tracker = core.QuestTracker
local view = tracker.View
view.Blocks = {}

local WIDTH, HEADER_HEIGHT, GAP, BLOCK_GAP = 240, 18, 4, 6
local TITLE_HEIGHT, LINE_HEIGHT, ACCENT_WIDTH, PAD, EDGE = 14, 12, 2, 6, 1
local BACKING, LINE_COLOR, WHITE = { 0.06, 0.07, 0.09, 0.9 }, { 0.25, 0.28, 0.32, 1 }, { 1, 1, 1, 1 }
local TITLE_COLOR, COMPLETE_COLOR, FAILED_COLOR = { 1, 0.82, 0 }, { 0.3, 0.9, 0.4 }, { 0.9, 0.25, 0.2 }
local OBJECTIVE_COLOR, FINISHED_COLOR = { 0.85, 0.85, 0.85 }, { 0.5, 0.5, 0.5 }
local FLAT = "Interface\\BUTTONS\\WHITE8X8"
local FADE_SECONDS, FLASH_SECONDS, FLASH_ALPHA, GLOW_SECONDS, GLOW_ALPHA = 0.15, 0.4, 0.3, 0.6, 0.35
local HIGHLIGHT_ALPHA = 0.5
local MORE_HEIGHT, MORE_COLOR = 14, { 0.6, 0.65, 0.7 }
local EXPANDED_ICON, COLLAPSED_ICON, HEADER_ICON_SIZE = "chevron-down", "chevron-right", 10
local CLICK_HINT, SHIFT_HINT = "Click: open in the quest log", "Shift-click: stop tracking"
local seen, hovered = {}, nil

local function label(name, fallback)
    local value = _G[name]
    return type(value) == "string" and value or fallback
end

local function flatTexture(parent, layer, color)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetTexture(FLAT)
    texture:SetVertexColor(unpack(color))
    return texture
end

local function text(parent, role, justify)
    local region = parent:CreateFontString(nil, "OVERLAY")
    media.Font(region, role)
    region:SetJustifyH(justify)
    region:SetWordWrap(false)
    return region
end

local function createHeader(holder)
    local header = CreateFrame("Button", nil, holder)
    header:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_HEIGHT)
    flatTexture(header, "BACKGROUND", BACKING):SetAllPoints(header)
    header.rikBorder = ui.Edges(header, EDGE, "BORDER")
    for _, line in ipairs(header.rikBorder) do line:SetVertexColor(unpack(LINE_COLOR)) end
    header.label = text(header, "small", "LEFT")
    header.label:SetPoint("LEFT", header, "LEFT", PAD, 0)
    header.label:SetText(label("TRACKER_HEADER_QUESTS", "Quests"))
    header.glyph = media.Icon(header, EXPANDED_ICON, HEADER_ICON_SIZE, "OVERLAY")
    header.glyph:SetPoint("RIGHT", header, "RIGHT", -PAD, 0)
    header.count = text(header, "small", "RIGHT")
    header.count:SetPoint("RIGHT", header.glyph, "LEFT", -PAD, 0)
    local highlight = header:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(header)
    highlight:SetTexture(media.highlight)
    header:RegisterForClicks("LeftButtonUp")
    header:SetScript("OnClick", tracker.ToggleCollapsed)
    return header
end

function view.Build(holder)
    holder:SetSize(WIDTH, HEADER_HEIGHT)
    view.Header = createHeader(holder)
end

local function showHint(self)
    self.highlight:Show()
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    hovered = self
    GameTooltip:SetText(self.title:GetText(), 1, 0.82, 0, 1, true)
    local quest = self.quest
    if quest then
        if quest.failed then GameTooltip:AddLine(label("FAILED", "Failed"), 0.9, 0.25, 0.2, true)
        elseif quest.complete then GameTooltip:AddLine(label("QUEST_WATCH_QUEST_READY", "Ready to turn in"), 0.3, 0.9, 0.4, true) end
        for _, objective in ipairs(quest.objectives) do
            local color = objective.finished and FINISHED_COLOR or OBJECTIVE_COLOR
            GameTooltip:AddLine(objective.text, color[1], color[2], color[3], true)
        end
    end
    GameTooltip:AddLine(CLICK_HINT, 1, 1, 1)
    GameTooltip:AddLine(SHIFT_HINT, 1, 1, 1)
    GameTooltip:AddLine(quest and quest.pinned and "Control-click: unpin" or "Control-click: pin to top", 1, 1, 1)
    GameTooltip:Show()
end

local function hideHint(self)
    self.highlight:Hide()
    if hovered == self then hovered = nil; GameTooltip:Hide() end
end

local function createBlock(holder)
    local frame = CreateFrame("Button", nil, holder)
    frame.lines = {}
    frame.glow = flatTexture(frame, "BACKGROUND", COMPLETE_COLOR)
    frame.glow:SetAllPoints(frame)
    frame.glow:SetAlpha(0)
    frame.accentAnim = motion.Tween(frame.glow, GLOW_ALPHA, 0, GLOW_SECONDS)
    frame.accent = flatTexture(frame, "ARTWORK", TITLE_COLOR)
    frame.accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.accent:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    frame.accent:SetWidth(ACCENT_WIDTH)
    frame.highlight = frame:CreateTexture(nil, "ARTWORK")
    frame.highlight:SetAllPoints(frame)
    frame.highlight:SetTexture(media.highlight)
    frame.highlight:SetAlpha(HIGHLIGHT_ALPHA)
    frame.highlight:Hide()
    frame.title = text(frame, "label", "LEFT")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, 0)
    frame.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    frame.title:SetHeight(TITLE_HEIGHT)
    frame.fade = motion.Tween(frame, 0, 1, FADE_SECONDS)
    frame:RegisterForClicks("LeftButtonUp")
    frame:SetScript("OnClick", tracker.Click)
    frame:SetScript("OnEnter", showHint)
    frame:SetScript("OnLeave", hideHint)
    frame:SetScript("OnHide", hideHint)
    return frame
end

local function createLine(frame, index)
    local line = CreateFrame("Frame", nil, frame)
    local top = -(TITLE_HEIGHT + (index - 1) * LINE_HEIGHT)
    line:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, top)
    line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, top)
    line:SetHeight(LINE_HEIGHT)
    line.flash = flatTexture(line, "BACKGROUND", WHITE)
    line.flash:SetAllPoints(line)
    line.flash:SetAlpha(0)
    line.flashAnim = motion.Tween(line.flash, FLASH_ALPHA, 0, FLASH_SECONDS)
    line.text = text(line, "small", "LEFT")
    line.text:SetAllPoints(line)
    return line
end

local function state(quest)
    return quest.failed and "failed" or quest.complete and "complete" or "active"
end

-- A finished quest needs one line, not its ticked-off objectives.
local function displayLines(quest)
    if quest.failed then return { { text = label("FAILED", "Failed"), color = FAILED_COLOR } } end
    if quest.complete then
        return { { text = label("QUEST_WATCH_QUEST_READY", "Ready to turn in"), color = COMPLETE_COLOR } }
    end
    local lines = {}
    for _, objective in ipairs(quest.objectives) do
        if not objective.finished or not core.Profile.questtracker.hideCompleted then
            lines[#lines + 1] = { text = "- " .. objective.text, color = objective.finished and FINISHED_COLOR or OBJECTIVE_COLOR }
        end
    end
    return lines
end

local function titleColor(quest)
    if quest.failed then return FAILED_COLOR end
    if quest.complete then return COMPLETE_COLOR end
    if not quest.level or type(GetQuestDifficultyColor) ~= "function" then return TITLE_COLOR end
    local ok, color = pcall(GetQuestDifficultyColor, quest.level)
    if not ok or type(color) ~= "table" then return TITLE_COLOR end
    return { color.r, color.g, color.b }
end

local function fillTitle(frame, quest)
    local color = titleColor(quest)
    if frame.questID ~= quest.id then hideHint(frame) end
    frame.questID, frame.quest = quest.id, quest
    local title = quest.level and string.format("[%d] %s", quest.level, quest.title) or quest.title
    frame.title:SetText((quest.pinned and "* " or "") .. title)
    frame.title:SetTextColor(unpack(color))
    frame.accent:SetVertexColor(unpack(color))
    if hovered == frame then showHint(frame) end
end

-- Returns the texts so the next render can tell which line changed.
local function fillLines(frame, lines, previous, animate)
    local texts = {}
    for index, entry in ipairs(lines) do
        local line = frame.lines[index] or createLine(frame, index)
        frame.lines[index] = line
        line.text:SetText(entry.text)
        line.text:SetTextColor(unpack(entry.color))
        line:Show()
        if animate and previous and previous[index] and previous[index] ~= entry.text then motion.Play(line.flashAnim) end
        texts[index] = entry.text
    end
    for index = #lines + 1, #frame.lines do frame.lines[index]:Hide() end
    frame:SetHeight(TITLE_HEIGHT + #lines * LINE_HEIGHT)
    return texts
end

local function fillBlock(frame, quest, visible)
    local previous, current = seen[quest.id], state(quest)
    local steady = previous ~= nil and previous.state == current
    fillTitle(frame, quest)
    local texts = fillLines(frame, displayLines(quest), previous and previous.lines, visible and steady)
    if visible and previous and not steady and current == "complete" then motion.Play(frame.accentAnim) end
    return { state = current, lines = texts }, previous == nil
end

local function place(frame, holder, offset)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -offset)
    frame:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -offset)
end

local function updateHeader(count, collapsed)
    view.Header.count:SetText(tostring(count))
    media.SetIcon(view.Header.glyph, collapsed and COLLAPSED_ICON or EXPANDED_ICON)
end

-- The "+N more" line that stands in for the quests a capped list has no room for.
local function moreLine(holder)
    if view.More then return view.More end
    view.More = holder:CreateFontString(nil, "OVERLAY")
    media.Font(view.More, "small")
    view.More:SetTextColor(unpack(MORE_COLOR))
    view.More:SetJustifyH("LEFT")
    view.More:Hide()
    return view.More
end

-- Whether a block ending at bottom fits under view.Limit, keeping room for the "+N more" line when
-- quests follow it. view.Limit is the tallest the list may get; nil means no cap.
local function fits(bottom, following)
    if not view.Limit then return true end
    return bottom + (following > 0 and BLOCK_GAP + MORE_HEIGHT or 0) <= view.Limit
end

local function showMore(holder, hidden, offset)
    local line = moreLine(holder)
    line:SetShown(hidden > 0)
    if hidden == 0 then return offset end
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -offset)
    line:SetText("+" .. hidden .. " more")
    return offset + MORE_HEIGHT + BLOCK_GAP
end

local function visibleLimit()
    local value = core.Profile.questtracker.maxVisible
    if type(value) ~= "number" or value ~= value or value < 1 or value > 25 then return math.huge end
    return math.floor(value)
end

function view.Render(holder, quests, collapsed, expanding)
    local offset, current, hidden = HEADER_HEIGHT + GAP, {}, 0
    local guidance = core.QuestPlanner and core.QuestPlanner.View
    local plannerHeight = guidance and guidance.RenderInline(holder, offset, view.Limit, collapsed) or 0
    offset = offset + plannerHeight
    for index, quest in ipairs(quests) do
        local frame = view.Blocks[index] or createBlock(holder)
        view.Blocks[index] = frame
        local snapshot, isNew = fillBlock(frame, quest, not collapsed)
        current[quest.id] = snapshot
        local shown = not collapsed and index <= visibleLimit() and hidden == 0 and fits(offset + frame:GetHeight(), #quests - index)
        if not collapsed and not shown then hidden = hidden + 1 end
        frame:SetShown(shown)
        if shown then
            place(frame, holder, offset)
            offset = offset + frame:GetHeight() + BLOCK_GAP
            if isNew or expanding then motion.Play(frame.fade) end
        end
    end
    for index = #quests + 1, #view.Blocks do view.Blocks[index]:Hide() end
    seen = current
    updateHeader(#quests, collapsed)
    offset = showMore(holder, hidden, offset)
    local open = not collapsed and (#quests > 0 or plannerHeight > 0)
    holder:SetSize(WIDTH, open and offset - BLOCK_GAP or HEADER_HEIGHT)
    holder:SetShown(#quests > 0 or (guidance ~= nil and core.QuestPlanner.enabled == true))
end
