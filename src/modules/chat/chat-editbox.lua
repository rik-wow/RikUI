-- The input bar. Readable first: the typing area is an opaque dark field and nothing light ever spans
-- it. The channel shows in the one-pixel border and in a two-pixel accent bar on the left, which
-- pulses once when the channel changes; taking the focus fades a glow in around the box; opening the
-- box fades its art in. All of RikUI's art lives on a child frame of its own, because Blizzard writes
-- the edit box's own alpha when it activates and deactivates chat, and a tween there would fight it.
-- Colours are written with three components: the fourth component of SetVertexColor is the region's
-- alpha on this client, and writing it undid an earlier SetAlpha(0) (the washed-out bar of 2026-09-20).
local core, motion, ui = RikUI, RikUI.Motion, RikUI.UI
local chat = core.Chat

local FLAT = "Interface\\BUTTONS\\WHITE8X8"
local FIELD = { 0.03, 0.035, 0.045, 0.97 }
local ACCENT_WIDTH, EDGE, GLOW_OUTSET = 2, 1, 1
local PULSE_LOW, PULSE_SECONDS, FADE_SECONDS, GLOW_ALPHA = 0.25, 0.3, 0.15, 0.55
local dressed, lastKey = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })

local function flat(parent, layer, sublevel)
    local texture = parent:CreateTexture(nil, layer, nil, sublevel)
    texture:SetTexture(FLAT)
    return texture
end

local function field(art)
    art.field = flat(art, "BACKGROUND", 1)
    art.field:SetAllPoints(art)
    art.field:SetVertexColor(FIELD[1], FIELD[2], FIELD[3], FIELD[4])
end

local function accent(art)
    art.accent = flat(art, "ARTWORK")
    art.accent:SetPoint("TOPLEFT", art, "TOPLEFT", EDGE, -EDGE)
    art.accent:SetPoint("BOTTOMLEFT", art, "BOTTOMLEFT", EDGE, EDGE)
    art.accent:SetWidth(ACCENT_WIDTH)
    art.accentPulse = motion.Tween(art.accent, PULSE_LOW, 1, PULSE_SECONDS)
end

-- A one-pixel line just outside the border, invisible until the box has the focus.
local function glow(art)
    local frame = CreateFrame("Frame", nil, art)
    frame:SetPoint("TOPLEFT", art, "TOPLEFT", -GLOW_OUTSET, GLOW_OUTSET)
    frame:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", GLOW_OUTSET, -GLOW_OUTSET)
    frame.lines = ui.Edges(frame, EDGE, "BORDER")
    frame:SetAlpha(0)
    frame.fade = motion.Tween(frame, 0, 1, FADE_SECONDS)
    art.glow = frame
end

local function focusGained(box)
    local frame = box.rikArt.glow
    frame:SetAlpha(1)
    motion.Play(frame.fade)
end

local function focusLost(box) box.rikArt.glow:SetAlpha(0) end

function chat.DressEditBox(box)
    if dressed[box] or not chat.IsFrame(box) then return end
    dressed[box] = true
    local art = CreateFrame("Frame", nil, box)
    art:SetAllPoints(box)
    art:SetFrameLevel(math.max(0, (box:GetFrameLevel() or 1) - 1))
    art.fade = motion.Tween(art, 0, 1, FADE_SECONDS)
    field(art)
    accent(art)
    glow(art)
    box.rikArt = art
    box:HookScript("OnEditFocusGained", focusGained)
    box:HookScript("OnEditFocusLost", focusLost)
    box:HookScript("OnShow", function() motion.Play(art.fade) end)
    chat.PaintEditBox(box, nil, nil, false)
end

local function tint(box, color, glowAlpha)
    local art = box.rikArt
    for _, line in ipairs(box.rikBorder or {}) do line:SetVertexColor(color[1], color[2], color[3]) end
    art.accent:SetVertexColor(color[1], color[2], color[3])
    for _, line in ipairs(art.glow.lines) do line:SetVertexColor(color[1], color[2], color[3], glowAlpha) end
end

-- color is the channel's { r, g, b } or nil for the neutral look; key names the channel, so the pulse
-- plays only when the channel really changed and not on every header refresh.
function chat.PaintEditBox(box, color, key, animate)
    if not box.rikArt then return end
    tint(box, color or chat.Colors.border, GLOW_ALPHA)
    if animate and color and lastKey[box] ~= key then motion.Play(box.rikArt.accentPulse) end
    lastKey[box] = key
end
