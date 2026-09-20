-- Flat chat bubbles. The engine owns and pools the bubbles; C_ChatBubbles lists the ones addons may
-- touch, which leaves out the forbidden bubbles of instances. A bubble appears a frame or more after
-- its chat event, so each event opens a one-second burst of scans instead of a permanent poll. The
-- font goes on the ChatBubbleFont object: bubble strings are never written, which keeps the colour
-- the client gives each chat type.
local core, media, skin, motion = RikUI, RikUI.Media, RikUI.Skin, RikUI.Motion
local bubbles = {}
core.ChatBubbles = bubbles

local EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_PARTY" }
local ART = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge",
    "BottomEdge", "LeftEdge", "RightEdge", "Center", "Tail" }
local SCAN_SECONDS, SCAN_INTERVAL = 1, 0.1
-- ChatBubbleTemplate reaches 16px past its string; the flat panel keeps 10px of that as padding.
local INSET, FONT_NAME, DEFAULT_SIZE, FLAGS = 6, "ChatBubbleFont", 14, "OUTLINE"
local seen, warnings = setmetatable({}, { __mode = "k" }), {}
local counts = { skinned = 0, font = false }
local remaining, sinceScan = 0, 0

local function warn(operation, reason)
    if warnings[operation] then return end
    warnings[operation] = true
    core:Print("Chat bubbles " .. operation .. ": " .. tostring(reason))
end

local function isForbidden(frame)
    return type(frame.IsForbidden) == "function" and frame:IsForbidden() == true
end

local function replayFade(frame) motion.Play(frame.rikFade) end

local function apply(frame)
    skin.Strip(frame, ART)
    frame.rikFill = skin.Fill(frame, skin.BACKING, INSET)
    frame.rikBorder = skin.Outline(frame, nil, INSET)
    frame.rikFade = motion.Tween(frame, 0, 1, skin.FADE_SECONDS)
    frame:HookScript("OnShow", replayFade)
    replayFade(frame)
end

-- The art lives on the bubble's first child. A bubble is looked at once, skinned or not.
local function visit(bubble)
    if seen[bubble] or isForbidden(bubble) then return end
    seen[bubble] = true
    local frame = bubble:GetChildren()
    if type(frame) ~= "table" or isForbidden(frame) then return end
    local ok, reason = pcall(apply, frame)
    if ok then counts.skinned = counts.skinned + 1 else warn("skin", reason) end
end

local function scan()
    local ok, list = pcall(C_ChatBubbles.GetAllChatBubbles)
    if not ok then warn("list", list) return end
    for _, bubble in ipairs(type(list) == "table" and list or {}) do visit(bubble) end
end

local function onUpdate(self, elapsed)
    remaining, sinceScan = remaining - elapsed, sinceScan + elapsed
    if sinceScan >= SCAN_INTERVAL then
        sinceScan = 0
        scan()
    end
    if remaining <= 0 then self:SetScript("OnUpdate", nil) end
end

local function startBurst()
    remaining = SCAN_SECONDS
    if bubbles.Scanner:GetScript("OnUpdate") then return end
    sinceScan = 0
    bubbles.Scanner:SetScript("OnUpdate", onUpdate)
end

local function restyleFont()
    local object = _G[FONT_NAME]
    if type(object) ~= "table" or type(object.SetFont) ~= "function" then return end
    local ok, _, size = pcall(object.GetFont, object)
    size = ok and type(size) == "number" and size > 0 and size or DEFAULT_SIZE
    local written, loaded = pcall(object.SetFont, object, media.font, size, FLAGS)
    counts.font = written and loaded ~= false
    if not counts.font then warn("font", written and "the client refused the font" or loaded) end
end

function bubbles:OnEnable()
    if type(C_ChatBubbles) ~= "table" or type(C_ChatBubbles.GetAllChatBubbles) ~= "function" then return end
    bubbles.Scanner = CreateFrame("Frame")
    restyleFont()
    for _, event in ipairs(EVENTS) do core:RegisterEvent(event, startBurst) end
end

function bubbles:Debug()
    core:Print("Chat bubbles skinned=" .. counts.skinned .. " font=" .. tostring(counts.font))
end

core:RegisterModule("chatbubbles", bubbles)
