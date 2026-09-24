-- Small pictures for the wizard: a whole-screen layout drawn from its rectangles (the same arithmetic
-- src/layout/layout-audit.lua checks, so the picture is the layout), and every action page a role would get.
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
    buffs = "hud", debuffs = "hud", minimap = "hud", combopoints = "hud", totems = "hud", druidmana = "hud", durability = "hud",
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
    slot:EnableMouse(true)
    slot:SetScript("OnEnter", function(self)
        if parent.onInspect then parent.onInspect(self.description or "Empty slot") end
    end)
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

local PAGE_LABELS = { main = "Main bar", battle = "Battle stance", defensive = "Defensive stance",
    berserker = "Berserker stance", stealth = "Stealth", cat = "Cat form", bear = "Bear form",
    bar2 = "Shift / mouse", bar3 = "Ctrl utility", bar4 = "Extra bar 4", bar5 = "Extra bar 5", extra = "Page 2 utility" }
local PREFIXES = { bar2 = "MULTIACTIONBAR1BUTTON", bar3 = "MULTIACTIONBAR2BUTTON",
    bar4 = "MULTIACTIONBAR3BUTTON", bar5 = "MULTIACTIONBAR4BUTTON", extra = false }

function preview.Pages(preset)
    local result = {}
    for _, key in ipairs(core.Setup.PageOrder) do
        if preset and preset.bars[key] then result[#result + 1] = { key = key, label = PAGE_LABELS[key] or key } end
    end
    return result
end

function preview.Name(entry)
    if not entry then return "Empty slot" end
    return entry.spell or entry.macro or (entry.item == 6948 and "Hearthstone") or "Item"
end

local function spellReadiness(names, class, level)
    local lowest, failure
    for _, name in ipairs(names) do
        local id, reason = core.Spells.HighestKnownRank(name, class)
        if id then return true, "Learned" end
        failure = failure or reason
        local data = core.Spells.Entry(name, class)
        if data and data.level and (not lowest or data.level < lowest) then lowest = data.level end
    end
    if failure then return false, "Spellbook unavailable" end
    if lowest and level and lowest > level then return false, "Not learned · level " .. lowest end
    return false, lowest and "Not learned" or "Not learned · acquisition level unknown"
end

function preview.Details(entry, preset, level)
    if not entry then return nil, "Empty slot", false end
    local icon, names
    if entry.spell then
        local data = core.Spells.Entry(entry.spell, preset.class)
        icon, names = data and data.icon, { entry.spell }
    elseif entry.macro then
        local macro = preset.macros[entry.macro]
        icon, names = macro and macro.icon, macro and macro.spells or {}
    elseif entry.item then
        return entry.item == 6948 and 134414 or 134400, preview.Name(entry) .. " · Item", true
    end
    local ready, status = true, "Macro"
    if names and #names > 0 then ready, status = spellReadiness(names, preset.class, level) end
    return icon, preview.Name(entry) .. " · " .. status, ready
end

function preview.FillBar(bar, preset, level, pageKey, opts)
    pageKey = pageKey or "main"
    local prefix = PREFIXES[pageKey]
    if prefix == nil then prefix = "ACTIONBUTTON" end
    local keys = core.Bindings.Preview(opts) or {}
    for index, slot in ipairs(bar.slots) do
        local entry = preset and preset.bars[pageKey] and preset.bars[pageKey][index] or nil
        local icon, description, ready = preview.Details(entry, preset, level)
        local key = prefix and keys[prefix .. index] or ""
        slot.icon:SetTexture(icon)
        slot.icon:SetAlpha(ready and 1 or DIM_ALPHA)
        slot.entry = entry
        slot.key:SetText(key or "")
        slot.description = description .. (key and key ~= "" and " · " .. key or "")
    end
end

-- The colour key under the layout pictures.
preview.Legend = { { "Action bars", KINDS.bars }, { "Unit frames", KINDS.units }, { "Cast bars and timers", KINDS.casts },
    { "Auras, minimap, class widgets", KINDS.hud }, { "Chat, tracker, meter, menu", KINDS.windows } }
