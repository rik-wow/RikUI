-- Empty preset slots are previews only; all action execution stays on the secure button.
local core, bars, setup = RikUI, RikUI.Bars, RikUI.Setup
local ICON_ALPHA, EDGE = 0.35, 1
local UNKNOWN_ICON = 134400
local entries, preset, cachedMarker, cachedRole, cachedClass, cachedSource = {}, nil
local warned = {}

local function warnOnce(operation)
    if warned[operation] then return end
    warned[operation] = true
    core:Print("Bars preset preview: " .. operation .. " unavailable.")
end

local function read(reader, operation, ...)
    if type(reader) ~= "function" then return nil end
    local ok, value = core.Secret.Read(reader, ...)
    if not ok then warnOnce(operation); return nil end
    if core.Secret.IsSecret(value) then return nil end
    return value
end

local function prepare()
    local marker = core.CharDB and core.CharDB.applied
    local _, class = UnitClass("player")
    local role = type(marker) == "table" and marker.role
    local source = core.Presets[class]
    if marker == cachedMarker and role == cachedRole and class == cachedClass and source == cachedSource then return end
    cachedMarker, cachedRole, cachedClass, cachedSource = marker, role, class, source
    entries, preset = {}, nil
    if type(marker) ~= "table" or marker.class ~= class or type(role) ~= "string" then return end
    preset = setup.Resolve(class, role)
    if not preset then return end
    for _, page in ipairs(setup.PageOrder) do
        for index, entry in pairs(preset.bars[page] or {}) do
            entries[setup.SlotToAction(page, index)] = entry
        end
    end
end

local function macroLevel(macro)
    local lowest
    for _, name in ipairs(macro.spells or {}) do
        local data = core.SpellData[name]
        if data and data.level and (not lowest or data.level < lowest) then lowest = data.level end
    end
    return lowest
end

local function entryArt(entry)
    if entry.spell then
        local data = core.SpellData[entry.spell]
        local id = data and data.ranks and data.ranks[1]
        local icon = read(C_Spell and C_Spell.GetSpellTexture, "spell icon", id or entry.spell)
        return icon or (data and data.icon) or UNKNOWN_ICON, entry.level
    end
    local macro = entry.macro and preset.macros[entry.macro]
    if macro then return macro.icon or UNKNOWN_ICON, entry.level or macroLevel(macro) end
    return read(C_Item and C_Item.GetItemIconByID, "item icon", entry.item) or UNKNOWN_ICON, entry.level
end

function bars.CreateGhost(button)
    local ghost = CreateFrame("Frame", nil, button)
    ghost:SetAllPoints(button)
    ghost:EnableMouse(false)
    -- Below the state overlay: hotkeys, borders and press feedback remain above the preview.
    ghost:SetFrameLevel(button:GetFrameLevel() + 1)
    ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
    ghost.icon:SetPoint("TOPLEFT", button, "TOPLEFT", EDGE, -EDGE)
    ghost.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -EDGE, EDGE)
    ghost.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ghost.icon:SetAlpha(ICON_ALPHA)
    ghost.levelText = ghost:CreateFontString(nil, "OVERLAY")
    ghost.levelText:SetPoint("BOTTOM", 0, 3)
    core.Media.Font(ghost.levelText, "small")
    ghost.levelText:SetTextColor(0.8, 0.83, 0.88, 1)
    ghost:Hide()
    button.ghost = ghost
end

local function updateGhost(button, ghost)
    ghost.entry = nil
    ghost:Hide()
    if not core.Profile or core.Profile.ghosts == false then return end
    prepare()
    local entry = entries[button.action]
    if not entry then return end
    local occupied = read(C_ActionBar and C_ActionBar.HasAction or HasAction, "slot contents", button.action)
    if occupied ~= false then return end -- Missing/opaque reads are not proof of an empty slot.
    local icon, level = entryArt(entry)
    ghost.icon:SetTexture(icon)
    ghost.levelText:SetText(level and ("Lv " .. level) or "")
    ghost.entry, ghost.requiredLevel = entry, level
    ghost:Show()
end

function bars.RefreshGhost(button)
    local ghost = button.ghost
    if not ghost then return end
    local wasPreview = ghost.entry ~= nil
    updateGhost(button, ghost)
    if (wasPreview or ghost.entry) and GameTooltip and GameTooltip:IsOwned(button) then
        GameTooltip:Hide()
        button:UpdateTooltip()
    end
end

function bars.RefreshGhosts(bar)
    for _, button in ipairs(bar.buttons or {}) do bars.RefreshGhost(button) end
end

function bars.ShowGhostTooltip(button)
    local ghost = button.ghost
    if not ghost or not ghost.entry then return false end
    GameTooltip:SetText(ghost.entry.spell or ghost.entry.macro or ghost.entry.item)
    GameTooltip:AddLine("Preset preview - empty slot", 0.8, 0.83, 0.88)
    if ghost.requiredLevel then
        GameTooltip:AddLine("Preset level: " .. ghost.requiredLevel, 0.8, 0.83, 0.88)
    end
    GameTooltip:Show()
    return true
end

local function setGhosts(shown)
    core.Profile.ghosts = shown == true
    for _, bar in pairs(bars.Frames) do bars.RefreshGhosts(bar) end
    core:Changed()
end

core:RegisterCommand("ghosts", function(args)
    if not core.Profile then core:Print("Still loading."); return end
    if args ~= "on" and args ~= "off" then core:Print("Usage: /rik ghosts on|off"); return end
    setGhosts(args == "on")
end, "Preview empty preset slots: /rik ghosts on|off", bars)

table.insert(bars.Options.settings, { type = "checkbox", key = "ghosts", label = "Preset ghost icons",
    get = function() return core.Profile.ghosts ~= false end, set = setGhosts })
