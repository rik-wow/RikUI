-- Small pictures for the wizard: a whole-screen layout drawn from its rectangles (the same arithmetic
-- src/layout/layout-audit.lua checks, so the picture is the layout), and the main bar a role would get.
local core, skin = RikUI, RikUI.Skin
local controls, layouts = core.WizardControls, core.Layouts
local preview = {}
core.WizardPreview = preview

-- The reference screen the pictures are drawn for: 16:9 at the default UI scale.
local SCREEN = { width = 1365, height = 768 }
local SCREEN_COLOR, DIM_ALPHA = { 0.03, 0.035, 0.045, 1 }, 0.3
local KINDS = {
    bars = { 0.32, 0.42, 0.6 }, units = { 0.3, 0.7, 0.4 }, casts = { 0.85, 0.65, 0.25 },
    hud = { 0.6, 0.45, 0.8 }, windows = { 0.45, 0.5, 0.56 },
}
local KIND_OF = {
    main = "bars", bar2 = "bars", bar3 = "bars", bar4 = "bars", bar5 = "bars", stance = "bars", pet = "bars", xpbar = "bars",
    player = "units", target = "units", focus = "units", tot = "units", petframe = "units", party = "units", raid = "units",
    castplayer = "casts", casttarget = "casts", castfocus = "casts", castpet = "casts", swingtimer = "casts",
    mirrortimers = "casts",
    buffs = "hud", debuffs = "hud", minimap = "hud", combopoints = "hud", totems = "hud", durability = "hud",
}
-- Left out of the picture: windows that float over the screen, and the raid grid, which takes the
-- party's place only in a raid.
local HIDDEN = { tooltip = true, bags = true, loot = true, raid = true }
local SLOTS, SLOT, SLOT_GAP = 12, 40, 6

local function block(canvas, rect, scale, color)
    local texture = canvas:CreateTexture(nil, "ARTWORK")
    texture:SetTexture(skin.FLAT)
    texture:SetVertexColor(color[1], color[2], color[3], 0.9)
    texture:SetSize(math.max(1, (rect.right - rect.left) * scale), math.max(1, (rect.top - rect.bottom) * scale))
    texture:SetPoint("BOTTOMLEFT", canvas, "BOTTOMLEFT", rect.left * scale, rect.bottom * scale)
    texture.key = rect.key
    return texture
end

-- Draws layout `name` width units wide into a new frame under parent; returns the frame.
function preview.Layout(parent, name, width)
    local scale = width / SCREEN.width
    local canvas = CreateFrame("Frame", nil, parent)
    canvas:SetSize(width, SCREEN.height * scale)
    skin.Fill(canvas, SCREEN_COLOR)
    skin.Outline(canvas)
    canvas.blocks = {}
    for key in pairs(layouts.Sizes) do
        local rect = not HIDDEN[key] and layouts.Rect(name, key, SCREEN) or nil
        if rect then canvas.blocks[key] = block(canvas, rect, scale, KINDS[KIND_OF[key] or "windows"]) end
    end
    return canvas
end

local function slotFrame(parent, index)
    local slot = CreateFrame("Frame", nil, parent)
    slot:SetSize(SLOT, SLOT)
    slot:SetPoint("LEFT", parent, "LEFT", (index - 1) * (SLOT + SLOT_GAP), 0)
    skin.Fill(slot, skin.CONTROL)
    skin.Outline(slot)
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 1, -1)
    slot.icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 1)
    skin.CropIcon(slot.icon)
    slot.key = controls.Text(slot, "small", "", controls.MUTED)
    slot.key:SetPoint("TOP", slot, "BOTTOM", 0, -3)
    return slot
end

-- Twelve empty slots in a row; preview.FillBar paints a role's main bar into them.
function preview.Bar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(SLOTS * SLOT + (SLOTS - 1) * SLOT_GAP, SLOT)
    bar.slots = {}
    for index = 1, SLOTS do bar.slots[index] = slotFrame(bar, index) end
    return bar
end

-- Setup leaves a macro's slot empty until the character knows one of the spells it lists, so the
-- macro comes at the lowest of their levels. A macro that lists none is placed at once.
local function macroLevel(macro)
    local lowest
    for _, name in ipairs(macro.spells or {}) do
        local data = core.Spells.Entry(name)
        if data and data.level and (not lowest or data.level < lowest) then lowest = data.level end
    end
    return lowest
end

local function entryArt(entry, preset)
    if type(entry) ~= "table" then return nil, nil end
    if entry.spell then
        local data = core.Spells.Entry(entry.spell)
        return data and data.icon or nil, entry.level or (data and data.level)
    end
    local macro = entry.macro and preset.macros and preset.macros[entry.macro]
    if not macro then return nil, nil end
    return macro.icon, macroLevel(macro)
end

-- A slot whose spell the character's level does not allow yet is drawn dim, the way a ghost slot is.
function preview.FillBar(bar, preset, level)
    for index, slot in ipairs(bar.slots) do
        local entry = preset and preset.bars.main and preset.bars.main[index] or nil
        local icon, needed = entryArt(entry, preset)
        slot.icon:SetTexture(icon)
        slot.icon:SetAlpha(needed and level and needed > level and DIM_ALPHA or 1)
        slot.entry = entry
        local key = core.Bindings.Scheme["ACTIONBUTTON" .. index]
        slot.key:SetText(key or "")
    end
end

-- The colour key under the layout pictures.
preview.Legend = { { "Action bars", KINDS.bars }, { "Unit frames", KINDS.units }, { "Cast bars and timers", KINDS.casts },
    { "Auras, minimap, class widgets", KINDS.hud }, { "Chat, tracker, meter, menu", KINDS.windows } }
