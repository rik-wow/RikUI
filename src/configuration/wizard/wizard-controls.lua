-- The wizard's own controls: a flat button, a compact check box for grids of choices, a selectable
-- card and a key cap. Flat fill, one-pixel edge, RikUI font; hover and selection fade instead of
-- switching. None of them is a secure frame.
local core, media, skin, motion = RikUI, RikUI.Media, RikUI.Skin, RikUI.Motion
local controls = {}
core.WizardControls = controls

local ACCENT, MUTED, DISABLED_ALPHA = { 0.3, 0.75, 1, 1 }, { 0.6, 0.65, 0.7 }, 0.4
local HOVER_ALPHA, HOVER_SECONDS = 0.18, 0.12
local BUTTON_WIDTH, BUTTON_HEIGHT = 110, 24
local BOX, CHECK_HEIGHT, CHECK_GAP = 14, 20, 6
controls.ACCENT, controls.MUTED = ACCENT, MUTED

function controls.Text(parent, role, text, color)
    local region = parent:CreateFontString(nil, "OVERLAY")
    media.Font(region, role or "label")
    if color then region:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
    region:SetText(text or "")
    return region
end

-- A highlight that fades in under the cursor.
local function hover(frame)
    local glow = frame:CreateTexture(nil, "ARTWORK")
    glow:SetAllPoints()
    glow:SetTexture(media.highlight)
    -- Three components: the fourth is the region's alpha, which the hover below owns.
    glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
    glow:SetAlpha(0)
    glow.fade = motion.Tween(glow, 0, HOVER_ALPHA, HOVER_SECONDS)
    frame:HookScript("OnEnter", function()
        if frame.disabled then return end
        glow:SetAlpha(HOVER_ALPHA)
        motion.Play(glow.fade)
    end)
    frame:HookScript("OnLeave", function() glow:SetAlpha(0) end)
    return glow
end

local function setDisabled(button, disabled)
    button.disabled = disabled == true
    button:SetAlpha(button.disabled and DISABLED_ALPHA or 1)
    button:EnableMouse(not button.disabled)
end

function controls.Button(parent, text, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    skin.Fill(button, skin.CONTROL)
    button.edge = skin.Outline(button)
    button.glow = hover(button)
    button.label = controls.Text(button, "label", text)
    button.label:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.SetDisabled = setDisabled
    button:SetScript("OnClick", function(self) if not self.disabled then onClick(self) end end)
    setDisabled(button, false)
    return button
end

local function paintCheck(check)
    local on = check.get() == true
    check.mark:SetAlpha(on and 1 or 0)
    check.label:SetTextColor(on and 1 or MUTED[1], on and 1 or MUTED[2], on and 1 or MUTED[3], 1)
end

-- A compact check box: a 14px box with an accent mark and the label beside it.
function controls.Check(parent, width, text, get, set)
    local check = CreateFrame("Button", nil, parent)
    check:SetSize(width, CHECK_HEIGHT)
    check.get = get
    check.box = CreateFrame("Frame", nil, check)
    check.box:SetSize(BOX, BOX)
    check.box:SetPoint("LEFT", check, "LEFT", 0, 0)
    skin.Fill(check.box, skin.CONTROL)
    skin.Outline(check.box)
    check.mark = check.box:CreateTexture(nil, "ARTWORK")
    check.mark:SetPoint("TOPLEFT", check.box, "TOPLEFT", 3, -3)
    check.mark:SetPoint("BOTTOMRIGHT", check.box, "BOTTOMRIGHT", -3, 3)
    check.mark:SetTexture(skin.FLAT)
    check.mark:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    check.mark.fade = motion.Tween(check.mark, 0, 1, HOVER_SECONDS)
    check.glow = hover(check)
    check.label = controls.Text(check, "small", text)
    check.label:SetPoint("LEFT", check.box, "RIGHT", CHECK_GAP, 0)
    check.label:SetPoint("RIGHT", check, "RIGHT", 0, 0)
    check.label:SetJustifyH("LEFT")
    check.label:SetWordWrap(false)
    check.Refresh = paintCheck
    check:SetScript("OnClick", function(self)
        set(not (get() == true))
        paintCheck(self)
        if get() == true then motion.Play(self.mark.fade) end
    end)
    paintCheck(check)
    return check
end

-- Checks laid out in columns, filled top to bottom. entries = { { text, get, set }, ... }.
function controls.CheckGrid(parent, entries, columns, width)
    local rows, checks = math.ceil(#entries / columns), {}
    for index, entry in ipairs(entries) do
        local column, row = math.floor((index - 1) / rows), (index - 1) % rows
        local check = controls.Check(parent, width - CHECK_GAP, entry.text, entry.get, entry.set)
        check:SetPoint("TOPLEFT", parent, "TOPLEFT", column * width, -row * (CHECK_HEIGHT + 2))
        checks[index] = check
    end
    return checks, rows * (CHECK_HEIGHT + 2)
end

-- A selectable card: the chosen one carries the accent edge.
function controls.Card(parent, width, height, onClick)
    local card = CreateFrame("Button", nil, parent)
    card:SetSize(width, height)
    skin.Fill(card, skin.CONTROL)
    skin.Outline(card)
    card.chosen = CreateFrame("Frame", nil, card)
    card.chosen:SetAllPoints()
    skin.Outline(card.chosen, ACCENT)
    card.chosen:SetAlpha(0)
    card.chosen.fade = motion.Tween(card.chosen, 0, 1, skin.FADE_SECONDS)
    card.glow = hover(card)
    function card:SetChosen(chosen)
        local was = self.isChosen == true
        self.isChosen = chosen == true
        self.chosen:SetAlpha(self.isChosen and 1 or 0)
        if self.isChosen and not was then motion.Play(self.chosen.fade) end
    end
    card:SetScript("OnClick", function(self) onClick(self) end)
    return card
end

-- A key cap for the keyboard picture: dim when the key is not part of the scheme.
local function paintCap(cap, active)
    cap.active = active == true
    cap.lit:SetAlpha(cap.active and 1 or 0)
    cap.label:SetTextColor(cap.active and 1 or MUTED[1], cap.active and 1 or MUTED[2], cap.active and 1 or MUTED[3], 1)
end

function controls.KeyCap(parent, width, height, text, active)
    local cap = CreateFrame("Frame", nil, parent)
    cap:SetSize(width, height)
    skin.Fill(cap, skin.CONTROL)
    skin.Outline(cap)
    cap.lit = CreateFrame("Frame", nil, cap)
    cap.lit:SetAllPoints()
    skin.Outline(cap.lit, ACCENT)
    cap.label = controls.Text(cap, "small", text)
    cap.label:SetPoint("CENTER", cap, "CENTER", 0, 0)
    cap.SetActive = paintCap
    paintCap(cap, active)
    return cap
end
