local core, interiors, skin = RikUI, RikUI.Interiors, RikUI.Skin
local PAGE_ART = { "TopBar", "BookBGHalved", "BookBGLeft", "BookBGRight", "BookCornerFlipbook", "Bookmark" }
local TALENT_ART = { "Background", "ClassBackground", "BackgroundBorder", "OverlayBackgroundRight",
    "OverlayBackgroundMid", "Clouds1", "Clouds2", "AirParticlesClose", "AirParticlesFar",
    "DividerHorizontalLeft", "DividerHorizontalRight", "DividerVerticalLeft", "DividerVerticalRight" }
local NODE_ART = { "Border", "BorderShadow", "StateBorder", "StateBorderHover", "Shadow", "Backplate" }
local STATE_INTERVAL = 0.1

local function stateColor(frame, state)
    if not skin.IsRegion(frame.SpendText) or type(frame.SpendText.GetTextColor) ~= "function" then return end
    local ok, reason = pcall(function()
        for _, edge in ipairs(state.edge) do edge:SetVertexColor(frame.SpendText:GetTextColor()) end
    end)
    if not ok then interiors.Warn(frame, reason) end
end

local function talent(frame)
    interiors.Item(frame)
    local state = interiors.State(frame)
    if not state then return end
    skin.Strip(frame, NODE_ART)
    skin.Typeface(frame.SpendText)
    stateColor(frame, state)
    if state.talent then return end
    state.talent, state.elapsed = true, 0
    core.Hooks.Script(frame, "OnUpdate", function(self, elapsed)
        state.elapsed = state.elapsed + elapsed
        if state.elapsed < STATE_INTERVAL then return end
        state.elapsed = 0
        stateColor(self, state)
    end)
end

local function connection(frame)
    for _, key in ipairs({ "Line", "GhostLine", "Background", "Fill", "FillScroll1", "FillScroll2" }) do
        local line = frame[key]
        if skin.IsRegion(line) and type(line.SetThickness) == "function" then
            line:SetTexture(skin.FLAT)
            line:SetThickness(2)
        end
    end
end

local function spells(frame)
    if skin.IsRegion(frame.BookBGLeft) or skin.IsRegion(frame.BookBGHalved) then
        interiors.Surface(frame, PAGE_ART)
    end
    if skin.IsRegion(frame.ClassBackground) and skin.IsRegion(frame.BackgroundBorder) then
        interiors.Surface(frame, TALENT_ART)
    end
    if skin.IsRegion(frame.StateBorder) and skin.IsRegion(frame.Icon) then
        talent(frame)
    elseif skin.IsRegion(interiors.Icon(frame)) then
        interiors.Item(frame)
        skin.Strip(frame, NODE_ART)
    end
    connection(frame)
    interiors.Labels(frame)
    for _, key in ipairs({ "SubName", "RequiredLevel", "SpendText", "UnspentLabel", "CurrencyAmount" }) do
        skin.Typeface(frame[key])
    end
end

interiors.Spells = spells
interiors.Register("spells", { "PlayerSpellsFrame" }, spells)

